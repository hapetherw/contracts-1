module abel::acoin_lend {
    
    use std::signer;

    use aptos_std::type_info::type_of;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::block;

    use abel::market;
    use abel::interest_rate_module;
    use abel::acoin::{Self, ACoin};
    use abel::constants::{Exp_Scale, Borrow_Rate_Max_Mantissa, Reserve_Factor_Max_Mantissa};

    //
    // Errors.
    //
    const EBORROW_RATE_ABSURDLY_HIGH: u64 = 1;
    const ELIQUIDATE_LIQUIDATOR_IS_BORROWER: u64 = 2;
    const ELIQUIDATE_CLOSE_AMOUNT_IS_ZERO: u64 = 3;
    const ELIQUIDATE_SEIZE_TOO_MUCH: u64 = 4;
    const ELIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER: u64 = 5;
    const ERESERVE_FACTOR_OUT_OF_BOUND: u64 = 6;
    const ETOKEN_INSUFFICIENT_CASH: u64 = 7;
    const EREDUCE_AMOUNT_TO_MUCH: u64 = 8;
    const ENOT_ADMIN: u64 = 9;


    //
    // entry functions
    //
    public entry fun transfer<CoinType>(
        from: &signer, 
        to: address, 
        amount: u64,
    ) {
        let acoin = acoin::withdraw<CoinType>(signer::address_of(from), amount);
        acoin::deposit(to, acoin);
    }

    public entry fun mint_entry<CoinType>(
        minter: &signer,
        mint_amount: u64,
    ) {
        let minter_addr = signer::address_of(minter);
        let coin = coin::withdraw<CoinType>(minter, mint_amount);
        let acoin = mint<CoinType>(minter, coin);
        acoin::deposit<CoinType>(minter_addr, acoin);
    }

    public entry fun redeem_entry<CoinType>(
        redeemer: &signer,
        redeem_tokens: u64,
    ) {
        let redeemer_addr = signer::address_of(redeemer);
        let acoin = acoin::withdraw<CoinType>(redeemer_addr, redeem_tokens);
        let coin = redeem<CoinType>(redeemer, acoin);
        coin::deposit<CoinType>(redeemer_addr, coin);
    }

    public entry fun redeem_underlying<CoinType>(
        redeemer: &signer,
        redeem_amount: u64,
    ) {
        let redeemer_addr = signer::address_of(redeemer);
        let exchange_rate_mantissa = exchange_rate_mantissa<CoinType>();
        let redeem_tokens = ((redeem_amount as u128) * Exp_Scale() / exchange_rate_mantissa as u64);
        let acoin = acoin::withdraw<CoinType>(redeemer_addr, redeem_tokens);
        let coin = redeem<CoinType>(redeemer, acoin);
        coin::deposit<CoinType>(redeemer_addr, coin);
    }

    public entry fun borrow_entry<CoinType>(
        borrower: &signer,
        borrow_amount: u64,
    ) {
        let borrower_addr = signer::address_of(borrower);
        let coin = borrow<CoinType>(borrower, borrow_amount);
        coin::deposit<CoinType>(borrower_addr, coin);
    }

    public entry fun repay_borrow_entry<CoinType>(
        payer: &signer,
        borrower: address,
        repay_amount: u64,
    ) {
        let coin = coin::withdraw<CoinType>(payer, repay_amount);
        repay_borrow<CoinType>(payer, borrower, coin);
    }

    public entry fun liquidate_borrow_entry<BorrowedCoinType, CollateralCoinType>(
        liquidator: &signer,
        borrower: address,
        repay_amount: u64,
    ) {
        let liquidator_addr = signer::address_of(liquidator);
        let coin = coin::withdraw<BorrowedCoinType>(liquidator, repay_amount);
        let acoin = liquidate_borrow<BorrowedCoinType, CollateralCoinType>(liquidator, borrower, coin);
        acoin::deposit<CollateralCoinType>(liquidator_addr, acoin);
    }


    //
    // Getter functions
    //
    public fun exchange_rate_mantissa<CoinType>(): u128 {
        let supply = acoin::total_supply<CoinType>();
        if (supply == 0) {
            acoin::initial_exchange_rate_mantissa<CoinType>()
        } else {
            let supply = acoin::total_supply<CoinType>();
            let total_cash = (acoin::get_cash<CoinType>() as u128);
            let total_borrows = acoin::total_borrows<CoinType>();
            let total_reserves = acoin::total_reserves<CoinType>();
            let cash_plus_borrows_minus_reserves = total_cash + total_borrows - total_reserves;
            cash_plus_borrows_minus_reserves * Exp_Scale() / supply
        }
    }

    public fun admin<CoinType>(): address {
        @abel
    }

    //
    // Public functions
    //

    public fun withdraw<CoinType>(
        account: &signer,
        amount: u64,
    ): ACoin<CoinType> {
        let src = signer::address_of(account);
        let err = market::withdraw_allowed<CoinType>(src, amount);
        assert!(err == 0, err);
        let acoin = acoin::withdraw<CoinType>(src, amount);
        market::withdraw_verify<CoinType>(src, amount);
        acoin
    }

    public fun deposit<CoinType>(
        account: &signer,
        acoin: ACoin<CoinType>,
    ) {
        let dst = signer::address_of(account);
        let amount = acoin::value<CoinType>(&acoin);
        let err = market::deposit_allowed<CoinType>(dst, amount);
        assert!(err == 0, err);
        acoin::deposit<CoinType>(dst, acoin);
        market::deposit_verify<CoinType>(dst, amount);
    }

    public fun accrue_interest<CoinType>() {
        let current_block_number = block::get_current_block_height();
        let accrual_block_number_prior = acoin::accrual_block_number<CoinType>();

        if (current_block_number == accrual_block_number_prior) {
            return
        };

        let cash_prior = acoin::get_cash<CoinType>();
        let borrows_prior = acoin::total_borrows<CoinType>();
        let reserves_prior = acoin::total_reserves<CoinType>();
        let borrow_index_prior = acoin::borrow_index<CoinType>();

        let borrow_rate_mantissa = interest_rate_module::get_borrow_rate((cash_prior as u128), borrows_prior, reserves_prior);
        assert!(borrow_rate_mantissa <= Borrow_Rate_Max_Mantissa(), EBORROW_RATE_ABSURDLY_HIGH);

        let block_delta = current_block_number - accrual_block_number_prior;
        let reserve_factor_mantissa = acoin::reserve_factor_mantissa<CoinType>();
        let simple_interest_factor = borrow_rate_mantissa * (block_delta as u128);
        let interest_accumulated = simple_interest_factor * borrows_prior / Exp_Scale();
        let total_borrows_new = interest_accumulated + borrows_prior;
        let total_reserves_new = interest_accumulated * reserve_factor_mantissa / Exp_Scale() + reserves_prior;
        let borrow_index_new = simple_interest_factor * borrow_index_prior / Exp_Scale() + borrow_index_prior;

        acoin::update_accrual_block_number<CoinType>();
        acoin::update_global_borrow_index<CoinType>(borrow_index_new);
        acoin::update_total_borrows<CoinType>(total_borrows_new);
        acoin::update_total_reserves<CoinType>(total_reserves_new);

        acoin::emit_accrue_interest_event<CoinType>(cash_prior, interest_accumulated, borrow_index_new, total_borrows_new);
    }

    public fun mint<CoinType>(
        minter: &signer,
        coin: Coin<CoinType>
    ): ACoin<CoinType> {
        let minter_addr = signer::address_of(minter);
        let mint_amount = coin::value(&coin);

        accrue_interest<CoinType>();

        let err = market::mint_allowed<CoinType>(minter_addr, mint_amount);
        assert!(err == 0, err);

        let exchange_rate_mantissa = exchange_rate_mantissa<CoinType>();
        let mint_tokens = ((mint_amount as u128) * Exp_Scale() / exchange_rate_mantissa as u64);

        acoin::deposit_to_treasury<CoinType>(coin);
        acoin::add_supply<CoinType>((mint_tokens as u128));

        market::mint_verify<CoinType>(minter_addr, mint_amount, mint_tokens);

        acoin::emit_mint_event<CoinType>(minter_addr, mint_amount, mint_tokens);

        acoin::mint<CoinType>(mint_tokens)
    }

    public fun redeem<CoinType>(
        redeemer: &signer,
        acoin: ACoin<CoinType>
    ): Coin<CoinType> {
        let redeemer_addr = signer::address_of(redeemer);
        let redeem_tokens = acoin::burn<CoinType>(acoin);

        accrue_interest<CoinType>();

        let err = market::redeem_allowed<CoinType>(redeemer_addr, redeem_tokens);
        assert!(err == 0, err);  

        let exchange_rate_mantissa = exchange_rate_mantissa<CoinType>();
        let redeem_amount = ((redeem_tokens as u128) * exchange_rate_mantissa / Exp_Scale() as u64);

        acoin::sub_supply<CoinType>((redeem_tokens as u128));

        market::redeem_verify<CoinType>(redeemer_addr, redeem_amount, redeem_tokens);

        acoin::emit_redeem_event<CoinType>(redeemer_addr, redeem_amount, redeem_tokens);

        acoin::withdraw_from_treasury<CoinType>(redeem_amount)
    }   

    public fun borrow<CoinType>(
        borrower: &signer,
        borrow_amount: u64
    ): Coin<CoinType> {
        let borrower_addr = signer::address_of(borrower);

        accrue_interest<CoinType>();

        let err = market::borrow_allowed<CoinType>(borrower_addr, borrow_amount);
        assert!(err == 0, err); 

        let account_borrows = acoin::borrow_balance<CoinType>(borrower_addr);
        let account_borrows_new = account_borrows + borrow_amount;

        acoin::add_total_borrows<CoinType>((borrow_amount as u128));

        acoin::update_account_borrows<CoinType>(borrower_addr, account_borrows_new, acoin::borrow_index<CoinType>());

        market::borrow_verify<CoinType>(borrower_addr, borrow_amount);

        acoin::emit_borrow_event<CoinType>(borrower_addr, borrow_amount, account_borrows_new, acoin::total_borrows<CoinType>());

        acoin::withdraw_from_treasury<CoinType>((borrow_amount as u64))
    }

    public fun repay_borrow<CoinType>(
        payer: &signer,
        borrower: address,
        coin: Coin<CoinType>
    ) {
        let repay_amount = coin::value(&coin);
        let payer_addr = signer::address_of(payer);

        accrue_interest<CoinType>();

        let err = market::repay_borrow_allowed<CoinType>(payer_addr, borrower, repay_amount);
        assert!(err == 0, err); 

        acoin::deposit_to_treasury<CoinType>(coin);

        let borrower_index = acoin::borrow_interest_index<CoinType>(borrower);
        let account_borrows = acoin::borrow_balance<CoinType>(borrower);
        let account_borrows_new = account_borrows - repay_amount;

        acoin::sub_total_borrows<CoinType>((repay_amount as u128));

        acoin::update_account_borrows<CoinType>(borrower, account_borrows_new, acoin::borrow_index<CoinType>());

        market::repay_borrow_verify<CoinType>(payer_addr, borrower, repay_amount, borrower_index);

        acoin::emit_repay_borrow_event<CoinType>(payer_addr, borrower, repay_amount, account_borrows_new, acoin::total_borrows<CoinType>());
    }

    public fun liquidate_borrow<BorrowedCoinType, CollateralCoinType>(
        liquidator: &signer, 
        borrower: address, 
        coin: Coin<BorrowedCoinType>
    ): ACoin<CollateralCoinType> {
        let repay_amount = coin::value(&coin);
        let liquidator_addr = signer::address_of(liquidator);

        accrue_interest<BorrowedCoinType>();
        accrue_interest<CollateralCoinType>();

        let err = market::liquidate_borrow_allowed<BorrowedCoinType, CollateralCoinType>(liquidator_addr, borrower, repay_amount);
        assert!(err == 0, err);

        assert!(borrower != liquidator_addr, ELIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER);

        assert!(repay_amount != 0, ELIQUIDATE_CLOSE_AMOUNT_IS_ZERO);

        repay_borrow<BorrowedCoinType>(liquidator, borrower, coin);

        let (amount_seize_error, seize_tokens) = market::liquidate_calculate_seize_tokens<BorrowedCoinType, CollateralCoinType>(repay_amount);
        assert!(amount_seize_error == 0, amount_seize_error);

        assert!(seize_tokens <= acoin::balance<CollateralCoinType>(borrower), ELIQUIDATE_SEIZE_TOO_MUCH);

        let acoin = seize<CollateralCoinType, BorrowedCoinType>(liquidator, borrower, seize_tokens);

        market::liquidate_borrow_verify<BorrowedCoinType, CollateralCoinType>(liquidator_addr, borrower, repay_amount, seize_tokens);

        acoin::emit_liquidate_borrow_event<BorrowedCoinType>(liquidator_addr, borrower, repay_amount, type_of<CollateralCoinType>(), seize_tokens);

        acoin
    }

    //
    // admin functions
    //

    public fun set_reserve_factor<CoinType>(admin: &signer, new_reserve_factor_mantissa: u128) {
        only_admin<CoinType>(admin);
        accrue_interest<CoinType>();
        assert!(new_reserve_factor_mantissa <= Reserve_Factor_Max_Mantissa(), ERESERVE_FACTOR_OUT_OF_BOUND);
        let old_reserve_factor_mantissa = acoin::reserve_factor_mantissa<CoinType>();
        acoin::set_reserve_factor_mantissa<CoinType>(new_reserve_factor_mantissa);
        acoin::emit_new_reserve_factor_event<CoinType>(old_reserve_factor_mantissa, new_reserve_factor_mantissa);
    }

    public fun add_reserves<CoinType>(account: &signer, coin: Coin<CoinType>) {
        accrue_interest<CoinType>();
        let add_amount = coin::value<CoinType>(&coin);
        acoin::deposit_to_treasury<CoinType>(coin);
        acoin::add_reserves<CoinType>((add_amount as u128));
        acoin::emit_reserves_added_event<CoinType>(signer::address_of(account), add_amount, acoin::total_reserves<CoinType>());
    }

    public fun reduce_reserves<CoinType>(admin: &signer, reduce_amount: u64) {
        only_admin<CoinType>(admin);
        let admin_addr = admin<CoinType>();
        accrue_interest<CoinType>();
        assert!(acoin::total_reserves<CoinType>() >= (reduce_amount as u128), EREDUCE_AMOUNT_TO_MUCH);
        assert!(acoin::get_cash<CoinType>() >= reduce_amount, ETOKEN_INSUFFICIENT_CASH);
        acoin::sub_reserves<CoinType>((reduce_amount as u128));
        let coin = acoin::withdraw_from_treasury<CoinType>(reduce_amount);
        coin::deposit<CoinType>(admin_addr, coin);
        acoin::emit_reserves_reduced_event<CoinType>(admin_addr, reduce_amount, acoin::total_reserves<CoinType>());
    }

    //
    // internal functions
    //

    fun only_admin<CoinType>(account: &signer) {
        assert!(signer::address_of(account) == admin<CoinType>(), ENOT_ADMIN);
    }

    fun seize<CollateralCoinType, BorrowedCoinType>(
        liquidator: &signer, 
        borrower: address, 
        seize_tokens: u64
    ): ACoin<CollateralCoinType> {
        let liquidator_addr = signer::address_of(liquidator);

        let err = market::seize_allowed<CollateralCoinType, BorrowedCoinType>(liquidator_addr, borrower, seize_tokens);
        assert!(err == 0, err); 

        assert!(borrower != liquidator_addr, ELIQUIDATE_SEIZE_LIQUIDATOR_IS_BORROWER);

        let acoin = acoin::withdraw<CollateralCoinType>(borrower, seize_tokens);

        market::seize_verify<CollateralCoinType, BorrowedCoinType>(liquidator_addr, borrower, seize_tokens);

        acoin
    }
}
