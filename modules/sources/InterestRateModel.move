module abel::interest_rate_module {

    use std::signer;

    use aptos_std::event::{Self, EventHandle};

    use aptos_framework::account;

    use abel::constants::{Exp_Scale};

    const ENOT_INIT: u64 = 1;
    const ENOT_ADMIN: u64 = 2;

    struct NewInterestParamsEvents has drop, store {
        base_rate_per_block: u128,
        multiplier_per_block: u128,
        jump_multiplier_per_block: u128,
        kink: u128,
    }

    struct InterestParams has key {
        base_rate_per_block: u128,
        multiplier_per_block: u128,
        jump_multiplier_per_block: u128,
        kink: u128,
        new_interest_params_events: EventHandle<NewInterestParamsEvents>,
    }

    public fun admin():address {
        @abel
    }

    public fun is_init(): bool {
        exists<InterestParams>(admin())
    } 

    public fun base_rate_per_block(): u128 acquires InterestParams {
        borrow_global<InterestParams>(admin()).base_rate_per_block
    }

    public fun multiplier_per_block(): u128 acquires InterestParams {
        borrow_global<InterestParams>(admin()).multiplier_per_block
    }

    public fun jump_multiplier_per_block(): u128 acquires InterestParams {
        borrow_global<InterestParams>(admin()).jump_multiplier_per_block
    }

    public fun kink(): u128 acquires InterestParams {
        borrow_global<InterestParams>(admin()).kink
    }

    public entry fun set(
        admin: &signer,
        base_rate_per_block: u128,
        multiplier_per_block: u128,
        jump_multiplier_per_block: u128,
        kink: u128,
    ) acquires InterestParams {
        assert!(signer::address_of(admin) == admin(), ENOT_ADMIN);
        if (!is_init()) {
            move_to(admin, InterestParams {
                base_rate_per_block,
                multiplier_per_block,
                jump_multiplier_per_block,
                kink,
                new_interest_params_events: account::new_event_handle<NewInterestParamsEvents>(admin),
            });
        } else {
            let params = borrow_global_mut<InterestParams>(admin());
            params.base_rate_per_block = base_rate_per_block;
            params.multiplier_per_block = multiplier_per_block;
            params.jump_multiplier_per_block = jump_multiplier_per_block;
            params.kink = kink;
        };
        let params = borrow_global_mut<InterestParams>(admin());
        event::emit_event<NewInterestParamsEvents>(
            &mut params.new_interest_params_events,
            NewInterestParamsEvents {
                base_rate_per_block,
                multiplier_per_block,
                jump_multiplier_per_block,
                kink,
            },
        );
    }

    public fun utilization_rate(
        cash: u128,
        borrows: u128,
        reserves: u128,
    ): u128 {
        if (borrows == 0) {
            0
        } else {
            borrows * Exp_Scale() / (cash + borrows + reserves)
        }
    }

    public fun get_borrow_rate(
        cash: u128,
        borrows: u128,
        reserves: u128,
    ): u128 acquires InterestParams {
        assert!(is_init(), ENOT_INIT);
        let util = utilization_rate(cash, borrows, reserves);
        if (util <= kink()) {
            util * multiplier_per_block() / Exp_Scale() + base_rate_per_block()
        } else {
            let normal_rate = kink() * multiplier_per_block() / Exp_Scale() + base_rate_per_block();
            let excess_util = util - kink();
            excess_util * jump_multiplier_per_block() / Exp_Scale() + normal_rate
        }
    }

    public fun get_supply_rate(
        cash: u128,
        borrows: u128,
        reserves: u128,
        reserve_factor_mantissa: u128,
    ): u128 acquires InterestParams {
        assert!(is_init(), ENOT_INIT);
        let one_minus_reserve_factor = Exp_Scale() - reserve_factor_mantissa;
        let borrow_rate = get_borrow_rate(cash, borrows, reserves);
        let rate_to_pool = borrow_rate * one_minus_reserve_factor / Exp_Scale();
        utilization_rate(cash, borrows, reserves) * rate_to_pool / Exp_Scale()
    }
}