/*
Below an explanation for the complex maths of division/inverse...
Proceed with Newton Raphson once more, like isqrt, this time to find 1/b
Recall Newton Raphson finds where a function crosses 0. Function f(x) = 0, must find 0
Place initial guess x0 then apply xn+1 = xn - f(xn)/f'(xn).
Choosing f(x) as f(x)= 1/x - b. The zero of the function is at x = 1/b, so Newton Raphson will give us 1/b
f(1/b) = 0, Newton Raphson pops out 1/b with certain error (quadratic convergence)
f'(x) = -1/x^2
Then:
xn+1 = xn - (1/xn - b)/(-1/xn^2) = xn + xn^2(1/xn - b) = xn + xn -bxn^2 = xn(2-bxn)
Hence we obtain:
xn+1 = xn(2-b*xn). That's: from guess xn approximating 1/b, to obtain better guess approximating 1/b, apply xn(2-b*xn)

Initial guess x0: i. FP27, b has exponent e, then 1/b has exponent -e. 
Obtaining -e:
From : e_stored = e_true +127 
Get => e_inv_stored = (-e_true) + 127
    => e_inv_stored = (-e_stored - 127) + 127
    => e_inv_stored = (-e_stored) +127+127
    => e_inv_stored = 254 - e_stored

Hence our exponent field for initial guess is: 254 - e_stored.
Sign bit: unchanged.
Mantissa and convergence: xn+1 = xn(2-bxn) only converges for bx0 < 2 if bx0 > 2 then 2-bx0 <0 : next guess is negative, diverges
Keeping b manitissa : b = 1.m * 2^e (e: exponent) 27FP notation
x0 = 1.m * 2^-e
bx0 = (1.m)^2. (1.m)^2 is below 2 when 1.m < sqrt2 ~1.41
for b= 12, 1.m = 1.5 so 1.5^2 > 2: diverges.
zero mantissa: x0 =1.0*2^-e
bx0 = (1.m) * 1.0 , m = mantissa of b. So 1.m is in [1; 2(. alwasy below 2 converges.
HENCE, set mantissa to 0.

Then we apply Newton Raphson 3 times, gives 0.4% margin so make sure there is small gap between cell and width of SDF (error epsilon minimized but never null),
could cause bleeding.
Error maths: en = 1-bxn (zero when perfect)
from xn+1 = xn(2-bxn) get bxn+1 = (1-en)(1+en) = 1-en^2,
and bxn+1 = en+1-1 
After some work this gives en+1 = en^2. Error squares with each iteration
For b= 10, zero mantissa, e0 = -0.25 ... e3 = 0.0015% after some work

flip exponent: 254 - exponent. 
*/

//total latency: 3 iteration * (4+4+4) = 36 clk. Each iter 12 clk
module fp_inverse(
    input logic clk,
    input logic [26:0] b,
    output logic [26:0] inv_b
);
localparam FP_2 = {1'b0, 8'd128, 18'h0}; //need 2 from the above
logic [26:0] x0, bx0, bx0_2, x1, bx1, bx1_2, x2, bx2, bx2_2, x3, x0_d, x1_d, x2_d;
logic [7:0] inv_exponent;

assign inv_exponent = 254 - b[25:18];
assign x0 = {b[26], inv_exponent, 18'h0}; //obtain initial guess x0

fp_mul u_mul0bxn (.clk(clk), .a(b), .b(x0), .out(bx0));
fp_sub u_sub02_bxn (.clk(clk), .a(FP_2), .b(bx0), .out(bx0_2));
state_pipe #(.WIDTH(27), .DEPTH(8)) state_pipe_x0 (.clk(clk), .in(x0), .out(x0_d)); //fp_mul and sub each take 4 clk so 8 clk total, and need x0 for final computation so delay x0 by 8 clk
fp_mul u_mulx1 (.clk(clk), .a(x0_d), .b(bx0_2), .out(x1));
//have x1

fp_mul u_mul1bxn (.clk(clk), .a(b), .b(x1), .out(bx1));
fp_sub u_sub12_bxn (.clk(clk), .a(FP_2), .b(bx1), .out(bx1_2));
state_pipe #(.WIDTH(27), .DEPTH(8)) state_pipe_x1 (.clk(clk), .in(x1), .out(x1_d)); //fp_mul and sub each take 4 clk so 8 clk total, and need x1 for final computation so delay x1 by 8 clk
fp_mul u_mulx2 (.clk(clk), .a(x1_d), .b(bx1_2), .out(x2));
//have x2

fp_mul u_mul2bxn (.clk(clk), .a(b), .b(x2), .out(bx2));
fp_sub u_sub22_bxn (.clk(clk), .a(FP_2), .b(bx2), .out(bx2_2));
state_pipe #(.WIDTH(27), .DEPTH(8)) state_pipe_x2 (.clk(clk), .in(x2), .out(x2_d)); //fp_mul and sub each take 4 clk so 8 clk total, and need x2 for final computation so delay x2 by 8 clk
fp_mul u_mulx3 (.clk(clk), .a(x2_d), .b(bx2_2), .out(x3));
//have x3

assign inv_b = x3;

endmodule