# Set the default time format
set_time_format -unit ns -decimal_places 3

# Create shorthand names for clocks
set MAIN_CLOCK [get_clocks {u_baseline_top|u_shell_subsys|u_clocks_and_resets|u_sys_pll|iopll_0_outclk0}]

# Create a virtual clock for the MAIN_CLOCK for use with IO timing
create_clock -name MAIN_CLOCK_virt -period [get_clock_info -period $MAIN_CLOCK]

# Set a loose/small output delay for LED PIOs to complete the I/O constraint requirement.
set_output_delay -source_latency_included -clock [get_clocks MAIN_CLOCK_virt] [expr {0.1 * [get_clock_info -period MAIN_CLOCK_virt]}] [get_ports {fpga_user_leds[*]}]
set_multicycle_path -from $MAIN_CLOCK -to [get_clocks MAIN_CLOCK_virt] -setup -end 3
set_multicycle_path -from $MAIN_CLOCK -to [get_clocks MAIN_CLOCK_virt] -hold -end 2

# Set a loose/small input delay for button PIOs to complete the I/O constraint requirement.
set_input_delay -source_latency_included -clock [get_clocks MAIN_CLOCK_virt] [expr {0.1 * [get_clock_info -period MAIN_CLOCK_virt]}] [get_ports {fpga_user_push_buttons[*]}]

# Set asynchronous clock groups between hps_internal_osc and system main clock.
set_clock_groups -asynchronous -group [get_clocks {hps_internal_osc}] -group $MAIN_CLOCK

# Use -no_synchronizer for the following intra-clock false paths
set_false_path -no_synchronizer -from [get_registers {*|u_clocks_and_resets|fpga_reset_n_sync|dreg[1]}] -to [get_registers {*|altera_reset_synchronizer_int_chain[1]}]
set_false_path -no_synchronizer -from [get_registers {*|u_fabric_subsys|rst_controller|r_sync_rst}] -to [get_registers {*|altera_reset_synchronizer_int_chain[1]}]

# OpenBMC sensor-board header pins — all HPS-managed, tristate-only FPGA fabric logic.
# Timing is controlled by HPS peripheral clocks (I3C, I2C, SPI, UART) which are
# asynchronous to the FPGA fabric clock; constrain as false paths.
set_false_path -to   [get_ports {i3c_sda}]
set_false_path -from [get_ports {i3c_sda}]
set_false_path -to   [get_ports {i3c_scl}]
set_false_path -from [get_ports {i3c_scl}]
set_false_path -to   [get_ports {i3c_pu}]
set_false_path -to   [get_ports {host_tx}]
set_false_path -from [get_ports {host_rx}]
set_false_path -to   [get_ports {acc_sda_sdi}]
set_false_path -from [get_ports {acc_sa0_sdo}]
set_false_path -to   [get_ports {acc_scl_spc}]
set_false_path -to   [get_ports {acc_cs_n}]
set_false_path -to   [get_ports {id_sd}]
set_false_path -from [get_ports {id_sd}]
set_false_path -to   [get_ports {id_sc}]
set_false_path -from [get_ports {id_sc}]

# Fan controller I/O — asynchronous to FPGA fabric clock; use loose I/O delays to satisfy I/O constraints.
set_input_delay  -source_latency_included -clock [get_clocks MAIN_CLOCK_virt] [expr {0.1 * [get_clock_info -period MAIN_CLOCK_virt]}] [get_ports {fan_tach}]
set_output_delay -source_latency_included -clock [get_clocks MAIN_CLOCK_virt] [expr {0.1 * [get_clock_info -period MAIN_CLOCK_virt]}] [get_ports {host_fpwm}]