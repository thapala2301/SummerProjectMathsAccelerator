/*
Floor function takes floor of a value eg 3.3 -> 3
True exponent e (e_stored - 127) 
if e<0, number less than 1: floor is 0
If e>=18, number is large int, no frac bits: floor = input unchanged
If 0 <= e < 18: binary point sits in mantissa bits: zero out the bottom 18-e mantissa bits

When stored exp < 127, that means true exp < 0 so it's definitely a fraction, ie abs(a)<1

Insight: floor goes toward -infinity.
floor(-2.5) = -3. Negatives get treated differently

|| a[25:18] < 8'd127 :  for -0.5, the mantissa happens to be 0 (0.5 = 1.0 × 2⁻¹, no fractional mantissa bits), 
so a[17:0] == trunc_a[17:0] would miss it. 
expo check catches that edge case.

4 clk latency
*/

module fp_floor (
    input logic clk,
    input logic [26:0] a,
    output logic [26:0] floor_a
);

localparam [26:0] FP_ONE     = 27'h1FC0000; 
localparam [26:0] FP_NEG_ONE = 27'h5FC0000;

logic [26:0] trunc_a;

//trunc towards 0
always_comb begin 
    if (a[25:18] < 8'd127) // abs(a) <1n trunc to 0
        trunc_a = 27'b0;
    else if (a[25:18] >= 8'd145) //true exp >= 18: already an int
        trunc_a = a;
    else 
        trunc_a = {a[26:18], a[17:0] & (18'h3FFFF) << (18-(a[25:18]-8'd127) )}; //do all 1s shifted left to get 0s after binary point anded with mantissa
end

//classify input 
logic need_sub;  //do we need to substract 1? It's the case when number is negative and not an int
assign need_sub = a[26] && (a[17:0] != trunc_a[17:0] || a[25:18] < 8'd127);
//a[17:0] != trunc_a[17:0] means truncation changed the mantissa = had fractional bits
//a[25:18] < 8'd127 means a| < 1, so trunc gave 0, still need -1

//delay classif sigs and trunc by 4 clk to match fp sub
logic [26:0] trunc_a_d;
logic need_sub_d;
state_pipe #(.WIDTH(27), .DEPTH(4)) sp_tr (.clk(clk), .in(trunc_a),   .out(trunc_a_d));
state_pipe #(.WIDTH(1),  .DEPTH(4)) sp_ns (.clk(clk), .in(need_sub),  .out(need_sub_d));

//fp sub
logic [26:0] trunc_1;
fp_sub u_sub (.clk(clk), .a(trunc_a), .b(FP_ONE), .out(trunc_1));

always_comb begin
    if (need_sub_d) floor_a = trunc_1; //truncated minus 1
    else floor_a = trunc_a_d;

end

endmodule