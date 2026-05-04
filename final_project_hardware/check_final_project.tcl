open_project {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/final_project_hardware.xpr}
set_property ip_repo_paths {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/ip_repo} [current_project]
update_ip_catalog -rebuild
open_bd_design {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd}
report_ip_status -file {C:/Users/Tim/Documents/ECE_615/final_project/final_project_hardware/ip_status.rpt}
upgrade_ip [get_ips]
validate_bd_design
update_compile_order -fileset sources_1
save_bd_design
close_project
exit
