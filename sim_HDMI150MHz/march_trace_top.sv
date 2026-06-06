`timescale 1ns/1ps
`default_nettype none

module march_trace_top (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [10:0] in_x,
    input  logic [9:0]  in_y,
    input  logic [19:0] in_pix_id,
    input  logic [26:0] in_pos_x,
    input  logic [26:0] in_pos_y,
    input  logic [26:0] in_pos_z,
    input  logic [26:0] in_ray_dir_x,
    input  logic [26:0] in_ray_dir_y,
    input  logic [26:0] in_ray_dir_z,
    input  logic [7:0]  in_iter,
    input  logic        in_valid,
    output logic        pix_done,
    output logic [19:0] out_pix_id,
    output logic [7:0]  out_iter,
    output logic [7:0]  fb_iter,
    output logic [26:0] fb_ray_dir_x,
    output logic [26:0] fb_ray_dir_y,
    output logic [26:0] fb_ray_dir_z,
    output logic [26:0] fb_pos_x,
    output logic [26:0] fb_pos_y,
    output logic [26:0] fb_pos_z,
    output logic [19:0] fb_pix_id,
    output logic        fb_valid,
    output logic [26:0] dbg_src_pos_x,
    output logic [26:0] dbg_src_pos_y,
    output logic [26:0] dbg_src_pos_z,
    output logic [26:0] dbg_d3_dist,
    output logic [7:0]  dbg_d3_iter,
    output logic        dbg_d3_valid
);

localparam [26:0] FP_ONE  = 27'h1FC0000;
localparam [26:0] FP_ZERO = 27'h0;
localparam [26:0] FP_NEG3 = 27'h6020000;
localparam [26:0] FP_707  = 27'h1F9A800;
localparam [26:0] FP_N707 = 27'h5F9A800;

logic [26:0] lookat[0:8];
logic [26:0] cam_origin [0:2];

assign lookat[0] = FP_707;  assign lookat[1] = FP_ZERO; assign lookat[2] = FP_707;
assign lookat[3] = FP_ZERO; assign lookat[4] = FP_ONE;  assign lookat[5] = FP_ZERO;
assign lookat[6] = FP_N707; assign lookat[7] = FP_ZERO; assign lookat[8] = FP_707;

assign cam_origin[0] = FP_NEG3;
assign cam_origin[1] = FP_ZERO;
assign cam_origin[2] = FP_NEG3;

march_core dut (
    .clk(clk),
    .rst_n(rst_n),
    .in_x(in_x),
    .in_y(in_y),
    .in_pix_id(in_pix_id),
    .in_pos_x(in_pos_x),
    .in_pos_y(in_pos_y),
    .in_pos_z(in_pos_z),
    .in_ray_dir_x(in_ray_dir_x),
    .in_ray_dir_y(in_ray_dir_y),
    .in_ray_dir_z(in_ray_dir_z),
    .in_iter(in_iter),
    .in_valid(in_valid),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .pix_done(pix_done),
    .out_pix_id(out_pix_id),
    .out_iter(out_iter),
    .fb_iter(fb_iter),
    .fb_ray_dir_x(fb_ray_dir_x),
    .fb_ray_dir_y(fb_ray_dir_y),
    .fb_ray_dir_z(fb_ray_dir_z),
    .fb_pos_x(fb_pos_x),
    .fb_pos_y(fb_pos_y),
    .fb_pos_z(fb_pos_z),
    .fb_pix_id(fb_pix_id),
    .fb_valid(fb_valid)
);

assign dbg_d3_dist  = dut.d3_dist;
assign dbg_d3_iter  = dut.d3_iter;
assign dbg_d3_valid = dut.d3_valid;

state_pipe #(.WIDTH(27), .DEPTH(6)) dbg_src_x_pipe(.clk(clk), .in(dut.d2_pos_x), .out(dbg_src_pos_x));
state_pipe #(.WIDTH(27), .DEPTH(6)) dbg_src_y_pipe(.clk(clk), .in(dut.d2_pos_y), .out(dbg_src_pos_y));
state_pipe #(.WIDTH(27), .DEPTH(6)) dbg_src_z_pipe(.clk(clk), .in(dut.d2_pos_z), .out(dbg_src_pos_z));

endmodule

`default_nettype wire
