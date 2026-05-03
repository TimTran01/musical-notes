# Package custom IP used by the current final_project_hardware block design.
#
# Run from repository root with:
#   vivado -mode batch -source tools/vivado_scripts/package_three_bank_generic_ips.tcl
#
# Packages:
#   DataProcessorTop
#   HannROM
#   bram_sp
#   goertzel_engines_3bank
#
# The helper RTL files stay inside their parent IP package. Keeping only the
# diagram-facing blocks visible in the IP catalog makes the rebuilt block design
# match the current schematic.

set main_project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set main_project_root [file dirname $main_project_path]
set source_dir         [file normalize "$main_project_root/final_project_hardware.srcs/sources_1/new"]
set ip_repo_dir        [file normalize "$main_project_root/ip_repo"]
set part_name          "xc7z010clg400-1"

proc package_one_ip {core_name display_name description rtl_files} {
    global main_project_root ip_repo_dir part_name

    set ip_root_dir  [file normalize "$ip_repo_dir/${core_name}_1_0"]
    set packager_dir [file normalize "$main_project_root/.${core_name}_ip_packager_tmp"]

    if {[file exists $ip_root_dir]} {
        file delete -force $ip_root_dir
    }
    if {[file exists $packager_dir]} {
        file delete -force $packager_dir
    }

    create_project ${core_name}_ip_packager $packager_dir -part $part_name -force
    set_property target_language VHDL [current_project]

    add_files -norecurse $rtl_files

    foreach rtl_file $rtl_files {
        if {[string match *.vhd $rtl_file]} {
            set_property file_type VHDL [get_files $rtl_file]
        }
    }

    set_property top $core_name [current_fileset]
    update_compile_order -fileset sources_1

    ipx::package_project \
        -root_dir $ip_root_dir \
        -vendor user.org \
        -library user \
        -taxonomy /UserIP \
        -import_files \
        -set_current true

    set core [ipx::current_core]
    set_property name $core_name $core
    set_property display_name $display_name $core
    set_property description $description $core
    set_property vendor_display_name {ECE 615} $core
    set_property company_url {https://example.local/ece615} $core

    ipx::infer_bus_interfaces $core

    foreach clk_name [list clk sys_clk] {
        set clk_if [ipx::get_bus_interfaces $clk_name -of_objects $core]
        if {[llength $clk_if] > 0} {
            set_property interface_mode slave $clk_if
        }
    }

    foreach rst_name [list rst sys_rst] {
        set rst_if [ipx::get_bus_interfaces $rst_name -of_objects $core]
        if {[llength $rst_if] > 0} {
            set_property interface_mode slave $rst_if
        }
    }

    ipx::update_checksums $core
    ipx::save_core $core
    close_project

    if {[file exists $packager_dir]} {
        file delete -force $packager_dir
    }

    puts "Packaged $core_name IP at: $ip_root_dir"
}

file mkdir $ip_repo_dir

package_one_ip \
    DataProcessorTop \
    {Data Processor Top} \
    {Three-bank data preprocessor with per-bank clock dividers, Hann address generation, RAM write controls, and Goertzel handshakes.} \
    [list \
        "$source_dir/DataProcessorController.vhd" \
        "$source_dir/DataProcessorDatapath.vhd" \
        "$source_dir/clk_divider.vhd" \
        "$source_dir/DataProcessorTop.vhd" \
    ]

package_one_ip \
    HannROM \
    {HannROM} \
    {Three-port synchronous Hann coefficient ROM for the 3 kHz, 12 kHz, and 48 kHz preprocessing banks.} \
    [list "$source_dir/HannROM.vhd"]

package_one_ip \
    bram_sp \
    {bram_sp} \
    {Single-clock 4096 x 24-bit bank RAM with independent write and registered read addresses.} \
    [list "$source_dir/bram_sp.vhd"]

package_one_ip \
    goertzel_engines_3bank \
    {Goertzel Engines 3 Bank} \
    {Diagram-facing wrapper that time-multiplexes one shared Goertzel core across three bank RAMs and emits the strongest detected piano-key number.} \
    [list \
        "$source_dir/goertzel_engines_3bank.vhd" \
        "$source_dir/goertzel_shared_multi_bank.vhd" \
        "$source_dir/goertzel_bank1_coeff.mem" \
        "$source_dir/goertzel_bank2_coeff.mem" \
        "$source_dir/goertzel_bank3_coeff.mem" \
    ]

open_project $main_project_path
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog
close_project

puts "Registered IP repository path: $ip_repo_dir"
