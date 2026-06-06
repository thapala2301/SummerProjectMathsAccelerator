//lookat has three axis: right, up, forward. Each is a dir in 3D space, so takes 3 numbers
//hence 9 numbers total


//UGLY RN, NEURAL IS JUST HERE BUT DOESN'T GO THROUGH MARCH CORE
module top(
    input  logic       clk, //PL clk 
    input  logic       rst_n, //don't use this 

    output logic [31:0] M_AXI_AWADDR,
    output logic M_AXI_AWVALID,
    input logic M_AXI_AWREADY,
    output logic [7:0] M_AXI_AWLEN,
    output logic [2:0] M_AXI_AWSIZE,
    output logic [1:0] M_AXI_AWBURST,
    output logic [3:0] M_AXI_AWCACHE,
    output logic [2:0] M_AXI_AWPROT,
    output logic [31:0] M_AXI_WDATA,
    output logic [3:0] M_AXI_WSTRB,
    output logic M_AXI_WVALID,
    input logic M_AXI_WREADY,
    input logic M_AXI_BVALID,
    output logic M_AXI_BREADY,
    input logic [1:0] M_AXI_BRESP
);

logic sys_clk;
logic locked;
logic btn_reset;
logic rst;

//Xilinx clk IP
clk_wiz_0 inst1_clkwiz(
    .clk_in1(clk),
    .reset(btn_reset),
    .clk_out1(sys_clk),
    .locked(locked)
);

assign btn_reset = rst_n;

//use this reset throughout as forces PLL VCO locking
assign rst = btn_reset | ~locked; //reset design till PLL locked phase and clocks are pure


/*
identity lookat: right = (1,0,0), up = (0,1,0) up is y axis, forward = (0,0,1) look along z
45° rotation around Y:
right   = ( 0.707, 0, -0.707)  // right is now front-right diagonal
up      = ( 0,     1,  0    )  // up unchanged
forward = ( 0.707, 0,  0.707)  // cam look toward +x and +z simultaneously
*/
localparam [26:0] FP_ONE     = 27'h1FC0000; //=1.0
localparam [26:0] FP_ZERO    = 27'h0000000;
localparam [26:0] FP_NEG_ONE = 27'h5FC0000; 
localparam [26:0] FP_P015    = 27'h1F0CCCD;
localparam [26:0] FP_P45     = 27'h2048000;

logic [26:0] lookat[0:8];
logic [26:0] cam_origin[0:2];

assign lookat[0] = FP_ONE;
assign lookat[1] = FP_ZERO;
assign lookat[2] = FP_ZERO;
assign lookat[3] = FP_ZERO;
assign lookat[4] = FP_ONE;
assign lookat[5] = FP_ZERO;
assign lookat[6] = FP_ZERO;
assign lookat[7] = FP_ZERO;
assign lookat[8] = FP_NEG_ONE;

assign cam_origin[0] = FP_ZERO;
assign cam_origin[1] = FP_P015;
assign cam_origin[2] = FP_P45;

logic [10:0] pd_x;
logic [9:0]  pd_y;
logic [19:0] pd_pix_id;
logic        pd_valid;
logic        fc_stall;

logic [10:0] fc_x;
logic [9:0]  fc_y;
logic [19:0] fc_pix_id;
logic [26:0] fc_pos_x;
logic [26:0] fc_pos_y;
logic [26:0] fc_pos_z;
logic [26:0] fc_dir_x;
logic [26:0] fc_dir_y;
logic [26:0] fc_dir_z;
logic [7:0]  fc_iter;
logic        fc_valid;

logic [19:0] mc_fb_pix_id;
logic [26:0] mc_fb_pos_x;
logic [26:0] mc_fb_pos_y;
logic [26:0] mc_fb_pos_z;
logic [26:0] mc_fb_dir_x;
logic [26:0] mc_fb_dir_y;
logic [26:0] mc_fb_dir_z;
logic [7:0]  mc_fb_iter;
logic        mc_fb_valid;

logic        mc_pix_done;
logic [19:0] mc_out_pix_id;
logic [7:0]  mc_out_iter;
logic        dispatch_pipeline_ready;
logic        render_bank;
logic        dispatch_enable;
logic [19:0] dispatch_count;
logic [19:0] done_count;
localparam [19:0] FRAME_RAY_COUNT = 20'd921600; //adjust this for diff resolution

assign dispatch_pipeline_ready = ~fc_stall & dispatch_enable;

always_ff @(posedge sys_clk) begin
    if (rst) begin
        render_bank <= 1'b0;
        dispatch_enable <= 1'b1;
        dispatch_count <= 20'd0;
        done_count <= 20'd0;
    end else begin
        if (dispatch_enable && pd_valid) begin
            if (dispatch_count == FRAME_RAY_COUNT - 1'b1) begin
                dispatch_count <= 20'd0;
                dispatch_enable <= 1'b0;
            end else begin
                dispatch_count <= dispatch_count + 1'b1;
            end
        end

        if (mc_pix_done) begin
            if (done_count == FRAME_RAY_COUNT - 1'b1) begin
                done_count <= 20'd0;
                render_bank <= ~render_bank;
                dispatch_enable <= 1'b1;
            end else begin
                done_count <= done_count + 1'b1;
            end
        end
    end
end

//px dispatch out
pixel_dispatch inst1_px_disp(
    .clk(sys_clk),
    .rst(rst),
    .pipeline_ready(dispatch_pipeline_ready),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid),
    .pix_id(pd_pix_id)
);

feedback_ctrl inst1_fb_ctrl(
    .clk(sys_clk),
    .rst(rst),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid),
    .pix_id(pd_pix_id),
    .fb_pix_id(mc_fb_pix_id),
    .fb_pos_x({5'b0, mc_fb_pos_x}),
    .fb_pos_y({5'b0, mc_fb_pos_y}),
    .fb_pos_z({5'b0, mc_fb_pos_z}),
    .fb_ray_dir_x({5'b0, mc_fb_dir_x}),
    .fb_ray_dir_y({5'b0, mc_fb_dir_y}),
    .fb_ray_dir_z({5'b0, mc_fb_dir_z}),
    .fb_iteration_count(mc_fb_iter),
    .fb_validity(mc_fb_valid),
    .pipeline_ready(1'b1),
    .out_x(fc_x),
    .out_y(fc_y),
    .out_pix_id(fc_pix_id),
    .out_pos_x(fc_pos_x),
    .out_pos_y(fc_pos_y),
    .out_pos_z(fc_pos_z),
    .out_ray_dir_x(fc_dir_x),
    .out_ray_dir_y(fc_dir_y),
    .out_ray_dir_z(fc_dir_z),
    .out_iteration_count(fc_iter),
    .out_validity(fc_valid),
    .stall(fc_stall)
);

axi_fb_writer inst_axi_writer(
    .clk(sys_clk),      .rst(rst),
    .pix_done(mc_pix_done),
    .out_pix_id(mc_out_pix_id),
    .out_iter(mc_out_iter),
    .render_bank(render_bank),
    .AWADDR(M_AXI_AWADDR),   .AWVALID(M_AXI_AWVALID), .AWREADY(M_AXI_AWREADY),
    .WDATA(M_AXI_WDATA),     .WSTRB(M_AXI_WSTRB),
    .WVALID(M_AXI_WVALID),   .WREADY(M_AXI_WREADY),
    .BVALID(M_AXI_BVALID),   .BREADY(M_AXI_BREADY),   .BRESP(M_AXI_BRESP),
    .AWLEN_out(M_AXI_AWLEN), .AWSIZE_out(M_AXI_AWSIZE),
    .AWBURST_out(M_AXI_AWBURST), .AWCACHE_out(M_AXI_AWCACHE), .AWPROT_out(M_AXI_AWPROT)
);


march_core inst1_mc(
    .clk(sys_clk),
    .rst_n(~rst),
    .in_x(fc_x),
    .in_y(fc_y),
    .in_pix_id(fc_pix_id),
    .in_pos_x(fc_pos_x),
    .in_pos_y(fc_pos_y),
    .in_pos_z(fc_pos_z),
    .in_ray_dir_x(fc_dir_x),
    .in_ray_dir_y(fc_dir_y),
    .in_ray_dir_z(fc_dir_z),
    .in_iter(fc_iter),
    .in_valid(fc_valid),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .pix_done(mc_pix_done),
    .out_pix_id(mc_out_pix_id),
    .out_iter(mc_out_iter),
    .fb_iter(mc_fb_iter),
    .fb_ray_dir_x(mc_fb_dir_x),
    .fb_ray_dir_y(mc_fb_dir_y),
    .fb_ray_dir_z(mc_fb_dir_z),
    .fb_pos_x(mc_fb_pos_x),
    .fb_pos_y(mc_fb_pos_y),
    .fb_pos_z(mc_fb_pos_z),
    .fb_pix_id(mc_fb_pix_id),
    .fb_valid(mc_fb_valid)
);

endmodule
