set qrc /home/share/pdk/sky130A/libs.tech/cadence/qrcTechFile

read_libs /home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/lib/sky130_fd_sc_hs__tt_025C_1v80.lib
read_physical -lefs [list \
  /home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/techlef/sky130_fd_sc_hs__nom.tlef \
  /home/share/pdk/sky130A/libs.ref/sky130_fd_sc_hs/lef/sky130_fd_sc_hs.lef \
]

set_db / .qrc_tech_file $qrc
puts "INFO: QRC tech file loaded."

set_db probabilistic_extraction true
puts "INFO: probabilistic_extraction enabled."

puts "TEST_PASSED"
exit
