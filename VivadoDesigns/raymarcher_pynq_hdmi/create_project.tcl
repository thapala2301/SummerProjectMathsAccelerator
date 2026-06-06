set origin_dir [file normalize [file dirname [info script]]]
set proj_dir [file normalize "$origin_dir/vivado/raymarcher_pynq_hdmi"]

create_project raymarcher_pynq_hdmi $proj_dir -part xc7z020clg400-1 -force

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list [file normalize "$origin_dir/ip_repo"]] [current_project]
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
    [file normalize "$origin_dir/rtl/fp/int2fp.v"] \
    [file normalize "$origin_dir/rtl/core/repeat_cell.sv"] \
    [file normalize "$origin_dir/rtl/core/scene_sdf.v"] \
    [file normalize "$origin_dir/rtl/core/sdf_term.v"] \
    [file normalize "$origin_dir/rtl/core/state_pipe.v"] \
    [file normalize "$origin_dir/rtl/control/FIFO.sv"] \
    [file normalize "$origin_dir/rtl/control/feedback_ctrl.sv"] \
    [file normalize "$origin_dir/rtl/video/framebuffer_bram.sv"] \
    [file normalize "$origin_dir/rtl/video/hdmi_timing.sv"] \
    [file normalize "$origin_dir/rtl/video/palette.sv"] \
    [file normalize "$origin_dir/rtl/video/iter_to_rgb.sv"] \
    [file normalize "$origin_dir/rtl/core/march_core.sv"] \
    [file normalize "$origin_dir/rtl/control/pixel_dispatch.sv"] \
    [file normalize "$origin_dir/rtl/core/ray_gen.sv"] \
    [file normalize "$origin_dir/rtl/video/scan_out.sv"] \
    [file normalize "$origin_dir/rtl/top/top.sv"] \
]

set ip_files [list \
    [file normalize "$origin_dir/ip/clk_wiz_0/clk_wiz_0.xci"] \
    [file normalize "$origin_dir/ip/rgb2dvi_0/rgb2dvi_0.xci"] \
]

add_files -norecurse $rtl_files
add_files -norecurse $ip_files
add_files -fileset constrs_1 -norecurse [file normalize "$origin_dir/constraints/pynq_z1.xdc"]

set_property top top [current_fileset]
update_compile_order -fileset sources_1

puts "Project created at: $proj_dir"
puts "Open this XPR next time:"
puts "  $proj_dir/raymarcher_pynq_hdmi.xpr"
