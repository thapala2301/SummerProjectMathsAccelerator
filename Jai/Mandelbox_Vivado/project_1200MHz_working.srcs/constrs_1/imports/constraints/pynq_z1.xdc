
# 125MHz system clock
set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# Allow the 125 MHz board clock to reach the clock wizard.
# Hierarchical filter works whether or not top is wrapped in a Block Design
# (e.g. design_1_i/top_0/inst/inst_top/inst1_clkwiz/...).
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets -hierarchical -filter {NAME =~ *inst1_clkwiz/inst/clk_in1_clk_wiz_0}]

# Reset (BTN0, active high when pressed)
set_property PACKAGE_PIN D19 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# HDMI TX, J11 on the PYNQ-Z1
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[*]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_n[*]}]

set_property PACKAGE_PIN L16 [get_ports hdmi_tx_clk_p]
set_property PACKAGE_PIN L17 [get_ports hdmi_tx_clk_n]
set_property PACKAGE_PIN J18 [get_ports {hdmi_tx_data_p[2]}]
set_property PACKAGE_PIN H18 [get_ports {hdmi_tx_data_n[2]}]
set_property PACKAGE_PIN K19 [get_ports {hdmi_tx_data_p[1]}]
set_property PACKAGE_PIN J19 [get_ports {hdmi_tx_data_n[1]}]
set_property PACKAGE_PIN K17 [get_ports {hdmi_tx_data_p[0]}]
set_property PACKAGE_PIN K18 [get_ports {hdmi_tx_data_n[0]}]

# CDC constraints
# write_bank_sync1 signal
set_false_path -to [get_pins -hier -filter {NAME =~ *isnt1_scan_out/write_bank_sync1_reg/D}]

# Camera register CDC: axi_camera_regs runs on clk_fpga_0 (50 MHz AXI clock).
# The ray-marcher runs on clk_out1_clk_wiz_0 (148.5 MHz).
# These clocks are asynchronous; suppress all inter-domain timing checks.
# (Cell-name filters are unreliable because Vivado absorbs 2-FF meta registers
#  into downstream SRLC32E chains, making filter matches empty.)
create_clock -period 8.000 -name clk -waveform {0.000 4.000} [get_ports clk]
set_false_path -from [get_clocks clk_fpga_0] -to [get_clocks clk_out1_clk_wiz_0]

# Floorplan: keep all compute logic together so routing stays short
# (Removed old pblock_compute)
# (Removed old pblock constraint)
# (Removed old add_cells) [get_cells inst1_bram]
# (Removed old resize) -add {SLICE_X0Y0:SLICE_X69Y149}
# (Removed old resize) -add {RAMB36_X0Y0:RAMB36_X2Y29}
# (Removed old resize) -add {DSP48_X0Y0:DSP48_X3Y59}


# IMU I2C (Arduino Header)
set_property PACKAGE_PIN P16 [get_ports iic_imu_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports iic_imu_scl_io]
set_property PACKAGE_PIN P15 [get_ports iic_imu_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports iic_imu_sda_io]



