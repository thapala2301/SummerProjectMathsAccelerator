//out returns minimum of the 2
module fp_min(
    input wire [26:0] a,
    input wire [26:0] b,
    output wire [26:0] out
);

//clean mux better than comb block w regs
assign out = (a[26]==1'b0 && b[26]==1'b0) ? (a[25:0]>b[25:0] ? b : a) :
             (a[26]==1'b1 && b[26]==1'b1) ? (a[25:0]>b[25:0] ? a : b) :
             (a[26]==1'b1) ? a : b;

endmodule