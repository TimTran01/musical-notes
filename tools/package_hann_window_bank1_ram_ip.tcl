# Package hann_window_bank1_ram as a reusable Vivado custom IP.
#
# Run from the repository root with:
#   vivado -mode batch -source tools/package_hann_window_bank1_ram_ip.tcl
#
# This script packages only the standalone bank-1 RAM RTL. It does not connect
# the IP to the current block design.

set main_project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set main_project_root [file dirname $main_project_path]
set source_dir         [file normalize "$main_project_root/final_project_hardware.srcs/sources_1/new"]
set ip_repo_dir        [file normalize "$main_project_root/ip_repo"]
set ip_root_dir        [file normalize "$ip_repo_dir/hann_window_bank1_ram_1_0"]
set packager_dir       [file normalize "$main_project_root/.bank1_ram_ip_packager_tmp"]

set part_name "xc7z010clg400-1"

if {[file exists $ip_root_dir]} {
    file delete -force $ip_root_dir
}
if {[file exists $packager_dir]} {
    file delete -force $packager_dir
}
file mkdir $ip_repo_dir

create_project hann_window_bank1_ram_ip_packager $packager_dir -part $part_name -force
set_property target_language VHDL [current_project]

add_files -norecurse [list \
    "$source_dir/hann_window_bank1_ram.vhd" \
]

set_property file_type VHDL [get_files "$source_dir/hann_window_bank1_ram.vhd"]
set_property top hann_window_bank1_ram [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]

set_property name hann_window_bank1_ram $core
set_property display_name {Hann Window Bank 1 RAM} $core
set_property description {Stores 4096 decimated 3 kHz, signed 24-bit Hann-windowed samples for bank 1.} $core
set_property vendor_display_name {ECE 615} $core
set_property company_url {https://example.local/ece615} $core

ipx::infer_bus_interfaces $core

set clk_if [ipx::get_bus_interfaces clk -of_objects $core]
if {[llength $clk_if] > 0} {
    set_property interface_mode slave $clk_if
}

set rst_if [ipx::get_bus_interfaces rst -of_objects $core]
if {[llength $rst_if] > 0} {
    set_property interface_mode slave $rst_if
}

ipx::update_checksums $core
ipx::save_core $core
close_project

open_project $main_project_path
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog
close_project

puts "Packaged hann_window_bank1_ram IP at: $ip_root_dir"
puts "Registered IP repository path: $ip_repo_dir"
