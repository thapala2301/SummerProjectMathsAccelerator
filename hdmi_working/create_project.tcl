set origin_dir [file normalize [file dirname [info script]]]
set proj_name cam
set proj_dir [file normalize "$origin_dir/v"]

create_project $proj_name $proj_dir -part xc7z020clg400-1 -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list \
    [file normalize "$origin_dir/ip_repo"] \
] [current_project]
update_ip_catalog

set rtl_files [list \
    [file normalize "$origin_dir/rtl/fp/fp_abs.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_add.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_isqrt.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_length.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_max.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_min.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_mul.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_negate.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_sub.v"] \
    [file normalize "$origin_dir/rtl/fp/fp_floor.sv"] \
    [file normalize "$origin_dir/rtl/fp/fp_inverse.sv"] \
    [file normalize "$origin_dir/rtl/fp/fp_div.sv"] \
    [file normalize "$origin_dir/rtl/fp/fp_mod.sv"] \
    [file normalize "$origin_dir/rtl/fp/int2fp.v"] \
    [file normalize "$origin_dir/rtl/core/repeat_cell.sv"] \
    [file normalize "$origin_dir/rtl/core/repeat_mod_cell.sv"] \
    [file normalize "$origin_dir/rtl/core/scene_sdf.v"] \
    [file normalize "$origin_dir/rtl/core/sdf_term.v"] \
    [file normalize "$origin_dir/rtl/core/state_pipe.v"] \
    [file normalize "$origin_dir/rtl/control/FIFO.sv"] \
    [file normalize "$origin_dir/rtl/control/feedback_ctrl.sv"] \
    [file normalize "$origin_dir/rtl/video/palette.sv"] \
    [file normalize "$origin_dir/rtl/video/ddr_rgb_writer.sv"] \
    [file normalize "$origin_dir/rtl/core/march_core.sv"] \
    [file normalize "$origin_dir/rtl/control/pixel_dispatch.sv"] \
    [file normalize "$origin_dir/rtl/core/ray_gen.sv"] \
    [file normalize "$origin_dir/rtl/top/top.sv"] \
    [file normalize "$origin_dir/rtl/top/top_ps.sv"] \
]

set ip_files [list \
    [file normalize "$origin_dir/ip/rgb2dvi_0/rgb2dvi_0.xci"] \
]

add_files -norecurse $rtl_files
add_files -norecurse $ip_files
add_files -fileset constrs_1 -norecurse [list [file normalize "$origin_dir/constraints/pynq_z1.xdc"]]

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
if {![file exists $bd_tcl]} {
    error "Missing exported block design Tcl: $bd_tcl"
}

source $bd_tcl

set bd_file [get_files -quiet control_bd.bd]
if {$bd_file eq ""} {
    error "control_bd.bd was not created by $bd_tcl"
}

set_property synth_checkpoint_mode Singular $bd_file
generate_target all $bd_file
make_wrapper -files $bd_file -top -import

set_property top top_ps [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "Project created at: $proj_dir"
puts "Open this XPR next time:"
puts "  $proj_dir/$proj_name.xpr"
