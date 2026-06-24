# Cadence Genus synthesis flow for fa_accel_top.
# Required environment:
#   STD_CELL_LIB=/absolute/path/to/sky130_fd_sc_hs__tt_025C_1v80.lib

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file dirname $SCRIPT_DIR]
set REPORT_DIR [file join $SCRIPT_DIR reports]
set OUTPUT_DIR [file join $SCRIPT_DIR outputs]

proc require_file {label path} {
  if {![file isfile $path]} {
    error "$label not found: $path"
  }
}

if {![info exists ::env(STD_CELL_LIB)] || $::env(STD_CELL_LIB) eq ""} {
  error "Set STD_CELL_LIB to the full Sky130 HS TT Liberty file"
}

set STD_CELL_LIB [file normalize $::env(STD_CELL_LIB)]
set SDC_FILE     [file join $SCRIPT_DIR constraints.sdc]
set RTL_FILES [list \
  [file join $REPO_ROOT rtl fa_pkg.sv] \
  [file join $REPO_ROOT rtl fa_regfile.sv] \
  [file join $REPO_ROOT rtl fa_scheduler.sv] \
  [file join $REPO_ROOT rtl fa_dot_pe.sv] \
  [file join $REPO_ROOT rtl fa_exp_approx.sv] \
  [file join $REPO_ROOT rtl fa_recip_approx.sv] \
  [file join $REPO_ROOT rtl fa_softmax_online.sv] \
  [file join $REPO_ROOT rtl fa_out_quant.sv] \
  [file join $REPO_ROOT rtl fa_dma_rd.sv] \
  [file join $REPO_ROOT rtl fa_dma_wr.sv] \
  [file join $REPO_ROOT rtl fa_q_buffer.sv] \
  [file join $REPO_ROOT rtl fa_kv_buffer.sv] \
  [file join $REPO_ROOT rtl fa_accel_top.sv]]

require_file "STD_CELL_LIB" $STD_CELL_LIB
require_file "SDC" $SDC_FILE
foreach rtl_file $RTL_FILES {
  require_file "RTL source" $rtl_file
}

file mkdir $REPORT_DIR
file mkdir $OUTPUT_DIR

set_db init_hdl_search_path [list [file join $REPO_ROOT rtl]]
set_db init_lib_search_path [list [file dirname $STD_CELL_LIB]]
set_db library [list $STD_CELL_LIB]
set_db hdl_language sv

read_hdl $RTL_FILES
elaborate fa_accel_top
read_sdc $SDC_FILE

check_design
syn_generic
syn_map
syn_opt

report_qor    > [file join $REPORT_DIR qor.rpt]
report_area   > [file join $REPORT_DIR area.rpt]
report_timing > [file join $REPORT_DIR timing.rpt]
report_power  > [file join $REPORT_DIR power.rpt]

write_hdl > [file join $OUTPUT_DIR fa_accel_top_mapped.v]
write_sdc > [file join $OUTPUT_DIR fa_accel_top_mapped.sdc]
