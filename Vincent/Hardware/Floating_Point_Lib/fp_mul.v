module fp_mul(
    input clk,
    input wire [26:0] a,
    input wire [26:0] b,
    output wire [26:0] out
);

reg s1_sign;
reg [8:0] s1_exp;
reg [37:0] s1_prod;

reg s2_sign;
reg [7:0] s2_exp;
reg [17:0] s2_mant;
reg zero_flag;
//first pass
always @ (posedge clk) begin
    zero_flag <= (a[25:18] == 8'd0) || (b[25:18] == 8'd0);
    s1_sign <= a[26]^b[26];
    s1_exp <= a[25:18]+b[25:18] - 9'd127;
    s1_prod <= {1'b1, a[17:0]}*{1'b1, b[17:0]};
end

always @ (posedge clk) begin
    if(zero_flag) begin
        s2_exp <= 8'd0;
        s2_mant <= 18'd0;
    end 
    else if (s1_prod[37]) begin //38 bit prod, 19 x 2 bits, each 1.mantissa is 19 bits
        s2_exp <= s1_exp[7:0]+1;
        s2_mant <= s1_prod[36:19];
    end
    else begin
        s2_exp <= s1_exp[7:0];
        s2_mant <= s1_prod[35:18];
    end
    s2_sign <= s1_sign;
end

assign out = {s2_sign, s2_exp, s2_mant};
endmodule