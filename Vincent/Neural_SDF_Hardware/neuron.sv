//simple neuron, preforms relu(w0*x + w1*y + w2*z + bias)
//only one input per clk, so must add the bias only when the last weight is sent
//neuron must take as parameter the number of connections it has going into it


//note this is very simple neuron, complexify later!!!
module neuron #(
    parameter dataWidth = 16,
    parameter actType = "relu",
    parameter nb_weights = 3,
    parameter weight_length = $clog2(nb_weights) //gives number of bits for addresses for weight memory
    )
    (
    input logic clk,
    input logic rst,
    input logic [dataWidth-1:0] curr_in,
    input logic valid_curr_in,
    output logic [dataWidth-1:0] neuron_out,
    output logic out_valid
);
//assume neuron has weight memory inside
logic [dataWidth-1:0] weights[0:nb_weights-1]; //store all the weights 
initial $readmemh("weights.hex", weights);


logic [weight_length-1:0] curr_weight_address;
logic [dataWidth-1:0] neuron_bias;
logic [dataWidth-1:0] result;
logic [dataWidth-1:0] curr_sum;
wire conn_done;
assign conn_done = (curr_weight_address == nb_weights-1) & valid_curr_in;
initial neuron_bias = 0;

always @ (posedge clk) begin
    if (rst | out_valid) begin
        curr_sum <= 0;
        curr_weight_address <= 0; 
    end
    else if (valid_curr_x) begin

        if (curr_weight_address == nb_weights-1)
            result <= curr_sum + weights[curr_weight_address] * curr_in + neuron_bias; //on last pass add bias
        else begin
            curr_weight_address <= curr_weight_address +1;
            curr_sum <= curr_sum + weights[curr_weight_address] *curr_in; //weight_x tbd
        end
    end

end



always @ (posedge clk) begin
    out_valid <= conn_done; //one clk later
end


neuron_ReLu inst1_ReLu(
    .in(result),
    .out(neuron_out)
);




endmodule