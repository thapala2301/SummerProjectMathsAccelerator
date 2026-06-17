/*
Computes a[b] = a mod b. Needed for space repetition. Ie I'm at pos 200 in x, need to go back to canonical cell so do 200[cell_size] and get 
coords within canonical cell to evaluate SDF.
Implemented as a[b] = a - b* floor(a/b), in 27FP

52 clk latency
*/

module fp_modulus (
    input logic clk,
    input logic [26:0] a,
    input logic [26:0] b,
    output logic [26:0] rem
);

logic [26:0] b_d, a_d, floor_a_b, a_b, b_floor_div;
fp_division u_dividea_b(.clk(clk), .a(a), .b(b), .a_over_b(a_b)); //uses a and b, obtain a/b - takes 40 clk
fp_floor u_floora_b (.clk(clk), .a(a_b), .floor_a(floor_a_b)); //takes 0 clk, comb, gets floor(a/b)

state_pipe #(.WIDTH(27), .DEPTH(44)) u_state_pipe_a (.clk(clk), .in(b), .out(b_d));

fp_mul u_mula_b(.clk(clk), .a(b_d), .b(floor_a_b), .out(b_floor_div)); //gets b* floor(a/b)

state_pipe #(.WIDTH(27), .DEPTH(48)) u_state_pipe_a2 (.clk(clk), .in(a), .out(a_d));
fp_sub u_suba_b_floor (.clk(clk), .a(a_d), .b(b_floor_div), .out(rem)); //gets a-b*floor(a/b)

endmodule