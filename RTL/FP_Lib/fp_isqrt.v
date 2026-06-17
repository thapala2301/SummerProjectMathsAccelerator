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
fp_add = 4 clk
fp_sub = 4clk

OBSOLETE COMMENTS..

Cycle 0:  y0, hx computed (combinational)
Cycle 2:  y2 = mul(y0, y0) done
          hx_delayed arrives (pipe DEPTH=2)
Cycle 4:  hxy2 = mul(hx_delayed, y2) done
Cycle 8:  sub = fp_sub(1.5, hxy2) done
          y0_delayed arrives (pipe DEPTH=8)
Cycle 10: out = mul(y0_delayed, sub) done

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
fp_mul mul_y0y0 (.clk(clk), .a(y0), .b(y0), .out(y2)); //2 clk latency appears 2clk later
//WAIT CLK
//WAIT CLK
fp_mul mul_hxy2 (.clk(clk), .a(hx_delayed), .b(y2), .out(hxy2));
//WAIT CLK
//WAIT CLK
fp_sub sub_1_5hxy2(.clk(clk), .a(fp_1_5), .b(hxy2), .out(sub));
//WAIT CLK
//WAIT CLK
fp_mul mul_y0_sub (.clk(clk), .a(y0_delayed), .b(sub), .out(out));
//final y0 sub computation: sub arrives at cycle 8. Final fp_mul needs y0 and sub simultaneously,
//so y0 must be held for 8 cycles. See as :
/*
Cycle 0: y0 computed
Cycle 2: y2 ready (fp_mul = 2)
Cycle 4: hxy2 ready (fp_mul = 2 more)
Cycle 8: sub ready (fp_sub = 4 more)
*/








endmodule