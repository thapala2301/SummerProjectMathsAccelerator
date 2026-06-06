`timescale 1ns/1ps
`default_nettype none

module scene_sdf_test_top (
    input  logic        clk,
    input  logic [26:0] px,
    input  logic [26:0] py,
    input  logic [26:0] pz,
    output logic [26:0] sdf_out
);

scene_sdf dut (
    .clk(clk),
    .px(px),
    .py(py),
    .pz(pz),
    .sdf_out(sdf_out)
);

endmodule

`default_nettype wire
