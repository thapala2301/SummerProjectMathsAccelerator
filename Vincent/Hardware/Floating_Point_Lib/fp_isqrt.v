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
fp_mul : 2 clk latency
fp_add = 4 clk
fp_sub = 4clk

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

wire [27:0] magic_number;
assign magic_number=27'h0x2F9B8CF
wire [27:0] y0;
wire [27:0] y2;
wire [27:0] hx;
assign y0 = magic_numer - (a>>1); //comb
fp_mul mul_y0y0 (.clk(clk), .a(y0), .b(y0), .out(y2)); //2 clk latency appears 2clk later
//WAIT 2 CLK
assign hx = 





endmodule