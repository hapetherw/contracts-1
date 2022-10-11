module abel::market {
    
    use std::string::{String};

    // enter/exit market
    public entry fun enter_market<CoinType>(account: &signer) {}
    public entry fun exit_market<CoinType>(account: &signer) {}

    // policy hooks
    public fun init_allowed<CoinType>(initializer: address, name: String, symbol: String, decimals: u8, initial_exchange_rate_mantissa: u128): u64 {0}

    public fun mint_allowed<CoinType>(minter: address, mint_amount: u64): u64 {0}
    public fun mint_verify<CoinType>(minter: address, mint_amount: u64, mint_tokens: u64) {}

    public fun redeem_allowed<CoinType>(redeemer: address, redeem_tokens: u64): u64 {0}
    public fun redeem_verify<CoinType>(redeemer: address, redeem_amount: u64, redeem_tokens: u64) {}

    public fun borrow_allowed<CoinType>(borrower: address, borrow_amount: u64): u64 {0}
    public fun borrow_verify<CoinType>(borrower: address, borrow_amount: u64) {}

    public fun repay_borrow_allowed<CoinType>(payer: address, borrower: address, repay_amount: u64): u64 {0}
    public fun repay_borrow_verify<CoinType>(payer: address, borrower: address, repay_amount: u64, borrower_index: u128) {}

    public fun liquidate_borrow_allowed<BorrowedCoinType, CollateralCoinType>(liquidator: address, borrower: address, repay_amount: u64): u64 {0}
    public fun liquidate_borrow_verify<BorrowedCoinType, CollateralCoinType>(liquidator: address, borrower: address, repay_amount: u64, seize_tokens: u64) {}

    public fun seize_allowed<CollateralCoinType, BorrowedCoinType>(liquidator: address, borrower: address, seize_tokens: u64): u64 {0}
    public fun seize_verify<CollateralCoinType, BorrowedCoinType>(liquidator: address, borrower: address, seize_tokens: u64) {}

    public fun withdraw_allowed<CoinType>(src: address, amount: u64): u64 {0}
    public fun withdraw_verify<CoinType>(src: address, amount: u64) {}

    public fun deposit_allowed<CoinType>(dst: address, amount: u64): u64 {0}
    public fun deposit_verify<CoinType>(dst: address, amount: u64) {}

    public fun liquidate_calculate_seize_tokens<BorrowedCoinType, CollateralCoinType>(repay_amount: u64): (u64, u64) {(0,0)}

}