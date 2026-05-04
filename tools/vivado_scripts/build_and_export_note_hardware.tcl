# Build bitstream and export the hardware platform for the Vitis note app.
#
# Run after connect_note_uart_bd.tcl:
#   /mnt/c/Xilinx/Vivado/2023.2/bin/vivado -mode batch -source tools/vivado_scripts/build_and_export_note_hardware.tcl

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set bd_path      [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd"]
set wrapper_file [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/new/design_1_wrapper.vhd"]
set xsa_dir      [file normalize "final_project_software/hw"]
set xsa_path     [file normalize "$xsa_dir/final_project_hardware.xsa"]

file mkdir $xsa_dir

open_project $project_path
open_bd_design $bd_path

validate_bd_design
generate_target all [get_files $bd_path] -force
set generated_wrappers [make_wrapper -files [get_files $bd_path] -top]
if {[llength $generated_wrappers] > 0} {
    file copy -force [lindex $generated_wrappers 0] $wrapper_file
}
if {[llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse $wrapper_file
}
set_property file_type VHDL [get_files $wrapper_file]
set_property top design_1_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {[string first "synth_design Complete!" $synth_status] < 0} {
    close_project
    error "synth_1 did not complete successfully"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {[string first "write_bitstream Complete!" $impl_status] < 0} {
    close_project
    error "write_bitstream did not complete successfully"
}

write_hw_platform -fixed -include_bit -force $xsa_path

close_project

puts "Exported hardware platform: $xsa_path"
