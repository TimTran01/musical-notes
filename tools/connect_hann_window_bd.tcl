# Connect hann_window_4096 into design_1 block diagram.
#
# Run from repository root with:
#   vivado -mode batch -source tools/connect_hann_window_bd.tcl
#
# The script is idempotent enough for normal project use: if the Hann instance
# or enable constant already exists, it reuses them. It also corrects reset
# wiring so active-high custom IP reset ports use proc_sys_reset/peripheral_reset
# instead of peripheral_aresetn.

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set bd_path      [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd"]

open_project $project_path
open_bd_design $bd_path

set sampler_cell "adc_sample_48khz_sam_0"
set hann_cell    "hann_window_4096_0"
set const_cell   "xlconstant_enable_1"
set reset_cell   "rst_ps7_0_50M"
set ps_cell      "processing_system7_0"

# Make sure the packaged Hann IP exists in the catalog before trying to place it.
update_ip_catalog

if {[llength [get_bd_cells -quiet $hann_cell]] == 0} {
    create_bd_cell -type ip -vlnv user.org:user:hann_window_4096:1.0 $hann_cell
}

# The sampler needs enable tied high for continuous playback. Reuse a one-bit
# xlconstant if it already exists; otherwise create and configure one.
if {[llength [get_bd_cells -quiet $const_cell]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 $const_cell
}
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells $const_cell]

# Helper that connects two pins only when they are not already connected.
proc connect_if_needed {source_pin dest_pin} {
    set source_obj [get_bd_pins $source_pin]
    set dest_obj   [get_bd_pins $dest_pin]
    set dest_net   [get_bd_nets -quiet -of_objects $dest_obj]

    if {[llength $dest_net] == 0} {
        connect_bd_net $source_obj $dest_obj
    }
}

# Helper that removes all current net connections from a pin. This is used for
# reset pins because earlier custom-IP reset wiring used active-low aresetn.
proc disconnect_pin {pin_name} {
    set pin_obj [get_bd_pins $pin_name]
    set nets [get_bd_nets -quiet -of_objects $pin_obj]
    foreach net $nets {
        disconnect_bd_net $net $pin_obj
    }
}

# Clock: both custom IPs run from the same 50 MHz Zynq FCLK_CLK0 domain.
connect_if_needed "$ps_cell/FCLK_CLK0" "$hann_cell/clk"

# Existing PS configuration has M_AXI_GP0 enabled. Its ACLK must be tied to a
# clock source or block-design validation fails, even though this task does not
# use AXI transactions yet.
connect_if_needed "$ps_cell/FCLK_CLK0" "$ps_cell/M_AXI_GP0_ACLK"

# Reset: hann_window_4096.rst and adc_sample_48khz_sampler.rst are active-high.
# Use proc_sys_reset/peripheral_reset, not peripheral_aresetn.
disconnect_pin "$sampler_cell/rst"
connect_bd_net [get_bd_pins "$reset_cell/peripheral_reset"] [get_bd_pins "$sampler_cell/rst"]
connect_if_needed "$reset_cell/peripheral_reset" "$hann_cell/rst"

# Sampler enable: run continuously for now. Later, this can be replaced by a
# real control signal when runtime start/stop control is needed.
connect_if_needed "$const_cell/dout" "$sampler_cell/enable"

# Sample stream: pass the 24-bit ADC sample, one-cycle valid pulse, frame index,
# and frame_start marker from the 48 kHz sampler into the Hann window IP.
connect_if_needed "$sampler_cell/sample" "$hann_cell/sample_in"
connect_if_needed "$sampler_cell/sample_valid" "$hann_cell/sample_valid_in"
connect_if_needed "$sampler_cell/sample_index" "$hann_cell/sample_index_in"
connect_if_needed "$sampler_cell/frame_start" "$hann_cell/frame_start_in"

# Leave Hann outputs unconnected for now. The next stage, Goertzel/bank sampler,
# will consume sample_out, sample_valid_out, sample_index_out, and frame_start_out.
validate_bd_design
save_bd_design
close_project

puts "Connected hann_window_4096_0 to adc_sample_48khz_sam_0 in design_1."
