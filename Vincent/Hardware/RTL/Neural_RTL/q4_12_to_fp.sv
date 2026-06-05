module q4_12_to_fp(
    input [15:0] in,
    output [26:0] out
);

wire sign_bit;
wire [3:0] int_part;
wire [11:0] fract_part;
assign sign_bit = in[15]; //msb is sgn in 2s comp
assign int_part = in[14:12];
assign fract_part = in[11:0];

//get leading 1
integer i;
logic [4:0] leading_pos;
logic [7:0] exponent_biased;
logic [17:0] mantissa;
logic [14:0] magnitude; //convert to 2s comp
assign magnitude = sign_bit ? (~in[14:0] + 1'b1) : in[14:0];

always_comb begin
    leading_pos = 0;
    for (i=14; i>=0; i=i-1) begin
        if (magnitude[i]) leading_pos = i;
    end
    exponent_biased = (leading_pos >= 12) ? 127 + (leading_pos - 12) : 127 - (12-leading_pos);
    mantissa = (32'(magnitude) << (18-leading_pos)) [17:0];
    if (magnitude == 0) begin exponent_biased = 0; mantissa = 0; end
end

assign out = {sign_bit, exponent_biased, mantissa};

//logic
endmodule