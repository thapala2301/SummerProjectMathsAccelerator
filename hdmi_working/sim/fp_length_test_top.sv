`timescale 1ns/1ps
`default_nettype none

module fp_length_test_top (
    input  logic        clk,
    input  logic [26:0] x,
    input  logic [26:0] y,
    input  logic [26:0] z,
    output logic [26:0] out
);

fp_length dut (
    .clk(clk),
    .x(x),
    .y(y),
    .z(z),
    .out(out)
);

endmodule

`default_nettype wire
