// scene_sdf.v  —  Mandelbox SDF, 4 iterations, full sphere fold
//
// FIXES vs previous version:
//   1. Outer sphere fold added: when 0.25 <= r^2 < 1.0, scale p by 1/r^2
//      (previously only the inner fold *4 was implemented, giving wrong shape)
//   2. All iterations now add the ORIGINAL world position (xi0/yi0/zi0) as
//      the constant c, matching z_{n+1} = scale*sf(bf(z_n)) + z_0
//      (previously iter 2-4 added the *previous iteration output*, which is wrong)
//   3. Pipeline delays corrected for actual module latencies:
//      fp_mul=5, fp_add=5, fp_sub=5, fp_isqrt=20, fp_length=40
//
// Per-iteration pipeline (61 cycles each, 62 for iter1 with input reg):
//   Pre:     reg inputs                              1 cycle   (iter1 only)
//   Stage A: fp_sub (box fold)                       5 cycles
//   Stage B: fp_mul x3 + fp_add x2 (r^2)           15 cycles  (5+5+5)
//   Stage C: isqrt + inv_r^2 + outer_mul + mux     31 cycles
//   Stage D: fp_mul (-1.5) + fp_add (offset)        10 cycles  (5+5)
//
//   iter1: 0  ->  62   (62 cycles, includes the initial reg)
//   iter2: 62 -> 123   (61 cycles)
//   iter3: 123-> 184   (61 cycles)
//   iter4: 184-> 245   (61 cycles)
//
// Final:
//   fp_length  40 cycles -> 285
//   fp_mul *0.2  5 cycles -> 290
//   reg          1 cycle  -> 291
//
// Set SDF_LAT = 291 in march_core.sv
//
// Mandelbox parameters:
//   scale     = -1.5
//   foldLimit =  1.0 (box fold clamp)
//   minR2     =  0.25 (inner sphere radius squared)
//   fixedR2   =  1.0  (outer sphere radius squared)

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
localparam [26:0] FP_NEG1P5 = {1'b1, 8'h7F, 18'h20000}; // -1.5
localparam [26:0] FP_ONE    = {1'b0, 8'h7F, 18'h00000}; //  1.0
localparam [26:0] FP_0P25   = {1'b0, 8'h7D, 18'h00000}; //  0.25
localparam [26:0] FP_FOUR   = {1'b0, 8'h81, 18'h00000}; //  4.0
// 0.2 = 2^-3 * 1.6,  exp=124=0x7C, frac=0.6*2^18=157286=0x26666
localparam [26:0] FP_0P2    = {1'b0, 8'h7C, 18'h26666};

// ============================================================
// Combinatorial utilities (zero cycles)
// ============================================================
// Clamp to [-1,1]: if |p|>1.0 return sign(p)*1.0
function automatic [26:0] fp_clamp1(input [26:0] a);
    fp_clamp1 = (a[25:0] > {8'h7F, 18'h0}) ? {a[26], 8'h7F, 18'h0} : a;
endfunction

// Multiply by 2: increment exponent (zero cycles)
function automatic [26:0] fp_times2(input [26:0] a);
    fp_times2 = (a[25:18] == 8'd0) ? 27'h0 : {a[26], a[25:18] + 8'd1, a[17:0]};
endfunction

// ============================================================
// PRE-ITERATION: register world position
// ============================================================
reg [26:0] xi0, yi0, zi0;
always @(posedge clk) begin
    xi0 <= px;
    yi0 <= py;
    zi0 <= pz;
end
// xi0/yi0/zi0 ready at cycle 1

// ============================================================
// ITERATION 1  (input: xi0 at cycle 1, output: i1_xo at cycle 62)
// ============================================================

// -- Stage A: box fold  (cycles 1->6) --
wire [26:0] i1_xc = fp_clamp1(xi0);
wire [26:0] i1_yc = fp_clamp1(yi0);
wire [26:0] i1_zc = fp_clamp1(zi0);
wire [26:0] i1_x2c = fp_times2(i1_xc);
wire [26:0] i1_y2c = fp_times2(i1_yc);
wire [26:0] i1_z2c = fp_times2(i1_zc);
wire [26:0] i1_xf, i1_yf, i1_zf;
fp_sub i1_bfx(.clk(clk), .a(i1_x2c), .b(xi0), .out(i1_xf)); // ready cycle 6
fp_sub i1_bfy(.clk(clk), .a(i1_y2c), .b(yi0), .out(i1_yf));
fp_sub i1_bfz(.clk(clk), .a(i1_z2c), .b(zi0), .out(i1_zf));

// -- Stage B: r^2 = xf^2 + yf^2 + zf^2  (cycles 6->21) --
wire [26:0] i1_x2, i1_y2, i1_z2, i1_r2xy, i1_z2_dl, i1_r2;
fp_mul i1_mx(.clk(clk), .a(i1_xf), .b(i1_xf), .out(i1_x2));  // ready 11
fp_mul i1_my(.clk(clk), .a(i1_yf), .b(i1_yf), .out(i1_y2));
fp_mul i1_mz(.clk(clk), .a(i1_zf), .b(i1_zf), .out(i1_z2));
fp_add i1_axy(.clk(clk), .a(i1_x2), .b(i1_y2), .out(i1_r2xy)); // ready 16
state_pipe #(.WIDTH(27), .DEPTH(5)) i1_pz2(.clk(clk), .in(i1_z2), .out(i1_z2_dl)); // 11+5=16
fp_add i1_axyz(.clk(clk), .a(i1_r2xy), .b(i1_z2_dl), .out(i1_r2)); // ready 21

// -- Stage C: full sphere fold  (cycles 21->52) --
// inner: r^2 < 0.25 -> multiply by 4
// outer: 0.25 <= r^2 < 1.0 -> multiply by 1/r^2
// else:  r^2 >= 1.0 -> keep

// register comparison flags (cycle 22)
reg i1_inner_r, i1_outer_r;
always @(posedge clk) begin
    i1_inner_r <= (i1_r2[25:0] < FP_0P25[25:0]);
    i1_outer_r <= (i1_r2[25:0] < FP_ONE[25:0]);  // true for inner too; inner takes priority in mux
end

// isqrt(r^2) = 1/|r|: 20 cycles from r2 (ready 21) -> inv_r ready 41
wire [26:0] i1_inv_r;
fp_isqrt i1_isq(.clk(clk), .a(i1_r2), .out(i1_inv_r));

// inv_r * inv_r = 1/r^2: 5 cycles -> ready 46
wire [26:0] i1_inv_r2;
fp_mul i1_invsq(.clk(clk), .a(i1_inv_r), .b(i1_inv_r), .out(i1_inv_r2));

// delay xf (ready 6) by 40 -> at 46, aligned with inv_r2
wire [26:0] i1_xf_dl, i1_yf_dl, i1_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(40)) i1_pdx(.clk(clk), .in(i1_xf), .out(i1_xf_dl));
state_pipe #(.WIDTH(27), .DEPTH(40)) i1_pdy(.clk(clk), .in(i1_yf), .out(i1_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(40)) i1_pdz(.clk(clk), .in(i1_zf), .out(i1_zf_dl));

// outer scale: xf * (1/r^2): 5 cycles -> ready 51
wire [26:0] i1_x_outer, i1_y_outer, i1_z_outer;
fp_mul i1_ofx(.clk(clk), .a(i1_xf_dl), .b(i1_inv_r2), .out(i1_x_outer));
fp_mul i1_ofy(.clk(clk), .a(i1_yf_dl), .b(i1_inv_r2), .out(i1_y_outer));
fp_mul i1_ofz(.clk(clk), .a(i1_zf_dl), .b(i1_inv_r2), .out(i1_z_outer));

// delay xf by 45 (= 40+5) -> at 51, aligned with outer result
wire [26:0] i1_xf_pass, i1_yf_pass, i1_zf_pass;
state_pipe #(.WIDTH(27), .DEPTH(5)) i1_ppx(.clk(clk), .in(i1_xf_dl), .out(i1_xf_pass));
state_pipe #(.WIDTH(27), .DEPTH(5)) i1_ppy(.clk(clk), .in(i1_yf_dl), .out(i1_yf_pass));
state_pipe #(.WIDTH(27), .DEPTH(5)) i1_ppz(.clk(clk), .in(i1_zf_dl), .out(i1_zf_pass));

// delay flags from 22 by 29 -> at 51
wire i1_inner_dl, i1_outer_dl;
state_pipe #(.WIDTH(1), .DEPTH(29)) i1_psi(.clk(clk), .in(i1_inner_r), .out(i1_inner_dl));
state_pipe #(.WIDTH(1), .DEPTH(29)) i1_pso(.clk(clk), .in(i1_outer_r), .out(i1_outer_dl));

// mux + register (cycle 52)
reg [26:0] i1_xs, i1_ys, i1_zs;
always @(posedge clk) begin
    i1_xs <= i1_inner_dl ? fp_times2(fp_times2(i1_xf_pass)) : i1_outer_dl ? i1_x_outer : i1_xf_pass;
    i1_ys <= i1_inner_dl ? fp_times2(fp_times2(i1_yf_pass)) : i1_outer_dl ? i1_y_outer : i1_yf_pass;
    i1_zs <= i1_inner_dl ? fp_times2(fp_times2(i1_zf_pass)) : i1_outer_dl ? i1_z_outer : i1_zf_pass;
end
// i1_xs ready at cycle 52

// -- Stage D: scale * p + c  (cycles 52->62) --
// c = xi0 (original world position, Julia-set constant)
wire [26:0] i1_xsc, i1_ysc, i1_zsc;
fp_mul i1_smx(.clk(clk), .a(i1_xs), .b(FP_NEG1P5), .out(i1_xsc)); // ready 57
fp_mul i1_smy(.clk(clk), .a(i1_ys), .b(FP_NEG1P5), .out(i1_ysc));
fp_mul i1_smz(.clk(clk), .a(i1_zs), .b(FP_NEG1P5), .out(i1_zsc));
// delay xi0 (ready 1) to 57: depth 56
wire [26:0] i1_cx, i1_cy, i1_cz;
state_pipe #(.WIDTH(27), .DEPTH(56)) i1_pcx(.clk(clk), .in(xi0), .out(i1_cx));
state_pipe #(.WIDTH(27), .DEPTH(56)) i1_pcy(.clk(clk), .in(yi0), .out(i1_cy));
state_pipe #(.WIDTH(27), .DEPTH(56)) i1_pcz(.clk(clk), .in(zi0), .out(i1_cz));
wire [26:0] i1_xo, i1_yo, i1_zo;
fp_add i1_oax(.clk(clk), .a(i1_xsc), .b(i1_cx), .out(i1_xo)); // ready 62
fp_add i1_oay(.clk(clk), .a(i1_ysc), .b(i1_cy), .out(i1_yo));
fp_add i1_oaz(.clk(clk), .a(i1_zsc), .b(i1_cz), .out(i1_zo));

// ============================================================
// ITERATION 2  (input: i1_xo at cycle 62, output: i2_xo at cycle 123)
// ============================================================
wire [26:0] i2_xc = fp_clamp1(i1_xo);
wire [26:0] i2_yc = fp_clamp1(i1_yo);
wire [26:0] i2_zc = fp_clamp1(i1_zo);
wire [26:0] i2_x2c = fp_times2(i2_xc);
wire [26:0] i2_y2c = fp_times2(i2_yc);
wire [26:0] i2_z2c = fp_times2(i2_zc);
wire [26:0] i2_xf, i2_yf, i2_zf;
fp_sub i2_bfx(.clk(clk), .a(i2_x2c), .b(i1_xo), .out(i2_xf)); // ready 67
fp_sub i2_bfy(.clk(clk), .a(i2_y2c), .b(i1_yo), .out(i2_yf));
fp_sub i2_bfz(.clk(clk), .a(i2_z2c), .b(i1_zo), .out(i2_zf));

wire [26:0] i2_x2, i2_y2, i2_z2, i2_r2xy, i2_z2_dl, i2_r2;
fp_mul i2_mx(.clk(clk), .a(i2_xf), .b(i2_xf), .out(i2_x2));  // ready 72
fp_mul i2_my(.clk(clk), .a(i2_yf), .b(i2_yf), .out(i2_y2));
fp_mul i2_mz(.clk(clk), .a(i2_zf), .b(i2_zf), .out(i2_z2));
fp_add i2_axy(.clk(clk), .a(i2_x2), .b(i2_y2), .out(i2_r2xy)); // ready 77
state_pipe #(.WIDTH(27), .DEPTH(5)) i2_pz2(.clk(clk), .in(i2_z2), .out(i2_z2_dl));
fp_add i2_axyz(.clk(clk), .a(i2_r2xy), .b(i2_z2_dl), .out(i2_r2)); // ready 82

reg i2_inner_r, i2_outer_r;
always @(posedge clk) begin
    i2_inner_r <= (i2_r2[25:0] < FP_0P25[25:0]);
    i2_outer_r <= (i2_r2[25:0] < FP_ONE[25:0]);
end
wire [26:0] i2_inv_r, i2_inv_r2;
fp_isqrt i2_isq(.clk(clk), .a(i2_r2), .out(i2_inv_r));         // ready 102
fp_mul   i2_invsq(.clk(clk), .a(i2_inv_r), .b(i2_inv_r), .out(i2_inv_r2)); // ready 107

wire [26:0] i2_xf_dl, i2_yf_dl, i2_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(40)) i2_pdx(.clk(clk), .in(i2_xf), .out(i2_xf_dl)); // 67+40=107
state_pipe #(.WIDTH(27), .DEPTH(40)) i2_pdy(.clk(clk), .in(i2_yf), .out(i2_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(40)) i2_pdz(.clk(clk), .in(i2_zf), .out(i2_zf_dl));

wire [26:0] i2_x_outer, i2_y_outer, i2_z_outer;
fp_mul i2_ofx(.clk(clk), .a(i2_xf_dl), .b(i2_inv_r2), .out(i2_x_outer)); // ready 112
fp_mul i2_ofy(.clk(clk), .a(i2_yf_dl), .b(i2_inv_r2), .out(i2_y_outer));
fp_mul i2_ofz(.clk(clk), .a(i2_zf_dl), .b(i2_inv_r2), .out(i2_z_outer));

wire [26:0] i2_xf_pass, i2_yf_pass, i2_zf_pass;
state_pipe #(.WIDTH(27), .DEPTH(5)) i2_ppx(.clk(clk), .in(i2_xf_dl), .out(i2_xf_pass)); // 107+5=112
state_pipe #(.WIDTH(27), .DEPTH(5)) i2_ppy(.clk(clk), .in(i2_yf_dl), .out(i2_yf_pass));
state_pipe #(.WIDTH(27), .DEPTH(5)) i2_ppz(.clk(clk), .in(i2_zf_dl), .out(i2_zf_pass));

wire i2_inner_dl, i2_outer_dl;
state_pipe #(.WIDTH(1), .DEPTH(29)) i2_psi(.clk(clk), .in(i2_inner_r), .out(i2_inner_dl)); // 83+29=112
state_pipe #(.WIDTH(1), .DEPTH(29)) i2_pso(.clk(clk), .in(i2_outer_r), .out(i2_outer_dl));

reg [26:0] i2_xs, i2_ys, i2_zs;
always @(posedge clk) begin
    i2_xs <= i2_inner_dl ? fp_times2(fp_times2(i2_xf_pass)) : i2_outer_dl ? i2_x_outer : i2_xf_pass;
    i2_ys <= i2_inner_dl ? fp_times2(fp_times2(i2_yf_pass)) : i2_outer_dl ? i2_y_outer : i2_yf_pass;
    i2_zs <= i2_inner_dl ? fp_times2(fp_times2(i2_zf_pass)) : i2_outer_dl ? i2_z_outer : i2_zf_pass;
end
// i2_xs ready 113

wire [26:0] i2_xsc, i2_ysc, i2_zsc;
fp_mul i2_smx(.clk(clk), .a(i2_xs), .b(FP_NEG1P5), .out(i2_xsc)); // ready 118
fp_mul i2_smy(.clk(clk), .a(i2_ys), .b(FP_NEG1P5), .out(i2_ysc));
fp_mul i2_smz(.clk(clk), .a(i2_zs), .b(FP_NEG1P5), .out(i2_zsc));
// offset = xi0 (original position), delay from 1 to 118: depth 117
wire [26:0] i2_cx, i2_cy, i2_cz;
state_pipe #(.WIDTH(27), .DEPTH(117)) i2_pcx(.clk(clk), .in(xi0), .out(i2_cx));
state_pipe #(.WIDTH(27), .DEPTH(117)) i2_pcy(.clk(clk), .in(yi0), .out(i2_cy));
state_pipe #(.WIDTH(27), .DEPTH(117)) i2_pcz(.clk(clk), .in(zi0), .out(i2_cz));
wire [26:0] i2_xo, i2_yo, i2_zo;
fp_add i2_oax(.clk(clk), .a(i2_xsc), .b(i2_cx), .out(i2_xo)); // ready 123
fp_add i2_oay(.clk(clk), .a(i2_ysc), .b(i2_cy), .out(i2_yo));
fp_add i2_oaz(.clk(clk), .a(i2_zsc), .b(i2_cz), .out(i2_zo));

// ============================================================
// ITERATION 3  (input: i2_xo at cycle 123, output: i3_xo at cycle 184)
// ============================================================
wire [26:0] i3_xc = fp_clamp1(i2_xo);
wire [26:0] i3_yc = fp_clamp1(i2_yo);
wire [26:0] i3_zc = fp_clamp1(i2_zo);
wire [26:0] i3_x2c = fp_times2(i3_xc);
wire [26:0] i3_y2c = fp_times2(i3_yc);
wire [26:0] i3_z2c = fp_times2(i3_zc);
wire [26:0] i3_xf, i3_yf, i3_zf;
fp_sub i3_bfx(.clk(clk), .a(i3_x2c), .b(i2_xo), .out(i3_xf)); // ready 128
fp_sub i3_bfy(.clk(clk), .a(i3_y2c), .b(i2_yo), .out(i3_yf));
fp_sub i3_bfz(.clk(clk), .a(i3_z2c), .b(i2_zo), .out(i3_zf));

wire [26:0] i3_x2, i3_y2, i3_z2, i3_r2xy, i3_z2_dl, i3_r2;
fp_mul i3_mx(.clk(clk), .a(i3_xf), .b(i3_xf), .out(i3_x2));  // ready 133
fp_mul i3_my(.clk(clk), .a(i3_yf), .b(i3_yf), .out(i3_y2));
fp_mul i3_mz(.clk(clk), .a(i3_zf), .b(i3_zf), .out(i3_z2));
fp_add i3_axy(.clk(clk), .a(i3_x2), .b(i3_y2), .out(i3_r2xy)); // ready 138
state_pipe #(.WIDTH(27), .DEPTH(5)) i3_pz2(.clk(clk), .in(i3_z2), .out(i3_z2_dl));
fp_add i3_axyz(.clk(clk), .a(i3_r2xy), .b(i3_z2_dl), .out(i3_r2)); // ready 143

reg i3_inner_r, i3_outer_r;
always @(posedge clk) begin
    i3_inner_r <= (i3_r2[25:0] < FP_0P25[25:0]);
    i3_outer_r <= (i3_r2[25:0] < FP_ONE[25:0]);
end
wire [26:0] i3_inv_r, i3_inv_r2;
fp_isqrt i3_isq(.clk(clk), .a(i3_r2), .out(i3_inv_r));         // ready 163
fp_mul   i3_invsq(.clk(clk), .a(i3_inv_r), .b(i3_inv_r), .out(i3_inv_r2)); // ready 168

wire [26:0] i3_xf_dl, i3_yf_dl, i3_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(40)) i3_pdx(.clk(clk), .in(i3_xf), .out(i3_xf_dl)); // 128+40=168
state_pipe #(.WIDTH(27), .DEPTH(40)) i3_pdy(.clk(clk), .in(i3_yf), .out(i3_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(40)) i3_pdz(.clk(clk), .in(i3_zf), .out(i3_zf_dl));

wire [26:0] i3_x_outer, i3_y_outer, i3_z_outer;
fp_mul i3_ofx(.clk(clk), .a(i3_xf_dl), .b(i3_inv_r2), .out(i3_x_outer)); // ready 173
fp_mul i3_ofy(.clk(clk), .a(i3_yf_dl), .b(i3_inv_r2), .out(i3_y_outer));
fp_mul i3_ofz(.clk(clk), .a(i3_zf_dl), .b(i3_inv_r2), .out(i3_z_outer));

wire [26:0] i3_xf_pass, i3_yf_pass, i3_zf_pass;
state_pipe #(.WIDTH(27), .DEPTH(5)) i3_ppx(.clk(clk), .in(i3_xf_dl), .out(i3_xf_pass)); // 168+5=173
state_pipe #(.WIDTH(27), .DEPTH(5)) i3_ppy(.clk(clk), .in(i3_yf_dl), .out(i3_yf_pass));
state_pipe #(.WIDTH(27), .DEPTH(5)) i3_ppz(.clk(clk), .in(i3_zf_dl), .out(i3_zf_pass));

wire i3_inner_dl, i3_outer_dl;
state_pipe #(.WIDTH(1), .DEPTH(29)) i3_psi(.clk(clk), .in(i3_inner_r), .out(i3_inner_dl)); // 144+29=173
state_pipe #(.WIDTH(1), .DEPTH(29)) i3_pso(.clk(clk), .in(i3_outer_r), .out(i3_outer_dl));

reg [26:0] i3_xs, i3_ys, i3_zs;
always @(posedge clk) begin
    i3_xs <= i3_inner_dl ? fp_times2(fp_times2(i3_xf_pass)) : i3_outer_dl ? i3_x_outer : i3_xf_pass;
    i3_ys <= i3_inner_dl ? fp_times2(fp_times2(i3_yf_pass)) : i3_outer_dl ? i3_y_outer : i3_yf_pass;
    i3_zs <= i3_inner_dl ? fp_times2(fp_times2(i3_zf_pass)) : i3_outer_dl ? i3_z_outer : i3_zf_pass;
end
// i3_xs ready 174

wire [26:0] i3_xsc, i3_ysc, i3_zsc;
fp_mul i3_smx(.clk(clk), .a(i3_xs), .b(FP_NEG1P5), .out(i3_xsc)); // ready 179
fp_mul i3_smy(.clk(clk), .a(i3_ys), .b(FP_NEG1P5), .out(i3_ysc));
fp_mul i3_smz(.clk(clk), .a(i3_zs), .b(FP_NEG1P5), .out(i3_zsc));
// offset = xi0, delay from 1 to 179: depth 178
wire [26:0] i3_cx, i3_cy, i3_cz;
state_pipe #(.WIDTH(27), .DEPTH(178)) i3_pcx(.clk(clk), .in(xi0), .out(i3_cx));
state_pipe #(.WIDTH(27), .DEPTH(178)) i3_pcy(.clk(clk), .in(yi0), .out(i3_cy));
state_pipe #(.WIDTH(27), .DEPTH(178)) i3_pcz(.clk(clk), .in(zi0), .out(i3_cz));
wire [26:0] i3_xo, i3_yo, i3_zo;
fp_add i3_oax(.clk(clk), .a(i3_xsc), .b(i3_cx), .out(i3_xo)); // ready 184
fp_add i3_oay(.clk(clk), .a(i3_ysc), .b(i3_cy), .out(i3_yo));
fp_add i3_oaz(.clk(clk), .a(i3_zsc), .b(i3_cz), .out(i3_zo));

// ============================================================
// ITERATION 4  (input: i3_xo at cycle 184, output: i4_xo at cycle 245)
// ============================================================
wire [26:0] i4_xc = fp_clamp1(i3_xo);
wire [26:0] i4_yc = fp_clamp1(i3_yo);
wire [26:0] i4_zc = fp_clamp1(i3_zo);
wire [26:0] i4_x2c = fp_times2(i4_xc);
wire [26:0] i4_y2c = fp_times2(i4_yc);
wire [26:0] i4_z2c = fp_times2(i4_zc);
wire [26:0] i4_xf, i4_yf, i4_zf;
fp_sub i4_bfx(.clk(clk), .a(i4_x2c), .b(i3_xo), .out(i4_xf)); // ready 189
fp_sub i4_bfy(.clk(clk), .a(i4_y2c), .b(i3_yo), .out(i4_yf));
fp_sub i4_bfz(.clk(clk), .a(i4_z2c), .b(i3_zo), .out(i4_zf));

wire [26:0] i4_x2, i4_y2, i4_z2, i4_r2xy, i4_z2_dl, i4_r2;
fp_mul i4_mx(.clk(clk), .a(i4_xf), .b(i4_xf), .out(i4_x2));  // ready 194
fp_mul i4_my(.clk(clk), .a(i4_yf), .b(i4_yf), .out(i4_y2));
fp_mul i4_mz(.clk(clk), .a(i4_zf), .b(i4_zf), .out(i4_z2));
fp_add i4_axy(.clk(clk), .a(i4_x2), .b(i4_y2), .out(i4_r2xy)); // ready 199
state_pipe #(.WIDTH(27), .DEPTH(5)) i4_pz2(.clk(clk), .in(i4_z2), .out(i4_z2_dl));
fp_add i4_axyz(.clk(clk), .a(i4_r2xy), .b(i4_z2_dl), .out(i4_r2)); // ready 204

reg i4_inner_r, i4_outer_r;
always @(posedge clk) begin
    i4_inner_r <= (i4_r2[25:0] < FP_0P25[25:0]);
    i4_outer_r <= (i4_r2[25:0] < FP_ONE[25:0]);
end
wire [26:0] i4_inv_r, i4_inv_r2;
fp_isqrt i4_isq(.clk(clk), .a(i4_r2), .out(i4_inv_r));         // ready 224
fp_mul   i4_invsq(.clk(clk), .a(i4_inv_r), .b(i4_inv_r), .out(i4_inv_r2)); // ready 229

wire [26:0] i4_xf_dl, i4_yf_dl, i4_zf_dl;
state_pipe #(.WIDTH(27), .DEPTH(40)) i4_pdx(.clk(clk), .in(i4_xf), .out(i4_xf_dl)); // 189+40=229
state_pipe #(.WIDTH(27), .DEPTH(40)) i4_pdy(.clk(clk), .in(i4_yf), .out(i4_yf_dl));
state_pipe #(.WIDTH(27), .DEPTH(40)) i4_pdz(.clk(clk), .in(i4_zf), .out(i4_zf_dl));

wire [26:0] i4_x_outer, i4_y_outer, i4_z_outer;
fp_mul i4_ofx(.clk(clk), .a(i4_xf_dl), .b(i4_inv_r2), .out(i4_x_outer)); // ready 234
fp_mul i4_ofy(.clk(clk), .a(i4_yf_dl), .b(i4_inv_r2), .out(i4_y_outer));
fp_mul i4_ofz(.clk(clk), .a(i4_zf_dl), .b(i4_inv_r2), .out(i4_z_outer));

wire [26:0] i4_xf_pass, i4_yf_pass, i4_zf_pass;
state_pipe #(.WIDTH(27), .DEPTH(5)) i4_ppx(.clk(clk), .in(i4_xf_dl), .out(i4_xf_pass)); // 229+5=234
state_pipe #(.WIDTH(27), .DEPTH(5)) i4_ppy(.clk(clk), .in(i4_yf_dl), .out(i4_yf_pass));
state_pipe #(.WIDTH(27), .DEPTH(5)) i4_ppz(.clk(clk), .in(i4_zf_dl), .out(i4_zf_pass));

wire i4_inner_dl, i4_outer_dl;
state_pipe #(.WIDTH(1), .DEPTH(29)) i4_psi(.clk(clk), .in(i4_inner_r), .out(i4_inner_dl)); // 205+29=234
state_pipe #(.WIDTH(1), .DEPTH(29)) i4_pso(.clk(clk), .in(i4_outer_r), .out(i4_outer_dl));

reg [26:0] i4_xs, i4_ys, i4_zs;
always @(posedge clk) begin
    i4_xs <= i4_inner_dl ? fp_times2(fp_times2(i4_xf_pass)) : i4_outer_dl ? i4_x_outer : i4_xf_pass;
    i4_ys <= i4_inner_dl ? fp_times2(fp_times2(i4_yf_pass)) : i4_outer_dl ? i4_y_outer : i4_yf_pass;
    i4_zs <= i4_inner_dl ? fp_times2(fp_times2(i4_zf_pass)) : i4_outer_dl ? i4_z_outer : i4_zf_pass;
end
// i4_xs ready 235

wire [26:0] i4_xsc, i4_ysc, i4_zsc;
fp_mul i4_smx(.clk(clk), .a(i4_xs), .b(FP_NEG1P5), .out(i4_xsc)); // ready 240
fp_mul i4_smy(.clk(clk), .a(i4_ys), .b(FP_NEG1P5), .out(i4_ysc));
fp_mul i4_smz(.clk(clk), .a(i4_zs), .b(FP_NEG1P5), .out(i4_zsc));
// offset = xi0, delay from 1 to 240: depth 239
wire [26:0] i4_cx, i4_cy, i4_cz;
state_pipe #(.WIDTH(27), .DEPTH(239)) i4_pcx(.clk(clk), .in(xi0), .out(i4_cx));
state_pipe #(.WIDTH(27), .DEPTH(239)) i4_pcy(.clk(clk), .in(yi0), .out(i4_cy));
state_pipe #(.WIDTH(27), .DEPTH(239)) i4_pcz(.clk(clk), .in(zi0), .out(i4_cz));
wire [26:0] i4_xo, i4_yo, i4_zo;
fp_add i4_oax(.clk(clk), .a(i4_xsc), .b(i4_cx), .out(i4_xo)); // ready 245
fp_add i4_oay(.clk(clk), .a(i4_ysc), .b(i4_cy), .out(i4_yo));
fp_add i4_oaz(.clk(clk), .a(i4_zsc), .b(i4_cz), .out(i4_zo));

// ============================================================
// DISTANCE ESTIMATE
// Approx SDF = length(z4) / |scale|^4 = length(z4) / 5.0625
// Multiply by 0.2 as conservative lower bound (prevents overstepping)
// fp_length latency = 40 cycles -> 245+40 = 285
// fp_mul *0.2: 5 cycles -> 290
// reg sdf_out: 1 cycle -> 291   SET SDF_LAT = 291 in march_core.sv
// ============================================================
wire [26:0] sdf_raw;
fp_length inst_len(.clk(clk), .x(i4_xo), .y(i4_yo), .z(i4_zo), .out(sdf_raw));

wire [26:0] sdf_scaled;
fp_mul inst_scale(.clk(clk), .a(sdf_raw), .b(FP_0P2), .out(sdf_scaled)); // ready 290

always @(posedge clk) sdf_out <= sdf_scaled; // ready 291

endmodule
`default_nettype wire
