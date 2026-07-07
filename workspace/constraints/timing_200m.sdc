create_clock -name clk -period 3.333 [get_ports clk]
set_input_delay  0.500 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.500 -clock clk [all_outputs]

# Multiplier 2-cycle paths: 48x17 (acc_mul, l_product) and 16x17 (v_mul)
# Multiplier inputs are registered, giving the multiplier 2 full cycles to complete
set_multicycle_path -setup 2 -to [get_pins u_core_u_update/acc_mul_reg_reg*/D]
set_multicycle_path -hold   1 -to [get_pins u_core_u_update/acc_mul_reg_reg*/D]
set_multicycle_path -setup 2 -to [get_pins u_core_u_update/v_mul_reg_reg*/D]
set_multicycle_path -hold   1 -to [get_pins u_core_u_update/v_mul_reg_reg*/D]
set_multicycle_path -setup 2 -to [get_pins u_core_u_update/l_product_reg_reg*/D]
set_multicycle_path -hold   1 -to [get_pins u_core_u_update/l_product_reg_reg*/D]
