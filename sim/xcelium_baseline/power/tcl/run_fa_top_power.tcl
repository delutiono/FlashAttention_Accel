# Cadence Joules vector-based gate-level power template for fa_top.
#
# Required on most servers:
#   setenv JOULES_STD_LIB /path/to/sky130_fd_sc_hs__*.lib
# Optional:
#   setenv JOULES_SRAM_LIBS "/path/to/sram1.lib /path/to/sram2.lib ..."
#   setenv JOULES_ACTIVITY_FILE power/out/activity/fa_top_power_s256.vcd
#   setenv JOULES_ACTIVITY_FORMAT vcd
#   setenv JOULES_OUT_DIR power/out/joules

proc env_or_default {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

set script_dir [file dirname [file normalize [info script]]]
set base_dir [file normalize [file join $script_dir ".." ".."]]
set out_dir [env_or_default JOULES_OUT_DIR [file join $base_dir "power" "out" "joules"]]
set activity_file [env_or_default JOULES_ACTIVITY_FILE [file join $base_dir "power" "out" "activity" "fa_top_power_s256.vcd"]]
set activity_format [string tolower [env_or_default JOULES_ACTIVITY_FORMAT "vcd"]]
file mkdir $out_dir

set default_std_lib [file normalize [file join $base_dir ".." ".." "genus" "workspace" "LIBS" "sky130_fd_sc_hs__tt_025C_1v80.lib"]]
set std_lib [env_or_default JOULES_STD_LIB $default_std_lib]
set sram_libs_env [env_or_default JOULES_SRAM_LIBS ""]

if {![file exists $activity_file]} {
  set gz_activity "${activity_file}.gz"
  if {[file exists $gz_activity]} {
    puts "ERROR: found compressed VCD $gz_activity but Joules is being given $activity_file"
    puts "       Run gzip -dk $gz_activity first, or set JOULES_ACTIVITY_FILE to an uncompressed VCD."
    exit 1
  }
  puts "ERROR: activity file not found: $activity_file"
  exit 1
}

if {![file exists $std_lib]} {
  puts "ERROR: standard-cell Liberty file not found: $std_lib"
  puts "       Set JOULES_STD_LIB to the SKY130 hs Liberty file used for this netlist."
  exit 1
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

if {$activity_format eq "vcd"} {
  read_stimulus -format vcd -file $activity_file -dut_instance tb_fa_top_power_s256.dut
} elseif {$activity_format eq "saif"} {
  read_stimulus -format saif -file $activity_file -dut_instance tb_fa_top_power_s256.dut
} else {
  puts "ERROR: unsupported JOULES_ACTIVITY_FORMAT '$activity_format'; use vcd or saif."
  exit 1
}

compute_power
report_power -out [file join $out_dir "fa_top_power_s256.rpt"]

if {[catch {report_power -by_hierarchy -out [file join $out_dir "fa_top_power_s256_by_hierarchy.rpt"]} err]} {
  puts "WARN: hierarchical report_power command failed: $err"
}

puts "INFO: Joules power reports written under $out_dir"
