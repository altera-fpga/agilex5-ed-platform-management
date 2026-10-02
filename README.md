# HPS OmniMC System Example Designs

This repository contains OpenBMC System Example Designs (OmniMC) for Altera Agilex 5 E-Series and Agilex 3 C-Series System On Chip (SoC) FPGA.
This project provides the necessary files and collaterals to build a complete solution, including exercising soft IP in the fabric, booting to U-Boot, then Linux, and running sample Linux applications.
Refer to the [OpenBMC System Example Design User Guide](https://github.com/altera-fpga/agilex5-ed-platform-management) for more information.

The [designs](#designs) are stored in individual folders. Each design can be opened, modified and compiled by using Quartus Prime software.
Repository releases are tagged for each version of Quartus Prime Software. It is recommended to use the release for your version of Quartus Prime.
These designs demonstrate the system integration between Hard Processor System (HPS) and FPGA IPs.

## Features and Specifications
This is applicable to all designs.
- Hard Processor System (HPS) enablement and configuration
  - Enable dual core Arm Cortex-A76 processor
  - Enable dual core Arm Cortex-A55 processor
  - HPS Peripheral and I/O. eg, NAND, SD/MMC, EMAC, USB, SPI, I2C, I3C, UART, and GPIO. (depends on the daughter card).
  - HPS Clock and Reset
  - HPS FPGA Bridge and Interrupt
    - Note: The System MMU port in F2H and F2SDRAM bridges are disabled by default in baseline design, unless otherwise specified.
- HPS EMIF configuration (starting 25.1.1 ECC is enabled by default)
- System integration with FPGA IPs
  - Peripheral subsystem that consists of System ID, Programmable I/O (PIO) IP for controlling DIPSW, PushButton, and LEDs.
  - 14-bit bidirectional GPIO (`universal_gpio`) and I3C/I2C bus-mode select (BMC sensor designs)
  - Debug subsystem that consists of JTAG-to-Avalon Master IP to allow System-Console debug activity and FPGA content access through JTAG
  - 256KB of FPGA On-Chip Memory

## Advanced feature
This is only applicable if the feature is enabled.
- Software-selectable I3C / EMAC0 I2C on the Altera Sensor Board SDA/SCL pads

## Dependency
* Altera Quartus Prime 26.1.1
* Supported Altera Development Kit
  - Agilex 5 FPGA E-Series 013B Development Kit DK-A5E013BM16AEA
  - Agilex 3 FPGA and SoC C-Series Development Kit DK-A3W135BM16AEA
  - Altera Sensor Board

## Tested platform for the hardware build flow
* SUSE Linux Enterprise Server 15 SP4

## Setup

Several tools are required to be in the path.

* Altera Quartus Prime 26.1.1
* Python 3.11.5 (only required when using command line to build)

### Example Setup for Altera Quartus Prime tools
This is recommended, when using command line to build.
```bash
export QUARTUS_ROOTDIR=~/alteraFPGA_pro/26.1.1/quartus
```
Note: Adapt the path above to where Quartus Prime is installed.

```bash
export PATH="$QUARTUS_ROOTDIR/bin:$QUARTUS_ROOTDIR/../qsys/bin:$QUARTUS_ROOTDIR/../niosv/bin:$QUARTUS_ROOTDIR/sopc_builder/bin:$QUARTUS_ROOTDIR/../questa_fe/bin:$QUARTUS_ROOTDIR/../syscon/bin:$QUARTUS_ROOTDIR/../riscfree/RiscFree:$PATH"
```

## Quick start

### Using command line

1. Choose a design under [designs](#designs) for your development kit.
2. Change to that design directory. Example:

```bash
cd dk-a5e013bm16aea-omnimc-sensor/bmc-demo
```

3. Follow the README in that directory for command-line build, simulation, and software steps.

### Using Quartus GUI
- Launch Quartus.
- Open the project. Example: dk-a5e013bm16aea-omnimc-sensor/bmc-demo/top.qpf
- Click the play button to compile the design.
- The compiled sof can be found in output_files folder of the project path.

### Notes
- Command line and Quartus GUI should not be used intertwined.
- Mixing both design build flows might not generate some fileset correctly and fail the build.


## Designs

This section lists **every** shipped design in the repository, grouped by development kit.
Each bullet links to that design's README for build instructions and functional detail;
use the platform index link for devkit context.

### Agilex 5 FPGA E-Series 013B Development Kit DK-A5E013BM16AEA — BMC Sensor

Platform index: [dk-a5e013bm16aea-omnimc-sensor](dk-a5e013bm16aea-omnimc-sensor/README.md)

* [dk-a5e013bm16aea-omnimc-sensor/bmc-demo](dk-a5e013bm16aea-omnimc-sensor/bmc-demo/README.md) :
  HPS OmniMC / OpenBMC System Example Design for the A5ED013 Development Kit with Altera Sensor Board.

### Agilex 3 FPGA and SoC C-Series Development Kit DK-A3W135BM16AEA — BMC Sensor

Platform index: [dk-a3w135bm16aea-omnimc-sensor](dk-a3w135bm16aea-omnimc-sensor/README.md)

* [dk-a3w135bm16aea-omnimc-sensor/bmc-demo](dk-a3w135bm16aea-omnimc-sensor/bmc-demo/README.md) :
  HPS OmniMC / OpenBMC System Example Design for the A3W135 Development Kit with Altera Sensor Board.

