# Dune Upload Table Workflow

This workflow backfills and updates a Dune uploaded table named:

```sql
dune.<your_namespace>.fill_token_collateral_offer
```

It does not use materialized views.

## How It Works

1. Creates the upload table with `POST /v1/uploads` if it does not already exist.
2. Runs the source SQL through `POST /v1/sql/execute` in 24-hour windows.
3. Reads the execution result rows from Dune.
4. Appends those rows to `fill_token_collateral_offer` with `POST /v1/uploads/{namespace}/{table_name}/insert`.
5. Writes a checkpoint to `dune/state/fill_token_collateral_offer.json`.
6. Commits that checkpoint so the next daily GitHub Actions run continues from the last successful window.

The first run starts at `2026-03-26T00:00:00Z` and processes one 24-hour window at a time until the current run time.

## Setup

Copy `.github/`, `dune/`, and `scripts/` into your GitHub repository.

Add these GitHub Actions repository secrets:

- `DUNE_API_KEY`: a Dune API key with read/write access.
- `DUNE_NAMESPACE`: your Dune username or team namespace.

Then run `Update Dune upload tables` manually once from GitHub Actions. After that, it runs every 24 hours.

## Add Another Table Later

Add a new SQL template under `dune/queries/`, then add another object to `dune/tables.json` with:

- `table_name`
- `query_file`
- `description`
- `start_at`
- `schema`
- optionally `performance`, if your Dune plan supports a named execution tier

The SQL template should use:

```sql
where block_time >= timestamp '{{start_at}}'
  and block_time < timestamp '{{end_at}}'
```

## Notes

- The workflow appends data. It does not clear or replace the Dune table.
- The workflow omits `performance` by default so Dune uses your account's default execution tier.
- If the table already contains data from a manual run, set the checkpoint file before running to avoid duplicates.
- I fixed the original SQL typo from `principa_mint_address` to `principal_mint_address`.
