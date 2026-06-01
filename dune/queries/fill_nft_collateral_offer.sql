WITH FillNftCollateralOffer AS (
    SELECT DISTINCT tx_id
    FROM solana.instruction_calls
    WHERE executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND bytearray_substring(data, 1, 8) = 0x87377b2b733d8f91
      AND block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
),
main AS (
    SELECT
        block_time,
        tx_id,
        to_base58(bytearray_substring(data, 17, 32)) AS lender,
        to_base58(bytearray_substring(data, 49, 32)) AS borrower,
        to_base58(bytearray_substring(data, 81, 32)) AS creator,
        to_base58(bytearray_substring(data, 113, 32)) AS offer,

        bytearray_to_bigint(bytearray_substring(data, 145, 1)) AS status_enum,
        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 146, 8))) AS fill_index,

        to_base58(bytearray_substring(data, 155, 32)) AS principal_mint_address,
        to_base58(bytearray_substring(data, 187, 32)) AS principal_token_program,

        to_base58(bytearray_substring(data, 220, 32)) AS collateral_mint_address,
        to_base58(bytearray_substring(data, 252, 32)) AS collateral_token_program,

        bytearray_to_bigint(0x00000000 || bytearray_reverse(bytearray_substring(data, 284, 4))) / pow(10, 2) AS apy,
        bytearray_to_bigint(0x00000000 || bytearray_reverse(bytearray_substring(data, 288, 4))) / 3600.0 AS duration_hour,

        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 292, 8))) / pow(10, 6) AS principal_amount,
        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 300, 8))) AS collateral_amount,
        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 308, 8))) AS interest,

        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 316, 8))) AS created_at,
        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 324, 8))) AS expired_at,
        bytearray_to_bigint(bytearray_reverse(bytearray_substring(data, 332, 8))) AS updated_at,

        bytearray_to_bigint(bytearray_substring(data, 340, 1)) AS bump,
        bytearray_to_bigint(bytearray_substring(data, 341, 1)) AS collateral_account_bump,
        bytearray_to_bigint(bytearray_substring(data, 342, 1)) AS loan_type_enum,

        to_base58(bytearray_substring(data, 343, 32)) AS pubkey
    FROM solana.instruction_calls
    WHERE executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND bytearray_substring(data, 1, 8) = 0xe445a52e51cb9a1d
      AND inner_instruction_index = 4
      AND block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
      AND tx_id IN (SELECT tx_id FROM FillNftCollateralOffer)
)
SELECT
    offer,
    pubkey,
    block_time,
    lender,
    borrower,
    principal_mint_address,
    collateral_mint_address,
    principal_amount,
    collateral_amount,
    interest,
    duration_hour,
    apy,
    loan_type_enum
FROM main;
