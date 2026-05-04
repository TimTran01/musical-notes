open_project {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/final_project_hardware.xpr}
set_property ip_repo_paths {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/ip_repo} [current_project]
update_ip_catalog
open_bd_design {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd}
reset_target all [get_files {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd}]
generate_target all [get_files {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd}]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_1_STATUS=$synth_status"
if {$synth_status ne "synth_design Complete!"} {
  exit 1
}
close_project
exit
