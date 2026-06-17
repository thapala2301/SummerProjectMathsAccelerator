/*
Normalize vector ie take vector * 1/length
That's vec * length, length being sqrt(x^2+y^2+z^2) = 1/|v|
*/

module fp_normalize(
    input logic clk,
    input logic [26:0] vec3_in [0:2],
    output logic [26:0] vec3_out [0:2]
);

logic [26:0] x, y, z, x2, y2, z2, z2_d, x2_y2, x2_y2_z2, x_d, y_d, z_d, length_1, x_out, y_out, z_out;
assign x = vec3_in[0];
assign y =vec3_in[1];
assign z = vec3_in[2];

fp_mul u_mulxx (.clk(clk), .a(x), .b(x), .out(x2));
fp_mul u_mulyy (.clk(clk), .a(y), .b(y), .out(y2));
fp_mul u_mulzz (.clk(clk), .a(z), .b(z), .out(z2));
fp_add u_addx2y2 (.clk(clk), .a(x2), .b(y2), .out(x2_y2));
fp_add u_addx2y2z2 (.clk(clk), .a(x2_y2), .b(z2_d), .out(x2_y2_z2));
//delay 
state_pipe #(.WIDTH(27), .DEPTH(4)) u_pipe_z2 (.clk(clk), .in(z2), .out(z2_d));


fp_isqrt u_inverse_sqrtlength (.clk(clk), .a(x2_y2_z2), .out(length_1));
//length 1 arrives CLK 28: fp_mul 4 clk, fp_Add 4clk, fp_add 4clk, fp_isqrt 16 clk ; total 28 clk
//delay
state_pipe #(.WIDTH(27), .DEPTH(28)) u_pipe_x (.clk(clk), .in(x), .out(x_d));
state_pipe #(.WIDTH(27), .DEPTH(28)) u_pipe_y (.clk(clk), .in(y), .out(y_d));
state_pipe #(.WIDTH(27), .DEPTH(28)) u_pipe_z (.clk(clk), .in(z), .out(z_d));
fp_mul u_mulx (.clk(clk), .a(x_d), .b(length_1), .out(x_out));
fp_mul u_muly (.clk(clk), .a(y_d), .b(length_1), .out(y_out));
fp_mul u_mulz (.clk(clk), .a(z_d), .b(length_1), .out(z_out));

assign vec3_out[0] = x_out;
assign vec3_out[1] = y_out;
assign vec3_out[2] = z_out;

endmodule