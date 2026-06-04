module repeat_cell(
    input  logic        clk,
    input  logic [26:0] p,
    output logic [26:0] q
);

localparam [26:0] THR_5   = 27'h2050000;
localparam [26:0] THR_15  = 27'h20B8000;
localparam [26:0] THR_25  = 27'h20E4000;
localparam [26:0] THR_35  = 27'h2106000;
localparam [26:0] THR_45  = 27'h211A000;
localparam [26:0] THR_55  = 27'h212E000;
localparam [26:0] THR_65  = 27'h2141000;
localparam [26:0] THR_75  = 27'h214B000;
localparam [26:0] THR_85  = 27'h2155000;
localparam [26:0] THR_95  = 27'h215F000;
localparam [26:0] THR_105 = 27'h2169000;
localparam [26:0] THR_115 = 27'h2173000;
localparam [26:0] THR_125 = 27'h217D000;
localparam [26:0] THR_135 = 27'h2183800;
localparam [26:0] THR_145 = 27'h2188800;
localparam [26:0] THR_155 = 27'h218D800;
localparam [26:0] THR_165 = 27'h2192800;
localparam [26:0] THR_175 = 27'h2197800;
localparam [26:0] THR_185 = 27'h219C800;
localparam [26:0] THR_195 = 27'h21A1800;
localparam [26:0] THR_205 = 27'h21A6800;
localparam [26:0] THR_215 = 27'h21AB800;
localparam [26:0] THR_225 = 27'h21B0800;
localparam [26:0] THR_235 = 27'h21B5800;
localparam [26:0] THR_245 = 27'h21BA800;
localparam [26:0] THR_255 = 27'h21BF800;

localparam [26:0] OFF_10  = 27'h2090000;
localparam [26:0] OFF_20  = 27'h20D0000;
localparam [26:0] OFF_30  = 27'h20F8000;
localparam [26:0] OFF_40  = 27'h2110000;
localparam [26:0] OFF_50  = 27'h2124000;
localparam [26:0] OFF_60  = 27'h2138000;
localparam [26:0] OFF_70  = 27'h2146000;
localparam [26:0] OFF_80  = 27'h2150000;
localparam [26:0] OFF_90  = 27'h215A000;
localparam [26:0] OFF_100 = 27'h2164000;
localparam [26:0] OFF_110 = 27'h216E000;
localparam [26:0] OFF_120 = 27'h2178000;
localparam [26:0] OFF_130 = 27'h2181000;
localparam [26:0] OFF_140 = 27'h2186000;
localparam [26:0] OFF_150 = 27'h218B000;
localparam [26:0] OFF_160 = 27'h2190000;
localparam [26:0] OFF_170 = 27'h2195000;
localparam [26:0] OFF_180 = 27'h219A000;
localparam [26:0] OFF_190 = 27'h219F000;
localparam [26:0] OFF_200 = 27'h21A4000;
localparam [26:0] OFF_210 = 27'h21A9000;
localparam [26:0] OFF_220 = 27'h21AE000;
localparam [26:0] OFF_230 = 27'h21B3000;
localparam [26:0] OFF_240 = 27'h21B8000;
localparam [26:0] OFF_250 = 27'h21BD000;
localparam [26:0] OFF_260 = 27'h21C1000;

function automatic [26:0] repeat_offset(input [26:0] abs_p);
begin
    if (abs_p < THR_5)        repeat_offset = 27'h0;
    else if (abs_p < THR_15)  repeat_offset = OFF_10;
    else if (abs_p < THR_25)  repeat_offset = OFF_20;
    else if (abs_p < THR_35)  repeat_offset = OFF_30;
    else if (abs_p < THR_45)  repeat_offset = OFF_40;
    else if (abs_p < THR_55)  repeat_offset = OFF_50;
    else if (abs_p < THR_65)  repeat_offset = OFF_60;
    else if (abs_p < THR_75)  repeat_offset = OFF_70;
    else if (abs_p < THR_85)  repeat_offset = OFF_80;
    else if (abs_p < THR_95)  repeat_offset = OFF_90;
    else if (abs_p < THR_105) repeat_offset = OFF_100;
    else if (abs_p < THR_115) repeat_offset = OFF_110;
    else if (abs_p < THR_125) repeat_offset = OFF_120;
    else if (abs_p < THR_135) repeat_offset = OFF_130;
    else if (abs_p < THR_145) repeat_offset = OFF_140;
    else if (abs_p < THR_155) repeat_offset = OFF_150;
    else if (abs_p < THR_165) repeat_offset = OFF_160;
    else if (abs_p < THR_175) repeat_offset = OFF_170;
    else if (abs_p < THR_185) repeat_offset = OFF_180;
    else if (abs_p < THR_195) repeat_offset = OFF_190;
    else if (abs_p < THR_205) repeat_offset = OFF_200;
    else if (abs_p < THR_215) repeat_offset = OFF_210;
    else if (abs_p < THR_225) repeat_offset = OFF_220;
    else if (abs_p < THR_235) repeat_offset = OFF_230;
    else if (abs_p < THR_245) repeat_offset = OFF_240;
    else if (abs_p < THR_255) repeat_offset = OFF_250;
    else                      repeat_offset = OFF_260;
end
endfunction

wire [26:0] abs_p;
wire [26:0] wrap_off_comb;
reg  [26:0] wrap_off;
reg  [26:0] p_r;
wire [26:0] p_minus_wrap;
wire [26:0] p_plus_wrap;
wire [26:0] p_d4;
wire        p_neg_d4;
wire        p_wrap_d4;

fp_abs inst_abs_p(.in(p), .out(abs_p));
assign wrap_off_comb = repeat_offset(abs_p);

//register wrappoff and p to break fp_abs and repeatoffset combinatorial path
always @(posedge clk) begin
    wrap_off <= wrap_off_comb;
    p_r      <= p;
end

fp_sub inst_sub_wrap(.clk(clk), .a(p_r), .b(wrap_off), .out(p_minus_wrap));
fp_add inst_add_wrap(.clk(clk), .a(p_r), .b(wrap_off), .out(p_plus_wrap));

// Delays increase by 1 to match the extra input register cycle
state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_p_d4    (.clk(clk), .in(p),               .out(p_d4));
state_pipe #(.WIDTH(1),  .DEPTH(5)) pipe_sign_d4 (.clk(clk), .in(p[26]),           .out(p_neg_d4));
state_pipe #(.WIDTH(1),  .DEPTH(5)) pipe_wrap_d4 (.clk(clk), .in(|wrap_off_comb),  .out(p_wrap_d4));

always_comb begin
    if (!p_wrap_d4)
        q = p_d4;
    else if (p_neg_d4)
        q = p_plus_wrap;
    else
        q = p_minus_wrap;
end

endmodule
