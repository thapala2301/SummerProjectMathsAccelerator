/*
Multiply a 3*3 matrix by a vector, for camera space -> world space transformation of coordinates with lookat projection
effectively:
(v1 v2 v3)* (v4), all 3*1 vectors
That's 
row 0: mtx[0]*vec[0] + mtx[1]*vec[1] + mtx[2]*vec[2]
row 1: mtx[3]*vec[0] + mtx[4]*vec[1] + mtx[5]*vec[2]
row 2: mtx[6]*vec[0] + mtx[7]*vec[1] + mtx[8]*vec[2]

see matrix as
(a b c
 d e f
 g h i )
and vector as
(j
 k
 l)
Then product is vector
(aj+bk+cl
 dj+ek+fl
 gj+hk+il)

 Total latency 8 clk
*/
module fp_mul_vec3_mat33 (
    input logic clk,
    input logic [26:0] mtx [0:8],
    input logic [26:0] vec_in [0:2],
    output logic [26:0] vec_out [0:2]
);

wire [26:0] a,b,c,d,e,f,g,h,i,j,k,l, aj, bk, cl, dj, ek, fl, gl, hk, il, aj_bk, dj_ek, gj_hk, r1, r2,r3;
wire [26:0] cl_d, fl_d, il_d; //delayed signals
assign a = mtx[0];
assign b = mtx[1];
assign c = mtx[2];
assign d = mtx[3];
assign e = mtx[4];
assign f = mtx[5];
assign g = mtx[6];
assign h = mtx[7];
assign i = mtx[8];
assign j = vec_in[0];
assign k = vec_in[1];
assign l = vec_in[2];

fp_mul u_mul0 (.clk(clk), .a(a), .b(j), .out(aj));
fp_mul u_mul1 (.clk(clk), .a(b), .b(k), .out(bk));
fp_mul u_mul2 (.clk(clk), .a(c), .b(l), .out(cl));
fp_mul u_mul3 (.clk(clk), .a(d), .b(j), .out(dj));
fp_mul u_mul4 (.clk(clk), .a(e), .b(k), .out(ek));
fp_mul u_mul5 (.clk(clk), .a(f), .b(l), .out(fl));
fp_mul u_mul6 (.clk(clk), .a(g), .b(j), .out(gj));
fp_mul u_mul7 (.clk(clk), .a(h), .b(k), .out(hk));
fp_mul u_mul8 (.clk(clk), .a(i), .b(l), .out(il));

//add 4 clk delay everywhere
fp_add u_add0(.clk(clk), .a(aj), .b(bk), .out(aj_bk));
fp_add u_add1(.clk(clk), .a(dj), .b(ek), .out(dj_ek));
fp_add u_add2(.clk(clk), .a(gj), .b(hk), .out(gj_hk));

//delayed signals
state_pipe #(.WIDTH(27), .DEPTH(4)) state_pipe_cm (.clk(clk), .in(cl), .out(cl_d));
state_pipe #(.WIDTH(27), .DEPTH(4)) state_pipe_fm (.clk(clk), .in(fl), .out(fl_d));
state_pipe #(.WIDTH(27), .DEPTH(4)) state_pipe_im (.clk(clk), .in(il), .out(il_d));

//final add
fp_add u_add3(.clk(clk), .a(aj_bk), .b(cl_d), .out(r1));
fp_add u_add4(.clk(clk), .a(dj_ek), .b(fl_d), .out(r2));
fp_add u_add5(.clk(clk), .a(gj_hk), .b(il_d), .out(r3));

assign vec_out[0] = r1;
assign vec_out[1] = r2;
assign vec_out[2] = r3;

endmodule