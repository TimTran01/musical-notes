# Upgrade existing Hann and Bank1 RAM BD instances after 24-bit interface change.
#
# Run from repository root with:
#   vivado -mode batch -source tools/upgrade_hann_24bit_bd.tcl
#
# This script refreshes the local IP catalog, upgrades locked IP instances in
# design_1, keeps the Hann-to-Bank1 wiring, and fixes active-high reset wiring
# for both custom IP blocks.

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set bd_path      [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd"]

open_project $project_path
update_ip_catalog
open_bd_design $bd_path

set hann_xci  "design_1_hann_window_4096_0_0"
set bank1_xci "design_1_hann_window_bank1_ram_0_0"

set ips_to_upgrade [list]
foreach ip_name [list $hann_xci $bank1_xci] {
    set ip_obj [get_ips -quiet $ip_name]
    if {[llength $ip_obj] > 0} {
        lappend ips_to_upgrade $ip_obj
    }
}

if {[llength $ips_to_upgrade] > 0} {
    upgrade_ip $ips_to_upgrade
}

proc disconnect_pin {pin_name} {
    set pin_obj [get_bd_pins -quiet $pin_name]
    if {[llength $pin_obj] == 0} {
        return
    }

    set nets [get_bd_nets -quiet -of_objects $pin_obj]
    foreach net $nets {
        disconnect_bd_net $net $pin_obj
    }
}

proc connect_if_needed {source_pin dest_pin} {
    set source_obj [get_bd_pins $source_pin]
    set dest_obj   [get_bd_pins $dest_pin]
    set dest_net   [get_bd_nets -quiet -of_objects $dest_obj]

    if {[llength $dest_net] == 0} {
        connect_bd_net $source_obj $dest_obj
    }
}

# Both custom RTL reset ports are active-high. Use peripheral_reset, not the
# active-low peripheral_aresetn output from proc_sys_reset.
disconnect_pin "hann_window_4096_0/rst"
disconnect_pin "hann_window_bank1_ram_0/rst"
connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_reset] \
               [get_bd_pins hann_window_4096_0/rst] \
               [get_bd_pins hann_window_bank1_ram_0/rst]

# Preserve/restore the intended 24-bit data path from Hann output into Bank1 RAM.
connect_if_needed "hann_window_4096_0/sample_out" "hann_window_bank1_ram_0/sample_in"
connect_if_needed "hann_window_4096_0/sample_valid_out" "hann_window_bank1_ram_0/sample_valid_in"
connect_if_needed "hann_window_4096_0/frame_start_out" "hann_window_bank1_ram_0/frame_start_in"

validate_bd_design
save_bd_design
close_project

puts "Upgraded Hann and Bank1 RAM BD instances to 24-bit sample path."
