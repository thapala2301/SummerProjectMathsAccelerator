module fp_mul(
    input clk,
    input wire [26:0] a,
    input wire [26:0] b,
    output wire [26:0] out
);

// stage 1: Input registers
(* srl_style = "register" *) reg [26:0] s1_a, s1_b;
(* srl_style = "register" *) reg [18:0] s1_a_dsp, s1_b_dsp;

always @(posedge clk) begin
    s1_a <= a;
    s1_b <= b;
    s1_a_dsp <= {1'b1, a[17:0]};
    s1_b_dsp <= {1'b1, b[17:0]};
end

// stage 2: DSP multiply and Exponent Add
(* use_dsp = "yes" *) reg [37:0] s2_prod;
reg s2_sign;
reg [8:0] s2_exp;
reg s2_zero;

always @(posedge clk) begin
    s2_prod <= s1_a_dsp * s1_b_dsp;
    s2_sign <= s1_a[26] ^ s1_b[26];
    s2_exp  <= s1_a[25:18] + s1_b[25:18] - 9'd127;
    s2_zero <= (s1_a[25:18] == 8'd0) || (s1_b[25:18] == 8'd0);
end

//stage 3: DSP pipeline out (PREG)
reg [37:0] s3_prod;
reg s3_sign;
reg [8:0] s3_exp;
reg s3_zero;

always @(posedge clk) begin
    s3_prod <= s2_prod;
    s3_sign <= s2_sign;
    s3_exp  <= s2_exp;
    s3_zero <= s2_zero;
end

//stage 4: normalise
reg s4_sign;
reg [7:0] s4_exp;
reg [17:0] s4_mant;

always @(posedge clk) begin
    if (s3_zero) begin
        s4_exp  <= 8'd0;
        s4_mant <= 18'd0;
    end else if (s3_prod[37]) begin
        s4_exp  <= s3_exp[7:0] + 8'd1;
        s4_mant <= s3_prod[36:19];
    end else begin
        s4_exp  <= s3_exp[7:0];
        s4_mant <= s3_prod[35:18];
    end
    s4_sign <= s3_sign;
end

// stage 5: maintain original 5-cycle latency
reg [26:0] s5_out;
always @(posedge clk) begin
    s5_out <= {s4_sign, s4_exp, s4_mant};
end

assign out = s5_out;
endmodule