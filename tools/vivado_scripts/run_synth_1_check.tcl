# Run project synthesis from batch and fail the Tcl process if synth_1 fails.
#
# Run from the repository root:
#   vivado -mode batch -source tools/vivado_scripts/run_synth_1_check.tcl

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]

open_project $project_path

# Reset the top-level synthesis run so the check uses the current generated BD
# products and current packaged IP output files.
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    close_project
    error "synth_1 did not complete successfully"
}

close_project
