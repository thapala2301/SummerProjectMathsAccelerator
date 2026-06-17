/*
Used throughout design, state pipe delays a signal N cycle, crucial as our design is heavily pipelined,
and sometimes signals must wait for others to arrive through computation: we pipe them through
Unpacked array version
*/
module state_pipe_unpacked_array #(
    parameter WIDTH =32,
    parameter NB_ELEMENTS = 16
    parameter DEPTH = 1 //the latency in clock cycles
)( 
    input wire clk,
    input wire [WIDTH-1:0] in [0:NB_ELEMENTS-1],
    output wire [WIDTH-1:0] out [0:NB_ELEMENTS-1]
);

//this command to make srl pipeline delays become FFs, saving 5465 luts. we have headroom in ff need to reduce lut count
//(* shreg_extract = "no" *) reg [WIDTH-1:0] pipe [0:DEPTH-1];
//but this blows up ff count

reg [WIDTH-1:0] pipe [0:DEPTH-1];
integer i;
always @(posedge clk) begin
    pipe[0] <= in;
    for (i = 1; i< DEPTH; i = i+1)
        pipe[i] <= pipe[i-1];
end

assign out = pipe[DEPTH-1];
endmodule