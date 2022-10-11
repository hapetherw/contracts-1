module abel::acoin {

    use std::error;
    use std::string;
    use std::signer;

    use aptos_std::type_info::TypeInfo;
    use aptos_std::event::{Self, EventHandle};

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::block;

    use abel::constants::{Mantissa_One};

    friend abel::acoin_lend;

    //
    // Errors.
    //
    const NO_ERROR: u64 = 0;
    const ECOIN_INFO_ADDRESS_MISMATCH: u64 = 1;
    const ECOIN_INFO_ALREADY_PUBLISHED: u64 = 2;
    const ECOIN_INFO_NOT_PUBLISHED: u64 = 3;
    const ECOIN_STORE_ALREADY_PUBLISHED: u64 = 4;
    const ECOIN_STORE_NOT_PUBLISHED: u64 = 5;
    const EINSUFFICIENT_BALANCE: u64 = 6;
    const EDESTRUCTION_OF_NONZERO_TOKEN: u64 = 7;
    const EZERO_COIN_AMOUNT: u64 = 9;
    const EFROZEN: u64 = 10;
    const ECOIN_SUPPLY_UPGRADE_NOT_SUPPORTED: u64 = 11;


    /// Events
    struct DepositEvent has drop, store {
        amount: u64,
    }

    struct WithdrawEvent has drop, store {
        amount: u64,
    }

    struct MintEvent has drop, store {
        minter: address,
        mint_amount: u64,
        mint_tokens: u64,
    }

    struct RedeemEvent has drop, store {
        redeemer: address,
        redeem_amount: u64,
        redeem_tokens: u64,
    }

    struct BorrowEvent has drop, store {
        borrower: address,
        borrow_amount: u64,
        account_borrows: u64,
        total_borrows: u128,
    }

    struct RepayBorrowEvent has drop, store {
        payer: address,
        borrower: address,
        repay_amount: u64,
        account_borrows: u64,
        total_borrows: u128,
    }

    struct LiquidateBorrowEvent has drop, store {
        liquidator: address,
        borrower: address,
        repay_amount: u64,
        ctoken_collateral: TypeInfo,
        seize_tokens: u64,
    }

    struct AccrueInterestEvent has drop, store {
        cash_prior: u64,
        interest_accumulated: u128,
        borrow_index: u128,
        total_borrows: u128,
    }

    struct NewReserveFactorEvent has drop, store {
        old_reserve_factor_mantissa: u128,
        new_reserve_factor_mantissa: u128,
    }

    struct ReservesAddedEvent has drop, store {
        benefactor: address,
        add_amount: u64,
        new_total_reserves: u128,
    }

    struct ReservesReducedEvent has drop, store {
        admin: address,
        reduce_amount: u64,
        new_total_reserves: u128,
    }

    /// Core data structures
    struct ACoin<phantom CoinType> has store {
        value: u64,
    }

    struct BorrowSnapshot has store, drop {
        principal: u64,
        interest_index: u128,
    }

    struct ACoinStore<phantom CoinType> has key {
        coin: ACoin<CoinType>,
        borrows: BorrowSnapshot,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
        mint_events: EventHandle<MintEvent>,
        redeem_events: EventHandle<RedeemEvent>,
        borrow_events: EventHandle<BorrowEvent>,
        repay_borrow_events: EventHandle<RepayBorrowEvent>,
        liquidate_borrow_events: EventHandle<LiquidateBorrowEvent>,
    }

    struct ACoinInfo<phantom CoinType> has key {
        name: string::String,
        symbol: string::String,
        decimals: u8,
        total_supply: u128,
        total_borrows: u128,
        total_reserves: u128,
        borrow_index: u128,
        accrual_block_number: u64,
        reserve_factor_mantissa: u128,
        initial_exchange_rate_mantissa: u128,
        treasury: Coin<CoinType>,
        accrue_interest_events: EventHandle<AccrueInterestEvent>,
        new_reserve_factor_events: EventHandle<NewReserveFactorEvent>,
        reserves_added_events: EventHandle<ReservesAddedEvent>,
        reserves_reduced_events: EventHandle<ReservesReducedEvent>,
    }

    //
    // getter functions
    //
    public fun balance<CoinType>(owner: address): u64 acquires ACoinStore {
        assert!(
            is_account_registered<CoinType>(owner),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );
        borrow_global<ACoinStore<CoinType>>(owner).coin.value
    }

    /// Returns `true` if `account_addr` is registered to receive `CoinType`.
    public fun is_account_registered<CoinType>(account_addr: address): bool {
        exists<ACoinStore<CoinType>>(account_addr)
    }

    /// Returns the `value` passed in `coin`.
    public fun value<CoinType>(coin: &ACoin<CoinType>): u64 {
        coin.value
    }

    fun acoin_address<CoinType>(): address {
        @abel
    }

    /// Returns `true` if the type `CoinType` is an initialized coin.
    public fun is_coin_initialized<CoinType>(): bool {
        exists<ACoinInfo<CoinType>>(acoin_address<CoinType>())
    }

    /// Returns the name of the coin.
    public fun name<CoinType>(): string::String acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).name
    }

    /// Returns the symbol of the coin, usually a shorter version of the name.
    public fun symbol<CoinType>(): string::String acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).symbol
    }

    /// Returns the number of decimals used to get its user representation.
    /// For example, if `decimals` equals `2`, a balance of `505` coins should
    /// be displayed to a user as `5.05` (`505 / 10 ** 2`).
    public fun decimals<CoinType>(): u8 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).decimals
    }

    public fun total_supply<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_supply
    }

    public fun total_borrows<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_borrows
    }

    public fun total_reserves<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_reserves
    }

    public fun borrow_index<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).borrow_index
    }

    public fun accrual_block_number<CoinType>(): u64 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).accrual_block_number
    }

    public fun reserve_factor_mantissa<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).reserve_factor_mantissa
    }

    public fun initial_exchange_rate_mantissa<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).initial_exchange_rate_mantissa
    }

    public fun get_cash<CoinType>(): u64 acquires ACoinInfo {
        coin::value<CoinType>(&borrow_global<ACoinInfo<CoinType>>(acoin_address<CoinType>()).treasury)
    }

    public fun borrow_principal<CoinType>(borrower: address): u64 acquires ACoinStore {
        borrow_global<ACoinStore<CoinType>>(borrower).borrows.principal
    }

    public fun borrow_interest_index<CoinType>(borrower: address): u128 acquires ACoinStore {
        borrow_global<ACoinStore<CoinType>>(borrower).borrows.interest_index
    }

    public fun borrow_balance<CoinType>(borrower: address): u64 acquires ACoinStore, ACoinInfo {
        assert!(
            is_account_registered<CoinType>(borrower),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );
        let principal = borrow_global<ACoinStore<CoinType>>(borrower).borrows.principal;
        let interest_index = borrow_global<ACoinStore<CoinType>>(borrower).borrows.interest_index;
        let global_interest_index = borrow_index<CoinType>();

        ((principal as u128) * global_interest_index / interest_index as u64)
    }

    // 
    // public functions 
    //

    public fun register<CoinType>(account: &signer) acquires ACoinInfo {
        let account_addr = signer::address_of(account);
        assert!(
            !is_account_registered<CoinType>(account_addr),
            error::already_exists(ECOIN_STORE_ALREADY_PUBLISHED),
        );

        let acoin_store = ACoinStore<CoinType> {
            coin: ACoin { value: 0 },
            borrows: BorrowSnapshot {
                principal: 0,
                interest_index: borrow_index<CoinType>(),
            },
            deposit_events: account::new_event_handle<DepositEvent>(account),
            withdraw_events: account::new_event_handle<WithdrawEvent>(account),
            mint_events: account::new_event_handle<MintEvent>(account),
            redeem_events: account::new_event_handle<RedeemEvent>(account),
            borrow_events: account::new_event_handle<BorrowEvent>(account),
            repay_borrow_events: account::new_event_handle<RepayBorrowEvent>(account),
            liquidate_borrow_events: account::new_event_handle<LiquidateBorrowEvent>(account),
        };
        move_to(account, acoin_store);
    }

    public fun zero<CoinType>(): ACoin<CoinType> {
        ACoin<CoinType> {
            value: 0
        }
    }

    public fun destroy_zero<CoinType>(zero_coin: ACoin<CoinType>) {
        let ACoin { value } = zero_coin;
        assert!(value == 0, error::invalid_argument(EDESTRUCTION_OF_NONZERO_TOKEN))
    }

    //
    // emit events
    //

    public(friend) fun emit_mint_event<CoinType>(
        minter: address,
        mint_amount: u64,
        mint_tokens: u64,
    ) acquires ACoinStore {
        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(minter);
        event::emit_event<MintEvent>(
            &mut coin_store.mint_events,
            MintEvent { 
                minter,
                mint_amount,
                mint_tokens,
            },
        );
    }

    public(friend) fun emit_redeem_event<CoinType>(
        redeemer: address,
        redeem_amount: u64,
        redeem_tokens: u64,
    ) acquires ACoinStore {
        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(redeemer);
        event::emit_event<RedeemEvent>(
            &mut coin_store.redeem_events,
            RedeemEvent { 
                redeemer,
                redeem_amount,
                redeem_tokens,
            },
        );
    }

    public(friend) fun emit_borrow_event<CoinType>(
        borrower: address,
        borrow_amount: u64,
        account_borrows: u64,
        total_borrows: u128,
    ) acquires ACoinStore {
        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(borrower);
        event::emit_event<BorrowEvent>(
            &mut coin_store.borrow_events,
            BorrowEvent { 
                borrower,
                borrow_amount,
                account_borrows,
                total_borrows,
            },
        );
    }

    public(friend) fun emit_repay_borrow_event<CoinType>(
        payer: address,
        borrower: address,
        repay_amount: u64,
        account_borrows: u64,
        total_borrows: u128,
    ) acquires ACoinStore {
        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(payer);
        event::emit_event<RepayBorrowEvent>(
            &mut coin_store.repay_borrow_events,
            RepayBorrowEvent { 
                payer,
                borrower,
                repay_amount,
                account_borrows,
                total_borrows,
            },
        );
    }

    public(friend) fun emit_liquidate_borrow_event<CoinType>(
        liquidator: address,
        borrower: address,
        repay_amount: u64,
        ctoken_collateral: TypeInfo,
        seize_tokens: u64,
    ) acquires ACoinStore {
        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(liquidator);
        event::emit_event<LiquidateBorrowEvent>(
            &mut coin_store.liquidate_borrow_events,
            LiquidateBorrowEvent { 
                liquidator,
                borrower,
                repay_amount,
                ctoken_collateral,
                seize_tokens,
            },
        );
    }

    public(friend) fun emit_accrue_interest_event<CoinType>(
        cash_prior: u64,
        interest_accumulated: u128,
        borrow_index: u128,
        total_borrows: u128,
    ) acquires ACoinInfo {
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>());
        event::emit_event<AccrueInterestEvent>(
            &mut coin_store.accrue_interest_events,
            AccrueInterestEvent { 
                cash_prior,
                interest_accumulated,
                borrow_index,
                total_borrows,
            },
        );
    }

    public(friend) fun emit_new_reserve_factor_event<CoinType>(
        old_reserve_factor_mantissa: u128,
        new_reserve_factor_mantissa: u128,
    ) acquires ACoinInfo {
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>());
        event::emit_event<NewReserveFactorEvent>(
            &mut coin_store.new_reserve_factor_events,
            NewReserveFactorEvent {
                old_reserve_factor_mantissa,
                new_reserve_factor_mantissa,
            },
        );
    }

    public(friend) fun emit_reserves_added_event<CoinType>(
        benefactor: address,
        add_amount: u64,
        new_total_reserves: u128,
    ) acquires ACoinInfo {
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>());
        event::emit_event<ReservesAddedEvent>(
            &mut coin_store.reserves_added_events,
            ReservesAddedEvent {
                benefactor,
                add_amount,
                new_total_reserves,
            },
        );
    }

    public(friend) fun emit_reserves_reduced_event<CoinType>(
        admin: address,
        reduce_amount: u64,
        new_total_reserves: u128,
    ) acquires ACoinInfo {
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>());
        event::emit_event<ReservesReducedEvent>(
            &mut coin_store.reserves_reduced_events,
            ReservesReducedEvent {
                admin,
                reduce_amount,
                new_total_reserves,
            },
        );
    }


    //
    // friend functions (only abel::acoin)
    //
    
    public(friend) fun initialize<CoinType>(
        account: &signer, 
        name: string::String,
        symbol: string::String,
        decimals: u8,
        initial_exchange_rate_mantissa: u128,
    ) {
        let account_addr = signer::address_of(account);

        assert!(
            acoin_address<CoinType>() == account_addr,
            error::invalid_argument(ECOIN_INFO_ADDRESS_MISMATCH),
        );

        assert!(
            !exists<ACoinInfo<CoinType>>(account_addr),
            error::already_exists(ECOIN_INFO_ALREADY_PUBLISHED),
        );

        let coin_info = ACoinInfo<CoinType> {
            name,
            symbol,
            decimals,
            total_supply: 0,
            total_borrows: 0,
            total_reserves: 0,
            borrow_index: Mantissa_One(),
            accrual_block_number: block::get_current_block_height(),
            reserve_factor_mantissa: 0,
            initial_exchange_rate_mantissa,
            treasury: coin::zero<CoinType>(),
            accrue_interest_events: account::new_event_handle<AccrueInterestEvent>(account),
            new_reserve_factor_events: account::new_event_handle<NewReserveFactorEvent>(account),
            reserves_added_events: account::new_event_handle<ReservesAddedEvent>(account),
            reserves_reduced_events: account::new_event_handle<ReservesReducedEvent>(account),
        };
        move_to(account, coin_info);
    }
    
    public(friend) fun withdraw<CoinType>(
        account_addr: address,
        amount: u64,
    ): ACoin<CoinType> acquires ACoinStore {
        assert!(
            is_account_registered<CoinType>(account_addr),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );

        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(account_addr);

        event::emit_event<WithdrawEvent>(
            &mut coin_store.withdraw_events,
            WithdrawEvent { amount },
        );

        let coin = &mut coin_store.coin;
        assert!(coin.value >= amount, error::invalid_argument(EINSUFFICIENT_BALANCE));
        coin.value = coin.value - amount;
        ACoin { value: amount }
    }

    public(friend) fun deposit<CoinType>(
        account_addr: address, 
        coin: ACoin<CoinType>,
    ) acquires ACoinStore {
        assert!(
            is_account_registered<CoinType>(account_addr),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );

        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(account_addr);

        event::emit_event<DepositEvent>(
            &mut coin_store.deposit_events,
            DepositEvent { amount: coin.value },
        );

        let dst_coin = &mut coin_store.coin;
        dst_coin.value = dst_coin.value + coin.value;
        let ACoin { value: _ } = coin;
    }

    public(friend) fun mint<CoinType>(amount: u64): ACoin<CoinType> {
        ACoin<CoinType> {
            value: amount
        }
    } 

    public(friend) fun burn<CoinType>(acoin: ACoin<CoinType>): u64 {
        let ACoin<CoinType> { value } = acoin;
        value
    }

    public(friend) fun update_account_borrows<CoinType>(borrower: address, principal: u64, interest_index: u128) acquires ACoinStore {
        borrow_global_mut<ACoinStore<CoinType>>(borrower).borrows = BorrowSnapshot{
            principal: principal,
            interest_index: interest_index,
        };
    }

    public(friend) fun add_supply<CoinType>(amount: u128) acquires ACoinInfo {
        let supply = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_supply;
        *supply = *supply + amount;
    }

    public(friend) fun sub_supply<CoinType>(amount: u128) acquires ACoinInfo {
        let supply = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_supply;
        *supply = *supply - amount;
    }

    public(friend) fun add_total_borrows<CoinType>(amount: u128) acquires ACoinInfo {
        let borrows = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_borrows;
        *borrows = *borrows + amount;
    }

    public(friend) fun sub_total_borrows<CoinType>(amount: u128) acquires ACoinInfo {
        let borrows = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_borrows;
        *borrows = *borrows - amount;
    }

    public(friend) fun add_reserves<CoinType>(amount: u128) acquires ACoinInfo {
        let reserves = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_reserves;
        *reserves = *reserves + amount;
    }

    public(friend) fun sub_reserves<CoinType>(amount: u128) acquires ACoinInfo {
        let reserves = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_reserves;
        *reserves = *reserves - amount;
    }

    public(friend) fun set_reserve_factor_mantissa<CoinType>(new_reserve_factor_mantissa: u128) acquires ACoinInfo {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).reserve_factor_mantissa = new_reserve_factor_mantissa;
    }

    public(friend) fun update_total_borrows<CoinType>(total_borrows_new: u128) acquires ACoinInfo {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_borrows = total_borrows_new;
    }

    public(friend) fun update_total_reserves<CoinType>(total_reserves_new: u128) acquires ACoinInfo {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).total_reserves = total_reserves_new;
    }

    public(friend) fun update_global_borrow_index<CoinType>(borrow_index_new: u128) acquires ACoinInfo {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).borrow_index = borrow_index_new;
    }

    public(friend) fun update_accrual_block_number<CoinType>() acquires ACoinInfo {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).accrual_block_number = block::get_current_block_height();
    }

    public(friend) fun deposit_to_treasury<CoinType>(coin: Coin<CoinType>) acquires ACoinInfo {
        let treasury_ref = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).treasury;
        coin::merge<CoinType>(treasury_ref, coin);
    }

    public(friend) fun withdraw_from_treasury<CoinType>(amount: u64): Coin<CoinType> acquires ACoinInfo {
        let treasury_ref = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address<CoinType>()).treasury;
        coin::extract<CoinType>(treasury_ref, amount)
    }

}