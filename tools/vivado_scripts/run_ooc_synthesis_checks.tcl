# Run out-of-context synthesis for the custom IP blocks used by design_1.
#
# Run from repository root with:
#   vivado -mode batch -source tools/vivado_scripts/run_ooc_synthesis_checks.tcl

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set bd_path      [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd"]

open_project $project_path
update_ip_catalog
open_bd_design $bd_path

generate_target all [get_files $bd_path]
create_ip_run [get_files $bd_path]

set ooc_runs [list]
foreach run_obj [get_runs -quiet *_synth_1] {
    set run_name [get_property NAME $run_obj]
    if {[string match "design_1_adc_sample_48khz_sam_0_*_synth_1" $run_name] ||
        [string match "design_1_DataProcessorTop_0_*_synth_1" $run_name] ||
        [string match "design_1_HannROM_0_*_synth_1" $run_name] ||
        [string match "design_1_bram_sp_0_*_synth_1" $run_name] ||
        [string match "design_1_bram_sp_1_*_synth_1" $run_name] ||
        [string match "design_1_bram_sp_2_*_synth_1" $run_name] ||
        [string match "design_1_goertzel_engines_3bank_0_*_synth_1" $run_name]} {
        lappend ooc_runs $run_obj
    }
}

if {[llength $ooc_runs] == 0} {
    error "No matching OOC synthesis runs were found."
}

foreach run_obj $ooc_runs {
    reset_run $run_obj
}

launch_runs $ooc_runs -jobs 4

foreach run_obj $ooc_runs {
    wait_on_run $run_obj
    set status [get_property STATUS $run_obj]
    puts "$run_obj status: $status"

    if {([string first "synth_design Complete" $status] < 0) &&
        ([string first "Using cached IP results" $status] < 0)} {
        error "$run_obj did not complete synthesis successfully."
    }
}

close_project

puts "OOC synthesis checks completed successfully."
