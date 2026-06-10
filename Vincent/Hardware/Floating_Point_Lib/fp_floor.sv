/*
Floor function takes floor of a value eg 3.3 -> 3
True exponent e (e_stored - 127) 
if e<0, number less than 1: floor is 0
If e>=18, number is large int, no frac bits: floor = input unchanged
If 0 <= e < 18: binary point sits in mantissa bits: zero out the bottom 18-e mantissa bits


FIX FOR NEGATIVES ****
*/

module fp_floor (
    input logic clk,
    input logic [26:0] a,
    output logic [26:0] floor_a
);

logic [7:0] true_exponent;
assign true_exponent = a[25:18]-127;

always_comb begin
    if (a[25:18] < 8'd127) //if true expo is neg
        floor_a = 0;
    else if (true_exponent >= 18)
        floor_a = a;
    else if (true_exponent>=0 & true_exponent < 18)
        //brush up understanding
        floor_a = {a[26:18], a[17:0] & (18'h3FFFF << (18 - true_exponent))}; //shift all ones left by 11-true exponent, AND with matissa, keep sign and expo unchanged
end


endmodule