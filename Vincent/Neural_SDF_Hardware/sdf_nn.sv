//top level chaining layers together
/*between layer serializer
layer 1 finishes: all o_valid sigs go high, x_out[0..31] holds all 32 results
but layer 2's neurons take one iput per clock
need FSM: sits idle till o_valid [0] set, captures all 32 outputs in holding red, starts sending them
after send 32 values back to idle
THIS IS SERIALIZER
lives between each pair of layers
*/
module sdf_nn #(
    parameter dataWidth = 16,
    parameter FP_length = 27
)
(
    input logic clk,
    input logic rst,
    input logic [FP_length-1:0] x,
    input logic [FP_length-1:0] y,
    input logic [FP_length-1:0] z,

    input logic xyz_valid,

    output logic [dataWidth-1:0] distance,
    output logic dist_valid,

    //weight loading ports
    input logic weightValid,
    input logic biasValid,
    input logic [31:0] weightValue,
    input logic [31:0] biasValue,
    input logic [31:0] config_layer_num,
    input logic [31:0] config_neuron_num,
    input logic [4:0] waddr //max 32 neurons so clog2(32)=5 bits

);

//convert fp to int
wire [dataWidth-1:0] x_int;
wire [dataWidth-1:0] y_int;
wire [dataWidth-1:0] z_int;
wire [dataWidth-1:0] dist_fp;

enum [1:0] {IDLE, SEND_X, SEND_Y, SEND_Z} state; //enum for state

reg [dataWidth-1:0] l1_in; //connects to layer 1 x_valid port
reg l1_valid;
//input serializer FSM
always @ (posedge clk) begin
    case state
    A : 
    endcase
end


endmodule