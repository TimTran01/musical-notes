# Regenerate design_1 block-design output products.
#
# Use this after repackaging or upgrading local IP. Vivado can leave an older
# generated synth wrapper in final_project_hardware.gen; if that wrapper still
# names prior IP instance modules, synthesis reports "module ... not found".
#
# Run from the repository root:
#   vivado -mode batch -source tools/vivado_scripts/regenerate_design_1_outputs.tcl

set project_path [file normalize "final_project_hardware/final_project_hardware.xpr"]
set ip_repo_dir  [file normalize "final_project_hardware/ip_repo"]
set bd_path      [file normalize "final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd"]

open_project $project_path

# Make sure the project sees the freshly packaged local IP definitions before
# regenerating BD products. This is what keeps the generated wrapper and .xci
# instance module names synchronized.
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog

open_bd_design $bd_path
validate_bd_design
save_bd_design

# Rebuild the HDL wrapper/netlists under final_project_hardware.gen from the
# current design_1.bd metadata. The -force option overwrites stale generated
# files that may still reference older IP instance names such as *_0_2.
generate_target all [get_files $bd_path] -force

# Refresh the project compile order after the generated files have been updated.
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

close_project

puts "Regenerated output products for design_1.bd"
