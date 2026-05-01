# Musical Notes

Vivado 2023.2 project for the Zybo Z7-10 note detector hardware design.

## Custom IP

Local packaged Vivado IP cores:

- `adc_sample_48khz_sampler` (`user.org:user:adc_sample_48khz_sampler:1.0`)
  Provides a repeatable ADC sample source for the hardware design. It wraps a synchronous ROM initialized from generated 24-bit ADC sample data, then outputs samples at a 48 kHz average rate from the 50 MHz Zynq PS clock.

- `hann_window_4096` (`user.org:user:hann_window_4096:1.0`)
  Applies a 4096-point Hann window to the sample stream. It uses generated coefficient memory and outputs signed 24-bit truncated Hann-windowed samples.

- `hann_window_bank1_ram` (`user.org:user:hann_window_bank1_ram:1.0`)
  Stores 4096 decimated 3 kHz samples from the 24-bit Hann output for later bank-specific detector processing. Piano-key selection is handled by later detector logic, not by this RAM.

The packaged IP sources are stored in `final_project_hardware/ip_repo` and instantiated in the main block design at `final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd`.

The packaged IP folders include RTL, memory data, and Vivado XGUI metadata. The helper scripts in `tools/` regenerate memory contents, package the IP, and update the block design when needed. Implementation details, generics, and timing behavior are documented in the VHDL comments.

## Rebuild

1. Install Vivado 2023.2 and the Digilent Zybo Z7-10 board files.
2. Open `final_project_hardware/final_project_hardware.xpr`.
3. Refresh IP repositories if Vivado prompts for it. The local IP repository is in `final_project_hardware/ip_repo`.
4. Regenerate block design output products, then run synthesis/implementation.

Tracked project inputs include the RTL, memory initialization files, testbenches, block design files, XCI IP configuration files, local packaged IP, and the XPR project file. Generated Vivado and Vitis output directories are ignored and should be rebuilt locally.
