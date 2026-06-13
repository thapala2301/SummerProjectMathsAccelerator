set origin_dir [file normalize [file dirname [info script]]]
set proj_name ui
set proj_dir [file normalize "$origin_dir/v_ui"]

create_project $proj_name $proj_dir -part xc7z020clg400-1 -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list \
    [file normalize "$origin_dir/ip_repo"] \
] [current_project]
update_ip_catalog

set rtl_files [list \
    [file normalize "$origin_dir/rtl/top/top_ps_ui.sv"] \
]

add_files -norecurse $rtl_files
add_files -norecurse [file normalize "$origin_dir/ip/rgb2dvi_0/rgb2dvi_0.xci"]
add_files -fileset constrs_1 -norecurse [file normalize "$origin_dir/constraints/pynq_z1_ui.xdc"]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKIN1_JITTER_PS {80.0} \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.PRIMARY_PORT {clk_in1} \
    CONFIG.NUM_OUT_CLKS {3} \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {51.2064} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {256.032} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_PORT {reset} \
    CONFIG.LOCKED_PORT {locked} \
] [get_ips clk_wiz_0]
generate_target all [get_files [get_property IP_FILE [get_ips clk_wiz_0]]]

set bd_tcl [file normalize "$origin_dir/control_bd.tcl"]
source $bd_tcl

set bd_file [get_files -quiet control_bd.bd]
set_property synth_checkpoint_mode Singular $bd_file
generate_target all $bd_file
make_wrapper -files $bd_file -top -import

set_property top top_ps_ui [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "UI project created at: $proj_dir"
