# Final Project Software

Vitis workspace files for the piano note detector.

## Hardware export

Run from the repository root after opening the project with Vivado 2023.2 installed. Package the local IP first, then connect the note bridge, then build/export the XSA:

```sh
cmd.exe /C C:/Xilinx/Vivado/2023.2/bin/vivado.bat -mode batch -source tools/vivado_scripts/package_three_bank_generic_ips.tcl
cmd.exe /C C:/Xilinx/Vivado/2023.2/bin/vivado.bat -mode batch -source tools/vivado_scripts/connect_note_uart_bd.tcl
cmd.exe /C C:/Xilinx/Vivado/2023.2/bin/vivado.bat -mode batch -source tools/vivado_scripts/build_and_export_note_hardware.tcl
```

The exported XSA is written to:

```text
final_project_software/hw/final_project_hardware.xsa
```

## Vitis app

Create and build the Vitis Unified IDE platform/application components from the exported XSA:

```sh
cmd.exe /C C:/Xilinx/Vitis/2023.2/bin/vitis.bat -s tools/vitis_scripts/create_note_uart_components.py
```

The canonical app source is:

```text
final_project_software/piano_detect_application/src/main.c
```

The tracked Vitis component definitions are:

```text
final_project_software/piano_detect_platform/vitis-comp.json
final_project_software/piano_detect_application/vitis-comp.json
```

The generated platform export, application build output, `_ide` folders, logs,
bitstream copies, and ELF files are local build products and are not committed.

Open `final_project_software` as the Vitis Unified IDE workspace. The platform
and application component folders stay inside that workspace.

The app sends one CSV line per interrupt-driven note event:

```text
key,note,freq_hz
```

Example:

```text
49,A4,440.00
```
