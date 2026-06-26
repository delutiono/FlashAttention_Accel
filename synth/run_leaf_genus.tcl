proc require_std_cell_lib {} {
  if {![info exists ::env(STD_CELL_LIB)] || $::env(STD_CELL_LIB) eq ""} {
    error "STD_CELL_LIB must name a readable Liberty timing library"
  }
  set lib_path [file normalize $::env(STD_CELL_LIB)]
  if {![file isfile $lib_path] || ![file readable $lib_path]} {
    error "STD_CELL_LIB is not a readable file: $lib_path"
  }
  return $lib_path
}

array set leaf_tops {
  exp       fa_exp_approx
  recip     fa_recip_approx
  softmax   fa_softmax_online_vec
  finalize  fa_finalize_vec
}
set supported_tops [list \
    fa_exp_approx \
    fa_recip_approx \
    fa_softmax_online_vec \
    fa_finalize_vec]

set std_cell_lib [require_std_cell_lib]
if {![info exists ::env(TOP)] || $::env(TOP) eq ""} {
  error "TOP must be one of exp, recip, softmax, finalize, or its fa_* module name"
}

set requested_top $::env(TOP)
if {[info exists leaf_tops($requested_top)]} {
  set top $leaf_tops($requested_top)
} else {
  set top $requested_top
}

if {[lsearch -exact $supported_tops $top] < 0} {
  error "unsupported leaf TOP '$requested_top'"
}

set report_dir [file join reports $top]
set output_dir [file join outputs $top]
file mkdir $report_dir
file mkdir $output_dir

set_db init_hdl_search_path {../rtl}
set_db hdl_language sv

read_libs $std_cell_lib
read_hdl -f filelist.f
elaborate $top

read_sdc constraints.sdc

check_design > [file join $report_dir check_design.rpt]
syn_generic
syn_map
syn_opt

report_area  > [file join $report_dir area.rpt]
report_timing > [file join $report_dir timing.rpt]
report_power > [file join $report_dir power.rpt]
report_qor > [file join $report_dir qor.rpt]
write_hdl > [file join $output_dir ${top}_mapped.v]
write_sdc > [file join $output_dir ${top}_mapped.sdc]
