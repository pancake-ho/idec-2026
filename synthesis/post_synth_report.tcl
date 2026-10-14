source $::env(SCRIPTS_DIR)/load.tcl
load_design 1_synth.odb 1_synth.sdc

puts "================ DESIGN AREA ================"
report_design_area

puts "================ TIMING ================"
report_checks -path_delay max \
    -slack_max 0.0 \
    -group_count 10 \
    -endpoint_count 10 \
    -fields {slew cap input_pins} \
    -format full_clock_expanded
report_worst_slack -max -digits 4
report_wns -digits 4
report_tns -digits 4

puts "================ POWER ================"
report_power
exit
