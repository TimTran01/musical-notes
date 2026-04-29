# Musical Notes

Vivado 2023.2 project for the Zybo Z7-10 note detector hardware design.

## Custom IP

Local packaged Vivado IP cores:

- `adc_sample_48khz_sampler` (`user.org:user:adc_sample_48khz_sampler:1.0`)

This IP is stored in `final_project_hardware/ip_repo/adc_sample_48khz_sampler_1_0` and instantiated in the main block design at `final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd`.

The sampler IP provides a repeatable ADC sample source for the hardware design. It wraps a synchronous ROM initialized from generated 24-bit ADC sample data, then outputs samples at a 48 kHz average rate from the 50 MHz Zynq PS clock. The implementation details, generics, and signal timing are documented in the VHDL comments.

The packaged IP includes the sampler RTL, ROM RTL, generated memory data, and Vivado XGUI metadata. The helper scripts in `tools/` regenerate the sample memory contents and repackage the IP when needed.

## Rebuild

1. Install Vivado 2023.2 and the Digilent Zybo Z7-10 board files.
2. Open `final_project_hardware/final_project_hardware.xpr`.
3. Refresh IP repositories if Vivado prompts for it. The local IP repository is in `final_project_hardware/ip_repo`.
4. Regenerate block design output products, then run synthesis/implementation.

Tracked project inputs include the RTL, memory initialization files, testbenches, block design files, XCI IP configuration files, local packaged IP, and the XPR project file. Generated Vivado and Vitis output directories are ignored and should be rebuilt locally.
