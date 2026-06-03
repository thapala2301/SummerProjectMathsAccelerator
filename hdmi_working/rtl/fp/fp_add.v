module fp_add(
    input wire clk,
    input [26:0] a,
    input [26:0] b,
    output [26:0] out
);

//Stage 1: compare full mag, sel big small, comp shift amt
reg [26:0] sm, bg;
reg [7:0] shift_amt;
always @ (posedge clk) begin
    if (a[25:0] > b[25:0]) begin
        sm <= b;
        bg <= a;
        shift_amt <= a[25:18]-b[25:18];
    end
    else begin // includes same expo??
        sm <= a;
        bg <= b;
        shift_amt <= b[25:18]-a[25:18];
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

//Stage 4: renormalize assemble output + if underflow : priority encoder
//overflow, no overflow, underflow
//state prop logic
reg [17:0] s4_mant;
reg [7:0] s4_exp;
reg s4_sign;
reg [4:0] lead_pos;
integer j;

always @ (posedge clk) begin
    


    //edge case, a = b
    if (mant_result == 20'b0) begin
        s4_sign <= 1'b0;
        s4_exp  <= 8'b0;
        s4_mant <= 18'b0;
    end else begin
        s4_sign <= s3_result_sign;
        lead_pos = 0;
        //upward scan LSB -> MSB
        for (j=0; j<20; j=j+1)
            if (mant_result[j]) lead_pos =j;
        
        if (lead_pos == 19) begin
            s4_mant <= mant_result[18:1];
            s4_exp <= s3_exp + 1;
        end
        else begin
            s4_mant <= mant_result << (18-lead_pos);
            s4_exp <= s3_exp + lead_pos - 8'd18; // if dot closer to LSB need to dec. 18 is threshold/normal scenario
        end
    end


end

assign out = {s4_sign, s4_exp, s4_mant};


endmodule