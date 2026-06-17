# HDMI TX TMDS differential pairs - PYNQ-Z1 J11
# Port names match the BD wrapper (design_1_wrapper)

set_property PACKAGE_PIN L16 [get_ports TMDS_Clk_p]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_Clk_p]
set_property PACKAGE_PIN L17 [get_ports TMDS_Clk_n]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_Clk_n]

set_property PACKAGE_PIN J18 [get_ports {TMDS_Data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_Data_p[2]}]
set_property PACKAGE_PIN H18 [get_ports {TMDS_Data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_Data_n[2]}]

set_property PACKAGE_PIN K19 [get_ports {TMDS_Data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_Data_p[1]}]
set_property PACKAGE_PIN J19 [get_ports {TMDS_Data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_Data_n[1]}]

set_property PACKAGE_PIN K17 [get_ports {TMDS_Data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_Data_p[0]}]
set_property PACKAGE_PIN K18 [get_ports {TMDS_Data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_Data_n[0]}]
