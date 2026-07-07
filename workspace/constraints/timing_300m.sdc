create_clock -name clk -period 3.333 [get_ports clk]
set_input_delay  0.500 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.500 -clock clk [all_outputs]
