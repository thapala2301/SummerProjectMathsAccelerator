module fp_negate(
    input wire [26:0] in,
    output wire [26:0] out
);
assign out ={~in[26], in[25:0]};
endmodule