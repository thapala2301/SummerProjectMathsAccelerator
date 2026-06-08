module state_pipe #(
    parameter WIDTH =32,
    parameter DEPTH = 1 //the latency in clock cycles
)( 
    input wire clk,
    input wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
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