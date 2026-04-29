# Musical Notes

Vivado 2023.2 project for the Zybo Z7-10 note detector hardware design.

## Rebuild

1. Install Vivado 2023.2 and the Digilent Zybo Z7-10 board files.
2. Open `final_project_hardware/final_project_hardware.xpr`.
3. Refresh IP repositories if Vivado prompts for it. The local IP repository is in `final_project_hardware/ip_repo`.
4. Regenerate block design output products, then run synthesis/implementation.

Tracked project inputs include the RTL, memory initialization files, testbenches, block design files, XCI IP configuration files, local packaged IP, and the XPR project file. Generated Vivado and Vitis output directories are ignored and should be rebuilt locally.
