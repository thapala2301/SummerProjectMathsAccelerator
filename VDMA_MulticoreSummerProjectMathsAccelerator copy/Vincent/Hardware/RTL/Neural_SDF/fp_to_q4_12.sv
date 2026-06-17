//FP is -1^sign * 2^exp-127 x 1.mantissa
/*
To convert to Q4.12, need the value multiplied by 2^12:

Q4.12 integer = value × 2^12
              = 2^(exp-127) × (mant/2^18) × 2^12
              = mant × 2^(exp - 127 - 18 + 12)
              = mant × 2^(exp - 133)

*/
module fp_to_q4_12(
    input logic [26:0] in,
    output logic [15:0] out
);

logic sign;
logic [7:0] exp;
logic [18:0] mant;
logic signed [7:0] shift_amt;

assign sign = in[26];
assign exp = in[25:18];
assign mant = {1'b1, in[17:0]};
assign shift_amt = $signed(exp) - 8'd133;


logic [15:0] magnitude;
//positive shift amount : increase mant, otherwise decrease manth
assign magnitude = shift_amt >= 0 ? mant << shift_amt : mant >> (-shift_amt);
assign out = sign ? (~magnitude+1) : magnitude; //2s comp

endmodule