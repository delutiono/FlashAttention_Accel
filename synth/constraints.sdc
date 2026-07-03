# Baseline timing environment for fa_accel_top Genus runs.
# The current baseline target is 5.000 ns (200 MHz). Keep this explicit in
# reports; tightening to 3.333 ns should be a separate PPA experiment.
set CLK_PERIOD_NS      5.000
set IO_DELAY_NS        0.500
set CLK_UNCERTAINTY_NS 0.200
set CLK_TRANSITION_NS  0.100
set OUT_LOAD_PF        0.020

create_clock -name clk -period $CLK_PERIOD_NS \
  -waveform [list 0.000 [expr {$CLK_PERIOD_NS / 2.0}]] [get_ports clk]

set_clock_uncertainty $CLK_UNCERTAINTY_NS [get_clocks clk]
set_clock_transition  $CLK_TRANSITION_NS  [get_clocks clk]

set input_ports  [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set output_ports [all_outputs]

set_input_delay  $IO_DELAY_NS -clock [get_clocks clk] $input_ports
set_output_delay $IO_DELAY_NS -clock [get_clocks clk] $output_ports

set_driving_cell -lib_cell sky130_fd_sc_hs__buf_4 $input_ports
set_load $OUT_LOAD_PF $output_ports

# rst_n is an asynchronous active-low reset in the RTL.
set_false_path -from [get_ports rst_n]
