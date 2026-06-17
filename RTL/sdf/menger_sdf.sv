// march_core.sv: instantiate menger_sdf and set SCENE_CORE_LAT = 5
// sdf_params[1] = box half-extent  (scene_shape_size, e.g. 4.5)
// sdf_params[2] = tunnel half-width (scene_shape_extra = shape_size/3, e.g. 1.5)
// ctrl: SCENE_CELL_SZ = 10.0, SCENE_HALF_CELL = 5.0
//
// Level-1 Menger sponge: cube with three axis-aligned square tunnels removed.
// Box SDF uses L-inf (no fp_length needed). Cross SDF uses abs/max/min only.
// Pipeline: abs(0) -> sub(4) -> max/min chain(0) -> reg(1) = 5 cycles total.

module menger_sdf(
    input         clk,
    input  [26:0] px,
    input  [26:0] py,
    input  [26:0] pz,
    input  logic [26:0] sdf_params [0:7],
    output reg   [26:0] sdf_out
);

wire [26:0] b = sdf_params[1]; // box half-extent
wire [26:0] t = sdf_params[2]; // tunnel half-width = b/3

// abs fold — combinational
wire [26:0] apx, apy, apz;
fp_abs inst_abs_x(.in(px), .out(apx));
fp_abs inst_abs_y(.in(py), .out(apy));
fp_abs inst_abs_z(.in(pz), .out(apz));

// --- Box SDF (L-inf): max(|px|-b, |py|-b, |pz|-b) ---
wire [26:0] dx, dy, dz;
fp_sub inst_dx(.clk(clk), .a(apx), .b(b), .out(dx));
fp_sub inst_dy(.clk(clk), .a(apy), .b(b), .out(dy));
fp_sub inst_dz(.clk(clk), .a(apz), .b(b), .out(dz));

wire [26:0] dyz, box_d;
fp_max inst_max_yz (.a(dy),  .b(dz),  .out(dyz));
fp_max inst_max_box(.a(dx),  .b(dyz), .out(box_d));

// --- Cross SDF: min(max(|px|,|py|), max(|py|,|pz|), max(|pz|,|px|)) - t ---
// negative inside any of the 3 axis-aligned square tunnels
wire [26:0] mxy, myz, mzx, cross_mn;
fp_max inst_mxy(.a(apx), .b(apy), .out(mxy));
fp_max inst_myz(.a(apy), .b(apz), .out(myz));
fp_max inst_mzx(.a(apz), .b(apx), .out(mzx));

wire [26:0] t_mn;
fp_min inst_mn1(.a(mxy), .b(myz), .out(t_mn));
fp_min inst_mn2(.a(t_mn), .b(mzx), .out(cross_mn));

wire [26:0] c1;
fp_sub inst_c1(.clk(clk), .a(cross_mn), .b(t), .out(c1));

// negate c1 (flip sign bit — subtract tunnels from box)
wire [26:0] neg_c1 = {~c1[26], c1[25:0]};

// max(box, -cross): carve tunnels out of box
wire [26:0] sdf_comb;
fp_max inst_final(.a(box_d), .b(neg_c1), .out(sdf_comb));

always @(posedge clk) sdf_out <= sdf_comb;

endmodule
