//takes Abs value of the proposed number
module fp_abs(
    input wire [26:0] in,
    output wire [26:0] out
);

assign out = {1'b0, in[25:0]};
endmodule