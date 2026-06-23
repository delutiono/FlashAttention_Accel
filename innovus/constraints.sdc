# SDC constraints for fa_accel_top physical synthesis
# Target: sky130 HS, TT corner, 25°C, 1.80V

# Clock definition — target 200 MHz (5 ns period)
create_clock -name clk -period 5.0 [get_ports clk]

# Clock uncertainty (jitter + skew margin) — 150ps for 130nm
set_clock_uncertainty 0.15 [get_clocks clk]

# Clock transition — 300ps (relaxed for 130nm HS)
set_clock_transition 0.3 [get_clocks clk]

# Input delays (exclude clk & rst_n)
set_input_delay -clock clk -max 1.0 [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay -clock clk -min 0.2 [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]

# Output delays
set_output_delay -clock clk -max 1.0 [all_outputs]
set_output_delay -clock clk -min 0.2 [all_outputs]

# Exclude reset from timing (async)
set_false_path -from [get_ports rst_n]

# Multicycle path for done/error/status (not every-cycle signals)
set_multicycle_path -setup 2 -to [get_ports {done_o error_o busy_o}]
set_multicycle_path -hold  1 -to [get_ports {done_o error_o busy_o}]

# Load and drive (exclude clk & rst_n)
set_load 0.05 [all_outputs]
set_driving_cell -lib_cell sky130_fd_sc_hs__buf_1 \
  [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
