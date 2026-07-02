# Innovus Physical Synthesis Run Script (Legacy UI)
# FlashAttention Accelerator - Sky130 HS
#
# Usage:
#   innovus -batch -file innovus/run_phys.tcl

# =============================================================
#  Paths
# =============================================================
set LIB_FILE  "/home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib"
set NETLIST   "$env(PWD)/synth/fa_accel_top_synth_netlist.v"
set SDC_FILE  "$env(PWD)/innovus/constraints.sdc"
set TECH_LEF  "/home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/techlef/sky130_fd_sc_hs__nom.tlef"
set CELL_LEF  "/home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/lef/sky130_fd_sc_hs.lef"

set DESIGN_NAME fa_accel_top_synth
set RESULTS_DIR "./results"
file mkdir $RESULTS_DIR

# =============================================================
#  Init design (LEF + timing lib + netlist)
# =============================================================
set init_lef_file    [list $TECH_LEF $CELL_LEF]
set init_mmmc_file   innovus/mmmc_setup.tcl
set init_verilog     $NETLIST
set init_top_cell    $DESIGN_NAME
set init_design_uniquify 1
set init_pwr_net     VPWR
set init_gnd_net     VGND

init_design

# MMMC loaded — activate constraint mode, then source SDC
set_interactive_constraint_modes c_mode
source $SDC_FILE

# =============================================================
#  Floorplan
# =============================================================
floorPlan -r 1.0 0.60 10 10 10 10

# =============================================================
#  Power
# =============================================================
set_power_analysis_mode -method static

globalNetConnect VPWR -type pgpin -pin VPWR -all -override
globalNetConnect VGND -type pgpin -pin VGND -all -override
globalNetConnect VPWR -type tiehi -all
globalNetConnect VGND -type tielo -all

addStripe -nets {VPWR VGND} -layer met1 -direction vertical \
  -width 2.0 -spacing 5.0 -set_to_set_distance 50 \
  -start_offset 50 -stop_offset 50

saveDesign ${RESULTS_DIR}/post_init.enc

# =============================================================
#  Placement
# =============================================================
setMultiCpuUsage -localCpu 8
setPlaceMode -place_global_timing_effort high -place_global_cong_effort high
place_design
saveDesign ${RESULTS_DIR}/post_place.enc

optDesign -preCTS
saveDesign ${RESULTS_DIR}/post_placeopt.enc

# =============================================================
#  CTS
# =============================================================
set_ccopt_property buffer_cells {sky130_fd_sc_hs__clkbuf_1 sky130_fd_sc_hs__clkbuf_2 sky130_fd_sc_hs__clkbuf_4 sky130_fd_sc_hs__clkbuf_8}
set_ccopt_property inverter_cells {sky130_fd_sc_hs__clkinv_1 sky130_fd_sc_hs__clkinv_2 sky130_fd_sc_hs__clkinv_4 sky130_fd_sc_hs__clkinv_8}
set_ccopt_property target_skew 0.200
set_ccopt_property target_insertion_delay min
set_ccopt_property max_fanout 32

clock_opt_design
saveDesign ${RESULTS_DIR}/post_cts.enc

# =============================================================
#  Routing
# =============================================================
setRouteMode -earlyGlobalEffortLevel standard
routeDesign
saveDesign ${RESULTS_DIR}/post_route.enc

setDelayCalMode -siAware false
setOptMode -opt_hold_cells {sky130_fd_sc_hs__buf_1 sky130_fd_sc_hs__buf_2 sky130_fd_sc_hs__buf_4} -opt_post_route_fix_si_transitions false
optDesign -postRoute -hold
saveDesign ${RESULTS_DIR}/post_routeopt.enc

# =============================================================
#  Reports
# =============================================================
file mkdir ${RESULTS_DIR}/timing
report_timing -nworst 100 > ${RESULTS_DIR}/timing/setup.rpt
report_timing -nworst 100 -late > ${RESULTS_DIR}/timing/hold.rpt
report_power -outfile ${RESULTS_DIR}/power.rpt
report_area  > ${RESULTS_DIR}/area.rpt
summaryReport > ${RESULTS_DIR}/cell_usage.rpt

# =============================================================
#  Output
# =============================================================
saveNetlist -includePowerGround ${RESULTS_DIR}/${DESIGN_NAME}_phys.v
write_sdf -version 2.1 ${RESULTS_DIR}/${DESIGN_NAME}_postroute.sdf
write_sdc ${RESULTS_DIR}/${DESIGN_NAME}_postroute.sdc
saveDesign ${RESULTS_DIR}/${DESIGN_NAME}.enc

puts "=== PHYSICAL SYNTHESIS COMPLETE ==="
puts "Results in: ${RESULTS_DIR}/"
