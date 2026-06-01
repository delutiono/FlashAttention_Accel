set_db init_hdl_search_path {../rtl}
set_db hdl_language sv

read_hdl -f filelist.f
elaborate fa_accel_top

read_sdc constraints.sdc

check_design
syn_generic
syn_map
syn_opt

report_area  > reports/area.rpt
report_timing > reports/timing.rpt
report_power > reports/power.rpt
