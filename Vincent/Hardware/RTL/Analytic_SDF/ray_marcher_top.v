/*
Top module
inputs: clk, rst, M_AXI write ports, ADD AXI-Lite cam reg
M_AXI ports go to PS7 HP port (high bandwidth) via AXI intercoonect, that's how px get written to DDR3.
VDMA seperately reads from DDR3 to drive display. Share DDR3 but talk to it independently through interconnect
AXI interconnect: acts as bridge between multiple AXI masters and slaves. Handles width conversion, CDC
Need AXI interconnect because PS7 HP port is single AXI slave port - has one set of AW W B AR R signals. But have multiple masters:
ray marcher + VDMA both accessing DDR3. Interconnect gives each master own dedicated port. Then internally arbitrates and funnels
AXI interconnect handles address mapping to PS7 HP port space
*/
module ray_marcher_top (
    input  wire       sys_clk, 
    input  wire       rst_n,

    output wire [31:0] M_AXI_AWADDR,
    output wire M_AXI_AWVALID,
    input wire M_AXI_AWREADY,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire [3:0] M_AXI_AWCACHE,
    output wire [2:0] M_AXI_AWPROT,
    output wire [31:0] M_AXI_WDATA,
    output wire [3:0] M_AXI_WSTRB,
    output wire M_AXI_WVALID,
    input wire M_AXI_WREADY,
    input wire M_AXI_BVALID,
    output wire M_AXI_BREADY,
    input wire [1:0] M_AXI_BRESP,

    //AXI LITE SIGNALS FOR interactivity of scene
    input wire [5:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    input wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    input wire s_axi_wready,
    input wire s_axi_bresp, s_axi_bvalid, s_axi_brready
);

wire rst;
assign rst =  ~rst_n;

localparam [26:0] FP_ONE     = 27'h1FC0000; 
localparam [26:0] FP_ZERO    = 27'h0000000;
localparam [26:0] FP_NEG_ONE = 27'h5FC0000; 
localparam [26:0] FP_P015    = 27'h1F0CCCD;
localparam [26:0] FP_P45     = 27'h2048000;

wire [26:0] lookat[0:8];
reg [26:0] cam_origin[0:2];
wire [26:0] cell_sz, f_fp, e_fp;


axi_camera_regs inst_cam_regs (
    .aclk(sys_clk), .aresetn(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), 
    .s_axi_wready(s_axi_wready),
    
);

assign lookat[0] = FP_ONE;
assign lookat[1] = FP_ZERO;
assign lookat[2] = FP_ZERO;
assign lookat[3] = FP_ZERO;
assign lookat[4] = FP_ONE;
assign lookat[5] = FP_ZERO;
assign lookat[6] = FP_ZERO;
assign lookat[7] = FP_ZERO;
assign lookat[8] = FP_NEG_ONE;


//assign cam_origin[2] = FP_P45;

wire [10:0] pd_x;
wire [9:0]  pd_y;
wire [19:0] pd_pix_id;
wire        pd_valid;


//fc: feedback control
//mc_fb: march core feedback , outputs from mc going back to feedback_ctrl
//specific march core signals. _x means xth march core , multicore impl
wire        fc_stall_0, fc_stall_1;
wire [10:0] fc_x_0, fc_x_1;
wire [9:0]  fc_y_0, fc_y_1;
wire [19:0] fc_pix_id_0, fc_pix_id_1;
wire [26:0] fc_pos_x_0, fc_pos_x_1;
wire [26:0] fc_pos_y_0, fc_pos_y_1;
wire [26:0] fc_pos_z_0, fc_pos_z_1;
wire [26:0] fc_dir_x_0, fc_dir_x_1;
wire [26:0] fc_dir_y_0, fc_dir_y_1;
wire [26:0] fc_dir_z_0, fc_dir_z_1;
wire [7:0]  fc_iter_0, fc_iter_1;
wire [26:0] fc_dist_0, fc_dist_1;
wire        fc_valid_0, fc_valid_1;

wire [19:0] mc_fb_pix_id_0, mc_fb_pix_id_1;
wire [26:0] mc_fb_pos_x_0, mc_fb_pos_x_1;
wire [26:0] mc_fb_pos_y_0, mc_fb_pos_y_1;
wire [26:0] mc_fb_pos_z_0, mc_fb_pos_z_1;
wire [26:0] mc_fb_dir_x_0, mc_fb_dir_x_1;
wire [26:0] mc_fb_dir_y_0, mc_fb_dir_y_1;
wire [26:0] mc_fb_dir_z_0, mc_fb_dir_z_1;
wire [7:0]  mc_fb_iter_0, mc_fb_iter_1;
wire [26:0] mc_fb_dist_0, mc_fb_dist_1;
wire        mc_fb_valid_0, mc_fb_valid_1;

wire        mc_pix_done_0, mc_pix_done_1;
wire [19:0] mc_out_pix_id_0, mc_out_pix_id_1;
wire [7:0]  mc_out_iter_0, mc_out_iter_1;
wire [26:0] mc_out_dist_0, mc_out_dist_1;

// --- end of specific march core signals

//in case of concurrent core use, must arbitrate
//march core choice/arbitrage, arb: arbiter, picks winner when concurrent use.
//the arb signals are sigs the priority mux sels from the cores before passing to axifbwriter
reg [1:0] core_sel;
wire fc_stall_cur; //stall if fifo full
wire dispatch_pipeline_ready;
wire arb_pix_done;
wire [19:0] arb_out_pix_id;
wire [7:0] arb_out_iter;
wire [26:0] arb_out_dist;


assign fc_stall_cur = (core_sel == 2'd0) ? fc_stall_0 : fc_stall_1;

reg        render_bank;
reg        dispatch_enable;
reg [19:0] dispatch_count;
reg [19:0] done_count;
assign dispatch_pipeline_ready = ~fc_stall_cur & dispatch_enable;

localparam [19:0] FRAME_RAY_COUNT = 20'd921600; //adjust this for diff resolution

always @(posedge sys_clk) begin
    if (rst) begin
        render_bank <= 1'b0;
        dispatch_enable <= 1'b1;
        dispatch_count <= 20'd0;
        done_count <= 20'd0;
        core_sel <= 2'd0;
    end else begin
        if (dispatch_enable && pd_valid) begin
           core_sel <= (core_sel == 2'd1) ? 2'd0 : core_sel + 1'b1;
            if (dispatch_count == FRAME_RAY_COUNT - 1'b1) begin
                dispatch_count <= 20'd0;
                dispatch_enable <= 1'b0;
            end 
            else begin
                dispatch_count <= dispatch_count + 1'b1;
            end
        end

        if (arb_pix_done) begin
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

assign arb_pix_done   = mc_pix_done_0 | mc_pix_done_1;
assign arb_out_pix_id = mc_pix_done_0 ? mc_out_pix_id_0 : mc_out_pix_id_1;
assign arb_out_iter   = mc_pix_done_0 ? mc_out_iter_0   : mc_out_iter_1;
assign arb_out_dist = mc_pix_done_0 ? mc_out_dist_0 : mc_out_dist_1;
//no possible collision, cores are dispatches 1 clk apart. outputs arrive one clk apart
//or is a safety net sorta
axi_fb_writer inst_axi_writer(
    .clk(sys_clk),      .rst(rst),
    .pix_done(arb_pix_done),
    .out_pix_id(arb_out_pix_id),
    .out_iter(arb_out_iter),
    .out_dist(arb_out_dist),
    .render_bank(render_bank),
    .AWADDR(M_AXI_AWADDR),   .AWVALID(M_AXI_AWVALID), .AWREADY(M_AXI_AWREADY),
    .WDATA(M_AXI_WDATA),     .WSTRB(M_AXI_WSTRB),
    .WVALID(M_AXI_WVALID),   .WREADY(M_AXI_WREADY),
    .BVALID(M_AXI_BVALID),   .BREADY(M_AXI_BREADY),   .BRESP(M_AXI_BRESP),
    .AWLEN_out(M_AXI_AWLEN), .AWSIZE_out(M_AXI_AWSIZE),
    .AWBURST_out(M_AXI_AWBURST), .AWCACHE_out(M_AXI_AWCACHE), .AWPROT_out(M_AXI_AWPROT)
);

//2 march core instances
march_core inst0_mc(
    .clk(sys_clk),
    .rst_n(~rst),
    .in_x(fc_x_0),
    .in_y(fc_y_0),
    .in_pix_id(fc_pix_id_0),
    .in_pos_x(fc_pos_x_0),
    .in_pos_y(fc_pos_y_0),
    .in_pos_z(fc_pos_z_0),
    .in_ray_dir_x(fc_dir_x_0),
    .in_ray_dir_y(fc_dir_y_0),
    .in_ray_dir_z(fc_dir_z_0),
    .in_iter(fc_iter_0),
    .in_dist(fc_dist_0),
    .in_valid(fc_valid_0),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .pix_done(mc_pix_done_0),
    .out_pix_id(mc_out_pix_id_0),
    .out_iter(mc_out_iter_0),
    .out_dist (mc_out_dist_0),
    .fb_iter(mc_fb_iter_0),
    .fb_dist(mc_fb_dist_0),
    .fb_ray_dir_x(mc_fb_dir_x_0),
    .fb_ray_dir_y(mc_fb_dir_y_0),
    .fb_ray_dir_z(mc_fb_dir_z_0),
    .fb_pos_x(mc_fb_pos_x_0),
    .fb_pos_y(mc_fb_pos_y_0),
    .fb_pos_z(mc_fb_pos_z_0),
    .fb_pix_id(mc_fb_pix_id_0),
    .fb_valid(mc_fb_valid_0)
);

march_core inst1_mc(
    .clk(sys_clk),
    .rst_n(~rst),
    .in_x(fc_x_1),
    .in_y(fc_y_1),
    .in_pix_id(fc_pix_id_1),
    .in_pos_x(fc_pos_x_1),
    .in_pos_y(fc_pos_y_1),
    .in_pos_z(fc_pos_z_1),
    .in_ray_dir_x(fc_dir_x_1),
    .in_ray_dir_y(fc_dir_y_1),
    .in_ray_dir_z(fc_dir_z_1),
    .in_iter(fc_iter_1),
    .in_dist(fc_dist_1),
    .in_valid(fc_valid_1),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .pix_done(mc_pix_done_1),
    .out_pix_id(mc_out_pix_id_1),
    .out_iter(mc_out_iter_1),
    .out_dist(mc_out_dist_1),
    .fb_iter(mc_fb_iter_1),
    .fb_dist(mc_fb_dist_1),
    .fb_ray_dir_x(mc_fb_dir_x_1),
    .fb_ray_dir_y(mc_fb_dir_y_1),
    .fb_ray_dir_z(mc_fb_dir_z_1),
    .fb_pos_x(mc_fb_pos_x_1),
    .fb_pos_y(mc_fb_pos_y_1),
    .fb_pos_z(mc_fb_pos_z_1),
    .fb_pix_id(mc_fb_pix_id_1),
    .fb_valid(mc_fb_valid_1)
);

//2 feedback ctrl instance
feedback_ctrl inst0_fb_ctrl(
    .clk(sys_clk),
    .rst(rst),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid & (core_sel == 2'd0)),
    .pix_id(pd_pix_id),
    .fb_pix_id(mc_fb_pix_id_0),
    .fb_pos_x({5'b0, mc_fb_pos_x_0}),
    .fb_pos_y({5'b0, mc_fb_pos_y_0}),
    .fb_pos_z({5'b0, mc_fb_pos_z_0}),
    .fb_ray_dir_x({5'b0, mc_fb_dir_x_0}),
    .fb_ray_dir_y({5'b0, mc_fb_dir_y_0}),
    .fb_ray_dir_z({5'b0, mc_fb_dir_z_0}),
    .fb_iteration_count(mc_fb_iter_0),
    .fb_dist(mc_fb_dist_0),
    .fb_validity(mc_fb_valid_0),
    .pipeline_ready(1'b1),
    .out_x(fc_x_0),
    .out_y(fc_y_0),
    .out_pix_id(fc_pix_id_0),
    .out_pos_x(fc_pos_x_0),
    .out_pos_y(fc_pos_y_0),
    .out_pos_z(fc_pos_z_0),
    .out_ray_dir_x(fc_dir_x_0),
    .out_ray_dir_y(fc_dir_y_0),
    .out_ray_dir_z(fc_dir_z_0),
    .out_iteration_count(fc_iter_0),
    .out_dist(fc_dist_0),
    .out_validity(fc_valid_0),
    .stall(fc_stall_0)
);

feedback_ctrl inst1_fb_ctrl(
    .clk(sys_clk),
    .rst(rst),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid & (core_sel == 2'd1)),
    .pix_id(pd_pix_id),
    .fb_pix_id(mc_fb_pix_id_1),
    .fb_pos_x({5'b0, mc_fb_pos_x_1}),
    .fb_pos_y({5'b0, mc_fb_pos_y_1}),
    .fb_pos_z({5'b0, mc_fb_pos_z_1}),
    .fb_ray_dir_x({5'b0, mc_fb_dir_x_1}),
    .fb_ray_dir_y({5'b0, mc_fb_dir_y_1}),
    .fb_ray_dir_z({5'b0, mc_fb_dir_z_1}),
    .fb_iteration_count(mc_fb_iter_1),
    .fb_dist(mc_fb_dist_1),
    .fb_validity(mc_fb_valid_1),
    .pipeline_ready(1'b1),
    .out_x(fc_x_1),
    .out_y(fc_y_1),
    .out_pix_id(fc_pix_id_1),
    .out_pos_x(fc_pos_x_1),
    .out_pos_y(fc_pos_y_1),
    .out_pos_z(fc_pos_z_1),
    .out_ray_dir_x(fc_dir_x_1),
    .out_ray_dir_y(fc_dir_y_1),
    .out_ray_dir_z(fc_dir_z_1),
    .out_iteration_count(fc_iter_1),
    .out_dist(fc_dist_1),
    .out_validity(fc_valid_1),
    .stall(fc_stall_1)
);


endmodule
