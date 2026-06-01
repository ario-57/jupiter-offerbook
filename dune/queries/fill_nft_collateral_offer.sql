WITH fill_txs AS (
    SELECT tx_id
    FROM solana.instruction_calls
    WHERE block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
      AND executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND bytearray_starts_with(data, 0x87377b2b733d8f91)
    GROUP BY tx_id
),
main_updates AS (
    SELECT
        block_time,
        tx_id,
        data
    FROM solana.instruction_calls
    WHERE block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
      AND executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND bytearray_starts_with(data, 0xe445a52e51cb9a1d)
      AND inner_instruction_index = 4
)
SELECT
    to_base58(bytearray_substring(m.data, 113, 32)) AS offer,
    to_base58(bytearray_substring(m.data, 343, 32)) AS pubkey,
    m.block_time,
    to_base58(bytearray_substring(m.data, 17, 32)) AS lender,
    to_base58(bytearray_substring(m.data, 49, 32)) AS borrower,
    to_base58(bytearray_substring(m.data, 155, 32)) AS principal_mint_address,
    to_base58(bytearray_substring(m.data, 220, 32)) AS collateral_mint_address,
    bytearray_to_bigint(bytearray_reverse(bytearray_substring(m.data, 292, 8))) / pow(10, 6) AS principal_amount,
    bytearray_to_bigint(bytearray_reverse(bytearray_substring(m.data, 300, 8))) AS collateral_amount,
    bytearray_to_bigint(bytearray_reverse(bytearray_substring(m.data, 308, 8))) AS interest,
    bytearray_to_bigint(0x00000000 || bytearray_reverse(bytearray_substring(m.data, 288, 4))) / 3600.0 AS duration_hour,
    bytearray_to_bigint(0x00000000 || bytearray_reverse(bytearray_substring(m.data, 284, 4))) / pow(10, 2) AS apy,
    bytearray_to_bigint(bytearray_substring(m.data, 342, 1)) AS loan_type_enum
FROM main_updates m
INNER JOIN fill_txs f
    ON m.tx_id = f.tx_id;
