with fillTokenCollateralOffer as (
    select
        block_time,
        tx_id,
        account_arguments[1] as lender,
        account_arguments[3] as borrower,
        account_arguments[6] as loan,
        account_arguments[9] as principal_mint_address,
        account_arguments[10] as collateral_mint_address,
        bytearray_to_bigint(
            bytearray_reverse(bytearray_substring(data, 9, 8))
        ) as collateral_fill_amount,

        bytearray_to_bigint(
            bytearray_reverse(bytearray_substring(data, 17, 8))
        ) / pow(10, 6) as max_principal,

        bytearray_to_bigint(
            0x00000000 ||
            bytearray_reverse(bytearray_substring(data, 25, 4))
        ) / 3600 as duration_hour,

        bytearray_to_bigint(
            0x00000000 ||
            bytearray_reverse(bytearray_substring(data, 29, 4))
        ) / pow(10, 2) as apy,

        bytearray_to_bigint(bytearray_substring(data, 33, 1)) as loan_type
    from solana.instruction_calls
    where block_time >= timestamp '{{start_at}}'
      and block_time < timestamp '{{end_at}}'
      and bytearray_substring(data, 1, 8) = 0xaafb00b5a3536ae4
      and executing_account = 'offerbkFMvVfpQhL8ZQ5iromnjct5rz3r52B9ewu3ie'
      and tx_success
)
select
    loan,
    block_time,
    lender,
    borrower,
    principal_mint_address,
    collateral_mint_address,
    collateral_fill_amount,
    max_principal,
    duration_hour,
    apy,
    loan_type
from fillTokenCollateralOffer;
