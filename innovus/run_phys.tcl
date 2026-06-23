# Innovus physical synthesis script for fa_accel_top
# Target: sky130 HS, TT corner, 25C, 1.80V
# Innovus version: v25.12
# Usage: innovus -batch -file innovus/run_phys.tcl

# ==========================================
# 0. Setup variables — EDIT these paths
# ==========================================
set DESIGN_NAME    fa_accel_top
set NETLIST_FILE   synth/fa_accel_top_netlist_full.v
set SDC_FILE       innovus/constraints.sdc
set LEF_FILE       sky130_fd_sc_hs.lef
set LIB_FILE       sky130_fd_sc_hs__tt_025C_1v80_slim.lib
set REPORT_DIR     reports

file mkdir ${REPORT_DIR}

# ==========================================
# 1. Read design
# ==========================================
set init_verilog   ${NETLIST_FILE}
set init_top_cell  ${DESIGN_NAME}
set init_lef_file  ${LEF_FILE}
# MMMC view definition inline
set init_mmmc_file innovus/mmmc.tcl
init_design

# ==========================================
# 2. Floorplan
# ==========================================
# Auto-calculate area from gate count, 70% utilization
floorPlan -site unit -d 0.70 1.0 10 10 10 10

# Connect all tie-hi/tie-lo cells
globalNetConnect VDD -type tiehi
globalNetConnect VSS -type tielo

# ==========================================
# 3. Power grid
# ==========================================
# Power rings and stripes for sky130 (6 metal layers available)
addRing -spacing_bottom 2 -spacing_top 2 -width_left 3 -width_right 3 \
  -width_bottom 3 -width_top 3 -layer_bottom met1 -layer_top met1 \
  -layer_left met2 -layer_right met2 -nets {VDD VSS} -offset 2

addStripe -nets {VDD VSS} -layer met2 -direction vertical \
  -width 3 -spacing 2 -number_of_sets 8

addStripe -nets {VDD VSS} -layer met3 -direction horizontal \
  -width 3 -spacing 2 -number_of_sets 8

# Route power for standard cells
sroute -connect {blockPin padPin padRing corePin} \
  -layerChangeRange {met1 met5} -blockPinTarget {nearestRingStripe} \
  -allowJogging 1 -crossoverViaLayerRange {met1 met5} \
  -nets {VDD VSS}

# ==========================================
# 4. Placement & optimization
# ==========================================
setPlaceMode -timingDriven true -reorderScan false
place_opt_design

# Early timing check
timeDesign -preCTS -outDir ${REPORT_DIR}

# ==========================================
# 5. Clock tree synthesis
# ==========================================
set_ccopt_property target_skew 0.15
set_ccopt_property target_slew 0.3
create_ccopt_clock_tree_spec -file ${REPORT_DIR}/ccopt.spec
ccopt_design -cts

# Post-CTS timing
timeDesign -postCTS -outDir ${REPORT_DIR}

# ==========================================
# 6. Routing
# ==========================================
setNanoRouteMode -quiet -timingEngine true
setNanoRouteMode -quiet -routeWithViaInPin true
setNanoRouteMode -quiet -routeTopRoutingLayer 5
setNanoRouteMode -quiet -routeBottomRoutingLayer 1
routeDesign -globalDetail

# Post-route optimization
optDesign -postRoute -setup -hold

# ==========================================
# 7. Reports
# ==========================================
puts "=== Generating reports ==="

# Timing
report_timing -path_type full_clock -slack_lesser_than 0.0 \
  -file ${REPORT_DIR}/timing_violations.rpt
report_timing -path_type full_clock -nworst 5 \
  -file ${REPORT_DIR}/timing_top5.rpt

# Area
report_area -outfile ${REPORT_DIR}/area.rpt

# Power
report_power -outfile ${REPORT_DIR}/power.rpt

# Design summary
summaryReport -noHtml -outfile ${REPORT_DIR}/summary.rpt

# Gate count
reportGateCount -outfile ${REPORT_DIR}/gate_count.rpt

# DRC
verify_drc -report ${REPORT_DIR}/drc.rpt

# Connectivity
verifyConnectivity -report ${REPORT_DIR}/connectivity.rpt

# ==========================================
# 8. Export final netlist
# ==========================================
saveDesign ${REPORT_DIR}/${DESIGN_NAME}_final.enc
write_netlist ${REPORT_DIR}/${DESIGN_NAME}_final.v

puts "=== Physical synthesis complete ==="
puts "Reports in: ${REPORT_DIR}/"
exit
