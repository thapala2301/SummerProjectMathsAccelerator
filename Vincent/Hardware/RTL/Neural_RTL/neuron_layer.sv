

module neuron_layer#(
    parameter layer_No = 0,
    parameter total_neuron_No = 4,
    parameter dataWidth = 16,
    parameter nb_weights = 3,
    parameter weight_length = $clog2(nb_weights)
)
(
    input logic clk,
    input logic rst,
    input logic [dataWidth-1:0] in,
    input logic valid_curr_in,
    output logic out_valid,
    output logic [dataWidth-1:0] out [0:total_neuron_No-1]

);


logic neuron_valids [0:total_neuron_No-1]; //pack as array

genvar i;
generate 
    for (i = 0; i<total_neuron_No; i=i+1) begin: gen_neurons
        //special syntax to custom file name, needed for weight loading, no latency as $ means at runtime
        localparam string wf = $sformatf("weights/w_%0d_%0d.hex", layer_No, i);
        localparam string bf = $sformatf("weights/b_%0d_%0d.hex", layer_No, i);
        neuron #(.dataWidth(dataWidth), .actType("relu"), .nb_weights(nb_weights), .weight_length(weight_length), .weightFile(wf), .biasFile(bf))
        insti_neuron(
            .clk(clk),
            .rst(rst),
            .curr_in(in),
            .valid_curr_in(valid_curr_in),
            .neuron_out(out[i]),
            .out_valid(neuron_valids[i])
        );
    end
endgenerate


assign out_valid = neuron_valids[0];

endmodule