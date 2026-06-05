//sdBoxFrame sdf, see IniguloQuilez SDF derivation and SW_Raymarching scaffold.frag (this code is Verilog equiv of the GLSL presented in that frag)
module scene_sdf(
    input clk,
    input [26:0] px, py, pz,
    output reg [26:0] sdf_out
);

wire [26:0] b_fp = {1'b0, 8'd127, 18'h00000}; // 1.0
 //RESET TO 4.5 in 1.8.18 WHEN ALL WORKs
wire [26:0] e_fp = {1'b0, 8'd124, 18'h0CCCD}; // 0.15
//RESET TO 0.15 WHEN ALL WORK

//b : half extent of box, e : edge thickness

//Stage A
wire [26:0] abs_px, abs_py, abs_pz, px_intermed, py_intermed, pz_intermed, px_intermed2, py_intermed2, pz_intermed2, temp_add_px, temp_add_py, temp_add_pz, qx, qy, qz;
fp_abs inst_abs_px (.in(px), .out(abs_px));
fp_abs inst_abs_py (.in(py), .out(abs_py));
fp_abs inst_abs_pz (.in(pz), .out(abs_pz));

fp_sub sub_px_b (.clk(clk), .a(abs_px), .b(b_fp), .out(px_intermed));
fp_sub sub_py_b(.clk(clk), .a(abs_py),.b(b_fp), .out(py_intermed));
fp_sub sub_pz_b(.clk(clk), .a(abs_pz), .b(b_fp), .out(pz_intermed));
//pi_intermed is new value of p for ith component

//Stage B: first add p+e then abs
fp_add add_px_intermed_e (.clk(clk), .a(px_intermed), .b(e_fp), .out(px_intermed2));
fp_add add_py_intermed_e(.clk(clk), .a(py_intermed),.b(e_fp), .out(py_intermed2));
fp_add add_pz_intermed_e(.clk(clk), .a(pz_intermed), .b(e_fp), .out(pz_intermed2));
//CLK4 latency, need to wait 8 more clk to be syc with qx,qy,qz
wire [26:0] px_intermed_d, py_intermed_d, pz_intermed_d;
state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_pxi(.clk(clk), .in(px_intermed), .out(px_intermed_d));
state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_pyi(.clk(clk), .in(py_intermed), .out(py_intermed_d));
state_pipe #(.WIDTH(27), .DEPTH(8)) pipe_pzi(.clk(clk), .in(pz_intermed), .out(pz_intermed_d));

fp_abs abs_px_intermed2_e (.in(px_intermed2), .out(temp_add_px));
fp_abs abs_py_intermed2_e (.in(py_intermed2), .out(temp_add_py));
fp_abs abs_pz_intermed2_e (.in(pz_intermed2), .out(temp_add_pz));

fp_sub tempx_e (.clk(clk), .a(temp_add_px), .b(e_fp), .out(qx));
fp_sub tempy_e(.clk(clk), .a(temp_add_py),.b(e_fp), .out(qy));
fp_sub tempz_e(.clk(clk), .a(temp_add_pz), .b(e_fp), .out(qz));
//CLK12 latency to get qx,qy,qz

//sdf_term : // length(max((v0,v1,v2),0.))+ min(max(v0,max(v1,v2)),0)
wire [26:0] term1, term2, term3;
sdf_term inst1_term1(.clk(clk), .vx(px_intermed_d), .vy(qy), .vz(qz), .out(term1));
sdf_term inst2_term2(.clk(clk), .vx(qx), .vy(py_intermed_d), .vz(qz), .out(term2));
sdf_term inst3_term3(.clk(clk), .vx(qx), .vy(qy), .vz(pz_intermed_d), .out(term3));

//now have stage A + B, take min of all
wire [26:0] temp_min, sdf_comb;
fp_min inst1_min(.a(term1), .b(term2), .out(temp_min));
fp_min inst2_min(.a(temp_min), .b(term3), .out(sdf_comb));
always @(posedge clk) sdf_out <= sdf_comb;




endmodule


