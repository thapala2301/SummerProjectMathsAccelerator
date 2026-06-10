//sdBoxFrame sdf, see IniguloQuilez SDF derivation and SW_Raymarching scaffold.frag (this code is Verilog equiv of the GLSL presented in that frag)
/*
GLSL code replicated in the module:
float sdBoxFrame(vec3 p, vec3 b, float e) {
    p = abs(p) - b;
    vec3 q = abs(p + e) - e;
    return min(min(
        length(max(vec3(p.x,q.y,q.z),0.))+min(max(p.x,max(q.y,q.z)),0.),
        length(max(vec3(q.x,p.y,q.z),0.))+min(max(q.x,max(p.y,q.z)),0.)),
        length(max(vec3(q.x,q.y,p.z),0.))+min(max(q.x,max(q.y,p.z)),0.));
}
p.x = x component of p

inputs: real world coordinates px,y,z
output: sdf_out, using space repitition and scene geometry for SDF

Need space repetition:
With modulus, we can apply space repetition, as we have a perfectly periodic scene fitting in a cell
We take the raytip of the world p, fold it to fit in the canonical cell,
evaluate SDF at q (using periodicity) and march ray p.
Folding : mapping p to nearest cell. SDF dist is valid everywhere, as neareast surf in real repeated world
is always same as nearest surface in canonical cell, provided half_ext < cell_sz/2 (for box frame, for other scenes look at most protruding param)
*/

module scene_sdf(
    input clk,
    input [26:0] px, py, pz,
    output reg [26:0] sdf_out
);

wire [26:0] b_fp = {1'b0, 8'd129, 18'h08000}; // 4.5
wire [26:0] e_fp = {1'b0, 8'd124, 18'h0CCCD}; // 0.15

//b : half extent of box, e : edge thickness

//obtain the coordinates in canonical cell for SDF computation- space repetition
localparam cell_sz  = 27'h2090000; //=10 in FP. TEMP. CHANGE TO INPUT FROM AXI WHEN MUSIC REACTIVE
wire [26:0] rep_px, rep_py, rep_pz;
fp_modulus inst_repeat_x(.clk(clk), .a(px), .b(cell_sz), .rem(rep_px));
fp_modulus inst_repeat_y(.clk(clk), .a(py), .b(cell_sz), .rem(rep_py));
fp_modulus inst_repeat_z(.clk(clk), .a(pz), .b(cell_sz), .rem(rep_pz));

//Stage A: p = abs(p) - b;
wire [26:0] abs_px, abs_py, abs_pz, px_intermed, py_intermed, pz_intermed, px_intermed2, py_intermed2, pz_intermed2, temp_add_px, temp_add_py, temp_add_pz, qx, qy, qz;
fp_abs inst_abs_px(.in(rep_px), .out(abs_px));
fp_abs inst_abs_py(.in(rep_py), .out(abs_py));
fp_abs inst_abs_pz(.in(rep_pz), .out(abs_pz));

fp_sub sub_px_b (.clk(clk), .a(abs_px), .b(b_fp), .out(px_intermed));
fp_sub sub_py_b(.clk(clk), .a(abs_py),.b(b_fp), .out(py_intermed));
fp_sub sub_pz_b(.clk(clk), .a(abs_pz), .b(b_fp), .out(pz_intermed));
//pi_intermed is new value of p for ith component

//Stage B: first add p+e then abs:  vec3 q = abs(p + e) - e;
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

reg [26:0] temp_min_reg, term3_reg;
always @ (posedge clk) begin
    temp_min_reg <= temp_min;
    term3_reg <= term3;
end

fp_min inst2_min(.a(temp_min_reg), .b(term3_reg), .out(sdf_comb));
always @(posedge clk) sdf_out <= sdf_comb;




endmodule


