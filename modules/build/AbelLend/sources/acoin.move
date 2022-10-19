module abel::acoin {

    use std::error;
    use std::string::{Self, String};
    use std::signer;

    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::{type_name, TypeInfo};
    use aptos_std::event::{Self, EventHandle};

    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::block;

    use abel::constants::{Exp_Scale, Mantissa_One};

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
    const EACOIN_NOT_REGISTERED_BY_USER: u64 = 12;


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

    struct ACoinUserSnapshot has store, drop {
        balance: u64,
        borrow_principal: u64,
        interest_index: u128,
    }

    struct AccountSnapshotTable has key {
        account_snapshots: Table<String, ACoinUserSnapshot>,
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

    struct ACoinGlobalSnapshot has store, drop {
        total_supply: u128,
        total_borrows: u128,
        total_reserves: u128,
        borrow_index: u128,
        accrual_block_number: u64,
        reserve_factor_mantissa: u128,
        initial_exchange_rate_mantissa: u128,
        treasury_balance: u64,
    }

    struct GlobalSnapshotTable has key {
        snapshots: Table<String, ACoinGlobalSnapshot>,
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

    /// Returns the `value` passed in `coin`.
    public fun value<CoinType>(coin: &ACoin<CoinType>): u64 {
        coin.value
    }

    public fun balance<CoinType>(owner: address): u64 acquires ACoinStore {
        assert!(
            is_account_registered<CoinType>(owner),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );
        borrow_global<ACoinStore<CoinType>>(owner).coin.value
    }

    public fun acoin_address(): address {
        @abel
    }

    /// Returns `true` if `account_addr` is registered to receive `CoinType`.
    public fun is_account_registered<CoinType>(account_addr: address): bool {
        exists<ACoinStore<CoinType>>(account_addr)
    }

    /// Returns `true` if the type `CoinType` is an initialized coin.
    public fun is_coin_initialized<CoinType>(): bool {
        exists<ACoinInfo<CoinType>>(acoin_address())
    }

    /// Returns the name of the coin.
    public fun name<CoinType>(): string::String acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).name
    }

    /// Returns the symbol of the coin, usually a shorter version of the name.
    public fun symbol<CoinType>(): string::String acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).symbol
    }

    /// Returns the number of decimals used to get its user representation.
    /// For example, if `decimals` equals `2`, a balance of `505` coins should
    /// be displayed to a user as `5.05` (`505 / 10 ** 2`).
    public fun decimals<CoinType>(): u8 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).decimals
    }

    public fun total_supply<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).total_supply
    }

    public fun total_borrows<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).total_borrows
    }

    public fun total_reserves<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).total_reserves
    }

    public fun borrow_index<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).borrow_index
    }

    public fun accrual_block_number<CoinType>(): u64 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).accrual_block_number
    }

    public fun reserve_factor_mantissa<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).reserve_factor_mantissa
    }

    public fun initial_exchange_rate_mantissa<CoinType>(): u128 acquires ACoinInfo {
        borrow_global<ACoinInfo<CoinType>>(acoin_address()).initial_exchange_rate_mantissa
    }

    public fun get_cash<CoinType>(): u64 acquires ACoinInfo {
        coin::value<CoinType>(&borrow_global<ACoinInfo<CoinType>>(acoin_address()).treasury)
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

    // return (acoin_balance, borrow_balance, exchange_rate_mantissa)
    public fun get_account_snapshot<CoinType>(account: address): (u64, u64, u128) acquires ACoinStore, ACoinInfo {
        (balance<CoinType>(account), borrow_balance<CoinType>(account), exchange_rate_mantissa<CoinType>())
    }
    public fun get_account_snapshot_no_type_args(coin_type: String, account: address): (u64, u64, u128) acquires AccountSnapshotTable, GlobalSnapshotTable {
        // get account snapshot
        let account_snapshots_ref = &borrow_global<AccountSnapshotTable>(account).account_snapshots;
        assert!(table::contains<String, ACoinUserSnapshot>(account_snapshots_ref, coin_type), EACOIN_NOT_REGISTERED_BY_USER);
        let acoin_snapshot_ref = table::borrow<String, ACoinUserSnapshot>(account_snapshots_ref, coin_type);
        let acoin_balance = acoin_snapshot_ref.balance;
        let principal = acoin_snapshot_ref.borrow_principal;
        let interest_index = acoin_snapshot_ref.interest_index; 
        // get acoin global snapshot
        let acoin_global_snapshot_ref = table::borrow<String, ACoinGlobalSnapshot>(&borrow_global<GlobalSnapshotTable>(acoin_address()).snapshots, coin_type);
        // get borrow balance
        let global_interest_index = acoin_global_snapshot_ref.borrow_index;
        let borrow_balance = ((principal as u128) * global_interest_index / interest_index as u64);
        // get exchange_rate_mantissa
        let total_supply = acoin_global_snapshot_ref.total_supply;
        let exchange_rate_mantissa: u128;
        if (total_supply == 0) {
            exchange_rate_mantissa = acoin_global_snapshot_ref.initial_exchange_rate_mantissa;
        } else {
            let total_borrows = acoin_global_snapshot_ref.total_borrows;
            let total_reserves = acoin_global_snapshot_ref.total_reserves;
            let total_cash = acoin_global_snapshot_ref.treasury_balance;
            let cash_plus_borrows_minus_reserves = (total_cash as u128) + total_borrows - total_reserves;
            exchange_rate_mantissa = cash_plus_borrows_minus_reserves * Exp_Scale() / total_supply;
        };
        (acoin_balance, borrow_balance, exchange_rate_mantissa)
    }

    public fun exchange_rate_mantissa<CoinType>(): u128 acquires ACoinInfo {
        let supply = total_supply<CoinType>();
        if (supply == 0) {
            initial_exchange_rate_mantissa<CoinType>()
        } else {
            let supply = total_supply<CoinType>();
            let total_cash = (get_cash<CoinType>() as u128);
            let total_borrows = total_borrows<CoinType>();
            let total_reserves = total_reserves<CoinType>();
            let cash_plus_borrows_minus_reserves = total_cash + total_borrows - total_reserves;
            cash_plus_borrows_minus_reserves * Exp_Scale() / supply
        }
    }

    // 
    // public functions 
    //

    public fun register<CoinType>(account: &signer) acquires AccountSnapshotTable, ACoinInfo {
        let account_addr = signer::address_of(account);
        assert!(
            !is_account_registered<CoinType>(account_addr),
            error::already_exists(ECOIN_STORE_ALREADY_PUBLISHED),
        );

        if (!exists<AccountSnapshotTable>(account_addr)) {
            move_to(account, AccountSnapshotTable{ account_snapshots: table::new<String, ACoinUserSnapshot>() });
        };

        // update snapshot
        let account_snapshots_ref = &mut borrow_global_mut<AccountSnapshotTable>(account_addr).account_snapshots;
        table::add(account_snapshots_ref, type_name<CoinType>(), ACoinUserSnapshot{
            balance: 0,
            borrow_principal: 0,
            interest_index: borrow_index<CoinType>(),
        });

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
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address());
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
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address());
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
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address());
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
        let coin_store = borrow_global_mut<ACoinInfo<CoinType>>(acoin_address());
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
    ) acquires GlobalSnapshotTable {
        let account_addr = signer::address_of(account);

        assert!(
            acoin_address() == account_addr,
            error::invalid_argument(ECOIN_INFO_ADDRESS_MISMATCH),
        );

        assert!(
            !exists<ACoinInfo<CoinType>>(account_addr),
            error::already_exists(ECOIN_INFO_ALREADY_PUBLISHED),
        );

        if (!exists<GlobalSnapshotTable>(account_addr)) {
            move_to(account, GlobalSnapshotTable{ snapshots: table::new<String, ACoinGlobalSnapshot>() });
        };

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(account_addr).snapshots;
        table::add<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>(), ACoinGlobalSnapshot{
            total_supply: 0,
            total_borrows: 0,
            total_reserves: 0,
            borrow_index: Mantissa_One(),
            accrual_block_number: block::get_current_block_height(),
            reserve_factor_mantissa: 0,
            initial_exchange_rate_mantissa,
            treasury_balance: 0,
        });

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
    ): ACoin<CoinType> acquires ACoinStore, AccountSnapshotTable {
        assert!(
            is_account_registered<CoinType>(account_addr),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );


        let coin_store = borrow_global_mut<ACoinStore<CoinType>>(account_addr);

        event::emit_event<WithdrawEvent>(
            &mut coin_store.withdraw_events,
            WithdrawEvent { amount },
        );

        let src_coin = &mut coin_store.coin;
        assert!(src_coin.value >= amount, error::invalid_argument(EINSUFFICIENT_BALANCE));
        src_coin.value = src_coin.value - amount;   

        // update account snapshot
        let snapshots_ref = &mut borrow_global_mut<AccountSnapshotTable>(account_addr).account_snapshots;
        table::borrow_mut<String, ACoinUserSnapshot>(snapshots_ref, type_name<CoinType>()).balance = src_coin.value;

        ACoin { value: amount }
    }

    public(friend) fun deposit<CoinType>(
        account_addr: address, 
        coin: ACoin<CoinType>,
    ) acquires ACoinStore, AccountSnapshotTable {
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

        // update account snapshot
        let snapshots_ref = &mut borrow_global_mut<AccountSnapshotTable>(account_addr).account_snapshots;
        table::borrow_mut<String, ACoinUserSnapshot>(snapshots_ref, type_name<CoinType>()).balance = dst_coin.value;
    }

    public(friend) fun mint<CoinType>(amount: u64): ACoin<CoinType> acquires ACoinInfo, GlobalSnapshotTable {
        // add total supply
        let supply = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_supply;
        *supply = *supply + (amount as u128);

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_supply = *supply;

        ACoin<CoinType> {
            value: amount
        }
    } 

    public(friend) fun burn<CoinType>(acoin: ACoin<CoinType>): u64 acquires ACoinInfo, GlobalSnapshotTable {
        let ACoin<CoinType> { value } = acoin;

        // sub total supply
        let supply = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_supply;
        *supply = *supply - (value as u128);

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_supply = *supply;

        value
    }

    public(friend) fun update_account_borrows<CoinType>(borrower: address, principal: u64, interest_index: u128) acquires ACoinStore, AccountSnapshotTable {
        borrow_global_mut<ACoinStore<CoinType>>(borrower).borrows = BorrowSnapshot{
            principal: principal,
            interest_index: interest_index,
        };

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<AccountSnapshotTable>(borrower).account_snapshots;
        let snapshot_ref = table::borrow_mut<String, ACoinUserSnapshot>(snapshots_ref, type_name<CoinType>());
        snapshot_ref.borrow_principal = principal;
        snapshot_ref.interest_index = interest_index;
    }

    public(friend) fun add_total_borrows<CoinType>(amount: u128) acquires ACoinInfo, GlobalSnapshotTable {
        let borrows = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_borrows;
        *borrows = *borrows + amount;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_borrows = *borrows;
    }

    public(friend) fun sub_total_borrows<CoinType>(amount: u128) acquires ACoinInfo, GlobalSnapshotTable {
        let borrows = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_borrows;
        *borrows = *borrows - amount;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_borrows = *borrows;
    }

    public(friend) fun add_reserves<CoinType>(amount: u128) acquires ACoinInfo, GlobalSnapshotTable {
        let reserves = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_reserves;
        *reserves = *reserves + amount;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_reserves = *reserves;
    }

    public(friend) fun sub_reserves<CoinType>(amount: u128) acquires ACoinInfo, GlobalSnapshotTable {
        let reserves = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_reserves;
        *reserves = *reserves - amount;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_reserves = *reserves;
    }

    public(friend) fun set_reserve_factor_mantissa<CoinType>(new_reserve_factor_mantissa: u128) acquires ACoinInfo, GlobalSnapshotTable {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).reserve_factor_mantissa = new_reserve_factor_mantissa;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).reserve_factor_mantissa = new_reserve_factor_mantissa;
    }

    public(friend) fun update_total_borrows<CoinType>(total_borrows_new: u128) acquires ACoinInfo, GlobalSnapshotTable {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_borrows = total_borrows_new;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_borrows = total_borrows_new;
    }

    public(friend) fun update_total_reserves<CoinType>(total_reserves_new: u128) acquires ACoinInfo, GlobalSnapshotTable {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).total_reserves = total_reserves_new;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).total_reserves = total_reserves_new;
    }

    public(friend) fun update_global_borrow_index<CoinType>(borrow_index_new: u128) acquires ACoinInfo, GlobalSnapshotTable {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).borrow_index = borrow_index_new;

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).borrow_index = borrow_index_new;
    }

    public(friend) fun update_accrual_block_number<CoinType>() acquires ACoinInfo, GlobalSnapshotTable {
        borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).accrual_block_number = block::get_current_block_height();

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).accrual_block_number = block::get_current_block_height();
    }

    public(friend) fun deposit_to_treasury<CoinType>(coin: Coin<CoinType>) acquires ACoinInfo, GlobalSnapshotTable {
        let treasury_ref = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).treasury;

        coin::merge<CoinType>(treasury_ref, coin);

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).treasury_balance = coin::value<CoinType>(treasury_ref);
    }

    public(friend) fun withdraw_from_treasury<CoinType>(amount: u64): Coin<CoinType> acquires ACoinInfo, GlobalSnapshotTable {
        let treasury_ref = &mut borrow_global_mut<ACoinInfo<CoinType>>(acoin_address()).treasury;

        let withdrawn_coin = coin::extract<CoinType>(treasury_ref, amount);

        // update snapshot
        let snapshots_ref = &mut borrow_global_mut<GlobalSnapshotTable>(acoin_address()).snapshots;
        table::borrow_mut<String, ACoinGlobalSnapshot>(snapshots_ref, type_name<CoinType>()).treasury_balance = coin::value<CoinType>(treasury_ref);

        withdrawn_coin
    }

}