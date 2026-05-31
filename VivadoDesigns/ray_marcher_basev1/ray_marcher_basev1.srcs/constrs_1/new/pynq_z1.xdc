
# 125MHz system clock
set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 8.000 -name sys_clk [get_ports clk]

# Reset (BTN0)
set_property PACKAGE_PIN D19 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# HDMI TX
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[*]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_n[*]}]

set_property PACKAGE_PIN T19 [get_ports hdmi_tx_clk_p]
set_property PACKAGE_PIN U19 [get_ports hdmi_tx_clk_n]
set_property PACKAGE_PIN V20 [get_ports {hdmi_tx_data_p[2]}]
set_property PACKAGE_PIN W20 [get_ports {hdmi_tx_data_n[2]}]
set_property PACKAGE_PIN T20 [get_ports {hdmi_tx_data_p[1]}]
set_property PACKAGE_PIN U20 [get_ports {hdmi_tx_data_n[1]}]
set_property PACKAGE_PIN N20 [get_ports {hdmi_tx_data_p[0]}]
set_property PACKAGE_PIN P20 [get_ports {hdmi_tx_data_n[0]}]

