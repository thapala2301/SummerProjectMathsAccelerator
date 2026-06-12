module fp_add(
    input wire clk,
    input [26:0] a,
    input [26:0] b,
    output [26:0] out
);

//Stage 1: compare magnitude, select big/small, compute shift
// Compare exponent first (8-bit) then mantissa only if equal
// This avoids a 26-bit ripple carry chain at 150 MHz
reg [26:0] sm, bg;
reg [7:0] shift_amt;

(* keep = "true" *) wire [7:0] diff_ab = a[25:18] - b[25:18];
(* keep = "true" *) wire [7:0] diff_ba = b[25:18] - a[25:18];
(* keep = "true" *) wire a_bigger = (a[25:0] > b[25:0]);

always @ (posedge clk) begin
    if (a_bigger) begin
        sm <= b;
        bg <= a;
        shift_amt <= diff_ab;
    end else begin
        sm <= a;
        bg <= b;
        shift_amt <= diff_ba;
    end
end


//Stage 2: shift sm mantisse, restore implicit 1.
//need to handle state propagation logic
reg s2_sign_bg, s2_sign_sm;
reg [7:0] s2_exp_bg;
reg [18:0] mant_sm, mant_bg;

//latching for state prop logic


always @(posedge clk) begin
    s2_sign_bg <= bg[26];
    s2_sign_sm <= sm[26];
    s2_exp_bg <= bg[25:18];
    mant_sm <= {1'b1, sm[17:0]}>>shift_amt;
    mant_bg <= {1'b1, bg[17:0]};
end

//Stage 3: add or sub mantisse
//state prop logic
reg s3_result_sign;
reg [7:0] s3_exp;


reg [19:0] mant_result;
always @ (posedge clk) begin
    s3_exp<= s2_exp_bg;
    s3_result_sign <= s2_sign_bg;
    if (s2_sign_bg == s2_sign_sm)
        mant_result <= mant_bg + mant_sm;
    else
        mant_result <= mant_bg - mant_sm;
end

//Stage 4: priority encoder
reg [4:0] lead_pos;
reg [19:0] s4_mant_result;
reg [7:0] s4_exp;
reg s4_sign;
reg s4_zero;

always @ (posedge clk) begin
    s4_sign <= s3_result_sign;
    s4_exp <= s3_exp;
    s4_mant_result <= mant_result;
    
    if (mant_result == 20'b0) begin
        s4_zero <= 1'b1;
        lead_pos <= 5'd0;
    end else begin
        s4_zero <= 1'b0;
        casex (mant_result)
            20'b1???????????????????: lead_pos <= 5'd0;
            20'b01??????????????????: lead_pos <= 5'd1;
            20'b001?????????????????: lead_pos <= 5'd2;
            20'b0001????????????????: lead_pos <= 5'd3;
            20'b00001???????????????: lead_pos <= 5'd4;
            20'b000001??????????????: lead_pos <= 5'd5;
            20'b0000001?????????????: lead_pos <= 5'd6;
            20'b00000001????????????: lead_pos <= 5'd7;
            20'b000000001???????????: lead_pos <= 5'd8;
            20'b0000000001??????????: lead_pos <= 5'd9;
            20'b00000000001?????????: lead_pos <= 5'd10;
            20'b000000000001????????: lead_pos <= 5'd11;
            20'b0000000000001???????: lead_pos <= 5'd12;
            20'b00000000000001??????: lead_pos <= 5'd13;
            20'b000000000000001?????: lead_pos <= 5'd14;
            20'b0000000000000001????: lead_pos <= 5'd15;
            20'b00000000000000001???: lead_pos <= 5'd16;
            20'b000000000000000001??: lead_pos <= 5'd17;
            20'b0000000000000000001?: lead_pos <= 5'd18;
            default: lead_pos <= 5'd0;
        endcase
    end
end

//Stage 5: shift mantissa and update exp
reg [17:0] s5_mant;
reg [7:0] s5_exp;
reg s5_sign;

always @(posedge clk) begin
    s5_sign <= s4_sign;
    if (s4_zero) begin
        s5_mant <= 18'b0;
        s5_exp <= 8'b0;
    end else begin
        if (lead_pos == 5'd0) begin
            s5_mant <= s4_mant_result[18:1];
            s5_exp <= s4_exp + 8'd1;
        end else begin
            // shift left by (lead_pos - 1)
            s5_mant <= (s4_mant_result[17:0] << (lead_pos - 5'd1));
            s5_exp <= s4_exp - (lead_pos - 5'd1);
        end
    end
end

assign out = {s5_sign, s5_exp, s5_mant};


endmodule