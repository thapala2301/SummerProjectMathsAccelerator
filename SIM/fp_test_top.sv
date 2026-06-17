`timescale 1ns/1ps
`default_nettype none

module fp_test_top (
    input  logic        clk,
    input  logic [26:0] mul_a,
    input  logic [26:0] mul_b,
    output logic [26:0] mul_out,
    input  logic [26:0] add_a,
    input  logic [26:0] add_b,
    output logic [26:0] add_out,
    input  logic [26:0] sub_a,
    input  logic [26:0] sub_b,
    output logic [26:0] sub_out,
    input  logic [26:0] isqrt_in,
    output logic [26:0] isqrt_out,
    input  logic [31:0] int_in,
    output logic [26:0] int_out
);

fp_mul   u_mul   (.clk(clk), .a(mul_a),   .b(mul_b),   .out(mul_out));
fp_add   u_add   (.clk(clk), .a(add_a),   .b(add_b),   .out(add_out));
fp_sub   u_sub   (.clk(clk), .a(sub_a),   .b(sub_b),   .out(sub_out));
fp_isqrt u_isqrt (.clk(clk), .a(isqrt_in),              .out(isqrt_out));
int2fp   u_int2fp(.in(int_in),                           .out(int_out));

endmodule

`default_nettype wire
