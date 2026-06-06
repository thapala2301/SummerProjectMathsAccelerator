module fp_mul(
    input clk,
    input wire [26:0] a,
    input wire [26:0] b,
    output wire [26:0] out
);

//stage 0 reg inputs break comb fanin to dsp
reg [26:0] s0_a, s0_b;
always @ (posedge clk) begin
    s0_a <= a;
    s0_b <= b;
end

// stage 1: DSP multiply + exp add
reg s1_sign;
reg [8:0] s1_exp;
reg [37:0] s1_prod;
reg s1_zero;
always @ (posedge clk) begin
    s1_zero <= (s0_a[25:18] == 8'd0) || (s0_b[25:18] == 8'd0);
    s1_sign <= s0_a[26] ^ s0_b[26];
    s1_exp  <= s0_a[25:18] + s0_b[25:18] - 9'd127;
end

(* use_dsp = "yes" *) wire [37:0] full_prod = {1'b1, s0_a[17:0]} * {1'b1, s0_b[17:0]};

always @(posedge clk) begin
    s1_prod <= full_prod;
end


// stage 2: register raw DSP output — breaks DSP output + carry normalise chain
reg s2_sign;
reg [8:0] s2_exp;
reg [37:0] s2_prod;
reg s2_zero;
always @ (posedge clk) begin
    s2_zero <= s1_zero;
    s2_sign <= s1_sign;
    s2_exp  <= s1_exp;
    s2_prod <= s1_prod;
end

// stage 3: normalise — now starts from registered s2_prod, path is short
reg s3_sign;
reg [7:0] s3_exp;
reg [17:0] s3_mant;
always @ (posedge clk) begin
    if (s2_zero) begin
        s3_exp  <= 8'd0;
        s3_mant <= 18'd0;
    end else if (s2_prod[37]) begin
        s3_exp  <= s2_exp[7:0] + 8'd1;
        s3_mant <= s2_prod[36:19];
    end else begin
        s3_exp  <= s2_exp[7:0];
        s3_mant <= s2_prod[35:18];
    end
    s3_sign <= s2_sign;
end


assign out = {s3_sign, s3_exp, s3_mant};
endmodule