/*
A wrapper:
Uses fp_inverse module to compute a/b by doing a* 1/b
*/

//total latency 40 clk
module fp_division (
    input logic clk,
    input logic [26:0] a,
    input logic [26:0] b,
    output logic [26:0] a_over_b
);

logic [26:0] inv_b, a_d;
fp_inverse u_inverse_b(.clk(clk), .in(b), .inv_b(inv_b));
//delay a by 36 clk for it to arrive at same moment as inverse
state_pipe #(.WIDTH(27), .DEPTH(36)) state_pipe_a (.clk(clk), .in(a), .out(a_d));
fp_mul u_mul_a_1_b (.clk(clk), .a(a_d), .b(inv_b), .out(a_over_b));

endmodule


