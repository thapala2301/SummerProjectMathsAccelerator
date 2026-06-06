module fp_add(
    input wire clk,
    input [26:0] a,
    input [26:0] b,
    output [26:0] out
);

//Stage 1: compare full mag, sel big small, comp shift amt
reg [26:0] sm, bg;
reg [7:0] shift_amt;

(* keep = "true" *) wire [7:0] diff_ab = a[25:18] - b[25:18];
(* keep = "true" *) wire [7:0] diff_ba = b[25:18] - a[25:18];
(* keep = "true" *) wire a_bigger = (a[25:0] > b[25:0]);
//pragma cmd forces the wires to not be a wide comparator feeding in a mux, but instead stay as seperate named nets so they stay distinct

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

//Stage 4: renormalize assemble output + if underflow : priority encoder
//overflow, no overflow, underflow
//state prop logic
reg [17:0] s4_mant;
reg [7:0] s4_exp;
reg s4_sign;

//though ugly, casex is much better than a for loop for a priority encoder function
//for loop synthesizes to 20 deep chain of mux, awful for timing. casex is pure priority encoder
//vivado maps each pattern to one LUT level with casex
always @ (posedge clk) begin
    
    //edge case, a = b
    if (mant_result == 20'b0) begin
        s4_sign <= 1'b0;
        s4_exp  <= 8'b0;
        s4_mant <= 18'b0;
    end else begin
        s4_sign <= s3_result_sign;
        casex (mant_result)
            20'b1???????????????????: begin
                s4_mant <= mant_result[18:1];
                s4_exp  <= s3_exp + 1;
            end
            20'b01??????????????????: begin
                s4_mant <= mant_result[17:0];
                s4_exp  <= s3_exp;
            end
            20'b001?????????????????: begin
                s4_mant <= {mant_result[16:0], 1'b0};
                s4_exp  <= s3_exp - 1;
            end
            20'b0001????????????????: begin
                s4_mant <= {mant_result[15:0], 2'b0};
                s4_exp  <= s3_exp - 2;
            end
            20'b00001???????????????: begin
                s4_mant <= {mant_result[14:0], 3'b0};
                s4_exp  <= s3_exp - 3;
            end
            20'b000001??????????????: begin
                s4_mant <= {mant_result[13:0], 4'b0};
                s4_exp  <= s3_exp - 4;
            end
            20'b0000001?????????????: begin
                s4_mant <= {mant_result[12:0], 5'b0};
                s4_exp  <= s3_exp - 5;
            end
            20'b00000001????????????: begin
                s4_mant <= {mant_result[11:0], 6'b0};
                s4_exp  <= s3_exp - 6;
            end
            20'b000000001???????????: begin
                s4_mant <= {mant_result[10:0], 7'b0};
                s4_exp  <= s3_exp - 7;
            end
            20'b0000000001??????????: begin
                s4_mant <= {mant_result[9:0],  8'b0};
                s4_exp  <= s3_exp - 8;
            end
            20'b00000000001?????????: begin
                s4_mant <= {mant_result[8:0],  9'b0};
                s4_exp  <= s3_exp - 9;
            end
            20'b000000000001????????: begin
                s4_mant <= {mant_result[7:0], 10'b0};
                s4_exp  <= s3_exp - 10;
            end
            20'b0000000000001???????: begin
                s4_mant <= {mant_result[6:0], 11'b0};
                s4_exp  <= s3_exp - 11;
            end
            20'b00000000000001??????: begin
                s4_mant <= {mant_result[5:0], 12'b0};
                s4_exp  <= s3_exp - 12;
            end
            20'b000000000000001?????: begin
                s4_mant <= {mant_result[4:0], 13'b0};
                s4_exp  <= s3_exp - 13;
            end
            20'b0000000000000001????: begin
                s4_mant <= {mant_result[3:0], 14'b0};
                s4_exp  <= s3_exp - 14;
            end
            20'b00000000000000001???: begin
                s4_mant <= {mant_result[2:0], 15'b0};
                s4_exp  <= s3_exp - 15;
            end
            20'b000000000000000001??: begin
                s4_mant <= {mant_result[1:0], 16'b0};
                s4_exp  <= s3_exp - 16;
            end
            20'b0000000000000000001?: begin
                s4_mant <= {mant_result[0],   17'b0};
                s4_exp  <= s3_exp - 17;
            end
            default: begin
                s4_mant <= 18'b0;
                s4_exp  <= 8'b0;
            end
        endcase
    end


end

assign out = {s4_sign, s4_exp, s4_mant};


endmodule