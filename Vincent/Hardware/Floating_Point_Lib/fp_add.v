module fp_add(
    input wire clk,
    input [26:0] a,
    input [26:0] b,
    output [26:0] out
);

//Stage 1: compare full mag, sel big small, comp shift amt
reg [26:0] small, big;
reg [7:0] shift_amt;
always @ (posedge clk) begin
    if (a[25:0] > b[25:0]) begin
        small <= b;
        big <= a;
        shift_amt <= a[25:18]-b[25:18];
    end
    else begin // includes same expo??
        small <= a;
        big <= b;
        shift_amt <= b[25:18]-a[25:18];
    end
end


//Stage 2: shift small mantisse, restore implicit 1.
//need to handle state propagation logic
reg s2_sign_big, s2_sign_small;
reg [7:0] s2_exp_big;
reg [18:0] mant_small, mant_big;

//latching for state prop logic


always @(posedge clk) begin
    s2_sign_big <= big[26];
    s2_sign_small <= small[26];
    s2_exp_big <= big[25:18];
    mant_small <= {1'b1, small[17:0]}>>shift_amt;
    mant_big <= {1'b1, big[17:0]};
end

//Stage 3: add or sub mantisse
//state prop logic
reg s3_result_sign;
reg [7:0] s3_exp;


reg [19:0] mant_result; 
always @ (posedge clk) begin
    s3_exp<= s2_exp_big;
    s3_result_sign <= s2_sign_big;
    if (s2_sign_big == s2_sign_small)
        mant_result <= mant_big + mant_small;
    else
        mant_result <= mant_big - mant_small;
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