module scene_sdf #(
    parameter WIDTH = 32,
    parameter FRAC = 29
) (
    input wire clk,
    input wire signed [WIDTH-1:0] px, py, pz,
    output wire signed [WIDTH-1:0] d 
);
endmodule
