set origin_dir [file normalize [file dirname [info script]]]
set proj_name cam
set proj_dir [file normalize "$origin_dir/v"]

create_project $proj_name $proj_dir -part xc7z020clg400-1 -force

# cd to script dir so add_files uses short relative paths (no spaces — avoids Vivado Windows bug)
cd $origin_dir

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list "$origin_dir/ip_repo"] [current_project]
update_ip_catalog

foreach f {
    rtl/fp/fp_abs.v
    rtl/fp/fp_add.v
    rtl/fp/fp_isqrt.v
    rtl/fp/fp_length.v
    rtl/fp/fp_max.v
    rtl/fp/fp_min.v
    rtl/fp/fp_mul.v
    rtl/fp/fp_negate.v
    rtl/fp/fp_sub.v
    rtl/fp/int2fp.v
    rtl/core/repeat_cell.sv
    rtl/core/scene_sdf.v
    rtl/core/sdf_term.v
    rtl/core/state_pipe.v
    rtl/control/FIFO.sv
    rtl/control/feedback_ctrl.sv
    rtl/video/palette.sv
    rtl/video/ddr_rgb_writer.sv
    rtl/core/march_core.sv
    rtl/control/pixel_dispatch.sv
    rtl/core/ray_gen.sv
    rtl/top/top.sv
    rtl/top/top_ps.sv
} {
    add_files -norecurse $f
}

add_files -norecurse ip/rgb2dvi_0/rgb2dvi_0.xci
add_files -fileset constrs_1 -norecurse constraints/pynq_z1.xdc

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

source control_bd.tcl

set bd_file [get_files -quiet control_bd.bd]
if {$bd_file eq ""} {
    error "control_bd.bd was not created"
}

set_property synth_checkpoint_mode Singular $bd_file
generate_target all $bd_file
make_wrapper -files $bd_file -top -import

set_property top top_ps [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "Project created at: $proj_dir"
puts "Open this XPR next time:"
puts "  $proj_dir/$proj_name.xpr"
