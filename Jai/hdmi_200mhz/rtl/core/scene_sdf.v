`default_nettype none

module scene_sdf(
    input  wire        clk,
    input  wire [26:0] px,
    input  wire [26:0] py,
    input  wire [26:0] pz,
    output reg  [26:0] sdf_out
);

// ============================================================
// FP27 constants
// ============================================================
// -1.5 = sign=1, exp=127, frac=0.5*2^18 = sign=1, exp=0x7F, frac=0x20000
localparam [26:0] FP_NEG1P5 = {1'b1, 8'h7F, 18'h20000};
// 1.0
localparam [26:0] FP_ONE    = {1'b0, 8'h7F, 18'h00000};
// 4.0 = 2^2, exp=129
localparam [26:0] FP_FOUR   = {1'b0, 8'h81, 18'h00000};
// 0.25 = 2^-2, exp=125
localparam [26:0] FP_0P25   = {1'b0, 8'h7D, 18'h00000};

// ============================================================
// UTILITY FUNCTIONS (combinatorial — zero cycles)
// ============================================================

// Multiply by 2: increment exponent field by 1
// Used in box fold: 2*clamp(p)
function automatic [26:0] fp_times2(input [26:0] a);
    fp_times2 = (a[25:18] == 8'd0) ? 27'h0 :
                {a[26], a[25:18] + 8'd1, a[17:0]};
endfunction

// Clamp to [-1, 1]: if |p| > 1.0 return sign(p)*1.0
// In 1.8.18 format: |p| is bits [25:0], 1.0 is {8'h7F, 18'h0}
function automatic [26:0] fp_clamp1(input [26:0] a);
    fp_clamp1 = (a[25:0] > {8'h7F, 18'h0}) ?
                {a[26], 8'h7F, 18'h0} : a;
endfunction

// ============================================================
// ITERATION HELPER MACRO — done as explicit stages for clarity
// Each iteration:
//   inputs:  xi, yi, zi  (position from previous iteration)
//   outputs: xo, yo, zo  (position after this iteration)
//   latency: 30 cycles
// ============================================================

// ============================================================
// PRE-ITERATION: register inputs
// ============================================================
reg [26:0] xi0, yi0, zi0;
always @(posedge clk) begin
    xi0 <= px;
    yi0 <= py;
    zi0 <= pz;
end
// xi0 ready at cycle 1

// ============================================================
// ITERATION 1
// ============================================================

// -- Stage A: Box fold (4 cycles) --
// fold(p) = 2*clamp(p, -1, 1) - p
// clamp and *2 are combinatorial
wire [26:0] i1_xc = fp_clamp1(xi0);
wire [26:0] i1_yc = fp_clamp1(yi0);
wire [26:0] i1_zc = fp_clamp1(zi0);
wire [26:0] i1_x2c = fp_times2(i1_xc);
wire [26:0] i1_y2c = fp_times2(i1_yc);
wire [26:0] i1_z2c = fp_times2(i1_zc);
// fp_sub: xf = 2*clamp(x) - x
wire [26:0] i1_xf, i1_yf, i1_zf;
fp_sub i1_bfx(.clk(clk), .a(i1_x2c), .b(xi0), .out(i1_xf)); // ready cycle 5
fp_sub i1_bfy(.clk(clk), .a(i1_y2c), .b(yi0), .out(i1_yf));
fp_sub i1_bfz(.clk(clk), .a(i1_z2c), .b(zi0), .out(i1_zf));

// -- Stage B: r² = xf² + yf² + zf² (12 cycles from i1_xf) --
// i1_xf ready at cycle 5, r² ready at cycle 5+12 = 17
wire [26:0] i1_x2, i1_y2, i1_z2;
fp_mul i1_mx(.clk(clk), .a(i1_xf), .b(i1_xf), .out(i1_x2)); // 4 cycles
fp_mul i1_my(.clk(clk), .a(i1_yf), .b(i1_yf), .out(i1_y2));
fp_mul i1_mz(.clk(clk), .a(i1_zf), .b(i1_zf), .out(i1_z2));
wire [26:0] i1_r2xy, i1_r2;
fp_add i1_axy(.clk(clk), .a(i1_x2), .b(i1_y2), .out(i1_r2xy)); // 4 cycles
wire [26:0] i1_z2_dl;
state_pipe #(.WIDTH(27), .DEPTH(4)) i1_pz2(.clk(clk), .in(i1_z2), .out(i1_z2_dl));
fp_add i1_axyz(.clk(clk), .a(i1_r2xy), .b(i1_z2_dl), .out(i1_r2)); // 4 cycles
// i1_r2 ready at cycle 5+12 = 17

// -- Stage C: Sphere fold (5 cycles from i1_r2) --
// if r² < 0.25: multiply by 4, else keep as-is
// i1_xf was ready at cycle 5, need it at cycle 17+1=18 → delay by 12+1=13
wire [26:0] i1_xf_dl, i1_yf_dl, i1_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(13)) i1_pdx(.clk(clk), .in(i1_xf), .out(i1_xf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i1_pdy(.clk(clk), .in(i1_yf), .out(i1_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i1_pdz(.clk(clk), .in(i1_zf), .out(i1_zf_dl));

// register r² comparison result to break comb path
reg i1_inner_r;
always @(posedge clk) i1_inner_r <= (i1_r2[25:0] < FP_0P25[25:0]);
// i1_inner_r ready at cycle 18

// multiply by 4 (in parallel — ready at cycle 18+4=22)
wire [26:0] i1_x4, i1_y4, i1_z4;
fp_mul i1_sfx(.clk(clk), .a(i1_xf_dl), .b(FP_FOUR), .out(i1_x4));
fp_mul i1_sfy(.clk(clk), .a(i1_yf_dl), .b(FP_FOUR), .out(i1_y4));
fp_mul i1_sfz(.clk(clk), .a(i1_zf_dl), .b(FP_FOUR), .out(i1_z4));

// delay unscaled version to align with i1_x4 (4 cycles)
wire [26:0] i1_xf_dl2, i1_yf_dl2, i1_zf_dl2;
wire        i1_inner_dl;
state_pipe #(.WIDTH(27), .DEPTH(4)) i1_pdx2(.clk(clk), .in(i1_xf_dl), .out(i1_xf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i1_pdy2(.clk(clk), .in(i1_yf_dl), .out(i1_yf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i1_pdz2(.clk(clk), .in(i1_zf_dl), .out(i1_zf_dl2));
state_pipe #(.WIDTH(1),  .DEPTH(4)) i1_psi (.clk(clk), .in(i1_inner_r), .out(i1_inner_dl));

// mux: inner sphere → *4, outer → keep, then register to break comb path
reg [26:0] i1_xs, i1_ys, i1_zs;
always @(posedge clk) begin
    i1_xs <= i1_inner_dl ? i1_x4 : i1_xf_dl2;
    i1_ys <= i1_inner_dl ? i1_y4 : i1_yf_dl2;
    i1_zs <= i1_inner_dl ? i1_z4 : i1_zf_dl2;
end
// i1_xs ready at cycle 23

// -- Stage D: Scale * p + offset (8 cycles) --
// scale = -1.5, offset = original world pos (px,py,pz)
wire [26:0] i1_xsc, i1_ysc, i1_zsc;
fp_mul i1_smx(.clk(clk), .a(i1_xs), .b(FP_NEG1P5), .out(i1_xsc)); // 4 cycles
fp_mul i1_smy(.clk(clk), .a(i1_ys), .b(FP_NEG1P5), .out(i1_ysc));
fp_mul i1_smz(.clk(clk), .a(i1_zs), .b(FP_NEG1P5), .out(i1_zsc));
// original px,py,pz must arrive at cycle 23+4=27 → delay from cycle 1 by 26
wire [26:0] i1_cx, i1_cy, i1_cz;
state_pipe #(.WIDTH(27), .DEPTH(26)) i1_pcx(.clk(clk), .in(xi0), .out(i1_cx));
state_pipe #(.WIDTH(27), .DEPTH(26)) i1_pcy(.clk(clk), .in(yi0), .out(i1_cy));
state_pipe #(.WIDTH(27), .DEPTH(26)) i1_pcz(.clk(clk), .in(zi0), .out(i1_cz));
wire [26:0] i1_xo, i1_yo, i1_zo;
fp_add i1_oax(.clk(clk), .a(i1_xsc), .b(i1_cx), .out(i1_xo)); // 4 cycles
fp_add i1_oay(.clk(clk), .a(i1_ysc), .b(i1_cy), .out(i1_yo));
fp_add i1_oaz(.clk(clk), .a(i1_zsc), .b(i1_cz), .out(i1_zo));
// i1_xo ready at cycle 1+4+12+5+8 = 30 cycles from xi0 (cycle 31 from px)

// ============================================================
// ITERATION 2  (inputs: i1_xo, i1_yo, i1_zo at cycle 31)
// ============================================================

wire [26:0] i2_xc = fp_clamp1(i1_xo);
wire [26:0] i2_yc = fp_clamp1(i1_yo);
wire [26:0] i2_zc = fp_clamp1(i1_zo);
wire [26:0] i2_x2c = fp_times2(i2_xc);
wire [26:0] i2_y2c = fp_times2(i2_yc);
wire [26:0] i2_z2c = fp_times2(i2_zc);
wire [26:0] i2_xf, i2_yf, i2_zf;
fp_sub i2_bfx(.clk(clk), .a(i2_x2c), .b(i1_xo), .out(i2_xf));
fp_sub i2_bfy(.clk(clk), .a(i2_y2c), .b(i1_yo), .out(i2_yf));
fp_sub i2_bfz(.clk(clk), .a(i2_z2c), .b(i1_zo), .out(i2_zf));
// i2_xf ready at cycle 35

wire [26:0] i2_x2, i2_y2, i2_z2, i2_r2xy, i2_r2, i2_z2_dl;
fp_mul i2_mx(.clk(clk), .a(i2_xf), .b(i2_xf), .out(i2_x2));
fp_mul i2_my(.clk(clk), .a(i2_yf), .b(i2_yf), .out(i2_y2));
fp_mul i2_mz(.clk(clk), .a(i2_zf), .b(i2_zf), .out(i2_z2));
fp_add i2_axy(.clk(clk), .a(i2_x2), .b(i2_y2), .out(i2_r2xy));
state_pipe #(.WIDTH(27), .DEPTH(4)) i2_pz2(.clk(clk), .in(i2_z2), .out(i2_z2_dl));
fp_add i2_axyz(.clk(clk), .a(i2_r2xy), .b(i2_z2_dl), .out(i2_r2));
// i2_r2 ready at cycle 47

wire [26:0] i2_xf_dl, i2_yf_dl, i2_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(13)) i2_pdx(.clk(clk), .in(i2_xf), .out(i2_xf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i2_pdy(.clk(clk), .in(i2_yf), .out(i2_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i2_pdz(.clk(clk), .in(i2_zf), .out(i2_zf_dl));
reg i2_inner_r;
always @(posedge clk) i2_inner_r <= (i2_r2[25:0] < FP_0P25[25:0]);
wire [26:0] i2_x4, i2_y4, i2_z4;
fp_mul i2_sfx(.clk(clk), .a(i2_xf_dl), .b(FP_FOUR), .out(i2_x4));
fp_mul i2_sfy(.clk(clk), .a(i2_yf_dl), .b(FP_FOUR), .out(i2_y4));
fp_mul i2_sfz(.clk(clk), .a(i2_zf_dl), .b(FP_FOUR), .out(i2_z4));
wire [26:0] i2_xf_dl2, i2_yf_dl2, i2_zf_dl2;
wire        i2_inner_dl;
state_pipe #(.WIDTH(27), .DEPTH(4)) i2_pdx2(.clk(clk), .in(i2_xf_dl), .out(i2_xf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i2_pdy2(.clk(clk), .in(i2_yf_dl), .out(i2_yf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i2_pdz2(.clk(clk), .in(i2_zf_dl), .out(i2_zf_dl2));
state_pipe #(.WIDTH(1),  .DEPTH(4)) i2_psi (.clk(clk), .in(i2_inner_r), .out(i2_inner_dl));
reg [26:0] i2_xs, i2_ys, i2_zs;
always @(posedge clk) begin
    i2_xs <= i2_inner_dl ? i2_x4 : i2_xf_dl2;
    i2_ys <= i2_inner_dl ? i2_y4 : i2_yf_dl2;
    i2_zs <= i2_inner_dl ? i2_z4 : i2_zf_dl2;
end
wire [26:0] i2_xsc, i2_ysc, i2_zsc;
fp_mul i2_smx(.clk(clk), .a(i2_xs), .b(FP_NEG1P5), .out(i2_xsc));
fp_mul i2_smy(.clk(clk), .a(i2_ys), .b(FP_NEG1P5), .out(i2_ysc));
fp_mul i2_smz(.clk(clk), .a(i2_zs), .b(FP_NEG1P5), .out(i2_zsc));
wire [26:0] i2_cx, i2_cy, i2_cz;
state_pipe #(.WIDTH(27), .DEPTH(26)) i2_pcx(.clk(clk), .in(i1_xo), .out(i2_cx));
state_pipe #(.WIDTH(27), .DEPTH(26)) i2_pcy(.clk(clk), .in(i1_yo), .out(i2_cy));
state_pipe #(.WIDTH(27), .DEPTH(26)) i2_pcz(.clk(clk), .in(i1_zo), .out(i2_cz));
wire [26:0] i2_xo, i2_yo, i2_zo;
fp_add i2_oax(.clk(clk), .a(i2_xsc), .b(i2_cx), .out(i2_xo));
fp_add i2_oay(.clk(clk), .a(i2_ysc), .b(i2_cy), .out(i2_yo));
fp_add i2_oaz(.clk(clk), .a(i2_zsc), .b(i2_cz), .out(i2_zo));
// i2_xo ready at cycle 61

// ============================================================
// ITERATION 3  (inputs: i2_xo, i2_yo, i2_zo at cycle 61)
// ============================================================

wire [26:0] i3_xc = fp_clamp1(i2_xo);
wire [26:0] i3_yc = fp_clamp1(i2_yo);
wire [26:0] i3_zc = fp_clamp1(i2_zo);
wire [26:0] i3_x2c = fp_times2(i3_xc);
wire [26:0] i3_y2c = fp_times2(i3_yc);
wire [26:0] i3_z2c = fp_times2(i3_zc);
wire [26:0] i3_xf, i3_yf, i3_zf;
fp_sub i3_bfx(.clk(clk), .a(i3_x2c), .b(i2_xo), .out(i3_xf));
fp_sub i3_bfy(.clk(clk), .a(i3_y2c), .b(i2_yo), .out(i3_yf));
fp_sub i3_bfz(.clk(clk), .a(i3_z2c), .b(i2_zo), .out(i3_zf));

wire [26:0] i3_x2, i3_y2, i3_z2, i3_r2xy, i3_r2, i3_z2_dl;
fp_mul i3_mx(.clk(clk), .a(i3_xf), .b(i3_xf), .out(i3_x2));
fp_mul i3_my(.clk(clk), .a(i3_yf), .b(i3_yf), .out(i3_y2));
fp_mul i3_mz(.clk(clk), .a(i3_zf), .b(i3_zf), .out(i3_z2));
fp_add i3_axy(.clk(clk), .a(i3_x2), .b(i3_y2), .out(i3_r2xy));
state_pipe #(.WIDTH(27), .DEPTH(4)) i3_pz2(.clk(clk), .in(i3_z2), .out(i3_z2_dl));
fp_add i3_axyz(.clk(clk), .a(i3_r2xy), .b(i3_z2_dl), .out(i3_r2));

wire [26:0] i3_xf_dl, i3_yf_dl, i3_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(13)) i3_pdx(.clk(clk), .in(i3_xf), .out(i3_xf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i3_pdy(.clk(clk), .in(i3_yf), .out(i3_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i3_pdz(.clk(clk), .in(i3_zf), .out(i3_zf_dl));
reg i3_inner_r;
always @(posedge clk) i3_inner_r <= (i3_r2[25:0] < FP_0P25[25:0]);
wire [26:0] i3_x4, i3_y4, i3_z4;
fp_mul i3_sfx(.clk(clk), .a(i3_xf_dl), .b(FP_FOUR), .out(i3_x4));
fp_mul i3_sfy(.clk(clk), .a(i3_yf_dl), .b(FP_FOUR), .out(i3_y4));
fp_mul i3_sfz(.clk(clk), .a(i3_zf_dl), .b(FP_FOUR), .out(i3_z4));
wire [26:0] i3_xf_dl2, i3_yf_dl2, i3_zf_dl2;
wire        i3_inner_dl;
state_pipe #(.WIDTH(27), .DEPTH(4)) i3_pdx2(.clk(clk), .in(i3_xf_dl), .out(i3_xf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i3_pdy2(.clk(clk), .in(i3_yf_dl), .out(i3_yf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i3_pdz2(.clk(clk), .in(i3_zf_dl), .out(i3_zf_dl2));
state_pipe #(.WIDTH(1),  .DEPTH(4)) i3_psi (.clk(clk), .in(i3_inner_r), .out(i3_inner_dl));
reg [26:0] i3_xs, i3_ys, i3_zs;
always @(posedge clk) begin
    i3_xs <= i3_inner_dl ? i3_x4 : i3_xf_dl2;
    i3_ys <= i3_inner_dl ? i3_y4 : i3_yf_dl2;
    i3_zs <= i3_inner_dl ? i3_z4 : i3_zf_dl2;
end
wire [26:0] i3_xsc, i3_ysc, i3_zsc;
fp_mul i3_smx(.clk(clk), .a(i3_xs), .b(FP_NEG1P5), .out(i3_xsc));
fp_mul i3_smy(.clk(clk), .a(i3_ys), .b(FP_NEG1P5), .out(i3_ysc));
fp_mul i3_smz(.clk(clk), .a(i3_zs), .b(FP_NEG1P5), .out(i3_zsc));
wire [26:0] i3_cx, i3_cy, i3_cz;
state_pipe #(.WIDTH(27), .DEPTH(26)) i3_pcx(.clk(clk), .in(i2_xo), .out(i3_cx));
state_pipe #(.WIDTH(27), .DEPTH(26)) i3_pcy(.clk(clk), .in(i2_yo), .out(i3_cy));
state_pipe #(.WIDTH(27), .DEPTH(26)) i3_pcz(.clk(clk), .in(i2_zo), .out(i3_cz));
wire [26:0] i3_xo, i3_yo, i3_zo;
fp_add i3_oax(.clk(clk), .a(i3_xsc), .b(i3_cx), .out(i3_xo));
fp_add i3_oay(.clk(clk), .a(i3_ysc), .b(i3_cy), .out(i3_yo));
fp_add i3_oaz(.clk(clk), .a(i3_zsc), .b(i3_cz), .out(i3_zo));
// i3_xo ready at cycle 91

// ============================================================
// ITERATION 4  (inputs: i3_xo, i3_yo, i3_zo at cycle 91)
// ============================================================

wire [26:0] i4_xc = fp_clamp1(i3_xo);
wire [26:0] i4_yc = fp_clamp1(i3_yo);
wire [26:0] i4_zc = fp_clamp1(i3_zo);
wire [26:0] i4_x2c = fp_times2(i4_xc);
wire [26:0] i4_y2c = fp_times2(i4_yc);
wire [26:0] i4_z2c = fp_times2(i4_zc);
wire [26:0] i4_xf, i4_yf, i4_zf;
fp_sub i4_bfx(.clk(clk), .a(i4_x2c), .b(i3_xo), .out(i4_xf));
fp_sub i4_bfy(.clk(clk), .a(i4_y2c), .b(i3_yo), .out(i4_yf));
fp_sub i4_bfz(.clk(clk), .a(i4_z2c), .b(i3_zo), .out(i4_zf));

wire [26:0] i4_x2, i4_y2, i4_z2, i4_r2xy, i4_r2, i4_z2_dl;
fp_mul i4_mx(.clk(clk), .a(i4_xf), .b(i4_xf), .out(i4_x2));
fp_mul i4_my(.clk(clk), .a(i4_yf), .b(i4_yf), .out(i4_y2));
fp_mul i4_mz(.clk(clk), .a(i4_zf), .b(i4_zf), .out(i4_z2));
fp_add i4_axy(.clk(clk), .a(i4_x2), .b(i4_y2), .out(i4_r2xy));
state_pipe #(.WIDTH(27), .DEPTH(4)) i4_pz2(.clk(clk), .in(i4_z2), .out(i4_z2_dl));
fp_add i4_axyz(.clk(clk), .a(i4_r2xy), .b(i4_z2_dl), .out(i4_r2));

wire [26:0] i4_xf_dl, i4_yf_dl, i4_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(13)) i4_pdx(.clk(clk), .in(i4_xf), .out(i4_xf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i4_pdy(.clk(clk), .in(i4_yf), .out(i4_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(13)) i4_pdz(.clk(clk), .in(i4_zf), .out(i4_zf_dl));
reg i4_inner_r;
always @(posedge clk) i4_inner_r <= (i4_r2[25:0] < FP_0P25[25:0]);
wire [26:0] i4_x4, i4_y4, i4_z4;
fp_mul i4_sfx(.clk(clk), .a(i4_xf_dl), .b(FP_FOUR), .out(i4_x4));
fp_mul i4_sfy(.clk(clk), .a(i4_yf_dl), .b(FP_FOUR), .out(i4_y4));
fp_mul i4_sfz(.clk(clk), .a(i4_zf_dl), .b(FP_FOUR), .out(i4_z4));
wire [26:0] i4_xf_dl2, i4_yf_dl2, i4_zf_dl2;
wire        i4_inner_dl;
state_pipe #(.WIDTH(27), .DEPTH(4)) i4_pdx2(.clk(clk), .in(i4_xf_dl), .out(i4_xf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i4_pdy2(.clk(clk), .in(i4_yf_dl), .out(i4_yf_dl2));
state_pipe #(.WIDTH(27), .DEPTH(4)) i4_pdz2(.clk(clk), .in(i4_zf_dl), .out(i4_zf_dl2));
state_pipe #(.WIDTH(1),  .DEPTH(4)) i4_psi (.clk(clk), .in(i4_inner_r), .out(i4_inner_dl));
reg [26:0] i4_xs, i4_ys, i4_zs;
always @(posedge clk) begin
    i4_xs <= i4_inner_dl ? i4_x4 : i4_xf_dl2;
    i4_ys <= i4_inner_dl ? i4_y4 : i4_yf_dl2;
    i4_zs <= i4_inner_dl ? i4_z4 : i4_zf_dl2;
end
wire [26:0] i4_xsc, i4_ysc, i4_zsc;
fp_mul i4_smx(.clk(clk), .a(i4_xs), .b(FP_NEG1P5), .out(i4_xsc));
fp_mul i4_smy(.clk(clk), .a(i4_ys), .b(FP_NEG1P5), .out(i4_ysc));
fp_mul i4_smz(.clk(clk), .a(i4_zs), .b(FP_NEG1P5), .out(i4_zsc));
wire [26:0] i4_cx, i4_cy, i4_cz;
state_pipe #(.WIDTH(27), .DEPTH(26)) i4_pcx(.clk(clk), .in(i3_xo), .out(i4_cx));
state_pipe #(.WIDTH(27), .DEPTH(26)) i4_pcy(.clk(clk), .in(i3_yo), .out(i4_cy));
state_pipe #(.WIDTH(27), .DEPTH(26)) i4_pcz(.clk(clk), .in(i3_zo), .out(i4_cz));
wire [26:0] i4_xo, i4_yo, i4_zo;
fp_add i4_oax(.clk(clk), .a(i4_xsc), .b(i4_cx), .out(i4_xo));
fp_add i4_oay(.clk(clk), .a(i4_ysc), .b(i4_cy), .out(i4_yo));
fp_add i4_oaz(.clk(clk), .a(i4_zsc), .b(i4_cz), .out(i4_zo));
// i4_xo ready at cycle 121

// ============================================================
// DISTANCE ESTIMATE
// Approx SDF = length(final_pos) / |scale|^N
// |scale|=1.5, N=4, |scale|^4 = 5.0625
// Divide by multiplying by 1/5.0625 = 0.1975
// 0.1975 in FP27: 2^-3 * 1.58 ≈ exp=124, frac≈0.58*2^18
// Simpler: just use length(pos) as distance estimate — slightly overestimates
// which makes marching conservative (safe, no artifacts)
// fp_length latency = 32 cycles — total SDF out at cycle 121+32 = 153
// Set SDF_LAT = 153 in march_core.sv
// ============================================================
wire [26:0] sdf_raw;
fp_length inst_len(.clk(clk), .x(i4_xo), .y(i4_yo), .z(i4_zo), .out(sdf_raw));

// Scale distance by 0.2 (conservative estimate keeps marching stable)
// 0.2 = 2^-3 * 1.6, exp=124, frac=0.6*2^18=157286=0x26666
localparam [26:0] FP_0P2 = {1'b0, 8'h7C, 18'h26666};
wire [26:0] sdf_scaled;
fp_mul inst_scale(.clk(clk), .a(sdf_raw), .b(FP_0P2), .out(sdf_scaled));
// sdf_scaled ready at cycle 121+32+4 = 157

always @(posedge clk) sdf_out <= sdf_scaled;
// sdf_out ready at cycle 158
// Set SDF_LAT = 158 in march_core.sv

endmodule
`default_nettype wire
