create_clock -name clk -period 5.000 [get_ports clk]
set_clock_uncertainty 0.150 [get_clocks clk]
set_clock_transition 0.300 [get_clocks clk]

set data_inputs [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay -max 1.000 -clock [get_clocks clk] $data_inputs
set_input_delay -min 0.200 -clock [get_clocks clk] $data_inputs
set_output_delay -max 1.000 -clock [get_clocks clk] [all_outputs]
set_output_delay -min 0.200 -clock [get_clocks clk] [all_outputs]

set_false_path -from [get_ports rst_n]
set_load 0.050 [all_outputs]
