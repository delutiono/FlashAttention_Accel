# Cadence Joules zero-delay Xreplay power template for fa_top.
#
# This flow does not read SDF. It maps RTL stimulus onto the same-source
# fa_top_mapped.v through the Genus RTL-to-gate mapping file and lets Joules
# invoke Xcelium through xreplay.

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set script_dir [file dirname [file normalize [info script]]]
set base_dir [file normalize [file join $script_dir ".." ".."]]
set power_dir [file join $base_dir "power"]

set out_dir [env_or_default JOULES_OUT_DIR [file join $power_dir "out" "joules_xreplay_zero"]]
set mapping_file [env_or_default JOULES_MAPPING_FILE [file join $power_dir "mapping" "fa_top_genus_mapping.rpt"]]
set rtl_stim [env_or_default JOULES_RTL_STIM [file join $power_dir "rtl_wave" "fa_top_power_s256_rtl.shm"]]
set rtl_stim_format [string tolower [env_or_default JOULES_RTL_STIM_FORMAT "shm"]]
set xrun_path [env_or_default JOULES_XRUN_PATH "xrun"]
set dut_instance [env_or_default JOULES_DUT_INSTANCE "tb_fa_top_power_s256.dut"]
set xreplay_start [env_or_default JOULES_XREPLAY_START ""]
set xreplay_end [env_or_default JOULES_XREPLAY_END ""]
set replayed_stim [env_or_default JOULES_REPLAYED_STIM [file join $out_dir "fa_top_power_s256_replayed_zero.vcd"]]

set default_std_lib [file normalize [file join $base_dir ".." ".." "genus" "workspace" "LIBS" "sky130_fd_sc_hs__tt_025C_1v80.lib"]]
set std_lib [env_or_default JOULES_STD_LIB $default_std_lib]
set sram_libs_env [env_or_default JOULES_SRAM_LIBS ""]

file mkdir $out_dir

foreach required [list $mapping_file $rtl_stim $std_lib [file join $base_dir "netlist" "fa_top_mapped.v"] [file join $base_dir "constraints" "fa_top_mapped.sdc"]] {
  if {![file exists $required]} {
    puts "ERROR: required Xreplay input not found: $required"
    exit 1
  }
}

set libs [list $std_lib]
if {$sram_libs_env ne ""} {
  foreach lib $sram_libs_env {
    if {![file exists $lib]} {
      puts "ERROR: SRAM Liberty file not found: $lib"
      exit 1
    }
    lappend libs $lib
  }
}

read_libs {*}$libs
read_hdl -sv [file join $base_dir "netlist" "fa_top_mapped.v"]
elaborate fa_top
read_sdc [file join $base_dir "constraints" "fa_top_mapped.sdc"]

set xreplay_cmd [list xreplay \
  -initial_state_point_value rtlstim \
  -timescale 1ns/1ps \
  -map_file $mapping_file \
  -xrun_path $xrun_path \
  -rtl_stim $rtl_stim \
  -stim_format $rtl_stim_format \
  -dut_instance $dut_instance \
  -delay_mode zero \
  -out $replayed_stim \
  -stim_annotation state]

if {$xreplay_start ne ""} {
  lappend xreplay_cmd -start $xreplay_start
}
if {$xreplay_end ne ""} {
  lappend xreplay_cmd -end $xreplay_end
}

puts "INFO: running zero-delay Xreplay:"
puts "INFO: $xreplay_cmd"
{*}$xreplay_cmd

compute_power
report_power -out [file join $out_dir "fa_top_power_s256_xreplay_zero.rpt"]
if {[catch {report_power -by_hierarchy -out [file join $out_dir "fa_top_power_s256_xreplay_zero_by_hierarchy.rpt"]} err]} {
  puts "WARN: hierarchical report_power command failed: $err"
}

puts "INFO: zero-delay Xreplay power reports written under $out_dir"
