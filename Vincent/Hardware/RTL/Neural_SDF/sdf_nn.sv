//takes 27 FP gets 16 INT does NN
//interface full FP, inside is INT conversion
//we use int16 Q4.12 format, enough for normalized scene coordinates


// TODO: scale x,y,z by 1/scene_scale before conversion
module sdf_nn #(
    parameter FP_length = 27,
    parameter dataWidth = 16

)
(
    input logic clk,
    input logic rst,
    input logic [FP_length-1:0] x_coord,
    input logic [FP_length-1:0] y_coord,
    input logic [FP_length-1:0] z_coord,
    input logic xyz_valid,

    output logic sdf_valid,
    output logic [FP_length-1:0] sdf_dist
);

//convert to int16
wire [15:0] x_int, y_int, z_int;
logic [15:0] x_reg, y_reg, z_reg;

fp_to_q4_12 inst1_xqcoord (.in(x_coord), .out(x_int));
fp_to_q4_12 inst1_yqcoord (.in(y_coord), .out(y_int));
fp_to_q4_12 inst1_zqcoord (.in(z_coord), .out(z_int));

wire [15:0] l1_out [0:31];
wire l1_valid;
logic [15:0] in_d;
logic l1_valid_in;

always @ (posedge clk)
    if(xyz_valid) begin x_reg <= x_int; y_reg <= y_int; z_reg<= z_int; end

wire valid_d1, valid_d2;
state_pipe #(.DEPTH(1),.WIDTH(1)) sp1(.clk(clk),.in(xyz_valid),.out(valid_d1));
state_pipe #(.DEPTH(2),.WIDTH(1)) sp2(.clk(clk),.in(xyz_valid),.out(valid_d2));

//mux sel x, then y, then z
assign in_d = xyz_valid ? x_reg : valid_d1 ? y_reg : z_reg;
assign l1_valid_in = xyz_valid | valid_d1 | valid_d2;
neuron_layer #(.layer_No(1), .total_neuron_No(32), .nb_weights(3)) 
inst1_l1 (
    .clk(clk),
    .rst(rst),
    .in(in_d),
    .valid_curr_in(l1_valid_in),
    .out(l1_out),
    .out_valid(l1_valid)
);


//between layer serializer: l1_valid goes high, all 32 values in l1_out[0..31] are ready sim.
//need to send one by one : FSM

logic [15:0] l2_in;
logic l2_valid_in;
logic [4:0] ser_count; //to 32 innit

logic [15:0] l2_out [0: 31];
logic l2_valid_out;
always @ (posedge clk) begin
    if(rst) begin
        ser_count <= 0;
        l2_valid_in <= 0;
    end
    else if (l1_valid) begin
        l2_in <= l1_out[0]; //init conds
        l2_valid_in <= 1;
        ser_count <= 1;
    end

    else if (l2_valid_in) begin //currently serializing
        l2_in <= l1_out [ser_count];
        ser_count <= ser_count +1;
        if (ser_count == 31) l2_valid_in <= 0; 
    end
end

neuron_layer #(.layer_No(2), .total_neuron_No(32), .nb_weights(32)) 
inst1_l2 (
    .clk(clk),
    .rst(rst),
    .in(l2_in),
    .valid_curr_in(l2_valid_in),
    .out(l2_out),
    .out_valid(l2_valid_out)
);

//layer 3: serializer, then instance


logic [15:0] l3_in;
logic l3_valid_in;
logic [4:0] ser3_count; //to 32 innit

logic [15:0] l3_out [0: 31];
logic l3_valid_out;
always @ (posedge clk) begin
    if(rst) begin
        ser3_count <= 0;
        l3_valid_in <= 0;
    end
    else if (l2_valid_out) begin
        l3_in <= l2_out[0]; //init conds
        l3_valid_in <= 1;
        ser3_count <= 1;
    end

    else if (l3_valid_in) begin //currently serializing
        l3_in <= l2_out [ser3_count];
        ser3_count <= ser3_count +1;
        if (ser3_count == 31) l3_valid_in <= 0; 
    end
end

neuron_layer #(.layer_No(3), .total_neuron_No(32), .nb_weights(32)) 
inst1_l3 (
    .clk(clk),
    .rst(rst),
    .in(l3_in),
    .valid_curr_in(l3_valid_in),
    .out(l3_out),
    .out_valid(l3_valid_out)
);

//final layer, back to 1.

logic [15:0] l4_in;
logic l4_valid_in;
logic [4:0] ser4_count; //to 32 innit

logic [15:0] l4_out [0:0]; //has to be an array
logic l4_valid_out;
always @ (posedge clk) begin
    if(rst) begin
        ser4_count <= 0;
        l4_valid_in <= 0;
    end
    else if (l3_valid_out) begin
        l4_in <= l3_out[0]; //init conds
        l4_valid_in <= 1;
        ser4_count <= 1;
    end

    else if (l4_valid_in) begin //currently serializing
        l4_in <= l3_out [ser4_count];
        ser4_count <= ser4_count +1;
        if (ser4_count == 31) l4_valid_in <= 0; 
    end
end

neuron_layer #(.layer_No(4), .total_neuron_No(1), .nb_weights(32)) 
inst1_l4 (
    .clk(clk),
    .rst(rst),
    .in(l4_in),
    .valid_curr_in(l4_valid_in),
    .out(l4_out),
    .out_valid(l4_valid_out)
);

logic [15:0] intermed_sdf_dist;
assign sdf_valid = l4_valid_out;
logic [26:0] intermed_fp_sdf_dist;
assign intermed_sdf_dist = l4_out[0];
q4_12_to_fp conv_dist (
    .in(intermed_sdf_dist),
    .out(intermed_fp_sdf_dist)
);


assign sdf_dist = intermed_fp_sdf_dist;
//need scaling





endmodule