`timescale 1ns/1ps
`default_nettype none

module scene_sdf_test_top (
    input  logic        clk,
    input  logic [26:0] px,
    input  logic [26:0] py,
    input  logic [26:0] pz,
    output logic [26:0] sdf_out
);

localparam [26:0] FP_SHAPE_SIZE = 27'h02050000;
localparam [26:0] FP_SHAPE_EXTRA = 27'h01F0CCCD;

scaffold_sdf dut (
    .clk(clk),
    .px(px),
    .py(py),
    .pz(pz),
    .shape_size(FP_SHAPE_SIZE),
    .shape_extra(FP_SHAPE_EXTRA),
    .sdf_out(sdf_out)
);

endmodule

`default_nettype wire
