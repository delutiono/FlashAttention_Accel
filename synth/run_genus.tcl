proc require_file {path label} {
  set resolved [file normalize $path]
  if {![file isfile $resolved] || ![file readable $resolved]} {
    error "$label is not a readable file: $resolved"
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

proc optional_file {env_name default_path label} {
  if {[info exists ::env($env_name)] && $::env($env_name) ne ""} {
    return [require_file $::env($env_name) $label]
  }
  set resolved [file normalize $default_path]
  if {[file isfile $resolved] && [file readable $resolved]} {
    return $resolved
  }
  puts "INFO: optional $label not found; skipping $resolved"
  return ""
}

proc optional_filelist {env_name default_path label} {
  if {[info exists ::env($env_name)] && $::env($env_name) ne ""} {
    return [file normalize $::env($env_name)]
  }
  set resolved [file normalize $default_path]
  if {[file isfile $resolved] && [file readable $resolved]} {
    return $resolved
  }
  puts "INFO: optional $label not found; skipping $resolved"
  return ""
}

proc require_std_cell_lib {default_path} {
  set lib_path [optional_file STD_CELL_LIB $default_path "standard-cell Liberty"]
  if {$lib_path eq ""} {
    error "STD_CELL_LIB must name a readable Liberty timing library when the repository default is absent"
  }
  return $lib_path
}

set script_dir [file dirname [info script]]
set repo_root [file normalize [file join $script_dir ..]]
set default_std_cell_lib [file join $repo_root sky130A libs.ref sky130_fd_sc_hs lib sky130_fd_sc_hs__tt_025C_1v80.lib]
set default_std_cell_tech_lef [file join $repo_root sky130A libs.ref sky130_fd_sc_hs techlef sky130_fd_sc_hs__nom.tlef]
set default_std_cell_cell_lef [file join $repo_root sky130A libs.ref sky130_fd_sc_hs lef sky130_fd_sc_hs.lef]
set default_std_cell_lef_filelist [file join $repo_root synth fa_stdcell_lefs.list]
set default_sram_wrapper_filelist [file join $repo_root synth fa_sram_macro_files.list]
set default_sram_lib_filelist [file join $repo_root synth fa_sram_tt_libs.list]
set default_sram_lef_filelist [file join $repo_root synth fa_sram_lefs.list]
set std_cell_lib [require_std_cell_lib $default_std_cell_lib]

set top fa_accel_top
if {[info exists ::env(TOP)] && $::env(TOP) ne ""} {
  set top $::env(TOP)
}

set rtl_filelist [file join $script_dir filelist.f]
set sdc_file [file join $script_dir constraints.sdc]
set report_dir [file join $script_dir reports $top]
set output_dir [file join $script_dir outputs $top]
file mkdir $report_dir
file mkdir $output_dir

set_db init_hdl_search_path {../rtl}
set_db hdl_language sv

set lib_files [list $std_cell_lib]
set sram_lib_filelist [optional_filelist SRAM_LIB_FILELIST $default_sram_lib_filelist "SRAM Liberty filelist"]
if {$sram_lib_filelist ne ""} {
  set lib_files [concat $lib_files [read_path_list $sram_lib_filelist "SRAM Liberty filelist"]]
}
foreach lib_file $lib_files {
  puts "INFO: LIB=$lib_file"
  read_libs $lib_file
}

set wrapper_filelist [optional_filelist SRAM_WRAPPER_FILELIST $default_sram_wrapper_filelist "SRAM wrapper filelist"]
if {$wrapper_filelist ne ""} {
  set wrapper_files [read_path_list $wrapper_filelist "SRAM wrapper filelist"]
  foreach wrapper_file $wrapper_files { puts "INFO: SRAM_RTL=$wrapper_file" }
  read_hdl -sv -define SYNTHESIS {*}$wrapper_files
}

set lef_files {}
set std_cell_lef_filelist [optional_filelist STD_CELL_LEF_FILELIST $default_std_cell_lef_filelist "standard-cell LEF filelist"]
if {$std_cell_lef_filelist ne ""} {
  set lef_files [concat $lef_files [read_path_list $std_cell_lef_filelist "standard-cell LEF filelist"]]
}
set lef_filelist [optional_filelist SRAM_LEF_FILELIST $default_sram_lef_filelist "SRAM LEF filelist"]
if {$lef_filelist ne ""} {
  set lef_files [concat $lef_files [read_path_list $lef_filelist "SRAM LEF filelist"]]
}
if {[llength $lef_files] > 0} {
  foreach lef_file $lef_files { puts "INFO: LEF=$lef_file" }
  set lef_arg [join $lef_files " "]
  if {[catch {read_physical -lefs $lef_arg} err]} {
    puts "WARNING: read_physical -lefs failed or is unsupported in this Genus setup: $err"
  }
}

read_hdl -define SYNTHESIS -f $rtl_filelist
elaborate $top

read_sdc $sdc_file

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
