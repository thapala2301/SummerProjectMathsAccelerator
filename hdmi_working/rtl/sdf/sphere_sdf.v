// fp_length finds the distance of point from the origin
// fp_sub deducts the radius
// If sdf is negative we are in the sphere, positive means out, zero means on

module sdf_sphere(
    input clk,
    input [26:0] px, py, pz,
    output reg [26:0] sdf_out
);

localparam [26:0] radius    = {1'b0, 8'd126, 18'h20000};
localparam [26:0] cell_sz   = {1'b0, 8'd128, 18'h00000};
localparam [26:0] half_cell = {1'b0, 8'd127, 18'h00000};

wire [26:0] rep_px;
wire [26:0] rep_py;
wire [26:0] rep_pz;

repeat_mod_cell inst_repeat_x(.clk(clk), .p(px), .cell_sz(cell_sz), .half_cell(half_cell), .q(rep_px));
repeat_mod_cell inst_repeat_y(.clk(clk), .p(py), .cell_sz(cell_sz), .half_cell(half_cell), .q(rep_py));
repeat_mod_cell inst_repeat_z(.clk(clk), .p(pz), .cell_sz(cell_sz), .half_cell(half_cell), .q(rep_pz));

wire [26:0] len;
fp_length inst_len(.clk(clk), .x(rep_px), .y(rep_py), .z(rep_pz), .out(len));

wire [26:0] sdf_comb;
fp_sub inst_sub(.clk(clk), .a(len), .b(radius), .out(sdf_comb));

always @(posedge clk) sdf_out <= sdf_comb;

endmodule
