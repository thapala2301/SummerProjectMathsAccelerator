// march_core.sv: instantiate scaffold_sdf and set SCENE_CORE_LAT = 50
// march_core.sv: set SCENE_CELL_SZ = 27'h2090000 and SCENE_HALF_CELL = 27'h2050000
// ctrl.py: set CAMERA_WRAP_CELL_SZ = 10.0 and CAMERA_WRAP_HALF_CELL = 5.0

module scaffold_sdf(
    input         clk,
    input  [26:0] px,
    input  [26:0] py,
    input  [26:0] pz,
    input  [26:0] shape_size,
    input  [26:0] shape_extra,
    output reg [26:0] sdf_out
);

wire [26:0] b_fp = shape_size;
wire [26:0] e_fp = shape_extra;

wire [26:0] abs_px;
wire [26:0] abs_py;
wire [26:0] abs_pz;
wire [26:0] px_intermed;
wire [26:0] py_intermed;
wire [26:0] pz_intermed;
wire [26:0] px_intermed2;
wire [26:0] py_intermed2;
wire [26:0] pz_intermed2;
wire [26:0] temp_add_px;
wire [26:0] temp_add_py;
wire [26:0] temp_add_pz;
wire [26:0] qx;
wire [26:0] qy;
wire [26:0] qz;
wire [26:0] px_intermed_d;
wire [26:0] py_intermed_d;
wire [26:0] pz_intermed_d;
wire [26:0] term1;
wire [26:0] term2;
wire [26:0] term3;
wire [26:0] temp_min;
wire [26:0] sdf_comb;

fp_abs inst_abs_px(.in(px), .out(abs_px));
fp_abs inst_abs_py(.in(py), .out(abs_py));
fp_abs inst_abs_pz(.in(pz), .out(abs_pz));

fp_sub sub_px_b(.clk(clk), .a(abs_px), .b(b_fp), .out(px_intermed));
fp_sub sub_py_b(.clk(clk), .a(abs_py), .b(b_fp), .out(py_intermed));
fp_sub sub_pz_b(.clk(clk), .a(abs_pz), .b(b_fp), .out(pz_intermed));

fp_add add_px_intermed_e(.clk(clk), .a(px_intermed), .b(e_fp), .out(px_intermed2));
fp_add add_py_intermed_e(.clk(clk), .a(py_intermed), .b(e_fp), .out(py_intermed2));
fp_add add_pz_intermed_e(.clk(clk), .a(pz_intermed), .b(e_fp), .out(pz_intermed2));

state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_pxi(.clk(clk), .in(px_intermed), .out(px_intermed_d));
state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_pyi(.clk(clk), .in(py_intermed), .out(py_intermed_d));
state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_pzi(.clk(clk), .in(pz_intermed), .out(pz_intermed_d));

fp_abs abs_px_intermed2_e(.in(px_intermed2), .out(temp_add_px));
fp_abs abs_py_intermed2_e(.in(py_intermed2), .out(temp_add_py));
fp_abs abs_pz_intermed2_e(.in(pz_intermed2), .out(temp_add_pz));

fp_sub tempx_e(.clk(clk), .a(temp_add_px), .b(e_fp), .out(qx));
fp_sub tempy_e(.clk(clk), .a(temp_add_py), .b(e_fp), .out(qy));
fp_sub tempz_e(.clk(clk), .a(temp_add_pz), .b(e_fp), .out(qz));

sdf_term inst1_term1(.clk(clk), .vx(px_intermed_d), .vy(qy), .vz(qz), .out(term1));
sdf_term inst2_term2(.clk(clk), .vx(qx), .vy(py_intermed_d), .vz(qz), .out(term2));
sdf_term inst3_term3(.clk(clk), .vx(qx), .vy(qy), .vz(pz_intermed_d), .out(term3));

fp_min inst1_min(.a(term1), .b(term2), .out(temp_min));

reg [26:0] temp_min_reg;
reg [26:0] term3_reg;

always @(posedge clk) begin
    temp_min_reg <= temp_min;
    term3_reg <= term3;
end

fp_min inst2_min(.a(temp_min_reg), .b(term3_reg), .out(sdf_comb));

always @(posedge clk) begin
    sdf_out <= sdf_comb;
end

endmodule

// length(max((v0, v1, v2), 0.0)) + min(max(v0, max(v1, v2)), 0.0)
module sdf_term(
    input clk,
    input wire [26:0] vx,
    input wire [26:0] vy,
    input wire [26:0] vz,
    output wire [26:0] out
);

    wire [26:0] cx = vx[26] ? 27'b0 : vx;
    wire [26:0] cy = vy[26] ? 27'b0 : vy;
    wire [26:0] cz = vz[26] ? 27'b0 : vz;

    wire [26:0] len;
    fp_length inst_len(.clk(clk), .x(cx), .y(cy), .z(cz), .out(len));

    wire [26:0] temp_max;
    fp_max inst1_max(.a(vy), .b(vz), .out(temp_max));

    reg [26:0] temp_max_reg;
    reg [26:0] vx_reg;
    always @(posedge clk) begin
        temp_max_reg <= temp_max;
        vx_reg <= vx;
    end

    wire [26:0] temp_maxv0_maxv1_v2;
    fp_max inst2_max(.a(vx_reg), .b(temp_max_reg), .out(temp_maxv0_maxv1_v2));
    wire [26:0] clamped_neg = temp_maxv0_maxv1_v2[26] ? temp_maxv0_maxv1_v2 : 27'b0;

    wire [26:0] clamped_neg_delayed;
    state_pipe #(.WIDTH(27), .DEPTH(31)) pipe_clamped_neg(.clk(clk), .in(clamped_neg), .out(clamped_neg_delayed));
    fp_add final_add(.clk(clk), .a(len), .b(clamped_neg_delayed), .out(out));

endmodule
