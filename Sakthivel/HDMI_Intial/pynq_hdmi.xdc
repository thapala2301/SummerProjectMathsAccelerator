# 125 MHz System Clock
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sysclk }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];

# Reset Button (BTN0)
set_property -dict { PACKAGE_PIN D19   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

# HDMI TX (TMDS)
set_property -dict { PACKAGE_PIN L16   IOSTANDARD TMDS_33 } [get_ports { TMDS_clk_p }];
set_property -dict { PACKAGE_PIN K17   IOSTANDARD TMDS_33 } [get_ports { TMDS_data_p[0] }];
set_property -dict { PACKAGE_PIN K19   IOSTANDARD TMDS_33 } [get_ports { TMDS_data_p[1] }];
set_property -dict { PACKAGE_PIN J18   IOSTANDARD TMDS_33 } [get_ports { TMDS_data_p[2] }];
