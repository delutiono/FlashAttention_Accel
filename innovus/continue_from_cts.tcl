# Continue from post-CTS checkpoint
set LIB_FILE  "/home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib"
set SDC_FILE  "$env(PWD)/innovus/constraints.sdc"
set DESIGN_NAME fa_accel_top_synth
set RESULTS_DIR "./results"

restoreDesign ${RESULTS_DIR}/post_cts.enc.dat
set_interactive_constraint_modes c_mode
source $SDC_FILE
setMultiCpuUsage -localCpu 8

# Routing
setRouteMode -earlyGlobalEffortLevel standard
routeDesign
saveDesign ${RESULTS_DIR}/post_route.enc

setDelayCalMode -siAware false
setOptMode -opt_hold_cells {sky130_fd_sc_hs__buf_1 sky130_fd_sc_hs__buf_2 sky130_fd_sc_hs__buf_4} -opt_post_route_fix_si_transitions false
optDesign -postRoute -hold
saveDesign ${RESULTS_DIR}/post_routeopt.enc

# Reports
file mkdir ${RESULTS_DIR}/timing
report_timing -nworst 100 > ${RESULTS_DIR}/timing/setup.rpt
report_timing -nworst 100 -late > ${RESULTS_DIR}/timing/hold.rpt
report_power -outfile ${RESULTS_DIR}/power.rpt
report_area  > ${RESULTS_DIR}/area.rpt
summaryReport > ${RESULTS_DIR}/cell_usage.rpt

# Output
saveNetlist -includePowerGround ${RESULTS_DIR}/${DESIGN_NAME}_phys.v
write_sdf -version 2.1 ${RESULTS_DIR}/${DESIGN_NAME}_postroute.sdf
write_sdc ${RESULTS_DIR}/${DESIGN_NAME}_postroute.sdc
saveDesign ${RESULTS_DIR}/${DESIGN_NAME}.enc

puts "=== ALL DONE ==="
