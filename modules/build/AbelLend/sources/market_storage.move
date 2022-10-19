module abel::market_storage {

    use std::vector;
    use std::signer;
    use std::string::{Self, String};

    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::type_name;
    use aptos_std::event::{Self, EventHandle};

    use aptos_framework::account;

    use abel::constants::{Exp_Scale};

    friend abel::market;

    // errors
    const ENOT_ADMIN: u64 = 1;
    const EALREADY_APPROVED: u64 = 2;
    const EALREADY_LISTED: u64 = 3;
    const ENOT_APPROVED: u64 = 4;

    //
    // events
    //

    struct MarketListedEvent has drop, store {
        coin: String,
    } 

    struct MarketEnteredEvent has drop, store {
        coin: String,
        account: address,
    }

    struct MarketExitedEvent has drop, store {
        coin: String,
        account: address,
    }

    struct NewPauseGuardianEvent has drop, store {
        old_pause_guardian: address,
        new_pause_guardian: address,
    }

    struct GlobalActionPausedEvent has drop, store {
        action: String,
        pause_state: bool,
    }

    struct MarketActionPausedEvent has drop, store {
        coin: String,
        action: String,
        pause_state: bool,
    }

    struct NewCloseFactorEvent has drop, store {
        old_close_factor_mantissa: u128,
        new_close_factor_mantissa: u128,
    }

    struct NewCollateralFactorEvent has drop, store {
        coin: String,
        old_collateral_factor_mantissa: u128,
        new_collateral_factor_mantissa: u128,
    }

    struct NewLiquidationIncentiveEvent has drop, store {
        old_liquidation_incentive_mantissa: u128,
        new_liquidation_incentive_mantissa: u128,
    }

    //
    // structs
    //
    struct MarketInfo has store, copy, drop {
        collateral_factor_mantissa: u128,
    }

    struct GlobalConfig has key {
        all_markets: vector<String>,
        markets_info: Table<String, MarketInfo>,
        close_factor_mantissa: u128,
        liquidation_incentive_mantissa: u128,
        pause_guardian: address,
        mint_guardian_paused: bool,
        borrow_guardian_paused: bool,
        deposit_guardian_paused: bool,
        seize_guardian_paused: bool,
        market_listed_events: EventHandle<MarketListedEvent>,
        new_pause_guardian_events: EventHandle<NewPauseGuardianEvent>,
        global_action_paused_events: EventHandle<GlobalActionPausedEvent>,
        new_close_factor_events: EventHandle<NewCloseFactorEvent>,
        new_liquidation_incentive_events: EventHandle<NewLiquidationIncentiveEvent>,
    }

    struct MarketConfig<phantom CoinType> has key {
        is_approved: bool,
        is_listed: bool,
        is_abeled: bool,
        mint_guardian_paused: bool,
        borrow_guardian_paused: bool,
        market_action_paused_events: EventHandle<MarketActionPausedEvent>,
        new_collateral_factor_events: EventHandle<NewCollateralFactorEvent>,
    }

    struct UserStorage has key {
        account_assets: vector<String>,
        market_membership: Table<String, bool>,
        market_entered_events: EventHandle<MarketEnteredEvent>,
        market_exited_events: EventHandle<MarketExitedEvent>,
    }

    // 
    // getter functions
    //
    public fun admin(): address {
        @abel
    }

    public fun close_factor_mantissa(): u128 acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).close_factor_mantissa
    }

    public fun liquidation_incentive_mantissa(): u128 acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).liquidation_incentive_mantissa
    }

    public fun is_approved<CoinType>(): bool acquires MarketConfig {
        if (!exists<MarketConfig<CoinType>>(admin())) { return false };
        borrow_global<MarketConfig<CoinType>>(admin()).is_approved
    }

    public fun is_listed<CoinType>(): bool acquires MarketConfig {
        if (!exists<MarketConfig<CoinType>>(admin())) { return false };
        borrow_global<MarketConfig<CoinType>>(admin()).is_listed
    }

    public fun account_assets(account: address): vector<String> acquires UserStorage {
        borrow_global<UserStorage>(account).account_assets
    }

    public fun account_membership<CoinType>(account: address): bool acquires UserStorage {
        if (!exists<UserStorage>(account)) {
            return false
        };
        let coin_type = type_name<CoinType>();
        let membership_table_ref = &borrow_global<UserStorage>(account).market_membership;
        if (!table::contains<String, bool>(membership_table_ref, coin_type)) {
            false
        } else {
            *table::borrow(membership_table_ref, coin_type)
        }
    }

    public fun mint_guardian_paused<CoinType>(): bool acquires MarketConfig {
        borrow_global<MarketConfig<CoinType>>(admin()).mint_guardian_paused
    }

    public fun borrow_guardian_paused<CoinType>(): bool acquires MarketConfig {
        borrow_global<MarketConfig<CoinType>>(admin()).borrow_guardian_paused
    }

    public fun deposit_guardian_paused(): bool acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).deposit_guardian_paused
    }

    public fun seize_guardian_paused(): bool acquires GlobalConfig {
        borrow_global<GlobalConfig>(admin()).seize_guardian_paused
    }

    public fun collateral_factor_mantissa(coin_type: String): u128 acquires GlobalConfig {
        table::borrow(&borrow_global<GlobalConfig>(admin()).markets_info, coin_type).collateral_factor_mantissa
    }

    // init
    public entry fun init(admin: &signer) {
        assert!(signer::address_of(admin) == admin(), ENOT_ADMIN);
        move_to(admin, GlobalConfig {
            all_markets: vector::empty<String>(),
            markets_info: table::new<String, MarketInfo>(),
            close_factor_mantissa: 5 * Exp_Scale() / 10,
            liquidation_incentive_mantissa: 108 * Exp_Scale() / 100,
            pause_guardian: admin(),
            mint_guardian_paused: false,
            borrow_guardian_paused: false,
            deposit_guardian_paused: false,
            seize_guardian_paused: false,
            market_listed_events: account::new_event_handle<MarketListedEvent>(admin),
            new_pause_guardian_events: account::new_event_handle<NewPauseGuardianEvent>(admin),
            global_action_paused_events: account::new_event_handle<GlobalActionPausedEvent>(admin),  
            new_close_factor_events: account::new_event_handle<NewCloseFactorEvent>(admin),
            new_liquidation_incentive_events: account::new_event_handle<NewLiquidationIncentiveEvent>(admin),
        });
    }

    // 
    // friend functions (only market)
    //
    public(friend) fun approve_market<CoinType>(admin: &signer) acquires MarketConfig {
        assert!(signer::address_of(admin) == admin(), ENOT_ADMIN);
        assert!(!is_approved<CoinType>(), EALREADY_APPROVED);
        if (!exists<GlobalConfig>(admin())) {
            init(admin);
        };
        move_to(admin, MarketConfig<CoinType> {
            is_approved: true,
            is_listed: false,
            is_abeled: false,
            mint_guardian_paused: false,
            borrow_guardian_paused: false,
            market_action_paused_events: account::new_event_handle<MarketActionPausedEvent>(admin),
            new_collateral_factor_events: account::new_event_handle<NewCollateralFactorEvent>(admin),
        });
    }

    public(friend) fun support_market<CoinType>() acquires MarketConfig, GlobalConfig {
        assert!(is_approved<CoinType>(), ENOT_APPROVED);
        assert!(!is_listed<CoinType>(), EALREADY_LISTED);

        let coin_type = type_name<CoinType>();

        let market_config = borrow_global_mut<MarketConfig<CoinType>>(admin());
        market_config.is_listed = true;

        let global_status = borrow_global_mut<GlobalConfig>(admin());
        vector::push_back<String>(&mut global_status.all_markets, coin_type);
        table::add<String, MarketInfo>(&mut global_status.markets_info, coin_type, MarketInfo{
            collateral_factor_mantissa: 0,
        });

        event::emit_event<MarketListedEvent>(
            &mut global_status.market_listed_events,
            MarketListedEvent {
                coin: type_name<CoinType>(),
            },
        );
    }

    public(friend) fun enter_market<CoinType>(account: address) acquires UserStorage {
        let user_store = borrow_global_mut<UserStorage>(account);
        let coin_type = type_name<CoinType>();
        vector::push_back(&mut user_store.account_assets, coin_type);
        table::upsert(&mut user_store.market_membership, coin_type, true);
        event::emit_event<MarketEnteredEvent>(
            &mut user_store.market_entered_events,
            MarketEnteredEvent { 
                coin: coin_type,
                account, 
            },
        );
    }

    public(friend) fun exit_market<CoinType>(account: address) acquires UserStorage {
        let user_store = borrow_global_mut<UserStorage>(account);
        let coin_type = type_name<CoinType>();
        table::upsert(&mut user_store.market_membership, coin_type, false);
        let account_assets_list = user_store.account_assets;
        let len = vector::length(&account_assets_list);
        let index: u64 = 0;
        while (index < len) {
            if (*vector::borrow(&account_assets_list, index) == coin_type) {
                vector::swap_remove(&mut account_assets_list, index);
                break
            };
            index = index + 1;
        };
        event::emit_event<MarketExitedEvent>(
            &mut user_store.market_exited_events,
            MarketExitedEvent { 
                coin: coin_type,
                account, 
            },
        );
    }

    public(friend) fun set_close_factor(new_close_factor_mantissa: u128) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let old_close_factor_mantissa = global_status.close_factor_mantissa;
        global_status.close_factor_mantissa = new_close_factor_mantissa;
        event::emit_event<NewCloseFactorEvent>(
            &mut global_status.new_close_factor_events,
            NewCloseFactorEvent {
                old_close_factor_mantissa,
                new_close_factor_mantissa,
            },
        );
    }

    public(friend) fun set_collateral_factor<CoinType>(new_collateral_factor_mantissa: u128) acquires MarketConfig, GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let coin_type = type_name<CoinType>();
        let old_collateral_factor_mantissa = table::borrow(&global_status.markets_info, coin_type).collateral_factor_mantissa;

        table::borrow_mut<String, MarketInfo>(&mut global_status.markets_info, coin_type).collateral_factor_mantissa = new_collateral_factor_mantissa;

        let market_info = borrow_global_mut<MarketConfig<CoinType>>(admin());
        event::emit_event<NewCollateralFactorEvent>(
            &mut market_info.new_collateral_factor_events,
            NewCollateralFactorEvent { 
                coin: type_name<CoinType>(),
                old_collateral_factor_mantissa,
                new_collateral_factor_mantissa,
            },
        );
    }

    public(friend) fun set_liquidation_incentive(new_liquidation_incentive_mantissa: u128) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let old_liquidation_incentive_mantissa = global_status.liquidation_incentive_mantissa;
        global_status.liquidation_incentive_mantissa = new_liquidation_incentive_mantissa;
        event::emit_event<NewLiquidationIncentiveEvent>(
            &mut global_status.new_liquidation_incentive_events,
            NewLiquidationIncentiveEvent {
                old_liquidation_incentive_mantissa,
                new_liquidation_incentive_mantissa,
            },
        );
    }

    public(friend) fun set_pause_guardian(new_pause_guardian: address) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        let old_pause_guardian = global_status.pause_guardian;
        global_status.pause_guardian = new_pause_guardian;
        event::emit_event<NewPauseGuardianEvent>(
            &mut global_status.new_pause_guardian_events,
            NewPauseGuardianEvent { 
                old_pause_guardian,
                new_pause_guardian, 
            },
        );
    }

    public(friend) fun set_mint_paused<CoinType>(state: bool) acquires MarketConfig {
        let market_info = borrow_global_mut<MarketConfig<CoinType>>(admin());
        market_info.mint_guardian_paused = state;
        event::emit_event<MarketActionPausedEvent>(
            &mut market_info.market_action_paused_events,
            MarketActionPausedEvent { 
                coin: type_name<CoinType>(),
                action: string::utf8(b"Mint"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun set_borrow_paused<CoinType>(state: bool) acquires MarketConfig {
        let market_info = borrow_global_mut<MarketConfig<CoinType>>(admin());
        market_info.borrow_guardian_paused = state;
        event::emit_event<MarketActionPausedEvent>(
            &mut market_info.market_action_paused_events,
            MarketActionPausedEvent { 
                coin: type_name<CoinType>(),
                action: string::utf8(b"Borrow"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun set_deposit_paused(state: bool) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        global_status.deposit_guardian_paused = state;
        event::emit_event<GlobalActionPausedEvent>(
            &mut global_status.global_action_paused_events,
            GlobalActionPausedEvent { 
                action: string::utf8(b"Deposit"),
                pause_state: state, 
            },
        );
    }

    public(friend) fun set_seize_paused(state: bool) acquires GlobalConfig {
        let global_status = borrow_global_mut<GlobalConfig>(admin());
        global_status.seize_guardian_paused = state;
        event::emit_event<GlobalActionPausedEvent>(
            &mut global_status.global_action_paused_events,
            GlobalActionPausedEvent { 
                action: string::utf8(b"Seize"),
                pause_state: state, 
            },
        );
    }


}