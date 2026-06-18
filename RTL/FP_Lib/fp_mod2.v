// fp_mod2: computes a mod 2.0 for FP27, result in [0, 2.0)
// Cheap replacement for fp_mod when divisor is exactly 2.0
// For |a| < 2 (exp <= 127): result = |a|
// For |a| >= 2: extract unit bit and fraction from mantissa, renormalise
// For negative a: result = 2.0 - pos_mod (if non-zero), else 0
// Latency: 1 cycle (stage1) + 4 cycles (fp_sub for neg) = 5 cycles total

module fp_mod2 (
    input  wire        clk,
    input  wire [26:0] a,
    output reg  [26:0] rem  // a mod 2.0, result in [0, 2.0)
);

wire        s_in = a[26];
wire [7:0]  e_in = a[25:18];
wire [17:0] m_in = a[17:0];

// -------------------------------------------------------
// Stage 1: compute pos_mod = |a| mod 2.0
// Uses casex on exponent to pick the right mantissa bits
// k = e - 127, unit bit = m[17-(k-1)] = m[18-k]
// -------------------------------------------------------
reg [26:0] s1_pos_mod;
reg        s1_neg;      // was input negative
reg        s1_is_zero;  // pos_mod == 0 (no negative correction needed)

// Normalise a sub-1 fraction (common function inlined per case below)
// Result for unit=0: casex on remaining mantissa bits

always @(posedge clk) begin
    s1_neg <= s_in;

    if (e_in <= 8'd127 || a[25:0] == 0) begin
        // |a| < 2 or a=0: result is |a|
        s1_pos_mod <= {1'b0, e_in, m_in};
        s1_is_zero <= (a[25:0] == 0);
    end else begin
        s1_is_zero <= 1'b0;
        casex (e_in)
        // --------------------------------------------------
        // k=1  (exp=128): |a| in [2,4)  unit=m[17] frac=m[16:0]
        // --------------------------------------------------
        8'd128: if (m_in[17]) s1_pos_mod <= {1'b0, 8'd127, m_in[16:0], 1'b0};
                else casex(m_in[16:0])
                    17'b1????????????????: s1_pos_mod <= {1'b0, 8'd126, m_in[15:0], 2'b0};
                    17'b01???????????????: s1_pos_mod <= {1'b0, 8'd125, m_in[14:0], 3'b0};
                    17'b001??????????????: s1_pos_mod <= {1'b0, 8'd124, m_in[13:0], 4'b0};
                    17'b0001?????????????: s1_pos_mod <= {1'b0, 8'd123, m_in[12:0], 5'b0};
                    17'b00001????????????: s1_pos_mod <= {1'b0, 8'd122, m_in[11:0], 6'b0};
                    17'b000001???????????: s1_pos_mod <= {1'b0, 8'd121, m_in[10:0], 7'b0};
                    17'b0000001??????????: s1_pos_mod <= {1'b0, 8'd120, m_in[9:0],  8'b0};
                    17'b00000001?????????: s1_pos_mod <= {1'b0, 8'd119, m_in[8:0],  9'b0};
                    17'b000000001????????: s1_pos_mod <= {1'b0, 8'd118, m_in[7:0], 10'b0};
                    17'b0000000001???????: s1_pos_mod <= {1'b0, 8'd117, m_in[6:0], 11'b0};
                    17'b00000000001??????: s1_pos_mod <= {1'b0, 8'd116, m_in[5:0], 12'b0};
                    17'b000000000001?????: s1_pos_mod <= {1'b0, 8'd115, m_in[4:0], 13'b0};
                    17'b0000000000001????: s1_pos_mod <= {1'b0, 8'd114, m_in[3:0], 14'b0};
                    17'b00000000000001???: s1_pos_mod <= {1'b0, 8'd113, m_in[2:0], 15'b0};
                    17'b000000000000001??: s1_pos_mod <= {1'b0, 8'd112, m_in[1:0], 16'b0};
                    17'b0000000000000001?: s1_pos_mod <= {1'b0, 8'd111, m_in[0],   17'b0};
                    17'b00000000000000001: s1_pos_mod <= {1'b0, 8'd110, 18'b0};
                    default:               begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        // --------------------------------------------------
        // k=2  (exp=129): unit=m[16] frac=m[15:0]
        // --------------------------------------------------
        8'd129: if (m_in[16]) s1_pos_mod <= {1'b0, 8'd127, m_in[15:0], 2'b0};
                else casex(m_in[15:0])
                    16'b1???????????????: s1_pos_mod <= {1'b0, 8'd126, m_in[14:0], 3'b0};
                    16'b01??????????????: s1_pos_mod <= {1'b0, 8'd125, m_in[13:0], 4'b0};
                    16'b001?????????????: s1_pos_mod <= {1'b0, 8'd124, m_in[12:0], 5'b0};
                    16'b0001????????????: s1_pos_mod <= {1'b0, 8'd123, m_in[11:0], 6'b0};
                    16'b00001???????????: s1_pos_mod <= {1'b0, 8'd122, m_in[10:0], 7'b0};
                    16'b000001??????????: s1_pos_mod <= {1'b0, 8'd121, m_in[9:0],  8'b0};
                    16'b0000001?????????: s1_pos_mod <= {1'b0, 8'd120, m_in[8:0],  9'b0};
                    16'b00000001????????: s1_pos_mod <= {1'b0, 8'd119, m_in[7:0], 10'b0};
                    16'b000000001???????: s1_pos_mod <= {1'b0, 8'd118, m_in[6:0], 11'b0};
                    16'b0000000001??????: s1_pos_mod <= {1'b0, 8'd117, m_in[5:0], 12'b0};
                    16'b00000000001?????: s1_pos_mod <= {1'b0, 8'd116, m_in[4:0], 13'b0};
                    16'b000000000001????: s1_pos_mod <= {1'b0, 8'd115, m_in[3:0], 14'b0};
                    16'b0000000000001???: s1_pos_mod <= {1'b0, 8'd114, m_in[2:0], 15'b0};
                    16'b00000000000001??: s1_pos_mod <= {1'b0, 8'd113, m_in[1:0], 16'b0};
                    16'b000000000000001?: s1_pos_mod <= {1'b0, 8'd112, m_in[0],   17'b0};
                    16'b0000000000000001: s1_pos_mod <= {1'b0, 8'd111, 18'b0};
                    default:              begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        // k=3 (exp=130): unit=m[15] frac=m[14:0]
        8'd130: if (m_in[15]) s1_pos_mod <= {1'b0, 8'd127, m_in[14:0], 3'b0};
                else casex(m_in[14:0])
                    15'b1??????????????: s1_pos_mod <= {1'b0, 8'd126, m_in[13:0], 4'b0};
                    15'b01?????????????: s1_pos_mod <= {1'b0, 8'd125, m_in[12:0], 5'b0};
                    15'b001????????????: s1_pos_mod <= {1'b0, 8'd124, m_in[11:0], 6'b0};
                    15'b0001???????????: s1_pos_mod <= {1'b0, 8'd123, m_in[10:0], 7'b0};
                    15'b00001??????????: s1_pos_mod <= {1'b0, 8'd122, m_in[9:0],  8'b0};
                    15'b000001?????????: s1_pos_mod <= {1'b0, 8'd121, m_in[8:0],  9'b0};
                    15'b0000001????????: s1_pos_mod <= {1'b0, 8'd120, m_in[7:0], 10'b0};
                    15'b00000001???????: s1_pos_mod <= {1'b0, 8'd119, m_in[6:0], 11'b0};
                    15'b000000001??????: s1_pos_mod <= {1'b0, 8'd118, m_in[5:0], 12'b0};
                    15'b0000000001?????: s1_pos_mod <= {1'b0, 8'd117, m_in[4:0], 13'b0};
                    15'b00000000001????: s1_pos_mod <= {1'b0, 8'd116, m_in[3:0], 14'b0};
                    15'b000000000001???: s1_pos_mod <= {1'b0, 8'd115, m_in[2:0], 15'b0};
                    15'b0000000000001??: s1_pos_mod <= {1'b0, 8'd114, m_in[1:0], 16'b0};
                    15'b00000000000001?: s1_pos_mod <= {1'b0, 8'd113, m_in[0],   17'b0};
                    15'b000000000000001: s1_pos_mod <= {1'b0, 8'd112, 18'b0};
                    default:             begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        // k=4 (exp=131): unit=m[14] frac=m[13:0]
        8'd131: if (m_in[14]) s1_pos_mod <= {1'b0, 8'd127, m_in[13:0], 4'b0};
                else casex(m_in[13:0])
                    14'b1?????????????: s1_pos_mod <= {1'b0, 8'd126, m_in[12:0], 5'b0};
                    14'b01????????????: s1_pos_mod <= {1'b0, 8'd125, m_in[11:0], 6'b0};
                    14'b001???????????: s1_pos_mod <= {1'b0, 8'd124, m_in[10:0], 7'b0};
                    14'b0001??????????: s1_pos_mod <= {1'b0, 8'd123, m_in[9:0],  8'b0};
                    14'b00001?????????: s1_pos_mod <= {1'b0, 8'd122, m_in[8:0],  9'b0};
                    14'b000001????????: s1_pos_mod <= {1'b0, 8'd121, m_in[7:0], 10'b0};
                    14'b0000001???????: s1_pos_mod <= {1'b0, 8'd120, m_in[6:0], 11'b0};
                    14'b00000001??????: s1_pos_mod <= {1'b0, 8'd119, m_in[5:0], 12'b0};
                    14'b000000001?????: s1_pos_mod <= {1'b0, 8'd118, m_in[4:0], 13'b0};
                    14'b0000000001????: s1_pos_mod <= {1'b0, 8'd117, m_in[3:0], 14'b0};
                    14'b00000000001???: s1_pos_mod <= {1'b0, 8'd116, m_in[2:0], 15'b0};
                    14'b000000000001??: s1_pos_mod <= {1'b0, 8'd115, m_in[1:0], 16'b0};
                    14'b0000000000001?: s1_pos_mod <= {1'b0, 8'd114, m_in[0],   17'b0};
                    14'b00000000000001: s1_pos_mod <= {1'b0, 8'd113, 18'b0};
                    default:            begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        // k=5..12: same pattern, shrinking fraction
        8'd132: if (m_in[13]) s1_pos_mod <= {1'b0, 8'd127, m_in[12:0], 5'b0};
                else casex(m_in[12:0])
                    13'b1????????????: s1_pos_mod <= {1'b0, 8'd126, m_in[11:0], 6'b0};
                    13'b01???????????: s1_pos_mod <= {1'b0, 8'd125, m_in[10:0], 7'b0};
                    13'b001??????????: s1_pos_mod <= {1'b0, 8'd124, m_in[9:0],  8'b0};
                    13'b0001?????????: s1_pos_mod <= {1'b0, 8'd123, m_in[8:0],  9'b0};
                    13'b00001????????: s1_pos_mod <= {1'b0, 8'd122, m_in[7:0], 10'b0};
                    13'b000001???????: s1_pos_mod <= {1'b0, 8'd121, m_in[6:0], 11'b0};
                    13'b0000001??????: s1_pos_mod <= {1'b0, 8'd120, m_in[5:0], 12'b0};
                    13'b00000001?????: s1_pos_mod <= {1'b0, 8'd119, m_in[4:0], 13'b0};
                    13'b000000001????: s1_pos_mod <= {1'b0, 8'd118, m_in[3:0], 14'b0};
                    13'b0000000001???: s1_pos_mod <= {1'b0, 8'd117, m_in[2:0], 15'b0};
                    13'b00000000001??: s1_pos_mod <= {1'b0, 8'd116, m_in[1:0], 16'b0};
                    13'b000000000001?: s1_pos_mod <= {1'b0, 8'd115, m_in[0],   17'b0};
                    13'b0000000000001: s1_pos_mod <= {1'b0, 8'd114, 18'b0};
                    default:           begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        8'd133: if (m_in[12]) s1_pos_mod <= {1'b0, 8'd127, m_in[11:0], 6'b0};
                else casex(m_in[11:0])
                    12'b1???????????: s1_pos_mod <= {1'b0, 8'd126, m_in[10:0], 7'b0};
                    12'b01??????????: s1_pos_mod <= {1'b0, 8'd125, m_in[9:0],  8'b0};
                    12'b001?????????: s1_pos_mod <= {1'b0, 8'd124, m_in[8:0],  9'b0};
                    12'b0001????????: s1_pos_mod <= {1'b0, 8'd123, m_in[7:0], 10'b0};
                    12'b00001???????: s1_pos_mod <= {1'b0, 8'd122, m_in[6:0], 11'b0};
                    12'b000001??????: s1_pos_mod <= {1'b0, 8'd121, m_in[5:0], 12'b0};
                    12'b0000001?????: s1_pos_mod <= {1'b0, 8'd120, m_in[4:0], 13'b0};
                    12'b00000001????: s1_pos_mod <= {1'b0, 8'd119, m_in[3:0], 14'b0};
                    12'b000000001???: s1_pos_mod <= {1'b0, 8'd118, m_in[2:0], 15'b0};
                    12'b0000000001??: s1_pos_mod <= {1'b0, 8'd117, m_in[1:0], 16'b0};
                    12'b00000000001?: s1_pos_mod <= {1'b0, 8'd116, m_in[0],   17'b0};
                    12'b000000000001: s1_pos_mod <= {1'b0, 8'd115, 18'b0};
                    default:          begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        8'd134: if (m_in[11]) s1_pos_mod <= {1'b0, 8'd127, m_in[10:0], 7'b0};
                else casex(m_in[10:0])
                    11'b1??????????: s1_pos_mod <= {1'b0, 8'd126, m_in[9:0],  8'b0};
                    11'b01?????????: s1_pos_mod <= {1'b0, 8'd125, m_in[8:0],  9'b0};
                    11'b001????????: s1_pos_mod <= {1'b0, 8'd124, m_in[7:0], 10'b0};
                    11'b0001???????: s1_pos_mod <= {1'b0, 8'd123, m_in[6:0], 11'b0};
                    11'b00001??????: s1_pos_mod <= {1'b0, 8'd122, m_in[5:0], 12'b0};
                    11'b000001?????: s1_pos_mod <= {1'b0, 8'd121, m_in[4:0], 13'b0};
                    11'b0000001????: s1_pos_mod <= {1'b0, 8'd120, m_in[3:0], 14'b0};
                    11'b00000001???: s1_pos_mod <= {1'b0, 8'd119, m_in[2:0], 15'b0};
                    11'b000000001??: s1_pos_mod <= {1'b0, 8'd118, m_in[1:0], 16'b0};
                    11'b0000000001?: s1_pos_mod <= {1'b0, 8'd117, m_in[0],   17'b0};
                    11'b00000000001: s1_pos_mod <= {1'b0, 8'd116, 18'b0};
                    default:         begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        8'd135: if (m_in[10]) s1_pos_mod <= {1'b0, 8'd127, m_in[9:0], 8'b0};
                else casex(m_in[9:0])
                    10'b1?????????: s1_pos_mod <= {1'b0, 8'd126, m_in[8:0],  9'b0};
                    10'b01????????: s1_pos_mod <= {1'b0, 8'd125, m_in[7:0], 10'b0};
                    10'b001???????: s1_pos_mod <= {1'b0, 8'd124, m_in[6:0], 11'b0};
                    10'b0001??????: s1_pos_mod <= {1'b0, 8'd123, m_in[5:0], 12'b0};
                    10'b00001?????: s1_pos_mod <= {1'b0, 8'd122, m_in[4:0], 13'b0};
                    10'b000001????: s1_pos_mod <= {1'b0, 8'd121, m_in[3:0], 14'b0};
                    10'b0000001???: s1_pos_mod <= {1'b0, 8'd120, m_in[2:0], 15'b0};
                    10'b00000001??: s1_pos_mod <= {1'b0, 8'd119, m_in[1:0], 16'b0};
                    10'b000000001?: s1_pos_mod <= {1'b0, 8'd118, m_in[0],   17'b0};
                    10'b0000000001: s1_pos_mod <= {1'b0, 8'd117, 18'b0};
                    default:        begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
                endcase
        // k>=9: precision too low, integer multiple of 2 in FP27 → 0
        default: begin s1_pos_mod <= 27'b0; s1_is_zero <= 1'b1; end
        endcase
    end
end

// -------------------------------------------------------
// Stage 2-5: for negative inputs, compute 2.0 - pos_mod
// TWO = {0, 128, 0} = 2.0 in FP27
// -------------------------------------------------------
localparam [26:0] TWO = {1'b0, 8'd128, 18'h0};

wire [26:0] two_minus;
fp_sub inst_neg_corr (.clk(clk), .a(TWO), .b(s1_pos_mod), .out(two_minus));

// Delay s1_neg and s1_is_zero by 4 cycles to align with fp_sub output
wire s1_neg_d, s1_zero_d;
wire [26:0] s1_pos_mod_d;
state_pipe #(.WIDTH(1),  .DEPTH(4)) pipe_neg  (.clk(clk), .in(s1_neg),      .out(s1_neg_d));
state_pipe #(.WIDTH(1),  .DEPTH(4)) pipe_zero (.clk(clk), .in(s1_is_zero),  .out(s1_zero_d));
state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_pmod (.clk(clk), .in(s1_pos_mod),  .out(s1_pos_mod_d));

// Final mux
always @(posedge clk) begin
    if (s1_zero_d)
        rem <= 27'b0;
    else if (s1_neg_d)
        rem <= two_minus;
    else
        rem <= s1_pos_mod_d;
end

endmodule
