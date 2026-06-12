
# 125MHz system clock
set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# Allow the 125 MHz board clock to reach the
# clock wizard even though Vivado does not seem to like it.
# Use hierarchical filter so this works whether or not the design
# is wrapped inside a Block Design (design_1_i/top_0/inst/inst_top/...).
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

# Arduino header I2C (for MPU-9250 via AXI IIC)
set_property PACKAGE_PIN W16 [get_ports iic_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports iic_scl_io]
set_property PACKAGE_PIN V16 [get_ports iic_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports iic_sda_io]

# CDC constraints
# write_bank_sync1 signal
set_false_path -to [get_pins -hier -filter {NAME =~ *isnt1_scan_out/write_bank_sync1_reg/D}]

# Floorplan: keep all compute logic together so routing stays short
create_pblock pblock_compute
add_cells_to_pblock [get_pblocks pblock_compute] [get_cells inst1_mc]
add_cells_to_pblock [get_pblocks pblock_compute] [get_cells inst1_bram]
resize_pblock [get_pblocks pblock_compute] -add {SLICE_X0Y0:SLICE_X69Y149}
resize_pblock [get_pblocks pblock_compute] -add {RAMB36_X0Y0:RAMB36_X2Y29}
resize_pblock [get_pblocks pblock_compute] -add {DSP48_X0Y0:DSP48_X3Y59}

