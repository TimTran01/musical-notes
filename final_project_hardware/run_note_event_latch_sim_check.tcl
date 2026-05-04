set project_path [file normalize "final_project_hardware.xpr"]
open_project $project_path
set_property source_mgmt_mode None [current_project]

set source_file [file normalize "final_project_hardware.srcs/sources_1/new/note_event_latch.vhd"]
set tb_file     [file normalize "final_project_hardware.srcs/sim_1/new/note_event_latch_tb.vhd"]

if {[llength [get_files -quiet $source_file]] == 0} {
    add_files -norecurse -fileset sources_1 $source_file
}

if {[llength [get_files -quiet $tb_file]] == 0} {
    add_files -norecurse -fileset sim_1 $tb_file
}

set_property top note_event_latch_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all

close_sim
close_project
exit
