//core NN layer
module layer #(
    parameter NN = 32,
    parameter numWeight = 3,
    parameter dataWidth = 16,
    parameter layerNum = 1,
    parameter actType = "relu",
    parameter addressWidth = $clog2(numWeight)
) 
(
    input logic clk,
    input logic rst,
    input logic [dataWidth-1:0] x_in,
    input logic x_valid,
    input logic weightValid,
    input logic biasValid,
    input logic [31:0] weightValue,
    input logic [31:0] biasValue,
    input logic [31:0] config_layer_num,
    input logic [31:0] config_neuron_num,
    input logic [addressWidth-1:0] waddr,

    output logic [NN-1:0] o_valid , //one bit per neuron, goes high when that neuron is done w compute
    output logic [dataWidth-1:0] x_out[0:NN-1]  //2d array
);



//generate all the neurons, w genvar statement (we load weights from PS through AXI otherwise file name is a pain)
genvar i; //counter the compiler uses to repeat instantiation
generate 
    for (i = 0; i<NN; i=i+1) begin : neuron_gen
    //one neuron inst
    neuron # (
        .numWeight(numWeight),
        .layerNo(layerNum),
        .neuronNo(i),
        .dataWidth(dataWidth),
        .actType(actType)
    ) neuron_ist (
        .clk(clk),
        .rst(rst),
        .myinput(x_in),
        .myinputvalid(x_valid),
        .weightvalid(weightValid),
        .biasvalid(biasValid),
        .waddr(waddr),
        .weightvalue(weightValue),
        .biasvalue(biasValue),
        .config_lay_num(config_layer_num),
        .config_neuron_num(config_neuron_num),
        .out(x_out[i]),
        .outvalid(o_valid[i])
    );
    end

endgenerate



endmodule