module neuron_ReLu #(parameter dataWidth = 16)
(
    input logic [dataWidth-1:0] in,
    output logic [dataWidth-1:0] out
);

//linear if output >=0 , 0 if input negative
assign out = in[dataWidth-1] ? 0 :in;

endmodule