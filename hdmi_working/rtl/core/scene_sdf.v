module scene_sdf(
    input        clk,
    input  [26:0] px,
    input  [26:0] py,
    input  [26:0] pz,
    output reg [26:0] sdf_out
);

wire [26:0] b_fp = {1'b0, 8'd129, 18'h08000};
wire [26:0] e_fp = {1'b0, 8'd124, 18'h0CCCD};

wire [26:0] rep_px;
wire [26:0] rep_py;
wire [26:0] rep_pz;

repeat_cell inst_repeat_x(.clk(clk), .p(px), .q(rep_px));
repeat_cell inst_repeat_y(.clk(clk), .p(py), .q(rep_py));
repeat_cell inst_repeat_z(.clk(clk), .p(pz), .q(rep_pz));

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

fp_abs inst_abs_px(.in(rep_px), .out(abs_px));
fp_abs inst_abs_py(.in(rep_py), .out(abs_py));
fp_abs inst_abs_pz(.in(rep_pz), .out(abs_pz));

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
fp_min inst2_min(.a(temp_min), .b(term3), .out(sdf_comb));

always @(posedge clk) begin
    sdf_out <= sdf_comb;
end

endmodule
