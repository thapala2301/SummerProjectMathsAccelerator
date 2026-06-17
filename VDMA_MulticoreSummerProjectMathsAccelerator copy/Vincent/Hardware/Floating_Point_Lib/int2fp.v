//convert from J format to V format 
/*
used in the neural RTL
takes in a 32 bit interger, outputs a 27 bit FP
*/
module int2fp(
    input wire [31:0] in,
    output wire [26:0] out
);

reg sign;
reg[30:0] mag;
reg [4:0] lead; //priority encoder see adder
reg [7:0] exp;
reg [17:0] mant;
integer j;
always @ (*) begin
    sign = in[31]; //sgn
    mag = in[31] ? (~in[30:0] +1): in [30:0]; //two comp if neg
    //priority encoder, records pos higher set big
    lead = 0;
    for (j = 0; j<31; j=j+1)
        if (mag[j]) lead = j;

    exp = lead+ 8'd98; //bin point in Q2.29 is bit 29, so bit 29 is 2^0 = 1
    // if leading 1 is pos k, real val of nb is 2^(k-29). so real exp = k-29 so stored = real+127 = k-29+127=k+98
    mant = (lead >=18) ? mag >> (lead-18) : mag << (18-lead); //lead >=18: leading 1 is high up, more than 18 bits of significant data, right shift to fit in 18 bits
    //lead < 18: leading 1 is low, fewer than 18 signifcant bits: left shift to fill 18 bit mant from top padding zeros to right

end
assign out = {sign, exp, mant};




endmodule