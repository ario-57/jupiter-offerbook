WITH events AS (
    SELECT *
    FROM solana.instruction_calls
    WHERE executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND tx_success
      AND varbinary_starts_with(data, 0xe445a52e51cb9a1dc2623358e476ad2e)
      AND block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
),
base AS (
    SELECT
        *,
        varbinary_to_integer(varbinary_substring(data, 219, 1)) AS collateral_kind
    FROM events
),
offsets AS (
    SELECT
        *,
        CASE
            WHEN collateral_kind IN (1, 2, 3) THEN 64
            WHEN collateral_kind = 4 THEN 32
            ELSE 0
        END AS collateral_payload_len
    FROM base
)
SELECT
    block_time,
    tx_id,
    outer_instruction_index,
    inner_instruction_index,

    to_base58(varbinary_substring(data, 17, 32)) AS lender,
    to_base58(varbinary_substring(data, 49, 32)) AS borrower,
    to_base58(varbinary_substring(data, 81, 32)) AS creator,
    to_base58(varbinary_substring(data, 113, 32)) AS offer,

    varbinary_to_integer(varbinary_substring(data, 145, 1)) AS status_id,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 146, 8))) AS VARCHAR) AS fill_index,

    varbinary_to_integer(varbinary_substring(data, 154, 1)) AS principal_kind,
    to_base58(varbinary_substring(data, 155, 32)) AS principal_mint,
    to_base58(varbinary_substring(data, 187, 32)) AS principal_token_program,

    collateral_kind,

    CASE
        WHEN collateral_kind IN (1, 2, 3)
            THEN to_base58(varbinary_substring(data, 220, 32))
    END AS collateral_mint,

    CASE
        WHEN collateral_kind IN (1, 2, 3)
            THEN to_base58(varbinary_substring(data, 252, 32))
    END AS collateral_token_program,

    CASE
        WHEN collateral_kind = 4
            THEN to_base58(varbinary_substring(data, 220, 32))
    END AS collateral_core_asset,

    varbinary_to_integer(varbinary_reverse(varbinary_substring(data, 220 + collateral_payload_len, 4))) AS apy,
    varbinary_to_integer(varbinary_reverse(varbinary_substring(data, 224 + collateral_payload_len, 4))) AS duration,

    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 228 + collateral_payload_len, 8))) AS VARCHAR) AS principal_amount,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 236 + collateral_payload_len, 8))) AS VARCHAR) AS collateral_amount,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 244 + collateral_payload_len, 8))) AS VARCHAR) AS interest,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 252 + collateral_payload_len, 8))) AS VARCHAR) AS created_at,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 260 + collateral_payload_len, 8))) AS VARCHAR) AS expired_at,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 268 + collateral_payload_len, 8))) AS VARCHAR) AS updated_at,

    varbinary_to_integer(varbinary_substring(data, 276 + collateral_payload_len, 1)) AS bump,
    varbinary_to_integer(varbinary_substring(data, 277 + collateral_payload_len, 1)) AS collateral_account_bump,
    varbinary_to_integer(varbinary_substring(data, 278 + collateral_payload_len, 1)) AS loan_type_id,

    to_base58(varbinary_substring(data, 279 + collateral_payload_len, 32)) AS pubkey
FROM offsets;
