`timescale 1ns/1ps

module state_pipe_tb;

parameter WIDTH = 8;
parameter DEPTH = 3;

reg clk;
reg [WIDTH-1:0] in;
wire [WIDTH-1:0] out;


state_pipe #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH)
) dut (
    .clk(clk),
    .in(in),
    .out(out)
);

initial clk = 0;
always #5 clk= ~clk;
    