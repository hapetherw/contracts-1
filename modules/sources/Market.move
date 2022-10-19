module abel::market {
    
    use std::vector;
    use std::signer;
    use std::string::{String};

    use aptos_std::type_info::type_name;

    use aptos_framework::aptos_coin::AptosCoin;

    use abel::market_storage as storage;
    use abel::acoin;
    use abel::oracle;
    use abel::constants::{Exp_Scale, Half_Scale};

    const ENONZERO_BORROW_BALANCE: u64 = 1;
    const EEXIT_MARKET_REJECTION: u64 = 2;
    const EMINT_PAUSED: u64 = 3;
    const EBORROW_PAUSED: u64 = 4;
    const EDEPOSIT_PAUSED: u64 = 5;
    const ESEIZE_PAUSED: u64 = 6;
    const ENOT_ADMIN: u64 = 7;

    // hook errors
    const NO_ERROR: u64 = 0;
    const EMARKET_NOT_LISTED: u64 = 101;
    const EINSUFFICIENT_LIQUIDITY: u64 = 102;
    const EREDEEM_TOKENS_ZERO: u64 = 103;
    const ENOT_MARKET_MEMBER: u64 = 104;
    const EPRICE_ERROR: u64 = 105;
    const EINSUFFICIENT_SHORTFALL: u64 = 106;
    const ETOO_MUCH_REPAY: u64 = 107;
    const EMARKET_NOT_APPROVED: u64 = 108;

    // enter/exit market
    public entry fun enter_market<CoinType>(account: &signer) {
        let account_addr = signer::address_of(account);

        // market not listed
        assert!(storage::is_listed<CoinType>(), EMARKET_NOT_LISTED);

        // already joined
        if (storage::account_membership<CoinType>(account_addr)) {
            return
        };

        storage::enter_market<CoinType>(account_addr);
    }
    public entry fun exit_market<CoinType>(account: &signer) {
        let account_addr = signer::address_of(account);
        let (tokens_held, amount_owed, _) = acoin::get_account_snapshot<CoinType>(account_addr);

        // Fail if the sender has a borrow balance 
        assert!(amount_owed == 0, ENONZERO_BORROW_BALANCE);

        // Fail if the sender is not permitted to redeem all of their tokens 
        assert!(withdraw_allowed_internal<CoinType>(account_addr, tokens_held) == NO_ERROR, EEXIT_MARKET_REJECTION );

        // already not in
        if (!storage::account_membership<CoinType>(account_addr)) {
            return
        };
        
        storage::exit_market<CoinType>(account_addr);
    }

    // getter functions


    // policy hooks
    public fun init_allowed<CoinType>(_initializer: address, _name: String, _symbol: String, _decimals: u8, _initial_exchange_rate_mantissa: u128): u64 {
        if (!storage::is_approved<CoinType>()) {
            return EMARKET_NOT_APPROVED
        };
        return NO_ERROR
    }
    public fun init_verify<CoinType>(_initializer: address, _name: String, _symbol: String, _decimals: u8, _initial_exchange_rate_mantissa: u128) {
        if (acoin::is_coin_initialized<CoinType>() && !storage::is_listed<CoinType>()) {
            market_listed<CoinType>();
        };
    }

    public fun mint_allowed<CoinType>(minter: address, _mint_amount: u64): u64 {
        assert!(!storage::mint_guardian_paused<CoinType>(), EMINT_PAUSED);

        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        update_abelcoin_supply_index<CoinType>();
        distribute_supplier_abelcoin<CoinType>(minter, false);

        NO_ERROR
    }
    public fun mint_verify<CoinType>(_minter: address, _mint_amount: u64, _mint_tokens: u64) {
        // currently nothing to do
    }

    public fun redeem_allowed<CoinType>(redeemer: address, redeem_tokens: u64): u64 {
        let allowed = withdraw_allowed_internal<CoinType>(redeemer, redeem_tokens);
        if (allowed != NO_ERROR) {
            return allowed
        };

        allowed = redeem_with_fund_allowed_internal<CoinType>(redeemer, redeem_tokens);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_abelcoin_supply_index<CoinType>();
        distribute_supplier_abelcoin<CoinType>(redeemer, false);

        NO_ERROR
    }
    public fun redeem_with_fund_allowed<CoinType>(redeemer: address, redeem_tokens: u64): u64 {
        let allowed = redeem_with_fund_allowed_internal<CoinType>(redeemer, redeem_tokens);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_abelcoin_supply_index<CoinType>();
        distribute_supplier_abelcoin<CoinType>(redeemer, false);

        NO_ERROR
    }
    public fun redeem_verify<CoinType>(_redeemer: address, redeem_amount: u64, redeem_tokens: u64) {
        assert!(redeem_tokens !=0 || redeem_amount == 0, EREDEEM_TOKENS_ZERO);
    }

    public fun borrow_allowed<CoinType>(borrower: address, borrow_amount: u64): u64 {
        assert!(!storage::borrow_guardian_paused<CoinType>(), EBORROW_PAUSED);

        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        if (!storage::account_membership<CoinType>(borrower)) {
            return ENOT_MARKET_MEMBER
        };

        if (oracle::get_underlying_price<CoinType>() == 0) {
            return EPRICE_ERROR
        };

        let (_, shortfall) = get_hypothetical_account_liquidity_internal<CoinType>(borrower, 0, borrow_amount);
        if (shortfall > 0) {
            return EINSUFFICIENT_LIQUIDITY
        };
        
        let borrow_index = acoin::borrow_index<CoinType>();
        update_abelcoin_borrow_index<CoinType>(borrow_index);
        distribute_borrower_abelcoin<CoinType>(borrower, borrow_index, false);

        NO_ERROR
    }
    public fun borrow_verify<CoinType>(_borrower: address, _borrow_amount: u64) {
        // currently nothing to do
    }

    public fun repay_borrow_allowed<CoinType>(_payer: address, borrower: address, _repay_amount: u64): u64 {
        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        let borrow_index = acoin::borrow_index<CoinType>();
        update_abelcoin_borrow_index<CoinType>(borrow_index);
        distribute_borrower_abelcoin<CoinType>(borrower, borrow_index, false);

        NO_ERROR
    }
    public fun repay_borrow_verify<CoinType>(_payer: address, _borrower: address, _repay_amount: u64, _borrower_index: u128) {
        // currently nothing to do
    }

    public fun liquidate_borrow_allowed<BorrowedCoinType, CollateralCoinType>(_liquidator: address, borrower: address, repay_amount: u64): u64 {
        if (!storage::is_listed<BorrowedCoinType>() || !storage::is_listed<CollateralCoinType>()) {
            return EMARKET_NOT_LISTED
        };

        let (_, shortfall) = get_account_liquidity_internal(borrower);
        if (shortfall == 0) {
            return EINSUFFICIENT_SHORTFALL
        };

        let borrow_balance = acoin::borrow_balance<BorrowedCoinType>(borrower);
        let max_close = storage::close_factor_mantissa() * (borrow_balance as u128) / Exp_Scale();
        if ((repay_amount as u128) > max_close) {
            return ETOO_MUCH_REPAY
        };

        NO_ERROR
    }
    public fun liquidate_borrow_verify<BorrowedCoinType, CollateralCoinType>(_liquidator: address, _borrower: address, _repay_amount: u64, _seize_tokens: u64) {
        // currently nothing to do
    }

    public fun seize_allowed<CollateralCoinType, BorrowedCoinType>(liquidator: address, borrower: address, _seize_tokens: u64): u64 {
        assert!(!storage::seize_guardian_paused(), ESEIZE_PAUSED);

        if (!storage::is_listed<BorrowedCoinType>() || !storage::is_listed<CollateralCoinType>()) {
            return EMARKET_NOT_LISTED
        };

        update_abelcoin_supply_index<CollateralCoinType>();
        distribute_supplier_abelcoin<CollateralCoinType>(borrower, false);
        distribute_supplier_abelcoin<CollateralCoinType>(liquidator, false);

        NO_ERROR
    }
    public fun seize_verify<CollateralCoinType, BorrowedCoinType>(_liquidator: address, _borrower: address, _seize_tokens: u64) {
        // currently nothing to do
    }

    public fun withdraw_allowed<CoinType>(src: address, amount: u64): u64 {
        let allowed = withdraw_allowed_internal<CoinType>(src, amount);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_abelcoin_supply_index<CoinType>();
        distribute_supplier_abelcoin<CoinType>(src, false);

        NO_ERROR
    }
    public fun withdraw_verify<CoinType>(_src: address, _amount: u64) {
        // currently nothing to do
    }

    public fun deposit_allowed<CoinType>(dst: address, amount: u64): u64 {
        let allowed = deposit_allowed_internal<CoinType>(dst, amount);
        if (allowed != NO_ERROR) {
            return allowed
        };

        update_abelcoin_supply_index<CoinType>();
        distribute_supplier_abelcoin<CoinType>(dst, false);

        NO_ERROR
    }
    public fun deposit_verify<CoinType>(_dst: address, _amount: u64) {
        // currently nothing to do
    }

    public fun liquidate_calculate_seize_tokens<BorrowedCoinType, CollateralCoinType>(repay_amount: u64): u64 {
        let price_borrowed_mantissa = oracle::get_underlying_price<BorrowedCoinType>();
        let price_collateral_mantissa = oracle::get_underlying_price<CollateralCoinType>();
        let exchange_rate_mantissa = acoin::exchange_rate_mantissa<CollateralCoinType>();
        let liquidation_incentive_mantissa = storage::liquidation_incentive_mantissa();
        let numerator = liquidation_incentive_mantissa * price_borrowed_mantissa;
        let denominator = price_collateral_mantissa * exchange_rate_mantissa;
        let ratio = numerator / denominator;
        (ratio * (repay_amount as u128) / Exp_Scale() as u64)
    }

    // internal functions
    
    fun update_abelcoin_supply_index<CoinType>() {}
    fun distribute_supplier_abelcoin<CoinType>(supplier: address, distribute_all: bool) {}

    fun update_abelcoin_borrow_index<CoinType>(market_borrow_index: u128) {}
    fun distribute_borrower_abelcoin<CoinType>(borrower: address, market_borrow_index: u128, distribute_all: bool) {}

    fun get_account_liquidity_internal(account: address): (u64, u64) {
        get_hypothetical_account_liquidity_internal<AptosCoin>(account, 0, 0)
    }
    fun get_hypothetical_account_liquidity_internal<ModifyCoinType>(account: address, redeem_tokens: u64, borrow_amount: u64): (u64, u64) {
        let assets = storage::account_assets(account);
        let index = vector::length<String>(&assets);
        let modify_coin_type = type_name<ModifyCoinType>();
        let sum_collateral: u128 = 0;
        let sum_borrow_plus_effects: u128 = 0;
        while (index > 0) {
            index = index - 1;
            let asset = *vector::borrow<String>(&assets, index);
            let (acoin_balance, borrow_balance, exchange_rate_mantissa) = acoin::get_account_snapshot_no_type_args(asset, account);
            let collateral_factor_mantissa = storage::collateral_factor_mantissa(asset);
            let oracle_price_mantissa = oracle::get_underlying_price_no_type_args(asset);
            let tokens_to_denom = mulExp(mulExp(collateral_factor_mantissa, exchange_rate_mantissa), oracle_price_mantissa);
            sum_collateral = sum_collateral + tokens_to_denom * (acoin_balance as u128) / Exp_Scale();
            sum_borrow_plus_effects = sum_borrow_plus_effects + oracle_price_mantissa * (borrow_balance as u128) / Exp_Scale();
            if (asset == modify_coin_type) {
                sum_borrow_plus_effects = sum_borrow_plus_effects + tokens_to_denom * (redeem_tokens as u128) / Exp_Scale();
                sum_borrow_plus_effects = sum_borrow_plus_effects + oracle_price_mantissa * (borrow_amount as u128) / Exp_Scale();
            };
        };
        if (sum_collateral > sum_borrow_plus_effects) {
            ((sum_collateral - sum_borrow_plus_effects as u64), 0)
        } else {
            (0, (sum_borrow_plus_effects - sum_collateral as u64))
        }
    }
    fun mulExp(a: u128, b: u128): u128 {
        (a * b + Half_Scale())/Exp_Scale()
    }

    fun redeem_with_fund_allowed_internal<CoinType>(_redeemer: address, _redeem_tokens: u64): u64 {
        if (!storage::is_listed<CoinType>()) {
            return EMARKET_NOT_LISTED
        };

        NO_ERROR
    }
    fun withdraw_allowed_internal<CoinType>(src: address, amount: u64): u64 {
        // If the src is not 'in' the market, then we can bypass the liquidity check 
        if (!storage::account_membership<CoinType>(src)) {
            return NO_ERROR
        };

        let (_, shortfall) = get_hypothetical_account_liquidity_internal<CoinType>(src, amount, 0);
        if (shortfall > 0) {
            return EINSUFFICIENT_LIQUIDITY
        };

        NO_ERROR
    }
    fun deposit_allowed_internal<CoinType>(_dst: address, _amount: u64): u64 {
        assert!(!storage::deposit_guardian_paused(), EDEPOSIT_PAUSED);

        NO_ERROR
    } 

    fun market_listed<CoinType>() {
        storage::support_market<CoinType>();
    } 

    // admin functions
    fun only_admin(account: &signer) {
        assert!(signer::address_of(account) == storage::admin(), ENOT_ADMIN);
    }

    public entry fun set_close_factor(admin: &signer, new_close_factor_mantissa: u128) {
        only_admin(admin);
        storage::set_close_factor(new_close_factor_mantissa);
    }

    public entry fun set_collateral_factor<CoinType>(admin: &signer, new_collateral_factor_mantissa: u128) {
        only_admin(admin);
        assert!(!storage::is_listed<CoinType>(), EMARKET_NOT_LISTED);
        storage::set_collateral_factor<CoinType>(new_collateral_factor_mantissa);
    }

    public entry fun set_liquidation_incentive(admin: &signer, new_liquidation_incentive_mantissa: u128) {
        only_admin(admin);
        storage::set_liquidation_incentive(new_liquidation_incentive_mantissa);
    }

    public entry fun approve_market<CoinType>(admin: &signer) {
        only_admin(admin);
        storage::approve_market<CoinType>(admin);
    }   
}