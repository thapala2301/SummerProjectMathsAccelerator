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
always #5 clk= ~clk; //flip clock every 5 time units. so every 5ns, hence period is 10ns

initial begin
    $dumpfile("state_pipe_tb.vcd");
    $dumpvars(0, state_pipe_tb);

    in = 0;
    #12;
    in = 8'hAA;
    #10;
    in = 8'hBB;
    #10; 
    in = 8'hCC;
    #10;
    in = 8'hDD;
    #100;
    $finish;
end
//feed 10 ns apart = 1 clk. 100 ns: out should be delayed by exactly depth = 3 cycles

initial begin
    $monitor("t=%0t in=%h out=%h", $time, in, out);
end

endmodule