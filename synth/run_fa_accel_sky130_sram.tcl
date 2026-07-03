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

proc env_flag {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return [expr {$::env($name) ne "0"}]
  }
  return $default_value
}

proc env_value {name default_value} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  return $default_value
}

proc optional_env_file {name label} {
  if {![info exists ::env($name)] || $::env($name) eq ""} {
    return ""
  }
  return [require_file $::env($name) $label]
}

proc run_physical_command {cmd fallback_cmd label allow_fallback} {
  if {[catch {uplevel 1 $cmd} err]} {
    if {$allow_fallback && $fallback_cmd ne ""} {
      puts "WARNING: $label failed; retrying $fallback_cmd because GENUS_ALLOW_PHYSICAL_FALLBACK=1: $err"
      uplevel 1 $fallback_cmd
      return 0
    }
    error "$label failed: $err"
  }
  return 1
}

proc try_write_def {path label} {
  if {[catch {write_def $path} err]} {
    puts "WARNING: $label DEF export failed: $err"
    return 0
  }
  puts "INFO: $label DEF written to $path"
  return 1
}

proc configure_multicpu {} {
  set threads [env_value GENUS_THREADS 8]
  if {![string is integer -strict $threads] || $threads < 1} {
    puts "WARNING: GENUS_THREADS=$threads is invalid; using 8."
    set threads 8
  }
  puts "INFO: GENUS_THREADS=$threads"

  if {$threads <= 1} {
    puts "INFO: Multi-CPU setup disabled because GENUS_THREADS <= 1."
    return
  }

  set commands [list \
    [list set_db max_cpus_per_server $threads] \
    [list set_db auto_super_thread true] \
    [list set_db super_thread_servers [list localhost $threads]] \
    [list set_multi_cpu_usage -local_cpu $threads]]
  foreach cmd $commands {
    if {[catch {eval $cmd} err]} {
      puts "WARNING: Multi-CPU command '$cmd' was not accepted in this Genus setup: $err"
    } else {
      puts "INFO: Applied multi-CPU command: $cmd"
    }
  }
}

proc configure_physical_context {output_dir top} {
  set process_node [env_value GENUS_PROCESS_NODE 130]
  if {[catch {set_db design_process_node $process_node} err]} {
    puts "WARNING: design_process_node=$process_node was not accepted: $err"
  } else {
    puts "INFO: design_process_node=$process_node"
  }

  set cap_table [optional_env_file GENUS_CAP_TABLE "cap table"]
  if {$cap_table ne ""} {
    puts "INFO: GENUS_CAP_TABLE=$cap_table"
    if {[catch {create_rc_corner -name sky130_pre_route_rc -cap_table $cap_table} err]} {
      puts "WARNING: create_rc_corner -cap_table failed; continuing without explicit cap table: $err"
    }
  } else {
    puts "INFO: GENUS_CAP_TABLE is unset; pre-route parasitic accuracy may remain limited."
  }

  set seed_def [optional_env_file GENUS_DEF_FILE "seed DEF floorplan"]
  if {$seed_def ne ""} {
    puts "INFO: Reading seed DEF floorplan: $seed_def"
    read_def $seed_def
    try_write_def [file join $output_dir ${top}_seed_floorplan_readback.def] "Seed floorplan readback"
    return 1
  }

  if {![env_flag GENUS_PREDICT_FLOORPLAN 1]} {
    puts "INFO: GENUS_PREDICT_FLOORPLAN=0 and GENUS_DEF_FILE is unset; no physical floorplan will be prepared."
    return 0
  }

  set fp_util [env_value GENUS_FP_UTIL 0.55]
  set fp_aspect [env_value GENUS_FP_ASPECT_RATIO 1.0]
  set fp_margin [env_value GENUS_FP_CORE_MARGIN 20.0]
  puts "INFO: Trying predict_floorplan before syn_generic -physical."
  puts "INFO: GENUS_FP_UTIL=$fp_util GENUS_FP_ASPECT_RATIO=$fp_aspect GENUS_FP_CORE_MARGIN=$fp_margin"

  set attempts [list \
    [list predict_floorplan -utilization $fp_util -aspect_ratio $fp_aspect -core_margin $fp_margin] \
    [list predict_floorplan -utilization $fp_util -aspect_ratio $fp_aspect] \
    [list predict_floorplan]]
  foreach attempt $attempts {
    puts "INFO: Attempting: $attempt"
    if {[catch {eval $attempt} err]} {
      puts "WARNING: predict_floorplan attempt failed: $err"
      continue
    }
    try_write_def [file join $output_dir ${top}_predict_floorplan.def] "Predicted floorplan"
    return 1
  }

  puts "WARNING: All predict_floorplan attempts failed."
  return 0
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

set allow_physical_fallback [env_flag GENUS_ALLOW_PHYSICAL_FALLBACK 0]

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
puts "INFO: GENUS_ALLOW_PHYSICAL_FALLBACK=$allow_physical_fallback"
puts "INFO: READ_SRAM_BEHAV_RTL=$read_sram_behav_rtl"

configure_multicpu

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
  puts "INFO: Preparing floorplan before physical-aware synthesis."
  set physical_floorplan_ready [configure_physical_context $output_dir $top]
  if {!$physical_floorplan_ready && !$allow_physical_fallback} {
    error "GENUS_PHYSICAL=1 requires GENUS_DEF_FILE or a successful predict_floorplan result. Set GENUS_ALLOW_PHYSICAL_FALLBACK=1 only for debug logical fallback runs."
  }
  puts "INFO: Running physical-aware synthesis stages."
  run_physical_command {syn_generic -physical} {syn_generic} "syn_generic -physical" $allow_physical_fallback
  redirect [file join $report_dir qor_generic.rpt] {report qor}
  run_physical_command {syn_map -physical} {syn_map} "syn_map -physical" $allow_physical_fallback
  redirect [file join $report_dir qor_mapped.rpt] {report qor}
  run_physical_command {syn_opt -physical} {syn_opt} "syn_opt -physical" $allow_physical_fallback
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
