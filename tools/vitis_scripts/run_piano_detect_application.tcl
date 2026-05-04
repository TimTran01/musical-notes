set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".." ".."]]

set elf_file [file normalize [file join $repo_root "final_project_software" "piano_detect_application" "build" "piano_detect_application.elf"]]
set ps7_init_file [file normalize [file join $repo_root "final_project_software" "piano_detect_application" "_ide" "psinit" "ps7_init.tcl"]]

if {![file exists $elf_file]} {
    error "Missing ELF: $elf_file"
}

if {![file exists $ps7_init_file]} {
    error "Missing ps7_init.tcl: $ps7_init_file"
}

connect
puts "Connected targets:"
puts [targets]

if {[catch {targets -set -nocase -filter {name =~ "*Cortex-A9*#0"}}]} {
    targets -set -nocase -filter {name =~ "*ARM*#0"}
}

rst -processor
source $ps7_init_file
ps7_init
ps7_post_config
dow $elf_file
con
puts "Running piano_detect_application.elf"
exit
