set project_path [file normalize "final_project_hardware.xpr"]

open_project $project_path
set_property source_mgmt_mode None [current_project]

set sim_files [list \
    [file normalize "final_project_hardware.srcs/sim_1/new/full_note_detector_wrapper_tb.vhd"] \
    [file normalize "final_project_hardware.srcs/sources_1/new/adc_samples.mem"] \
    [file normalize "final_project_hardware.srcs/sources_1/new/goertzel_bank1_coeff.mem"] \
    [file normalize "final_project_hardware.srcs/sources_1/new/goertzel_bank2_coeff.mem"] \
    [file normalize "final_project_hardware.srcs/sources_1/new/goertzel_bank3_coeff.mem"] \
]

foreach sim_file $sim_files {
    if {[llength [get_files -quiet $sim_file]] == 0} {
        add_files -norecurse -fileset sim_1 $sim_file
    }
}

set_property file_type {Memory File} [get_files -quiet "*adc_samples.mem"]
set_property file_type {Memory File} [get_files -quiet "*goertzel_bank*_coeff.mem"]
set_property top full_note_detector_wrapper_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all

set xsim_dir [file normalize "final_project_hardware.sim/sim_1/behav/xsim"]
close_sim
file copy -force [file join $xsim_dir "simulate.log"] [file join $xsim_dir "full_design_simulate.log"]
close_project
exit
