# MMMC view definition for fa_accel_top
# Single-corner: sky130 HS TT 25C 1.80V

# Library set
create_library_set -name lib_tt \
  -timing [list sky130_fd_sc_hs__tt_025C_1v80_slim.lib]

# RC corner — use default extraction (no cap_table for sky130)
# Pre/post-route resistance/capacitance scaling factors
create_rc_corner -name rc_tt \
  -preRoute_res 1.0 -postRoute_res 1.0 \
  -preRoute_cap 1.0 -postRoute_cap 1.0 \
  -preRoute_clkres 0.5 -preRoute_clkcap 0.5

# Delay corner
create_delay_corner -name dc_tt \
  -library_set lib_tt \
  -rc_corner rc_tt

# Constraint mode
create_constraint_mode -name cm_func \
  -sdc_files [list innovus/constraints.sdc]

# Analysis view
create_analysis_view -name av_tt \
  -constraint_mode cm_func \
  -delay_corner dc_tt

# Activate view
set_analysis_view -setup [list av_tt] -hold [list av_tt]
