# MMMC setup for fa_accel_top — sky130 HS TT 25C 1.80V
create_library_set -name lib_set \
  -timing [list /home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib]
create_rc_corner -name rc_tt \
  -preRoute_res  1.0 -postRoute_res  1.0 \
  -preRoute_cap  1.0 -postRoute_cap  1.0 \
  -preRoute_clkres 0.5 -preRoute_clkcap 0.5
create_delay_corner -name dc_tt -library_set lib_set -rc_corner rc_tt
create_constraint_mode -name c_mode \
  -sdc_files [list $env(PWD)/innovus/constraints.sdc]
create_analysis_view -name av_tt -delay_corner dc_tt -constraint_mode c_mode
set_analysis_view -setup av_tt -hold av_tt
