# Package adc_sample_48khz_sampler as a reusable Vivado custom IP.
#
# Run from the repository root with:
#   vivado -mode batch -source tools/package_adc_sampler_ip.tcl
#
# Vivado block diagrams show packaged IP from IP repositories. Plain RTL files
# in sources_1 can be added with "Add Module", but they do not automatically
# appear in the IP Catalog. This script creates a local IP repository entry for
# the 48 kHz sampler so it is visible from "Add IP".

set main_project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set main_project_root [file dirname $main_project_path]
set source_dir         [file normalize "$main_project_root/final_project_hardware.srcs/sources_1/new"]
set ip_repo_dir        [file normalize "$main_project_root/ip_repo"]
set ip_root_dir        [file normalize "$ip_repo_dir/adc_sample_48khz_sampler_1_0"]
set packager_dir       [file normalize "$main_project_root/.ip_packager_tmp"]

set part_name "xc7z010clg400-1"

# Recreate only generated packaging output. The original project RTL remains in
# final_project_hardware.srcs/sources_1/new and is not modified by this cleanup.
if {[file exists $ip_root_dir]} {
    file delete -force $ip_root_dir
}
if {[file exists $packager_dir]} {
    file delete -force $packager_dir
}
file mkdir $ip_repo_dir

# Use a temporary project containing only the synthesizable IP sources. This
# avoids accidentally packaging block diagrams or testbenches into the IP.
create_project adc_sample_ip_packager $packager_dir -part $part_name -force
set_property target_language VHDL [current_project]

add_files -norecurse [list \
    "$source_dir/adc_sample_rom.vhd" \
    "$source_dir/adc_sample_48khz_sampler.vhd" \
    "$source_dir/adc_samples.mem" \
]

set_property file_type VHDL [get_files "$source_dir/adc_sample_rom.vhd"]
set_property file_type VHDL [get_files "$source_dir/adc_sample_48khz_sampler.vhd"]
set_property top adc_sample_48khz_sampler [current_fileset]
update_compile_order -fileset sources_1

# Package the clean temporary project. adc_sample_48khz_sampler is the public IP
# top; adc_sample_rom and adc_samples.mem are included as internal support files.
ipx::package_project \
    -root_dir $ip_root_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]

# Basic IP identity shown in Vivado's IP Catalog.
set_property name adc_sample_48khz_sampler $core
set_property display_name {ADC Sample 48 kHz Sampler} $core
set_property description {Reads generated 24-bit ADC samples from ROM at an average 48 kHz rate using a 50 MHz Zynq clock.} $core
set_property vendor_display_name {ECE 615} $core
set_property company_url {https://example.local/ece615} $core

# Associate clock/reset metadata so block automation recognizes clk and rst as
# infrastructure signals, while enable and sample outputs remain plain ports.
ipx::infer_bus_interfaces $core

set clk_if [ipx::get_bus_interfaces clk -of_objects $core]
if {[llength $clk_if] > 0} {
    set_property interface_mode slave $clk_if
}

set rst_if [ipx::get_bus_interfaces rst -of_objects $core]
if {[llength $rst_if] > 0} {
    set_property interface_mode slave $rst_if
}

# Refresh checksums and write component.xml.
ipx::update_checksums $core
ipx::save_core $core
close_project

# Register the local IP repository with the actual hardware project so the IP
# appears under IP Catalog -> User Repository and in the block design "Add IP"
# search box.
open_project $main_project_path
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog
close_project

puts "Packaged adc_sample_48khz_sampler IP at: $ip_root_dir"
puts "Added IP repository path to project: $ip_repo_dir"
