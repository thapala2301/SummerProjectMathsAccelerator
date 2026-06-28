// march_core.sv: instantiate sdf_twisted_torus and set SCENE_CORE_LAT = 101
// march_core.sv: set SCENE_CELL_SZ = 27'h2090000 and SCENE_HALF_CELL = 27'h2050000
// ctrl.py: set CAMERA_WRAP_CELL_SZ = 10.0 and CAMERA_WRAP_HALF_CELL = 5.0
//
// The twisted torus is our original torus but with the XZ plane rotated by
// angle = py * TWIST at each height, producing a helical twist along Y.
// Flow of module: twist angle -> Taylor cos/sin -> 2D rotation -> torus SDF

module sdf_twisted_torus(
    input clk,
    input [26:0] px, py, pz,
    output reg [26:0] sdf_out
);

localparam [26:0] FP_ZERO  = 27'h0;
localparam [26:0] BIG_R    = {1'b0, 8'd127, 18'h33333};
localparam [26:0] SMALL_R  = {1'b0, 8'd125, 18'h4CCCD};
localparam [26:0] TWIST    = {1'b0, 8'd125, 18'h00000};
localparam [26:0] FP_ONE   = {1'b0, 8'd127, 18'h00000};
localparam [26:0] FP_HALF  = {1'b0, 8'd126, 18'h00000};
localparam [26:0] FP_SIXTH = {1'b0, 8'd124, 18'h15555};

// Calculating the twist angle
wire [26:0] angle;
fp_mul inst_angle(.clk(clk), .a(py), .b(TWIST), .out(angle));

// Cos approximation via Taylor
wire [26:0] angle2, angle2_2, cos_a, cos_a_d4;
fp_mul inst_a2(.clk(clk), .a(angle), .b(angle), .out(angle2));

fp_mul inst_a2_2(.clk(clk), .a(angle2), .b(FP_HALF), .out(angle2_2));
fp_sub inst_cos(.clk(clk), .a(FP_ONE), .b(angle2_2), .out(cos_a));
state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_cos(.clk(clk), .in(cos_a), .out(cos_a_d4));

// Sine approximation via Taylor
wire [26:0] angle3, angle3_6, sin_a;
wire [26:0] angle_d4;
state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_ang(.clk(clk), .in(angle), .out(angle_d4));
fp_mul inst_a3(.clk(clk), .a(angle2), .b(angle_d4), .out(angle3));
fp_mul inst_a3_6(.clk(clk), .a(angle3), .b(FP_SIXTH), .out(angle3_6));
wire [26:0] angle_d16;
state_pipe #(.WIDTH(27), .DEPTH(12)) pipe_ang12(.clk(clk), .in(angle), .out(angle_d16));
fp_sub inst_sin(.clk(clk), .a(angle_d16), .b(angle3_6), .out(sin_a));

// rotated_x = px*cos - pz*sin
// rotated_z = px*sin + pz*cos
// Think rotation matrices being applied to our original points kinda
wire [26:0] px_d20, pz_d20;
state_pipe #(.WIDTH(27), .DEPTH(20)) pipe_px(.clk(clk), .in(px), .out(px_d20));
state_pipe #(.WIDTH(27), .DEPTH(20)) pipe_pz(.clk(clk), .in(pz), .out(pz_d20));

wire [26:0] px_cos, pz_sin, px_sin, pz_cos;
fp_mul inst_px_cos(.clk(clk), .a(px_d20), .b(cos_a_d4), .out(px_cos));
fp_mul inst_pz_sin(.clk(clk), .a(pz_d20), .b(sin_a),    .out(pz_sin));
fp_mul inst_px_sin(.clk(clk), .a(px_d20), .b(sin_a),    .out(px_sin));
fp_mul inst_pz_cos(.clk(clk), .a(pz_d20), .b(cos_a_d4), .out(pz_cos));

wire [26:0] rx, rz;
fp_sub inst_rx(.clk(clk), .a(px_cos), .b(pz_sin), .out(rx));
fp_add inst_rz(.clk(clk), .a(px_sin), .b(pz_cos), .out(rz));

// Now we analyse the torus having rotated co-ordinates and that
wire [26:0] len_xz;
fp_length inst_len_xz(.clk(clk), .x(rx), .y(FP_ZERO), .z(rz), .out(len_xz));

wire [26:0] qx;
fp_sub inst_qx(.clk(clk), .a(len_xz), .b(BIG_R), .out(qx));

wire [26:0] py_d64;
state_pipe #(.WIDTH(27), .DEPTH(64)) pipe_py(.clk(clk), .in(py), .out(py_d64));

wire [26:0] len_q;
fp_length inst_len_q(.clk(clk), .x(qx), .y(py_d64), .z(FP_ZERO), .out(len_q));

wire [26:0] sdf_comb;
fp_sub inst_sub(.clk(clk), .a(len_q), .b(SMALL_R), .out(sdf_comb));

always @(posedge clk) sdf_out <= sdf_comb;

endmodule