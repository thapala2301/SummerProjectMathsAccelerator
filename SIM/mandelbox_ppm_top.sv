`timescale 1ns/1ps
`default_nettype none

// Thin wrapper: exposes scene_sdf (mandelbox.sv) for Verilator PPM testbench.
// Pipeline latency: SCENE_CORE_LAT = 224 cycles.
module mandelbox_ppm_top (
    input  logic        clk,
    input  logic [26:0] px,
    input  logic [26:0] py,
    input  logic [26:0] pz,
    output logic [26:0] sdf_out
);

scene_sdf inst_sdf (
    .clk(clk),
    .px(px), .py(py), .pz(pz),
    .sdf_out(sdf_out)
);

endmodule

`default_nettype wire
