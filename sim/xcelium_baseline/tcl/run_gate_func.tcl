if {[info exists ::env(XCELIUM_RUN_FOR)] && $::env(XCELIUM_RUN_FOR) ne ""} {
  puts "xcelium_baseline: run for $::env(XCELIUM_RUN_FOR)"
  run $::env(XCELIUM_RUN_FOR)
} else {
  puts "xcelium_baseline: run until testbench finishes"
  run
}

exit
