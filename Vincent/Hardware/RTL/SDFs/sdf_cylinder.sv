// Capped cylinder along Y axis: radius R, half-height H
// dx = length(px,pz) - R   This is the signed radial distance from tube wall
// dy = |py| - H            This is the signed distance from caps
// SDF = length(max(dx,0), max(dy,0)) + min(max(dx,dy), 0)
// The last term has the job of handling the interior: when both negative it returns max(dx,dy)

module sdf_cylinder(
    input clk,
    input [26:0] px, py, pz,
    output reg [26:0] sdf_out
);

localparam [26:0] FP_ZERO = 27'h0;
localparam [26:0] R       = {1'b0, 8'd127, 18'h00000}; 
localparam [26:0] H       = {1'b0, 8'd126, 18'h00000}; // half-height = 0.5

// Radial signed distance: fp_length(32) + fp_sub(4) 
wire [26:0] len_xz;
fp_length inst_lxz(.clk(clk), .x(px), .y(FP_ZERO), .z(pz), .out(len_xz));
wire [26:0] dx;
fp_sub inst_dx(.clk(clk), .a(len_xz), .b(R), .out(dx));

// Vertical signed distance: fp_abs(0) + fp_sub(4) 
wire [26:0] abs_py;
fp_abs inst_ay(.in(py), .out(abs_py));
wire [26:0] dy_raw;
fp_sub inst_dy(.clk(clk), .a(abs_py), .b(H), .out(dy_raw));

// Delay dy to arrive with dx at 36 cycles 
wire [26:0] dy;
state_pipe #(.WIDTH(27), .DEPTH(32)) pipe_dy(.clk(clk), .in(dy_raw), .out(dy));

// 2D box SDF components 
wire [26:0] mx, my, inner_max, inner;
assign mx        = dx[26] ? FP_ZERO : dx;          // max(dx, 0)
assign my        = dy[26] ? FP_ZERO : dy;           // max(dy, 0)
fp_max inst_imax(.a(dx), .b(dy), .out(inner_max));
assign inner     = inner_max[26] ? inner_max : FP_ZERO; 

// Outer distance: length of the positive components 
wire [26:0] len_outer;
fp_length inst_lout(.clk(clk), .x(mx), .y(my), .z(FP_ZERO), .out(len_outer));

// Delay inner to match len_outer 
wire [26:0] inner_d;
state_pipe #(.WIDTH(27), .DEPTH(32)) pipe_inner(.clk(clk), .in(inner), .out(inner_d));

wire [26:0] sdf_comb;
fp_add inst_add(.clk(clk), .a(len_outer), .b(inner_d), .out(sdf_comb));

always @(posedge clk) sdf_out <= sdf_comb;
endmodule