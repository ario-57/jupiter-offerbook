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
DEFAULT_BACKFILL_WINDOW_DAYS = 5
DEFAULT_REFRESH_WINDOW_DAYS = 1
POLL_SECONDS = 10
MAX_POLLS = 180


def parse_time(value):
    if value == "now":
        return datetime.now(timezone.utc).replace(microsecond=0)
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def format_time(value):
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sql_timestamp(value):
    return value.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def log(message):
    print(message, flush=True)


def notice(message):
    log(f"::notice::{message}")


def append_summary(line):
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    with open(summary_path, "a", encoding="utf-8") as summary:
        summary.write(line + "\n")


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
            log(f"{namespace}.{table['table_name']} already exists.")
            return
        raise
    log(result.get("message") or f"Created {namespace}.{table['table_name']}.")


def render_sql(template, start_at, end_at):
    return template.replace("{{start_at}}", sql_timestamp(start_at)).replace("{{end_at}}", sql_timestamp(end_at))


def execute_sql(sql, performance, api_key):
    payload = {"sql": sql}
    if performance:
        payload["performance"] = performance
    response = request("POST", "/sql/execute", api_key, payload)
    return response["execution_id"]


def wait_for_execution(execution_id, api_key):
    for _ in range(MAX_POLLS):
        result = request("GET", f"/execution/{execution_id}/status", api_key)
        state = result.get("state") or result.get("execution_state")

        if state in {"QUERY_STATE_PENDING", "QUERY_STATE_EXECUTING"}:
            log(f"Execution {execution_id} is {state}; checking status again in {POLL_SECONDS}s.")
            time.sleep(POLL_SECONDS)
            continue
        if state == "QUERY_STATE_COMPLETED":
            return

        raise RuntimeError(f"Execution {execution_id} ended with state {state}: {result.get('error')}")

    raise RuntimeError(f"Execution {execution_id} did not finish after {MAX_POLLS * POLL_SECONDS} seconds.")


def fetch_all_rows(execution_id, api_key):
    wait_for_execution(execution_id, api_key)

    offset = 0
    rows = []

    while True:
        query = urlencode({"limit": 1000, "offset": offset})
        result = request("GET", f"/execution/{execution_id}/results?{query}", api_key)
        rows.extend(result.get("result", {}).get("rows", []))
        next_offset = result.get("next_offset")
        if next_offset is None:
            return rows
        offset = next_offset


def rows_to_csv(rows, columns, inserted_at):
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    inserted_at_value = sql_timestamp(inserted_at)
    for row in rows:
        csv_row = {column: row.get(column) for column in columns}
        if "inserted_at" in columns and not csv_row.get("inserted_at"):
            csv_row["inserted_at"] = inserted_at_value
        writer.writerow(csv_row)
    return output.getvalue()


def insert_rows(table, namespace, rows, api_key):
    if not rows:
        return {"rows_written": 0}

    columns = [column["name"] for column in table["schema"]]
    csv_body = rows_to_csv(rows, columns, datetime.now(timezone.utc))
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


def configured_historical_windows(table, now):
    windows = []
    for window in table.get("historical_windows", []):
        start_at = parse_time(window["start_at"])
        end_at = now if window["end_at"] == "now" else parse_time(window["end_at"])
        if start_at < end_at:
            windows.append((start_at, min(end_at, now), window.get("label", "configured historical backfill")))
    return windows


def choose_window(table, start_at, now, has_checkpoint):
    if table.get("backfill_once_until_now") and not has_checkpoint:
        return now - start_at, "one-shot historical backfill"

    backfill_window = timedelta(days=table.get("backfill_window_days", DEFAULT_BACKFILL_WINDOW_DAYS))
    refresh_window = timedelta(days=table.get("refresh_window_days", DEFAULT_REFRESH_WINDOW_DAYS))
    remaining = now - start_at
    if remaining > backfill_window:
        return backfill_window, "historical backfill"
    return refresh_window, "24-hour refresh"


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


def ingest_window(table, query_template, namespace, api_key, start_at, end_at, mode):
    start_label = format_time(start_at)
    end_label = format_time(end_at)
    sql = render_sql(query_template, start_at, end_at)

    notice(f"Starting {table['table_name']} {mode} window: {start_label} -> {end_label}")
    log(f"::group::{table['table_name']} {mode}: {start_label} to {end_label}")
    log(f"Mode: {mode}")
    log(f"Timeframe start: {start_label}")
    log(f"Timeframe end:   {end_label}")

    execution_id = execute_sql(sql, table.get("performance"), api_key)
    log(f"Dune execution ID: {execution_id}")
    rows = fetch_all_rows(execution_id, api_key)
    result = insert_rows(table, namespace, rows, api_key)
    rows_written = result.get("rows_written", len(rows))

    log(f"Rows inserted: {rows_written}")
    log("::endgroup::")
    notice(f"Finished {table['table_name']} {mode} window: {start_label} -> {end_label}; inserted {rows_written} rows")
    append_summary(f"| {mode} | `{start_label}` | `{end_label}` | `{execution_id}` | {rows_written} |")
    return rows_written


def process_table(root, table, namespace, api_key):
    create_table(table, namespace, api_key)

    state_path = root / "dune" / "state" / f"{table['table_name']}.json"
    query_template = (root / table["query_file"]).read_text(encoding="utf-8")
    has_checkpoint = state_path.exists()
    start_at = read_checkpoint(state_path, table)
    now = datetime.now(timezone.utc).replace(microsecond=0)

    append_summary(f"## {table['table_name']}")
    append_summary("")
    append_summary(f"Checkpoint start: `{format_time(start_at)}`")
    append_summary(f"Run target end: `{format_time(now)}`")
    append_summary(f"Configured historical windows: `{len(table.get('historical_windows', []))}`")
    append_summary(f"One-shot historical backfill: `{str(table.get('backfill_once_until_now', False)).lower()}`")
    append_summary(f"Refresh window: `{table.get('refresh_window_days', DEFAULT_REFRESH_WINDOW_DAYS)} day`")
    append_summary("")
    append_summary("| Mode | Window start | Window end | Execution ID | Rows inserted |")
    append_summary("| --- | --- | --- | --- | ---: |")

    if not has_checkpoint and table.get("historical_windows"):
        last_end_at = start_at
        for window_start, window_end, mode in configured_historical_windows(table, now):
            if window_start >= now:
                continue
            ingest_window(table, query_template, namespace, api_key, window_start, window_end, mode)
            last_end_at = max(last_end_at, window_end)
            write_checkpoint(state_path, table, last_end_at)
        return

    if start_at >= now:
        message = f"{table['table_name']}: nothing to ingest."
        notice(message)
        append_summary(f"| n/a | {format_time(start_at)} | {format_time(now)} | n/a | 0 |")
        return

    while start_at < now:
        window, mode = choose_window(table, start_at, now, has_checkpoint)
        end_at = min(start_at + window, now)
        ingest_window(table, query_template, namespace, api_key, start_at, end_at, mode)
        start_at = end_at
        write_checkpoint(state_path, table, start_at)
        has_checkpoint = True


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
