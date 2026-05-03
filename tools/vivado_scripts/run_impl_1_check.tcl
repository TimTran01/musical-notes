# Run project implementation from batch and fail the Tcl process if impl_1 does
# not finish. This is the implementation-side companion to run_synth_1_check.tcl
# and is useful for catching placement DRC/resource errors such as CARRY4 or DSP
# over-utilization before reopening the Vivado GUI.
#
# Run from the repository root:
#   vivado -mode batch -source tools/vivado_scripts/run_impl_1_check.tcl

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]

open_project $project_path

# Re-run implementation against the current synthesized netlist and packaged IP
# checkpoints. reset_run impl_1 preserves synth_1 but clears stale place/route
# results that may have been produced by an older datapath.
reset_run impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"

if {[string first "Complete!" $impl_status] < 0} {
    close_project
    error "impl_1 did not complete successfully"
}

close_project
