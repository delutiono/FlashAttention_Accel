set STAGE syn
set DEFAULT_TOP fa_accel_top

proc require_file {path label} {
  set resolved [file normalize $path]
  if {![file isfile $resolved] || ![file readable $resolved]} {
    error "$label is not a readable file: $resolved"
  }
  return $resolved
}

proc env_or_default {name default_path} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return [file normalize $::env($name)]
  }
  return [file normalize $default_path]
}

proc require_dir {path label} {
  set resolved [file normalize $path]
  if {![file isdirectory $resolved]} {
    error "$label is not a directory: $resolved"
  }
  return $resolved
}

proc read_path_list {path label} {
  set list_path [require_file $path $label]
  set list_dir [file dirname $list_path]
  set fd [open $list_path r]
  set paths {}
  while {[gets $fd line] >= 0} {
    set item [string trim $line]
    if {$item eq "" || [string match "#*" $item]} {
      continue
    }
    if {[file pathtype $item] eq "absolute"} {
      set resolved [file normalize $item]
    } else {
      set resolved [file normalize [file join $list_dir $item]]
    }
    lappend paths [require_file $resolved $label]
  }
  close $fd
  return $paths
}

proc write_text_report {path lines} {
  set fd [open $path w]
  foreach line $lines {
    puts $fd $line
  }
  close $fd
}

set script_dir [file dirname [info script]]
set bundle_root [env_or_default GENUS_PROJECT_ROOT [file join $script_dir ..]]
set workspace_dir [env_or_default GENUS_WORKSPACE_DIR [file join $bundle_root workspace]]
set results_root [env_or_default GENUS_RESULTS_DIR [file join $bundle_root results]]
set bundle_root [require_dir $bundle_root "Genus project root"]
set workspace_dir [require_dir $workspace_dir "Genus workspace directory"]
set filelist_dir [file join $workspace_dir filelists]
set constraint_dir [file join $workspace_dir constraints]

set top $DEFAULT_TOP
if {[info exists ::env(TOP)] && $::env(TOP) ne ""} {
  set top $::env(TOP)
}

set physical_mode 1
if {[info exists ::env(GENUS_PHYSICAL)] && $::env(GENUS_PHYSICAL) eq "0"} {
  set physical_mode 0
}

set read_sram_behav_rtl 0
if {[info exists ::env(READ_SRAM_BEHAV_RTL)] && $::env(READ_SRAM_BEHAV_RTL) ne "0"} {
  set read_sram_behav_rtl 1
}

set report_dir [file join $results_root reports $top]
set output_dir [file join $results_root outputs $top]
set log_dir [file join $results_root logs]
file mkdir $report_dir
file mkdir $output_dir
file mkdir $log_dir

set rtl_filelist [env_or_default RTL_FILELIST [file join $filelist_dir rtl.f]]
set sram_behav_filelist [env_or_default SRAM_BEHAV_RTL_FILELIST [file join $filelist_dir sram_macro_verilog.f]]
set lib_filelist [env_or_default LIB_FILELIST [file join $filelist_dir libs_tt.f]]
set lef_filelist [env_or_default LEF_FILELIST [file join $filelist_dir lefs.f]]
set sdc_file [env_or_default SDC_FILE [file join $constraint_dir timing_300m.sdc]]

puts "INFO: STAGE=$STAGE"
puts "INFO: TOP=$top"
puts "INFO: PROJECT_ROOT=$bundle_root"
puts "INFO: WORKSPACE_DIR=$workspace_dir"
puts "INFO: RESULTS_DIR=$results_root"
puts "INFO: PHYSICAL_MODE=$physical_mode"
puts "INFO: READ_SRAM_BEHAV_RTL=$read_sram_behav_rtl"

set lib_files [read_path_list $lib_filelist "Liberty filelist"]
foreach lib_file $lib_files {
  puts "INFO: LIB=$lib_file"
}
eval read_libs $lib_files

set lef_files [read_path_list $lef_filelist "LEF filelist"]
foreach lef_file $lef_files {
  puts "INFO: LEF=$lef_file"
}
if {[llength $lef_files] > 0} {
  set lef_arg [join $lef_files " "]
  if {[catch {read_physical -lefs $lef_arg} err]} {
    puts "WARNING: read_physical -lefs failed or is unsupported in this Genus setup: $err"
  }
}

set_db init_hdl_search_path [list [file join $workspace_dir RTL]]
set_db hdl_language sv
catch {set_db hdl_track_filename_row_col true}
if {[catch {set_db hdl_resolve_instance_with_libcell true} err]} {
  puts "WARNING: hdl_resolve_instance_with_libcell not accepted: $err"
}
puts "INFO: Defining SYNTHESIS for Genus RTL read so SRAM wrappers use unparameterized macro instances."

if {$read_sram_behav_rtl} {
  set sram_behav_files [read_path_list $sram_behav_filelist "SRAM behavioral Verilog filelist"]
  foreach src $sram_behav_files {
    puts "INFO: SRAM_BEHAV_RTL=$src"
  }
  eval read_hdl -sv $sram_behav_files
} else {
  puts "INFO: SRAM behavioral Verilog is packaged but not read by default; Liberty cells resolve SRAM macro instances."
}

set rtl_files [read_path_list $rtl_filelist "RTL filelist"]
foreach src $rtl_files {
  puts "INFO: RTL=$src"
}
eval read_hdl -sv -define SYNTHESIS $rtl_files

elaborate $top

set sram_refs [list \
  sky130_sram_0kbytes_1rw1r_32x64_8]
set sram_report_lines {}
set total_sram_insts 0
foreach ref $sram_refs {
  set insts [get_cells -hier -filter "ref_name == $ref"]
  set count [sizeof_collection $insts]
  lappend sram_report_lines "$ref $count"
  puts "INFO: SRAM_COUNT $ref = $count"
  if {$count > 0} {
    catch {set_db $insts .preserve true}
    catch {set_db $insts .dont_touch true}
    set total_sram_insts [expr {$total_sram_insts + $count}]
  }
}
lappend sram_report_lines "TOTAL $total_sram_insts"
write_text_report [file join $report_dir sram_macro_instances.rpt] $sram_report_lines
if {$total_sram_insts == 0} {
  error "No SRAM macro instances were found after elaboration; check Liberty names and wrapper RTL."
}

read_sdc [require_file $sdc_file "timing SDC"]

redirect [file join $report_dir check_design_pre.rpt] {check_design}
redirect [file join $report_dir hierarchy_pre.rpt] {report hierarchy}
if {[catch {redirect [file join $report_dir timing_lint_pre.rpt] {report timing -lint}} err]} {
  puts "WARNING: optional timing lint report failed: $err"
}
if {[catch {redirect [file join $report_dir unmapped_pre.rpt] {report unmapped}} err]} {
  puts "WARNING: optional unmapped pre-synth report failed: $err"
}

if {$physical_mode} {
  puts "INFO: Running physical-aware synthesis stages when supported."
  if {[catch {syn_generic -physical} err]} {
    puts "WARNING: syn_generic -physical failed; retrying syn_generic: $err"
    syn_generic
  }
  redirect [file join $report_dir qor_generic.rpt] {report qor}
  if {[catch {syn_map -physical} err]} {
    puts "WARNING: syn_map -physical failed; retrying syn_map: $err"
    syn_map
  }
  redirect [file join $report_dir qor_mapped.rpt] {report qor}
  if {[catch {syn_opt -physical} err]} {
    puts "WARNING: syn_opt -physical failed; retrying syn_opt: $err"
    syn_opt
  }
} else {
  puts "INFO: Running logical synthesis stages."
  syn_generic
  redirect [file join $report_dir qor_generic.rpt] {report qor}
  syn_map
  redirect [file join $report_dir qor_mapped.rpt] {report qor}
  syn_opt
}

redirect [file join $report_dir timing.rpt] {report timing}
redirect [file join $report_dir area.rpt] {report area}
redirect [file join $report_dir power.rpt] {report power}
redirect [file join $report_dir qor_final.rpt] {report qor}
redirect [file join $report_dir check_design_post.rpt] {check_design}
redirect [file join $report_dir hierarchy_final.rpt] {report hierarchy}
if {[catch {redirect [file join $report_dir gates.rpt] {report gates}} err]} {
  puts "WARNING: optional gates report failed: $err"
}
if {[catch {redirect [file join $report_dir cell_usage.rpt] {report cell_usage}} err]} {
  puts "WARNING: optional cell usage report failed: $err"
}
if {[catch {redirect [file join $report_dir unmapped_final.rpt] {report unmapped}} err]} {
  puts "WARNING: optional unmapped final report failed: $err"
}

write_hdl > [file join $output_dir ${top}_mapped.v]
write_sdc > [file join $output_dir ${top}_mapped.sdc]
if {[catch {write_db [file join $output_dir ${top}.db]} err]} {
  puts "WARNING: optional write_db failed: $err"
}

puts "GENUS_DONE $top"
exit
