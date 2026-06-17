// march_core.sv: instantiate sdf_sphere and set SCENE_CORE_LAT = 37
// march_core.sv: set SCENE_CELL_SZ = 27'h2090000 and SCENE_HALF_CELL = 27'h2050000
// ctrl.py: set CAMERA_WRAP_CELL_SZ = 10.0 and CAMERA_WRAP_HALF_CELL = 5.0

// fp_length finds the distance of point from the origin.
// fp_sub deducts the radius.
// If sdf is negative we are in the sphere, positive means out, zero means on.

module sdf_sphere(
    input clk,
    input [26:0] px, py, pz,
    output reg [26:0] sdf_out
);

localparam [26:0] radius    = {1'b0, 8'd128, 18'h00000};

wire [26:0] len;
fp_length inst_len(.clk(clk), .x(px), .y(py), .z(pz), .out(len));

wire [26:0] sdf_comb;
fp_sub inst_sub(.clk(clk), .a(len), .b(radius), .out(sdf_comb));

always @(posedge clk) sdf_out <= sdf_comb;

endmodule
