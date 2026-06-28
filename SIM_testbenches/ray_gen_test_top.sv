`timescale 1ns/1ps
`default_nettype none

module ray_gen_test_top (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [10:0] pix_x,
    input  logic [9:0]  pix_y,
    input  logic [19:0] pix_id_in,
    input  logic        valid_in,
    input  logic [26:0] lookat0,
    input  logic [26:0] lookat1,
    input  logic [26:0] lookat2,
    input  logic [26:0] lookat3,
    input  logic [26:0] lookat4,
    input  logic [26:0] lookat5,
    input  logic [26:0] lookat6,
    input  logic [26:0] lookat7,
    input  logic [26:0] lookat8,
    input  logic [26:0] cam_origin0,
    input  logic [26:0] cam_origin1,
    input  logic [26:0] cam_origin2,
    output logic [26:0] ray_orig0,
    output logic [26:0] ray_orig1,
    output logic [26:0] ray_orig2,
    output logic [26:0] ray_dir0,
    output logic [26:0] ray_dir1,
    output logic [26:0] ray_dir2,
    output logic [19:0] pix_id_out,
    output logic        valid_out,
    output logic        pipeline_ready
);

logic [26:0] lookat     [0:8];
logic [26:0] cam_origin [0:2];
logic [26:0] ray_orig   [0:2];
logic [26:0] ray_dir    [0:2];

always_comb begin
    lookat[0] = lookat0;
    lookat[1] = lookat1;
    lookat[2] = lookat2;
    lookat[3] = lookat3;
    lookat[4] = lookat4;
    lookat[5] = lookat5;
    lookat[6] = lookat6;
    lookat[7] = lookat7;
    lookat[8] = lookat8;

    cam_origin[0] = cam_origin0;
    cam_origin[1] = cam_origin1;
    cam_origin[2] = cam_origin2;

    ray_orig0 = ray_orig[0];
    ray_orig1 = ray_orig[1];
    ray_orig2 = ray_orig[2];
    ray_dir0  = ray_dir[0];
    ray_dir1  = ray_dir[1];
    ray_dir2  = ray_dir[2];
end

ray_gen dut (
    .clk(clk),
    .rst_n(rst_n),
    .pix_x(pix_x),
    .pix_y(pix_y),
    .pix_id_in(pix_id_in),
    .valid_in(valid_in),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .ray_orig(ray_orig),
    .ray_dir(ray_dir),
    .pix_id_out(pix_id_out),
    .valid_out(valid_out),
    .pipeline_ready(pipeline_ready)
);

endmodule

`default_nettype wire
