# Run implementation through bitstream generation and fail the Tcl process if
# write_bitstream does not complete.
#
# Run from the repository root:
#   vivado -mode batch -source tools/vivado_scripts/run_bitstream_check.tcl
#
# This check is intentionally separate from run_impl_1_check.tcl. Placement and
# routing can complete even when write_bitstream later rejects unconstrained
# package pins, so this script verifies the final DRC gate as well.

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]

open_project $project_path

# Re-run implementation from a clean impl_1 state and continue all the way
# through write_bitstream. The synthesized netlist is preserved; run
# tools/vivado_scripts/run_synth_1_check.tcl first after RTL or block-design changes.
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"

if {[string first "write_bitstream Complete!" $impl_status] < 0} {
    close_project
    error "write_bitstream did not complete successfully"
}

close_project
