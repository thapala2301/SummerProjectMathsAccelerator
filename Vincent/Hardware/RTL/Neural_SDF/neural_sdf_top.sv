//need axi on PL side for this
module neural_sdf_top(
    input logic clk,
    input logic rst,
    output logic baking_done, //ready to start render

    input logic [26:0] x,y,z,
    input logic query_valid,
    output logic [26:0] distance, //feed to ray marcher
    output logic dist_valid
);

wire [26:0] bake_x, bake_y, bake_z;
wire bake_xyz_valid;
wire sdf_valid;
wire [26:0] sdf_dist;
wire [26:0] bram_wdata;
wire bram_we;


wire [14:0] bram_waddr;  // baking_ctrl → sdf_bram port A
wire [14:0] bram_raddr;  // trilinear → sdf_bram port B
wire [26:0] bram_rdata;  // sdf_bram port B → trilinear


//what is started for??
logic started;
wire start= ~started;
always_ff @ (posedge clk) if (rst) started <= 0; else started <= 1;

baking_ctrl inst1_bakectrl(
    .clk(clk), .rst(rst),
    .start(start),
    .done(baking_done),
    .x(bake_x), .y(bake_y), .z(bake_z),
    .xyz_valid(bake_xyz_valid),
    .sdf_valid(sdf_valid),
    .sdf_dist(sdf_dist),
    .bram_addr(bram_waddr),
    .bram_wdata(bram_wdata),
    .bram_we(bram_we)
);

sdf_nn #(
    .FP_length(27),
    .dataWidth(16)
)
inst1_nn (
    .clk(clk), .rst(rst),
    .x_coord(bake_x), .y_coord(bake_y), .z_coord(bake_z),
    .xyz_valid(bake_xyz_valid),
    .sdf_valid(sdf_valid),
    .sdf_dist(sdf_dist)
);


sdf_bram u_sdfbram
(
    .clka(clk), .wea(bram_we), .addra(bram_waddr), .dina(bram_wdata),
    .clkb(clk), .addrb(bram_raddr), .doutb(bram_rdata)

);

trilinear_interp u_triliniterp(
    .clk(clk), .rst(rst),
    .x(x), .y(y), .z(z),
    .query_valid(query_valid),
    .distance(distance),
    .dist_valid(dist_valid),
    .bram_dout(bram_rdata),
    .bram_addr(bram_raddr)

);



endmodule