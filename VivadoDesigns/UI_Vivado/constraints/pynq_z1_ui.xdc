# 125MHz system clock
set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets inst_clkwiz/inst/clk_in1_clk_wiz_0]

# Reset (BTN0, active high when pressed)
set_property PACKAGE_PIN D19 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# Buttons for UI navigation via EMIO (BTN1=down, BTN2=up, BTN3=music)
set_property PACKAGE_PIN D20 [get_ports {btns[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btns[0]}]
set_property PACKAGE_PIN L20 [get_ports {btns[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btns[1]}]
set_property PACKAGE_PIN L19 [get_ports {btns[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btns[2]}]

# HDMI TX
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
