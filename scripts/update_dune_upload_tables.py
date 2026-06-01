#!/usr/bin/env python3
import csv
import io
import json
import os
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


API_BASE = "https://api.dune.com/api/v1"
WINDOW = timedelta(days=1)
POLL_SECONDS = 10
MAX_POLLS = 180


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def format_time(value):
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sql_timestamp(value):
    return value.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def request(method, path, api_key, body=None, content_type="application/json"):
    headers = {"X-Dune-Api-Key": api_key}
    data = None
    if body is not None:
        if isinstance(body, bytes):
            data = body
        elif content_type == "application/json":
            data = json.dumps(body).encode("utf-8")
        else:
            data = str(body).encode("utf-8")
        headers["Content-Type"] = content_type

    req = Request(f"{API_BASE}{path}", data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=120) as response:
            raw = response.read()
            ctype = response.headers.get("Content-Type", "")
            if "application/json" in ctype:
                return json.loads(raw.decode("utf-8"))
            return raw.decode("utf-8")
    except HTTPError as error:
        detail = error.read().decode("utf-8")
        raise RuntimeError(f"Dune API {method} {path} failed: {error.code} {detail}") from error


def create_table(table, namespace, api_key):
    payload = {
        "namespace": namespace,
        "table_name": table["table_name"],
        "description": table.get("description", ""),
        "is_private": table.get("is_private", False),
        "schema": table["schema"],
    }
    try:
        result = request("POST", "/uploads", api_key, payload)
    except RuntimeError as error:
        message = str(error).lower()
        if "already" in message or "exists" in message:
            print(f"{namespace}.{table['table_name']} already exists.")
            return
        raise
    print(result.get("message") or f"Created {namespace}.{table['table_name']}.")


def render_sql(template, start_at, end_at):
    return template.replace("{{start_at}}", sql_timestamp(start_at)).replace("{{end_at}}", sql_timestamp(end_at))


def execute_sql(sql, performance, api_key):
    payload = {"sql": sql}
    if performance:
        payload["performance"] = performance
    response = request("POST", "/sql/execute", api_key, payload)
    return response["execution_id"]


def fetch_all_rows(execution_id, api_key):
    offset = 0
    rows = []

    for _ in range(MAX_POLLS):
        query = urlencode({"limit": 1000, "offset": offset})
        result = request("GET", f"/execution/{execution_id}/results?{query}", api_key)
        state = result.get("state")

        if state in {"QUERY_STATE_PENDING", "QUERY_STATE_EXECUTING"}:
            time.sleep(POLL_SECONDS)
            continue
        if state != "QUERY_STATE_COMPLETED":
            raise RuntimeError(f"Execution {execution_id} ended with state {state}: {result.get('error')}")

        rows.extend(result.get("result", {}).get("rows", []))
        next_offset = result.get("next_offset")
        if next_offset is None:
            return rows
        offset = next_offset

    raise RuntimeError(f"Execution {execution_id} did not finish after {MAX_POLLS * POLL_SECONDS} seconds.")


def rows_to_csv(rows, columns):
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({column: row.get(column) for column in columns})
    return output.getvalue()


def insert_rows(table, namespace, rows, api_key):
    if not rows:
        return {"rows_written": 0}

    columns = [column["name"] for column in table["schema"]]
    csv_body = rows_to_csv(rows, columns)
    namespace_q = quote(namespace, safe="")
    table_q = quote(table["table_name"], safe="")
    return request(
        "POST",
        f"/uploads/{namespace_q}/{table_q}/insert",
        api_key,
        csv_body,
        content_type="text/csv",
    )


def read_checkpoint(path, table):
    if path.exists():
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("next_start_at"):
            return parse_time(data["next_start_at"])
    return parse_time(table["start_at"])


def write_checkpoint(path, table, next_start_at):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "table_name": table["table_name"],
                "next_start_at": format_time(next_start_at),
                "updated_at": format_time(datetime.now(timezone.utc)),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def process_table(root, table, namespace, api_key):
    create_table(table, namespace, api_key)

    state_path = root / "dune" / "state" / f"{table['table_name']}.json"
    query_template = (root / table["query_file"]).read_text(encoding="utf-8")
    start_at = read_checkpoint(state_path, table)
    now = datetime.now(timezone.utc).replace(microsecond=0)

    if start_at >= now:
        print(f"{table['table_name']}: nothing to ingest.")
        return

    while start_at < now:
        end_at = min(start_at + WINDOW, now)
        sql = render_sql(query_template, start_at, end_at)
        print(f"{table['table_name']}: querying {format_time(start_at)} to {format_time(end_at)}")

        execution_id = execute_sql(sql, table.get("performance"), api_key)
        rows = fetch_all_rows(execution_id, api_key)
        result = insert_rows(table, namespace, rows, api_key)

        print(
            f"{table['table_name']}: inserted {result.get('rows_written', len(rows))} rows "
            f"for {format_time(start_at)} to {format_time(end_at)}"
        )
        start_at = end_at
        write_checkpoint(state_path, table, start_at)


def main():
    api_key = os.environ.get("DUNE_API_KEY")
    namespace = os.environ.get("DUNE_NAMESPACE")
    if not api_key:
        raise SystemExit("DUNE_API_KEY is required.")
    if not namespace:
        raise SystemExit("DUNE_NAMESPACE is required, for example your Dune username or team namespace.")

    root = Path.cwd()
    config = json.loads((root / "dune" / "tables.json").read_text(encoding="utf-8"))
    for table in config["tables"]:
        process_table(root, table, namespace, api_key)


if __name__ == "__main__":
    main()
