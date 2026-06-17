module fp_sub(
    input clk,
    input wire [26:0] a,
    input wire [26:0] b,
    output wire [26:0] out
);

//substraction is just a + (-b) :)
wire [26:0] b_neg;
assign b_neg = {~b[26], b[25:0]};
//port name on outside, being the thing in the module we r using
fp_add add_sub_(
    .clk(clk),
    .a(a),
    .b(b_neg),
    .out(out)
);

endmodule
