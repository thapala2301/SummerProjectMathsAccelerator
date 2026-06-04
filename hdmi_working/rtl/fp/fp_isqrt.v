//heaviest module, newton raphson iter (e<0.1%) + magic number computation
//start with first magic FSR Quake III Arena Carmack trick
//the apply newton raphson once, good enough
//very elegant maths for magic number!!! see litterature
/*steps:
1. y0 = magic - (x_bits >> 1)        — bit manipulation, combinational
2. y2 = y0 × y0                       — fp_mul
3. hx = x with exponent-1             — multiply x by 0.5, just subtract 1 from exp
4. hxy2 = hx × y2                     — fp_mul  (= 0.5×x×y0²)
5. sub = 1.5 - hxy2   , after 1.5 conversion to our format                 — fp_sub
6. out = y0 × sub                      — fp_mul
*/

/*
fp_mul : 4 clk latency
fp_sub : 4 clk

Cycle 0:  y0, hx computed (combinational)
Cycle 4:  y2 = mul(y0, y0) done       — hx_delayed DEPTH=4
Cycle 8:  hxy2 = mul(hx, y2) done
Cycle 12: sub = fp_sub(1.5, hxy2)     — y0_delayed DEPTH=12
Cycle 16: out = mul(y0, sub) done

*/
module fp_isqrt(
    input clk,
    input wire [26:0] a,
    output wire [26:0] out
);

wire [26:0] magic_number;
assign magic_number=27'h2F9B8CF;
wire [26:0] y0;
wire [26:0] y0_delayed;
wire [26:0] y2;
wire [26:0] hx;
wire [26:0] hx_delayed;
wire [26:0] hxy2;
wire [26:0] sub;
wire [26:0] fp_1_5 = {1'b0, 8'd127, 18'h20000};
assign y0 = magic_number - (a>>1); //comb
assign hx = {a[26], a[25:18] -8'd1, a[17:0]}; //comb:mantissa unchanged, just sub 1 from exp
//State pipes for waiting and propagating valu
state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_hx(
    .clk(clk),
    .in(hx),
    .out(hx_delayed)
);

state_pipe #(.WIDTH(27), .DEPTH(12)) pipe_y0(
    .clk(clk),
    .in(y0),
    .out(y0_delayed)
);
fp_mul mul_y0y0 (.clk(clk), .a(y0), .b(y0), .out(y2)); //3 clk latency
fp_mul mul_hxy2 (.clk(clk), .a(hx_delayed), .b(y2), .out(hxy2));
fp_sub sub_1_5hxy2(.clk(clk), .a(fp_1_5), .b(hxy2), .out(sub));
fp_mul mul_y0_sub (.clk(clk), .a(y0_delayed), .b(sub), .out(out));








endmodule