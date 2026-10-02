#
# SPDX-License-Identifier: MIT-0
# SPDX-FileCopyrightText: Copyright (C) 2025 Altera Corporation
#
# =============================================================================
# axi_fan_control_hw.tcl
#
# Platform Designer (Qsys) component descriptor for the axi_fan_control IP.
# Defines all interfaces (clock, reset, AXI4-Lite subordinate, interrupt, conduit)
# and maps each port to the correct interface role.
#
# HDL source (verbatim ADI, dual-licensed GPLv2 OR ADI-BSD):
#   https://github.com/analogdevicesinc/hdl/blob/main/library/axi_fan_control/axi_fan_control.v
#   https://github.com/analogdevicesinc/hdl/tree/main/library/common (up_axi.v, util_pulse_gen.v)
# =============================================================================

package require -exact qsys 25.3.1

# -----------------------------------------------------------------------------
# Module properties
# -----------------------------------------------------------------------------
set_module_property NAME              axi_fan_control
set_module_property VERSION           1.0
set_module_property DISPLAY_NAME      "Fan Control"
set_module_property DESCRIPTION       "AXI4 fan controller (ADI axi_fan_control.v) with PWM output and tachometer input"
set_module_property GROUP             "Fan Control"
set_module_property AUTHOR            "Analog Devices (verbatim); Altera wrapper"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE          false

# -----------------------------------------------------------------------------
# HDL file
# -----------------------------------------------------------------------------
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH generate_fileset
set_fileset_property QUARTUS_SYNTH TOP_LEVEL axi_fan_control

add_fileset SIM_VERILOG SIM_VERILOG generate_fileset
set_fileset_property SIM_VERILOG TOP_LEVEL axi_fan_control

proc generate_fileset {entity_name} {
    add_fileset_file axi_fan_control.v VERILOG PATH ../src/axi_fan_control.v TOP_LEVEL_FILE
    add_fileset_file up_axi.v VERILOG PATH ../src/adi_common/up_axi.v
    add_fileset_file util_pulse_gen.v VERILOG PATH ../src/adi_common/util_pulse_gen.v
}

# -----------------------------------------------------------------------------
# Parameters (ADI names — match axi_fan_control.v)
# -----------------------------------------------------------------------------
add_parameter ID INTEGER 0
set_parameter_property ID DISPLAY_NAME "Core ID"
set_parameter_property ID UNITS        None
set_parameter_property ID HDL_PARAMETER true

add_parameter PWM_FREQUENCY_HZ INTEGER 5000
set_parameter_property PWM_FREQUENCY_HZ DISPLAY_NAME "PWM Frequency (Hz)"
set_parameter_property PWM_FREQUENCY_HZ UNITS        None
set_parameter_property PWM_FREQUENCY_HZ HDL_PARAMETER true

add_parameter INTERNAL_SYSMONE INTEGER 0
set_parameter_property INTERNAL_SYSMONE DISPLAY_NAME "Use internal SYSMON (0=external temp_in; must be 0 on Agilex)"
set_parameter_property INTERNAL_SYSMONE UNITS        None
set_parameter_property INTERNAL_SYSMONE HDL_PARAMETER true

add_parameter AVG_POW INTEGER 7
set_parameter_property AVG_POW DISPLAY_NAME "Tacho Averaging Window (2^N samples, max 7)"
set_parameter_property AVG_POW UNITS        None
set_parameter_property AVG_POW HDL_PARAMETER true

# PWM output polarity. 0 = active-high (pin high = fan full speed), correct for
# the SM43 40-pin Pi header + Geekworm X-FAN40 path (no inverting buffer on the
# carrier; verified on AG21: pwm1=255 -> 3.3 V -> fan full). 1 = active-low for
# carriers that re-invert the PWM on the board.
add_parameter PWM_ACTIVE_LOW INTEGER 0
set_parameter_property PWM_ACTIVE_LOW DISPLAY_NAME "PWM active-low (0=high=full speed; 1=inverting carrier)"
set_parameter_property PWM_ACTIVE_LOW UNITS        None
set_parameter_property PWM_ACTIVE_LOW HDL_PARAMETER true

foreach {name default label} {
    TEMP_00_H   5  "Temp threshold: below = PWM 0% (deg C)"
    TEMP_25_L  20  "Temp threshold: above = PWM 25% (deg C)"
    TEMP_25_H  40  "Temp threshold: below = PWM 25% (deg C)"
    TEMP_50_L  60  "Temp threshold: above = PWM 50% (deg C)"
    TEMP_50_H  70  "Temp threshold: below = PWM 50% (deg C)"
    TEMP_75_L  80  "Temp threshold: above = PWM 75% (deg C)"
    TEMP_75_H  90  "Temp threshold: below = PWM 75% (deg C)"
    TEMP_00_L  95  "Temp threshold: above = PWM 100% (deg C); CSR name TEMP_100_L"
} {
    add_parameter $name INTEGER $default
    set_parameter_property $name DISPLAY_NAME $label
    set_parameter_property $name UNITS        None
    set_parameter_property $name HDL_PARAMETER true
}

foreach {name default label} {
    TACHO_T25  1470000 "Tacho half-period at PWM 25% (100 MHz clock cycles)"
    TACHO_T50   820000 "Tacho half-period at PWM 50% (100 MHz clock cycles)"
    TACHO_T75   480000 "Tacho half-period at PWM 75% (100 MHz clock cycles)"
    TACHO_T100  340000 "Tacho half-period at PWM 100% (100 MHz clock cycles)"
    TACHO_TOL_PERCENT 25 "Tacho tolerance (%)"
} {
    add_parameter $name INTEGER $default
    set_parameter_property $name DISPLAY_NAME $label
    set_parameter_property $name UNITS        None
    set_parameter_property $name HDL_PARAMETER true
}

# -----------------------------------------------------------------------------
# Interface 1 — Clock Input
# -----------------------------------------------------------------------------
add_interface clock clock end
set_interface_property clock clockRate 0
set_interface_property clock ENABLED true

add_interface_port clock s_axi_aclk clk Input 1

# -----------------------------------------------------------------------------
# Interface 2 — Reset Input (active-low)
# -----------------------------------------------------------------------------
add_interface reset reset end
set_interface_property reset associatedClock    clock
set_interface_property reset synchronousEdges   DEASSERT
set_interface_property reset ENABLED true

add_interface_port reset s_axi_aresetn reset_n Input 1

# -----------------------------------------------------------------------------
# Interface 3 — AXI4-Lite Subordinate
# -----------------------------------------------------------------------------
add_interface s_axi axi4lite end
set_interface_property s_axi associatedClock clock
set_interface_property s_axi associatedReset reset
set_interface_property s_axi ENABLED true

add_interface_port s_axi s_axi_awvalid awvalid Input  1
add_interface_port s_axi s_axi_awaddr  awaddr  Input  10
add_interface_port s_axi s_axi_awprot  awprot  Input  3
add_interface_port s_axi s_axi_awready awready Output 1
add_interface_port s_axi s_axi_wvalid  wvalid  Input  1
add_interface_port s_axi s_axi_wdata   wdata   Input  32
add_interface_port s_axi s_axi_wstrb   wstrb   Input  4
add_interface_port s_axi s_axi_wready  wready  Output 1
add_interface_port s_axi s_axi_bvalid  bvalid  Output 1
add_interface_port s_axi s_axi_bresp   bresp   Output 2
add_interface_port s_axi s_axi_bready  bready  Input  1
add_interface_port s_axi s_axi_arvalid arvalid Input  1
add_interface_port s_axi s_axi_araddr  araddr  Input  10
add_interface_port s_axi s_axi_arprot  arprot  Input  3
add_interface_port s_axi s_axi_arready arready Output 1
add_interface_port s_axi s_axi_rvalid  rvalid  Output 1
add_interface_port s_axi s_axi_rdata   rdata   Output 32
add_interface_port s_axi s_axi_rresp   rresp   Output 2
add_interface_port s_axi s_axi_rready  rready  Input  1

# -----------------------------------------------------------------------------
# Interface 4 — Interrupt Sender
# -----------------------------------------------------------------------------
add_interface irq_sender interrupt end
set_interface_property irq_sender associatedClock clock
set_interface_property irq_sender associatedReset reset
set_interface_property irq_sender ENABLED true

add_interface_port irq_sender irq irq Output 1

# -----------------------------------------------------------------------------
# Interface 5 — Conduit (external board signals)
# -----------------------------------------------------------------------------
add_interface fan_io conduit end
set_interface_property fan_io associatedClock ""
set_interface_property fan_io associatedReset ""
set_interface_property fan_io ENABLED true

add_interface_port fan_io temp_in temp_in Input  10
add_interface_port fan_io tacho   tacho   Input  1
add_interface_port fan_io pwm     pwm     Output 1
