# Musical Notes

Vivado 2023.2 hardware project for the Zybo Z7-10 piano-note detector.

The current hardware project is `final_project_hardware`. It contains the
openable Vivado project, the block design, the local packaged IP repository,
the RTL sources used to package those IPs, and simulation testbenches for the
detector path.

## Hardware Design

The block design is stored at
`final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1/design_1.bd`
and can be opened from `final_project_hardware/final_project_hardware.xpr`.

At a high level, the design replays a generated 48 kHz ADC sample frame,
preprocesses the stream into three analysis banks, runs a shared Goertzel
detector across all 88 piano-note bins, and latches the detected note for the
Zynq processing system through AXI GPIO and an interrupt.

The custom IP packages live under `final_project_hardware/ip_repo`. The block
design also uses standard Vivado/Zynq IP such as Processing System 7, AXI GPIO,
AXI interconnect, reset/constant blocks, and debug ILA cores.

## Custom IP

### `adc_sample_48khz_sampler`

Vivado VLNV: `user.org:user:adc_sample_48khz_sampler:1.0`

This IP provides the repeatable ADC input stream used by the hardware design.
It wraps `adc_sample_rom`, reads 24-bit signed samples from `adc_samples.mem`,
and emits a one-clock `sample_valid` pulse for each output sample. The default
configuration is a 50 MHz input clock and a 48 kHz sample rate.

Because 50 MHz does not divide evenly into 48 kHz, the sampler uses a
fractional accumulator instead of creating a separate 48 kHz clock domain. It
alternates the sample spacing between 1041 and 1042 input-clock cycles so the
long-term average rate is exactly 48 kHz. The ROM holds one 4096-sample frame;
`sample_index` and `frame_start` identify the current frame position.

### `DataProcessorTop`

Vivado VLNV: `user.org:user:DataProcessorTop:1.0`

`DataProcessorTop` is the three-bank preprocessing IP. It connects
`DataProcessorController`, `DataProcessorDatapath`, and `clk_divider` into the
block-design interface used by the current system. The preprocessor accepts one
24-bit ADC sample stream and produces windowed RAM write traffic for the 3 kHz,
12 kHz, and 48 kHz analysis banks.

The datapath owns the bank counters, Hann coefficient address generation, sample
multiplication, and write data formatting. The controller sequences each bank's
write enable and Goertzel start/done handshake. The included `clk_divider`
logic provides the per-bank timing enables needed for the 3 kHz, 12 kHz, and
48 kHz data paths while keeping the IP synchronous to the shared system clock.

The public ports are intentionally bank-specific: `hann_addr0..2`, `ram_addr3`,
`ram_addr12`, `ram_addr48`, `ram_data3`, `ram_data12`, `ram_data48`,
`RAM_WE3`, `RAM_WE12`, `RAM_WE48`, `G_EN3`, `G_EN12`, `G_EN48`, and matching
`G_DONE` inputs. These signals wire directly to the Hann ROM, bank RAMs, and
Goertzel wrapper in the block design.

### `HannROM`

Vivado VLNV: `user.org:user:HannROM:1.0`

`HannROM` is a three-port synchronous coefficient ROM shared by the three
preprocessing banks. Each port accepts a 12-bit address and returns a 24-bit
Hann coefficient on the shared clock, allowing the 3 kHz, 12 kHz, and 48 kHz
banks to fetch independent coefficients in the same cycle.

The full analysis window is 4096 samples, but the Hann window is symmetric. To
save ROM space, the IP stores only the first 2048 coefficients. Addresses
0..2047 read directly from the stored table, while addresses 2048..4095 mirror
through `4095 - addr` to reconstruct the second half of the window.

### `bram_sp`

Vivado VLNV: `user.org:user:bram_sp:1.0`

`bram_sp` is the packaged bank RAM IP, displayed by Vivado as
`bram_sp_v1_0`. The block design instantiates three copies, one each for the
3 kHz, 12 kHz, and 48 kHz sample banks.

The RAM is parameterized by `DATA_WIDTH` and `ADDR_WIDTH`, with the detector
using the default 24-bit data width and 12-bit address width for 4096 samples.
It has one synchronous write interface and one registered read interface with
independent write and read addresses. The preprocessor writes windowed samples;
the Goertzel wrapper later reads those samples by bank and block.

### `goertzel_engines_3bank`

Vivado VLNV: `user.org:user:goertzel_engines_3bank:1.0`

This IP wraps the note-detection stage for all three RAM banks. It accepts the
per-bank `G_EN` requests from the preprocessor, reads the requested bank RAM
through `RAM_ADDR3`, `RAM_ADDR12`, and `RAM_ADDR48`, and returns the matching
`G_DONE` pulse when that bank's block has been processed.

Internally the wrapper time-multiplexes one shared Goertzel core across the
three banks. This keeps the design small enough for the Zybo Z7-10 while still
covering all 88 piano keys. Bank 1 maps 24 bins to keys 1..24, bank 2 maps
24 bins to keys 25..48, and bank 3 maps 40 bins to keys 49..88. The coefficient
tables are loaded from `goertzel_bank1_coeff.mem`,
`goertzel_bank2_coeff.mem`, and `goertzel_bank3_coeff.mem`.

After all three banks have fresh candidates, the wrapper compares their raw
Goertzel powers, emits the strongest piano-key number on `NOTE_KEY`, and pulses
`NOTE_VALID` for one clock.

### `note_event_latch`

Vivado VLNV: `user.org:user:note_event_latch:1.0`

`note_event_latch` turns the one-clock note decision from the Goertzel wrapper
into a software-readable event. When `NOTE_VALID` is asserted, it stores the
7-bit `NOTE_KEY`, raises `pending`, and drives a level-sensitive `irq` to the
processing system. Software clears the pending event through a one-bit `clear`
input connected through AXI GPIO.

## Project Layout

- `final_project_hardware/final_project_hardware.xpr`: Vivado 2023.2 project.
- `final_project_hardware/final_project_hardware.srcs/sources_1/bd/design_1`: main block design.
- `final_project_hardware/final_project_hardware.srcs/sources_1/new`: RTL and memory files used by the project.
- `final_project_hardware/final_project_hardware.srcs/sim_1/new`: hardware simulation testbenches and note-vector memories.
- `final_project_hardware/ip_repo`: local packaged custom IP repository.
- `tools/generate_adc_samples.py`: regenerates ADC sample memory contents.
- `tools/generate_goertzel_bank_files.py`: regenerates Goertzel coefficient memories.
- `tools/vivado_scripts`: Vivado batch scripts for packaging IP, regenerating block-design output products, synthesis/implementation checks, bitstream generation, and hardware export.

Generated Vivado run directories, caches, logs, bitstreams, and Vitis output
products are not tracked. They should be rebuilt locally from the project,
source, memory, block-design, and script inputs in this repository.

## Rebuild

1. Install Vivado 2023.2 and the Digilent Zybo Z7-10 board files.
2. Open `final_project_hardware/final_project_hardware.xpr`.
3. Refresh the local IP repository if Vivado prompts for it. The repository path
   is `final_project_hardware/ip_repo`.
4. Regenerate block-design output products for `design_1`.
5. Run synthesis, implementation, and bitstream generation.

The same flow can be run from batch scripts in `tools/vivado_scripts`. The most
useful entry points are `regenerate_design_1_outputs.tcl`,
`run_synth_1_check.tcl`, `run_impl_1_check.tcl`, `run_bitstream_check.tcl`, and
`build_and_export_note_hardware.tcl`.

## Simulation

The tracked testbench inputs are under
`final_project_hardware/final_project_hardware.srcs/sim_1/new`. The full design
and all-88-note checks can be launched with:

```sh
vivado -mode batch -source final_project_hardware/run_full_sim_check.tcl
vivado -mode batch -source final_project_hardware/run_88_note_sim_check.tcl
```

The Python check scripts in `final_project_hardware` compare theoretical note
results against hardware simulation output. Generated reports are local build
artifacts and are not required to open or rebuild the Vivado project.
