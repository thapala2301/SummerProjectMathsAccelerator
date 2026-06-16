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

localparam [26:0] FAR_COORD        = 27'h2164000;
localparam int    NUM_REPEAT_BANDS = 26;

localparam logic [26:0] THRESHOLDS [0:NUM_REPEAT_BANDS-1] = '{
    THR_5,   THR_15,  THR_25,  THR_35,  THR_45,  THR_55,  THR_65,
    THR_75,  THR_85,  THR_95,  THR_105, THR_115, THR_125, THR_135,
    THR_145, THR_155, THR_165, THR_175, THR_185, THR_195, THR_205,
    THR_215, THR_225, THR_235, THR_245, THR_255
};

localparam logic [26:0] OFFSETS [0:NUM_REPEAT_BANDS-1] = '{
    27'h0,   OFF_10,  OFF_20,  OFF_30,  OFF_40,  OFF_50,  OFF_60,
    OFF_70,  OFF_80,  OFF_90,  OFF_100, OFF_110, OFF_120, OFF_130,
    OFF_140, OFF_150, OFF_160, OFF_170, OFF_180, OFF_190, OFF_200,
    OFF_210, OFF_220, OFF_230, OFF_240, OFF_250
};

function automatic [26:0] repeat_offset(input [26:0] abs_p);
    logic matched;
    begin
        repeat_offset = OFFSETS[NUM_REPEAT_BANDS-1];
        matched = 1'b0;

        for (int idx = 0; idx < NUM_REPEAT_BANDS - 1; idx++) begin
            if (!matched && (abs_p < THRESHOLDS[idx])) begin
                repeat_offset = OFFSETS[idx];
                matched = 1'b1;
            end
        end
    end
endfunction

wire [26:0] abs_p;
wire [26:0] wrap_offset_next;
wire        in_range_next;
reg  [26:0] wrap_offset_latched;
reg  [26:0] p_latched;
wire [26:0] p_minus_offset;
wire [26:0] p_plus_offset;
wire [26:0] p_delayed;
wire        p_neg_delayed;
wire        wrap_active_delayed;
wire        in_range_delayed;

fp_abs inst_abs_p(.in(p), .out(abs_p));
assign wrap_offset_next = repeat_offset(abs_p);
assign in_range_next = (abs_p < THRESHOLDS[NUM_REPEAT_BANDS - 1]);

// Register the selected wrap offset so the compare path is separated from the add/sub path
always @(posedge clk) begin
    wrap_offset_latched <= wrap_offset_next;
    p_latched <= p;
end

fp_sub inst_sub_wrap(.clk(clk), .a(p_latched), .b(wrap_offset_latched), .out(p_minus_offset));
fp_add inst_add_wrap(.clk(clk), .a(p_latched), .b(wrap_offset_latched), .out(p_plus_offset));

// Delay the pass-through path by the same 5 cycles as the wrapped path.
state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_p_delayed           (.clk(clk), .in(p),                 .out(p_delayed));
state_pipe #(.WIDTH(1),  .DEPTH(5)) pipe_sign_delayed        (.clk(clk), .in(p[26]),             .out(p_neg_delayed));
state_pipe #(.WIDTH(1),  .DEPTH(5)) pipe_wrap_active_delayed (.clk(clk), .in(|wrap_offset_next), .out(wrap_active_delayed));
state_pipe #(.WIDTH(1),  .DEPTH(5)) pipe_range_delayed       (.clk(clk), .in(in_range_next),     .out(in_range_delayed));

always_comb begin
    if (!in_range_delayed)
        q = FAR_COORD;
    else if (!wrap_active_delayed)
        q = p_delayed;
    else if (p_neg_delayed)
        q = p_plus_offset;
    else
        q = p_minus_offset;
end

endmodule
