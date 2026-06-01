WITH FillTokenPrincipalOffer AS (
    SELECT
        block_time,
        tx_id,
        account_arguments[1] AS borrower,
        account_arguments[3] AS lender,
        account_arguments[6] AS loan,
        account_arguments[9] AS principal_mint_address,
        account_arguments[10] AS collateral_mint_address,

        bytearray_to_bigint(
            bytearray_reverse(bytearray_substring(data, 9, 8))
        ) / pow(10, 6) AS principal_fill_amount,

        bytearray_to_bigint(
            bytearray_reverse(bytearray_substring(data, 17, 8))
        ) AS max_collateral,

        bytearray_to_bigint(
            0x00000000 ||
            bytearray_reverse(bytearray_substring(data, 25, 4))
        ) / 3600.0 AS duration_hour,

        bytearray_to_bigint(
            0x00000000 ||
            bytearray_reverse(bytearray_substring(data, 29, 4))
        ) / pow(10, 2) AS apy,

        bytearray_to_bigint(bytearray_substring(data, 33, 1)) AS loan_type
    FROM solana.instruction_calls
    WHERE block_date >= CAST(timestamp '{{start_at}}' AS date)
      AND block_date <= CAST(timestamp '{{end_at}}' AS date)
      AND block_time >= timestamp '{{start_at}}'
      AND block_time < timestamp '{{end_at}}'
      AND bytearray_substring(data, 1, 8) = 0x53d7b0a1b06981b1
      AND executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      AND tx_success = true
)
SELECT
    loan,
    block_time,
    lender,
    borrower,
    principal_mint_address,
    collateral_mint_address,
    principal_fill_amount,
    max_collateral,
    duration_hour,
    apy,
    loan_type
FROM FillTokenPrincipalOffer;
