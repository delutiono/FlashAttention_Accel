set default_shm [file normalize [file join [pwd] "power" "rtl_wave" "fa_top_power_s256_rtl.shm"]]
if {[info exists ::env(RTL_POWER_SHM)] && $::env(RTL_POWER_SHM) ne ""} {
  set rtl_power_shm [file normalize $::env(RTL_POWER_SHM)]
} else {
  set rtl_power_shm $default_shm
}

file mkdir [file dirname $rtl_power_shm]
database -open rtl_power -shm -into $rtl_power_shm -default
probe -create tb_fa_top_power_s256.dut -depth all -database rtl_power
run
exit
