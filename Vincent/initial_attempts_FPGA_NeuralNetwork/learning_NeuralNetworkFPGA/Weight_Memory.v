//dual port BRAM: one port writes weights in, one port reads weights out during inference
module Weight_Memory #(
    parameter numWeight = 3,
    parameter neuronNo = 0,
    parameter layerNo = 0,
    parameter addressWidth = 2,
    parameter dataWidth = 16,
    parameter weightFile = ""
)(
    input clk,
    input wen,
    input ren,
    input [addressWidth-1:0] wadd,
    input [addressWidth:0] radd,
    input [dataWidth-1:0] win,
    output reg [dataWidth-1:0] wout
);

reg [dataWidth-1:0] mem [0:numWeight-1];

//verilog preprocessor directive: when compile: pass flag `define pretrained in CLI or include.v
//if defined, use weights from file at synth
//if not defined, use AXI runtime loading path
`ifdef pretrained
    initial begin
        $readmemb(weightFile, mem);
    end
`else 
    always @ (posedge clk) begin 
        if (wen) 
            mem[waddr] <= win;
    end
`endif

always @ (posedge clk) begin
    if(ren)
        wout <= mem[radd];
end

endmodule