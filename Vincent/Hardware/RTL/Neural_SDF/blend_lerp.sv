//10 clk per lerp
module blend_lerp(
    input logic clk,
    input logic rst,
    input logic [26:0] a,b,t,
    output logic [26:0] out_blend
);

//deal with FP27 arithmetic here
//compute : a + t*(b-a)
logic [26:0] a_b, intermed_out, t_d, a_d;

state_pipe #(.WIDTH(27), .DEPTH(4)) delay_t (.clk(clk), .in(t), .out(t_d));
state_pipe #(.WIDTH(27), .DEPTH(6)) delay_a (.clk(clk), .in(a), .out(a_d));

fp_sub inst1_fp_sub_b_a (.clk(clk), .a(b), .b(a), .out(a_b));

fp_mul inst1_fp_mul_t_a_b (.clk(clk), .a(a_b), .b(t_d), .out(intermed_out));

fp_add inst1_fp_add_a_itdout (.clk(clk), .a(a_d), .b(intermed_out), .out(out_blend));


endmodule