module abel::constants {

    public fun Exp_Scale(): u128 { 100000000 }
    public fun Mantissa_One(): u128 { Exp_Scale() }
    public fun Borrow_Rate_Max_Mantissa(): u128 { 5 * Exp_Scale() / 1000000 } // (.0005% / block)
    public fun Reserve_Factor_Max_Mantissa(): u128 { Exp_Scale() }

}