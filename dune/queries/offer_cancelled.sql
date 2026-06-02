WITH events AS (
    SELECT *
    FROM solana.instruction_calls
    WHERE executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND tx_success
      AND (
          varbinary_starts_with(data, 0xe445a52e51cb9a1d94d2d19e81320fa6)
          OR varbinary_starts_with(data, 0xe445a52e51cb9a1d2d2aafd633c09a09)
      )
      AND block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
),
p AS (
    SELECT
        *,
        varbinary_to_integer(varbinary_substring(data, 51, 1)) AS principal_kind
    FROM events
),
c AS (
    SELECT
        *,
        CASE
            WHEN principal_kind IN (1, 2, 3) THEN 64
            WHEN principal_kind = 4 THEN 32
            ELSE 0
        END AS principal_payload_len
    FROM p
),
f AS (
    SELECT
        *,
        52 + principal_payload_len AS collateral_kind_pos,
        varbinary_to_integer(varbinary_substring(data, 52 + principal_payload_len, 1)) AS collateral_kind
    FROM c
),
o AS (
    SELECT
        *,
        CASE
            WHEN collateral_kind IN (1, 2, 3) THEN 64
            WHEN collateral_kind = 4 THEN 32
            ELSE 0
        END AS collateral_payload_len
    FROM f
),
offsets AS (
    SELECT
        *,
        53 + principal_payload_len + collateral_payload_len AS filter_kind_pos,
        varbinary_to_integer(varbinary_substring(data, 53 + principal_payload_len + collateral_payload_len, 1)) AS filter_kind
    FROM o
),
decoded AS (
    SELECT
        *,
        CASE
            WHEN filter_kind = 0 THEN 0
            WHEN filter_kind IN (1, 2) THEN 32
            WHEN filter_kind = 3 THEN 264
            ELSE 0
        END AS filter_payload_len
    FROM offsets
)
SELECT
    block_time,
    tx_id,

    to_base58(varbinary_substring(data, 17, 32)) AS creator,

    varbinary_to_integer(varbinary_substring(data, 49, 1)) AS side_id,
    varbinary_to_integer(varbinary_substring(data, 50, 1)) AS status_id,

    principal_kind,
    to_base58(varbinary_substring(data, 52, 32)) AS principal_mint,
    CASE WHEN principal_kind IN (1, 2, 3)
        THEN to_base58(varbinary_substring(data, 84, 32))
    END AS principal_token_program,

    collateral_kind,
    CASE WHEN collateral_kind IN (1, 2, 3, 4)
        THEN to_base58(varbinary_substring(data, collateral_kind_pos + 1, 32))
    END AS collateral_asset_1,
    CASE WHEN collateral_kind IN (1, 2, 3)
        THEN to_base58(varbinary_substring(data, collateral_kind_pos + 33, 32))
    END AS collateral_token_program,

    filter_kind,

    54 + principal_payload_len + collateral_payload_len + filter_payload_len AS tail_pos,

    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 54 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS principal_amount,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 62 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS remaining_principal,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 70 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS collateral_amount,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 78 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS remaining_collateral,

    varbinary_to_integer(varbinary_reverse(varbinary_substring(data, 86 + principal_payload_len + collateral_payload_len + filter_payload_len, 4))) AS apy,
    varbinary_to_integer(varbinary_reverse(varbinary_substring(data, 90 + principal_payload_len + collateral_payload_len + filter_payload_len, 4))) AS duration,

    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 94 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS created_at,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 102 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS expired_at,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 110 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS updated_at,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 118 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS min_fill_amount,
    CAST(varbinary_to_uint256(varbinary_reverse(varbinary_substring(data, 126 + principal_payload_len + collateral_payload_len + filter_payload_len, 8))) AS VARCHAR) AS fill_counter,

    varbinary_to_integer(varbinary_substring(data, 134 + principal_payload_len + collateral_payload_len + filter_payload_len, 1)) AS allow_partial_fill,
    varbinary_to_integer(varbinary_substring(data, 135 + principal_payload_len + collateral_payload_len + filter_payload_len, 1)) AS bump,

    to_base58(varbinary_substring(data, 136 + principal_payload_len + collateral_payload_len + filter_payload_len, 32)) AS countered_offer,
    to_base58(varbinary_substring(data, 168 + principal_payload_len + collateral_payload_len + filter_payload_len, 32)) AS pubkey
FROM decoded;
