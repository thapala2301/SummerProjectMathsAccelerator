// 3-level Menger sponge SDF
// march_core.sv: set SCENE_CORE_LAT = 77, instantiate menger_sdf instead of scaffold_sdf
// ctrl.py: scene_cell_sz=2.0, scene_half_cell=1.0, scene_shape_size=1.0 (box half-extent)
//
// All 3 levels computed in PARALLEL from same px/py/pz input.
// Level 1: fold at s=1 (fp_mod only, no fp_mul) → 68 cycle path → state_pipe DEPTH=8
// Level 2: scale s=3  (fp_mul+fp_mod+...)       → 76 cycle path → no delay
// Level 3: scale s=9  (fp_mul+fp_mod+...)        → 76 cycle path → no delay
// Box SDF:  abs+sub+max                          →  4 cycle path → state_pipe DEPTH=72
// Final register: +1 cycle → SCENE_CORE_LAT = 77

module menger_sdf(
    input         clk,
    input  [26:0] px,
    input  [26:0] py,
    input  [26:0] pz,
    input  logic [26:0] sdf_params [0:7],
    output reg   [26:0] sdf_out
);

wire [26:0] b = sdf_params[1]; // box half-extent, set scene_shape_size=1.0

// FP27: {sign(1), exp_biased(8), mantissa(18)}
localparam [26:0] ONE   = {1'b0, 8'd127, 18'h00000}; // 1.0
localparam [26:0] TWO   = {1'b0, 8'd128, 18'h00000}; // 2.0
localparam [26:0] THREE = {1'b0, 8'd128, 18'h20000}; // 3.0
localparam [26:0] NINE  = {1'b0, 8'd130, 18'h08000}; // 9.0
localparam [26:0] INV3  = {1'b0, 8'd125, 18'h15555}; // 1/3
localparam [26:0] INV9  = {1'b0, 8'd123, 18'h31C71}; // 1/9

// =========================================================
// BOX SDF (L-inf norm): max(|px|-b, |py|-b, |pz|-b)
// Ready at t=4, delayed 72 cycles to align with t=76
// =========================================================
wire [26:0] apx, apy, apz;
fp_abs inst_bx_abs(.in(px), .out(apx));
fp_abs inst_by_abs(.in(py), .out(apy));
fp_abs inst_bz_abs(.in(pz), .out(apz));

wire [26:0] bdx, bdy, bdz;
fp_sub inst_bdx(.clk(clk), .a(apx), .b(b), .out(bdx));
fp_sub inst_bdy(.clk(clk), .a(apy), .b(b), .out(bdy));
fp_sub inst_bdz(.clk(clk), .a(apz), .b(b), .out(bdz));

wire [26:0] bdyz, box_d_raw;
fp_max inst_box_maxyz(.a(bdy),    .b(bdz), .out(bdyz));
fp_max inst_box_maxxyz(.a(bdx),   .b(bdyz),.out(box_d_raw));

wire [26:0] box_d;
state_pipe #(.WIDTH(27), .DEPTH(72)) pipe_box(.clk(clk), .in(box_d_raw), .out(box_d));

// =========================================================
// LEVEL 1 (s=1): fold=mod(p,2)-1, cross, no final fp_mul
// Ready at t=68, delayed 8 cycles to align with t=76
// =========================================================
wire [26:0] lv1_mx, lv1_my, lv1_mz;
fp_mod inst_lv1_modx(.clk(clk), .a(px), .b(TWO), .rem(lv1_mx)); // t=52
fp_mod inst_lv1_mody(.clk(clk), .a(py), .b(TWO), .rem(lv1_my));
fp_mod inst_lv1_modz(.clk(clk), .a(pz), .b(TWO), .rem(lv1_mz));

wire [26:0] a1x, a1y, a1z;
fp_sub inst_lv1_ax(.clk(clk), .a(lv1_mx), .b(ONE), .out(a1x)); // t=56
fp_sub inst_lv1_ay(.clk(clk), .a(lv1_my), .b(ONE), .out(a1y));
fp_sub inst_lv1_az(.clk(clk), .a(lv1_mz), .b(ONE), .out(a1z));

wire [26:0] abs_a1x, abs_a1y, abs_a1z;
fp_abs inst_lv1_absx(.in(a1x), .out(abs_a1x)); // t=56 combinational
fp_abs inst_lv1_absy(.in(a1y), .out(abs_a1y));
fp_abs inst_lv1_absz(.in(a1z), .out(abs_a1z));

wire [26:0] r1x_pre, r1y_pre, r1z_pre;
fp_mul inst_lv1_rmx(.clk(clk), .a(THREE), .b(abs_a1x), .out(r1x_pre)); // t=60
fp_mul inst_lv1_rmy(.clk(clk), .a(THREE), .b(abs_a1y), .out(r1y_pre));
fp_mul inst_lv1_rmz(.clk(clk), .a(THREE), .b(abs_a1z), .out(r1z_pre));

wire [26:0] r1x, r1y, r1z;
fp_sub inst_lv1_rx(.clk(clk), .a(ONE), .b(r1x_pre), .out(r1x)); // t=64
fp_sub inst_lv1_ry(.clk(clk), .a(ONE), .b(r1y_pre), .out(r1y));
fp_sub inst_lv1_rz(.clk(clk), .a(ONE), .b(r1z_pre), .out(r1z));

wire [26:0] ar1x, ar1y, ar1z;
fp_abs inst_lv1_arx(.in(r1x), .out(ar1x)); // t=64 combinational
fp_abs inst_lv1_ary(.in(r1y), .out(ar1y));
fp_abs inst_lv1_arz(.in(r1z), .out(ar1z));

wire [26:0] lv1_mxy, lv1_myz, lv1_mzx, lv1_tmp, lv1_cross;
fp_max inst_lv1_mxy(.a(ar1x), .b(ar1y), .out(lv1_mxy)); // combinational
fp_max inst_lv1_myz(.a(ar1y), .b(ar1z), .out(lv1_myz));
fp_max inst_lv1_mzx(.a(ar1z), .b(ar1x), .out(lv1_mzx));
fp_min inst_lv1_mn1(.a(lv1_mxy), .b(lv1_myz), .out(lv1_tmp));
fp_min inst_lv1_mn2(.a(lv1_tmp), .b(lv1_mzx), .out(lv1_cross));

wire [26:0] c1_raw;
fp_sub inst_lv1_c(.clk(clk), .a(lv1_cross), .b(ONE), .out(c1_raw)); // t=68, s=1 so no mul

wire [26:0] c1;
state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_c1(.clk(clk), .in(c1_raw), .out(c1)); // t=76

// =========================================================
// LEVEL 2 (s=3): p*3 -> mod(.,2)-1 -> cross -> /3
// Ready at t=76
// =========================================================
wire [26:0] px3, py3, pz3;
fp_mul inst_lv2_px(.clk(clk), .a(px), .b(THREE), .out(px3)); // t=4
fp_mul inst_lv2_py(.clk(clk), .a(py), .b(THREE), .out(py3));
fp_mul inst_lv2_pz(.clk(clk), .a(pz), .b(THREE), .out(pz3));

wire [26:0] lv2_mx, lv2_my, lv2_mz;
fp_mod inst_lv2_modx(.clk(clk), .a(px3), .b(TWO), .rem(lv2_mx)); // t=56
fp_mod inst_lv2_mody(.clk(clk), .a(py3), .b(TWO), .rem(lv2_my));
fp_mod inst_lv2_modz(.clk(clk), .a(pz3), .b(TWO), .rem(lv2_mz));

wire [26:0] a2x, a2y, a2z;
fp_sub inst_lv2_ax(.clk(clk), .a(lv2_mx), .b(ONE), .out(a2x)); // t=60
fp_sub inst_lv2_ay(.clk(clk), .a(lv2_my), .b(ONE), .out(a2y));
fp_sub inst_lv2_az(.clk(clk), .a(lv2_mz), .b(ONE), .out(a2z));

wire [26:0] abs_a2x, abs_a2y, abs_a2z;
fp_abs inst_lv2_absx(.in(a2x), .out(abs_a2x));
fp_abs inst_lv2_absy(.in(a2y), .out(abs_a2y));
fp_abs inst_lv2_absz(.in(a2z), .out(abs_a2z));

wire [26:0] r2x_pre, r2y_pre, r2z_pre;
fp_mul inst_lv2_rmx(.clk(clk), .a(THREE), .b(abs_a2x), .out(r2x_pre)); // t=64
fp_mul inst_lv2_rmy(.clk(clk), .a(THREE), .b(abs_a2y), .out(r2y_pre));
fp_mul inst_lv2_rmz(.clk(clk), .a(THREE), .b(abs_a2z), .out(r2z_pre));

wire [26:0] r2x, r2y, r2z;
fp_sub inst_lv2_rx(.clk(clk), .a(ONE), .b(r2x_pre), .out(r2x)); // t=68
fp_sub inst_lv2_ry(.clk(clk), .a(ONE), .b(r2y_pre), .out(r2y));
fp_sub inst_lv2_rz(.clk(clk), .a(ONE), .b(r2z_pre), .out(r2z));

wire [26:0] ar2x, ar2y, ar2z;
fp_abs inst_lv2_arx(.in(r2x), .out(ar2x));
fp_abs inst_lv2_ary(.in(r2y), .out(ar2y));
fp_abs inst_lv2_arz(.in(r2z), .out(ar2z));

wire [26:0] lv2_mxy, lv2_myz, lv2_mzx, lv2_tmp, lv2_cross;
fp_max inst_lv2_mxy(.a(ar2x), .b(ar2y), .out(lv2_mxy));
fp_max inst_lv2_myz(.a(ar2y), .b(ar2z), .out(lv2_myz));
fp_max inst_lv2_mzx(.a(ar2z), .b(ar2x), .out(lv2_mzx));
fp_min inst_lv2_mn1(.a(lv2_mxy), .b(lv2_myz), .out(lv2_tmp));
fp_min inst_lv2_mn2(.a(lv2_tmp), .b(lv2_mzx), .out(lv2_cross));

wire [26:0] c2_sub;
fp_sub inst_lv2_c(.clk(clk), .a(lv2_cross), .b(ONE), .out(c2_sub)); // t=72

wire [26:0] c2;
fp_mul inst_lv2_inv(.clk(clk), .a(c2_sub), .b(INV3), .out(c2)); // t=76

// =========================================================
// LEVEL 3 (s=9): p*9 -> mod(.,2)-1 -> cross -> /9
// Identical pipeline to Level 2, different constants
// Ready at t=76
// =========================================================
wire [26:0] px9, py9, pz9;
fp_mul inst_lv3_px(.clk(clk), .a(px), .b(NINE), .out(px9));
fp_mul inst_lv3_py(.clk(clk), .a(py), .b(NINE), .out(py9));
fp_mul inst_lv3_pz(.clk(clk), .a(pz), .b(NINE), .out(pz9));

wire [26:0] lv3_mx, lv3_my, lv3_mz;
fp_mod inst_lv3_modx(.clk(clk), .a(px9), .b(TWO), .rem(lv3_mx));
fp_mod inst_lv3_mody(.clk(clk), .a(py9), .b(TWO), .rem(lv3_my));
fp_mod inst_lv3_modz(.clk(clk), .a(pz9), .b(TWO), .rem(lv3_mz));

wire [26:0] a3x, a3y, a3z;
fp_sub inst_lv3_ax(.clk(clk), .a(lv3_mx), .b(ONE), .out(a3x));
fp_sub inst_lv3_ay(.clk(clk), .a(lv3_my), .b(ONE), .out(a3y));
fp_sub inst_lv3_az(.clk(clk), .a(lv3_mz), .b(ONE), .out(a3z));

wire [26:0] abs_a3x, abs_a3y, abs_a3z;
fp_abs inst_lv3_absx(.in(a3x), .out(abs_a3x));
fp_abs inst_lv3_absy(.in(a3y), .out(abs_a3y));
fp_abs inst_lv3_absz(.in(a3z), .out(abs_a3z));

wire [26:0] r3x_pre, r3y_pre, r3z_pre;
fp_mul inst_lv3_rmx(.clk(clk), .a(THREE), .b(abs_a3x), .out(r3x_pre));
fp_mul inst_lv3_rmy(.clk(clk), .a(THREE), .b(abs_a3y), .out(r3y_pre));
fp_mul inst_lv3_rmz(.clk(clk), .a(THREE), .b(abs_a3z), .out(r3z_pre));

wire [26:0] r3x, r3y, r3z;
fp_sub inst_lv3_rx(.clk(clk), .a(ONE), .b(r3x_pre), .out(r3x));
fp_sub inst_lv3_ry(.clk(clk), .a(ONE), .b(r3y_pre), .out(r3y));
fp_sub inst_lv3_rz(.clk(clk), .a(ONE), .b(r3z_pre), .out(r3z));

wire [26:0] ar3x, ar3y, ar3z;
fp_abs inst_lv3_arx(.in(r3x), .out(ar3x));
fp_abs inst_lv3_ary(.in(r3y), .out(ar3y));
fp_abs inst_lv3_arz(.in(r3z), .out(ar3z));

wire [26:0] lv3_mxy, lv3_myz, lv3_mzx, lv3_tmp, lv3_cross;
fp_max inst_lv3_mxy(.a(ar3x), .b(ar3y), .out(lv3_mxy));
fp_max inst_lv3_myz(.a(ar3y), .b(ar3z), .out(lv3_myz));
fp_max inst_lv3_mzx(.a(ar3z), .b(ar3x), .out(lv3_mzx));
fp_min inst_lv3_mn1(.a(lv3_mxy), .b(lv3_myz), .out(lv3_tmp));
fp_min inst_lv3_mn2(.a(lv3_tmp), .b(lv3_mzx), .out(lv3_cross));

wire [26:0] c3_sub;
fp_sub inst_lv3_c(.clk(clk), .a(lv3_cross), .b(ONE), .out(c3_sub));

wire [26:0] c3;
fp_mul inst_lv3_inv(.clk(clk), .a(c3_sub), .b(INV9), .out(c3));

// =========================================================
// COMBINE: d = max(box, max(-c1, max(-c2, -c3)))
// All signals aligned at t=76. Negate = flip sign bit in FP27.
// CSG subtraction: max(box, -cross) = box minus fractal holes
// =========================================================
wire [26:0] neg_c1 = {~c1[26], c1[25:0]};
wire [26:0] neg_c2 = {~c2[26], c2[25:0]};
wire [26:0] neg_c3 = {~c3[26], c3[25:0]};

wire [26:0] stage1, stage2, sdf_comb;
fp_max inst_fin1(.a(box_d), .b(neg_c1), .out(stage1));
fp_max inst_fin2(.a(stage1),.b(neg_c2), .out(stage2));
fp_max inst_fin3(.a(stage2),.b(neg_c3), .out(sdf_comb));

always @(posedge clk) sdf_out <= sdf_comb;

endmodule
