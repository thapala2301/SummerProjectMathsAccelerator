/*
Used throughout design, state pipe delays a signal N cycle, crucial as our design is heavily pipelined,
and sometimes signals must wait for others to arrive through computation: we pipe them through
*/

module state_pipe #(
    parameter WIDTH = 32,
    parameter DEPTH = 1
)(
    input wire clk,
    input wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);

genvar g;
generate
    if (DEPTH > 113) begin : g_deep
        // SRL for very deep pipes only (DEPTH=114+) — saves flip-flops
        reg [WIDTH-1:0] pipe [0:DEPTH-1];
        always @(posedge clk) pipe[0] <= in;
        for (g = 1; g < DEPTH; g = g+1) begin : gen_pipe
            always @(posedge clk) pipe[g] <= pipe[g-1];
        end
        assign out = pipe[DEPTH-1];
    end else begin : g_shallow
    
        // FF mode for pipes up to depth 113 — saves LUTs, plenty of FF headroom
        (* shreg_extract = "no" *) reg [WIDTH-1:0] pipe [0:DEPTH-1];
        always @(posedge clk) pipe[0] <= in;
        for (g = 1; g < DEPTH; g = g+1) begin : gen_pipe
            always @(posedge clk) pipe[g] <= pipe[g-1];
        end
        assign out = pipe[DEPTH-1];
    end
endgenerate

endmodule
