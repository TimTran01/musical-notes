# Add the PL-to-PS note bridge used by the Vitis UART note application.
#
# Run from repository root:
#   /mnt/c/Xilinx/Vivado/2023.2/bin/vivado -mode batch -source tools/vivado_scripts/connect_note_uart_bd.tcl

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set bd_path      [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd"]
set source_dir   [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/new"]
set latch_file   [file normalize "$source_dir/note_event_latch.vhd"]
set wrapper_file [file normalize "$source_dir/design_1_wrapper.vhd"]
set adc_samples_file "adc_samples.mem"
set bank1_coeff_file "goertzel_bank1_coeff.mem"
set bank2_coeff_file "goertzel_bank2_coeff.mem"
set bank3_coeff_file "goertzel_bank3_coeff.mem"

open_project $project_path

if {[llength [get_files -quiet $latch_file]] == 0} {
    add_files -norecurse $latch_file
    set_property file_type VHDL [get_files $latch_file]
}
update_compile_order -fileset sources_1
update_ip_catalog

open_bd_design $bd_path

report_ip_status -file [file normalize "final_project_hardware/note_uart_ip_status.rpt"]
set design_ips [get_ips -quiet]
if {[llength $design_ips] > 0} {
    upgrade_ip $design_ips
}

set ps_cell       "processing_system7_0"
set reset_cell    "rst_ps7_0_50M"
set goertzel_cell "goertzel_engines_3bank_0"
set sampler_cell  "adc_sample_48khz_sam_0"
set latch_cell    "note_event_latch_0"
set gpio_cell     "note_axi_gpio_0"
set concat_cell   "note_status_concat_0"

proc create_ip_if_missing {cell_name vlnv} {
    if {[llength [get_bd_cells -quiet $cell_name]] == 0} {
        create_bd_cell -type ip -vlnv $vlnv $cell_name
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

proc connect_intf_if_needed {source_pin dest_pin} {
    set source_obj [get_bd_intf_pins $source_pin]
    set dest_obj   [get_bd_intf_pins $dest_pin]
    set dest_net   [get_bd_intf_nets -quiet -of_objects $dest_obj]

    if {[llength $dest_net] == 0} {
        connect_bd_intf_net $source_obj $dest_obj
    }
}

set_property -dict [list \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_IRQ_F2P_MODE {DIRECT} \
] [get_bd_cells $ps_cell]

create_ip_if_missing $latch_cell "user.org:user:note_event_latch:1.0"
create_ip_if_missing $gpio_cell "xilinx.com:ip:axi_gpio:2.0"
create_ip_if_missing $concat_cell "xilinx.com:ip:xlconcat:2.1"

set_property -dict [list \
    CONFIG.MEM_FILE $adc_samples_file \
] [get_bd_cells $sampler_cell]

set_property -dict [list \
    CONFIG.BANK1_COEFF_FILE $bank1_coeff_file \
    CONFIG.BANK2_COEFF_FILE $bank2_coeff_file \
    CONFIG.BANK3_COEFF_FILE $bank3_coeff_file \
] [get_bd_cells $goertzel_cell]

set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {8} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO2_WIDTH {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
    CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells $gpio_cell]

set_property -dict [list \
    CONFIG.NUM_PORTS {2} \
    CONFIG.IN0_WIDTH {7} \
    CONFIG.IN1_WIDTH {1} \
] [get_bd_cells $concat_cell]

# Clock and reset for the latch and AXI GPIO.
connect_if_needed "$ps_cell/FCLK_CLK0" "$latch_cell/clk"
connect_if_needed "$reset_cell/peripheral_reset" "$latch_cell/rst"
connect_if_needed "$ps_cell/FCLK_CLK0" "$gpio_cell/s_axi_aclk"
connect_if_needed "$reset_cell/peripheral_aresetn" "$gpio_cell/s_axi_aresetn"

# Existing note result keeps feeding the ILA and now also feeds the software latch.
connect_if_needed "$goertzel_cell/NOTE_KEY" "$latch_cell/note_key"
connect_if_needed "$goertzel_cell/NOTE_VALID" "$latch_cell/note_valid"

# GPIO channel 1 input: bit 7 pending, bits 6:0 key.
connect_if_needed "$latch_cell/latched_key" "$concat_cell/In0"
connect_if_needed "$latch_cell/pending" "$concat_cell/In1"
connect_if_needed "$concat_cell/dout" "$gpio_cell/gpio_io_i"

# GPIO channel 2 output clears the held pending interrupt.
connect_if_needed "$gpio_cell/gpio2_io_o" "$latch_cell/clear"

# Level-sensitive PL interrupt into the Zynq PS.
connect_if_needed "$latch_cell/irq" "$ps_cell/IRQ_F2P"

# Attach AXI GPIO to PS GP0. BD automation inserts the required interconnect if
# the design does not already contain one.
if {[llength [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins "$gpio_cell/S_AXI"]]] == 0} {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
        -config [list \
            Clk_master {/processing_system7_0/FCLK_CLK0 (50 MHz)} \
            Clk_slave {/processing_system7_0/FCLK_CLK0 (50 MHz)} \
            Clk_xbar {/processing_system7_0/FCLK_CLK0 (50 MHz)} \
            Master {/processing_system7_0/M_AXI_GP0} \
            Slave {/$gpio_cell/S_AXI} \
            intc_ip {New AXI Interconnect} \
            master_apm {0} \
        ] \
        [get_bd_intf_pins "$gpio_cell/S_AXI"]
}

assign_bd_address

validate_bd_design
save_bd_design
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
update_compile_order -fileset sim_1

close_project

puts "Connected note UART bridge in design_1."
