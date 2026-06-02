//most generic neuron, handles weight memory feeding from AXI vs pure rom, handles MAC operation and further activation

#include "include.v"
module neuron #(
    parameter dataWidth = 16,
    parameter layerNo = 0, // which layer of network
    parameter neuronNo = 0, //which neuron in layer
    parameter numWeight = 0,
    parameter actType = "sigmoid",
    parameter weightFile = "",
    parameter weightIntWidth = 4, //.?
    parameter sigmoidSize = 10, //.?
    parameter biasFile = "",
    parameter addressWidth = $clog2(numWeight),
    parameter AXI_dataWidth = 32
)
    (
    input logic clk,
    input logic rst,
    input logic [dataWidth-1:0] myinput,
    input logic myinputvalid,
    input logic weightvalid,
    input logic biasvalid,
    input logic [addressWidth-1:0] waddr,
    input logic [AXI_dataWidth-1:0] weightvalue,
    input logic [AXI_dataWidth-1:0] biasvalue,
    input logic [AXI_dataWidth-1:0] config_lay_num,
    input logic [AXI_dataWidth-1:0] config_neuron_num,
    output logic [dataWidth-1:0] out,
    output logic outvalid 

);


wire [dataWidth-1:0] w_out;
reg [dataWidth-1:0] myinput_d;
reg [2*dataWidth-1:0] mul;
wire muxValid_f;
wire muxValid;

reg [2*dataWidth-1:0] sum, bias; //sum does not have the overflow, only intermediate signals do

reg weight_valid, mult_valid, muxValid_d;
wire [2*dataWidth:0] comboAdd, biasAdd; //need to be able to read overflow on intermediate signals, bit 2*dataWidth; sign bit is bit 2*dataWidth-1

assign comboAdd = mul + sum;
assign biasAdd = bias + sum;

always @ (posedge clk) begin
    myinput_d <= myinput;
end

always @ (posedge clk) begin
    mul <= myinput_d * w_out;
end

always @ (posedge clk) begin
    if (rst | outvalid) begin //outvalid means the neuron outputs its value, reset the sum
        sum<= 0;
    end

    else if (muxValid_f) begin //if we are on last pass, must add weight
        if(!bias[2*dataWidth-1] & !sum[2*dataWidth-1] & biasAdd[2*dataWidth-1]) 
        //positive + positive = negative, overflow happened. 
        //in and, for if to be taken all amount to 1 so the 1st and 2nd term must be 1 so pos initially
            sum <= {1'b0, {(2*dataWidth-1){1'b1}}}; //clamp to maximum representable positive value

        else if (bias[2*dataWidth-1] & sum[2*dataWidth-1] & !biasAdd[2*dataWidth-1])
        //all must be 1 so neg + neg = pos : neg overflow clamp to most neg value
            sum <= {1'b1, {(2*dataWidth-1){1'b0}}}; //clamp to most neg value
        else
            sum <= biasAdd;
    end

    else if (muxValid) begin

        if(!mul[2*dataWidth-1] & !sum[2*dataWidth-1] & comboAdd[2*dataWidth-1]) 
            sum <= {1'b0, {(2*dataWidth-1){1'b1}}}; //same sat logic
        else if (mul[2*dataWidth-1] & sum[2*dataWidth-1] & !comboAdd[2*dataWidth-1])
            sum <= {1'b1, {(2*dataWidth-1){1'b0}}}; //same sat logic
        else
            sum <= comboAdd;
    end
end

reg [31:0] biasReg [0:0]; //array of exactly 1 el. $readmemb needs an array to write into even if it's only one bias value
//bias valid low when PS isn't currently sending a bias value.



`ifdef pretrained
    initial $readmemb(biasFile, biasReg);
    always @ (posedge clk)
        bias <= {biasReg[0][dataWidth-1:0], {dataWidth{1'b0}}};
`else
    always@(posedge clk)
        if (biasvalid & config_lay_num == layerNo & config_neuron_num == neuronNo)
            bias <= {biasvalue[dataWidth-1:0], {dataWidth{1'b0}}};
            //sum: 32 bits wide if dataWidth=16. accumulates prod of 16*16=32 bit nb
            //biasvalue comes as 16 bit nb. must shift to int part, not frac part
`endif

reg [addressWidth-1:0] r_addr ;
//r_addr counter, step through weights at every input
always @ (posedge clk) begin
    if(rst | outvalid)
        r_addr <= 0;
    else if (myinputvalid)
        r_addr <= r_addr +1;
end

Weight_Memory#(
    .numWeight(numWeight),
    .neuronNo(neuronNo),
    .layerNo(layerNo),
    .addressWidth(addressWidth),
    .dataWidth(dataWidth),
    .weightFile(weightFile)
) wm_inst1(
    .clk(clk),
    .ren(myinputvalid),
    .radd(r_addr),
    .wout(w_out),
    .wen(weightvalid & config_lay_num == layerNo & config_neuron_num == neuronNo),
    .wadd(waddr),
    .win(weightvalue[dataWidth-1:0])
);

reg sigValid;
always @ (posedge clk) sigValid <= muxValid_f;
always @ (posedge clk) outvalid <= sigValid;

generate 
    if (actType == "sigmoid")
    begin: siginst
    //inst rom sigmoid
        Sig_ROM #(.inWidth(sigmoidSize), .dataWidth(dataWidth)) s1 (
            .clk(clk),
            .x(sum[2*dataWidth-1-:sigmoidSize]),
            .out(out)
        );
    end
    else
    begin: ReLuinst
        ReLu #(.dataWidth(dataWidth), .weightIntWidth(weightIntWidth)) s1 (
            .clk(clk),
            .x(sum),
            .out(out)
        );
    end
endgenerate


/*
To understand what is ts:
clock:          1  2  3  4  5  6
myinputvalid:   1  1  1  0  0  0   ← 3 inputs arriving
weight_valid:   0  1  1  1  0  0   ← 1 cycle later
mult_valid:     0  0  1  1  1  0   ← 2 cycles later
muxValid_d:     0  0  0  1  1  1   ← 3 cycles later
*/
always @ (posedge clk) begin
    weight_valid <= myinputvalid;
    mult_valid <= weight_valid;
    muxValid_d <= mult_valid;
end
assign muxValid = mult_valid;
assign muxValid_f = !muxValid & muxValid_d;
//w*x

//accumator: sum+= mulse: each neuron has its own sum reg, its the running total of all wx products
//since: a neuron computes: f(w0*x0+w1*x1+w2*x2 ... + bias)
//but in hw, inputs arrive one per clock, so sum builds up: clock N = sum = sum+bias-> feed to ReLu-> output
//bias add
//outvalid pipeline
//weight mem inst
//relu inst

endmodule