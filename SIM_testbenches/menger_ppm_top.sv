`timescale 1ns/1ps
`default_nettype none

// Full pipeline: repeat_mod_cell (REPEAT_LAT=18) -> menger_sdf (SCENE_CORE_LAT=83)
// Total latency from px/py/pz to sdf_out: 101 cycles
// Constants match top.sv hardcoded values:
//   cell_sz=2.0, half_cell=1.0, shape_size=1.0 (box b=1.0)
module menger_ppm_top (
    input  logic        clk,
    input  logic [26:0] px,
    input  logic [26:0] py,
    input  logic [26:0] pz,
    output logic [26:0] sdf_out
);

localparam [26:0] CELL_SZ   = 27'h2000000; // FP27 2.0
localparam [26:0] HALF_CELL = 27'h1FC0000; // FP27 1.0
localparam [26:0] SHAPE_SZ  = 27'h1FC0000; // FP27 1.0 — Menger box half-extent

wire [26:0] sx, sy, sz;
repeat_mod_cell inst_rx(.clk(clk), .p(px), .cell_sz(CELL_SZ), .half_cell(HALF_CELL), .q(sx));
repeat_mod_cell inst_ry(.clk(clk), .p(py), .cell_sz(CELL_SZ), .half_cell(HALF_CELL), .q(sy));
repeat_mod_cell inst_rz(.clk(clk), .p(pz), .cell_sz(CELL_SZ), .half_cell(HALF_CELL), .q(sz));

logic [26:0] sdf_params [0:7];
assign sdf_params[0] = CELL_SZ;
assign sdf_params[1] = SHAPE_SZ;
assign sdf_params[2] = 27'h0;
assign sdf_params[3] = 27'h0;
assign sdf_params[4] = 27'h0;
assign sdf_params[5] = 27'h0;
assign sdf_params[6] = 27'h0;
assign sdf_params[7] = 27'h0;

menger_sdf inst_sdf(
    .clk(clk),
    .px(sx), .py(sy), .pz(sz),
    .sdf_params(sdf_params),
    .sdf_out(sdf_out)
);

endmodule

`default_nettype wire
