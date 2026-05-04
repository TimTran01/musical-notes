# Program the connected Zybo Z7 with the current piano detector bitstream.
#
# Run from the repository root:
#   vivado -mode batch -source tools/vivado_scripts/program_note_hardware.tcl

set repo_root [file normalize [file join [file dirname [info script]] ".." ".."]]
set bit_file [file normalize [file join $repo_root "final_project_hardware" "final_project_hardware.runs" "impl_1" "design_1_wrapper.bit"]]

if {![file exists $bit_file]} {
    error "Missing bitstream: $bit_file"
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set devices [get_hw_devices xc7z010*]
if {[llength $devices] == 0} {
    set devices [get_hw_devices]
}
if {[llength $devices] == 0} {
    error "No hardware devices found"
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

puts "Programmed FPGA with $bit_file"
close_hw_manager
