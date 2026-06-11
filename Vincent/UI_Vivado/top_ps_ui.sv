module top_ps_ui (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [2:0]  btns,          // BTN1=down BTN2=up BTN3=confirm via EMIO
    output logic        hdmi_tx_clk_p,
    output logic        hdmi_tx_clk_n,
    output logic [2:0]  hdmi_tx_data_p,
    output logic [2:0]  hdmi_tx_data_n,

    inout  logic [14:0] DDR_addr,
    inout  logic [2:0]  DDR_ba,
    inout  logic        DDR_cas_n,
    inout  logic        DDR_ck_n,
    inout  logic        DDR_ck_p,
    inout  logic        DDR_cke,
    inout  logic        DDR_cs_n,
    inout  logic [3:0]  DDR_dm,
    inout  logic [31:0] DDR_dq,
    inout  logic [3:0]  DDR_dqs_n,
    inout  logic [3:0]  DDR_dqs_p,
    inout  logic        DDR_odt,
    inout  logic        DDR_ras_n,
    inout  logic        DDR_reset_n,
    inout  logic        DDR_we_n,
    inout  logic        FIXED_IO_ddr_vrn,
    inout  logic        FIXED_IO_ddr_vrp,
    inout  logic [53:0] FIXED_IO_mio,
    inout  logic        FIXED_IO_ps_clk,
    inout  logic        FIXED_IO_ps_porb,
    inout  logic        FIXED_IO_ps_srstb
);

// clocks and resets
logic sys_clk;
logic clk_pixel;
logic clk_tmds_5x;
logic locked;
logic rst;
logic pl_axi_aclk;
logic pl_axi_aresetn;
logic pixel_clk;
logic pixel_aresetn;

// video signals from BD
logic [23:0] bd_vid_data;
logic        vid_hsync;
logic        vid_vsync;
logic        vid_active;
logic [23:0] hdmi_data;

clk_wiz_0 inst_clkwiz (
    .clk_in1   (clk),
    .reset     (rst_n),
    .clk_out1  (sys_clk),
    .clk_out2  (clk_pixel),
    .clk_out3  (clk_tmds_5x),
    .locked    (locked)
);

assign rst            = rst_n | ~locked;
assign pl_axi_aclk    = sys_clk;
assign pl_axi_aresetn = ~rst;
assign pixel_clk      = clk_pixel;
assign pixel_aresetn  = ~rst;

assign hdmi_data = vid_active ? bd_vid_data : 24'd0;

control_bd_wrapper inst_ps_bd (
    .DDR_addr             (DDR_addr),
    .DDR_ba               (DDR_ba),
    .DDR_cas_n            (DDR_cas_n),
    .DDR_ck_n             (DDR_ck_n),
    .DDR_ck_p             (DDR_ck_p),
    .DDR_cke              (DDR_cke),
    .DDR_cs_n             (DDR_cs_n),
    .DDR_dm               (DDR_dm),
    .DDR_dq               (DDR_dq),
    .DDR_dqs_n            (DDR_dqs_n),
    .DDR_dqs_p            (DDR_dqs_p),
    .DDR_odt              (DDR_odt),
    .DDR_ras_n            (DDR_ras_n),
    .DDR_reset_n          (DDR_reset_n),
    .DDR_we_n             (DDR_we_n),
    .FIXED_IO_ddr_vrn     (FIXED_IO_ddr_vrn),
    .FIXED_IO_ddr_vrp     (FIXED_IO_ddr_vrp),
    .FIXED_IO_mio         (FIXED_IO_mio),
    .FIXED_IO_ps_clk      (FIXED_IO_ps_clk),
    .FIXED_IO_ps_porb     (FIXED_IO_ps_porb),
    .FIXED_IO_ps_srstb    (FIXED_IO_ps_srstb),
    // no ray marcher writing frames — tie off FB write port
    .S_AXI_FB_WR_araddr   (32'd0),
    .S_AXI_FB_WR_arburst  (2'b01),
    .S_AXI_FB_WR_arcache  (4'd0),
    .S_AXI_FB_WR_arlen    (8'd0),
    .S_AXI_FB_WR_arlock   (1'b0),
    .S_AXI_FB_WR_arprot   (3'd0),
    .S_AXI_FB_WR_arqos    (4'd0),
    .S_AXI_FB_WR_arready  (),
    .S_AXI_FB_WR_arsize   (3'd3),
    .S_AXI_FB_WR_arvalid  (1'b0),
    .S_AXI_FB_WR_awaddr   (32'd0),
    .S_AXI_FB_WR_awburst  (2'b01),
    .S_AXI_FB_WR_awcache  (4'd0),
    .S_AXI_FB_WR_awlen    (8'd0),
    .S_AXI_FB_WR_awlock   (1'b0),
    .S_AXI_FB_WR_awprot   (3'd0),
    .S_AXI_FB_WR_awqos    (4'd0),
    .S_AXI_FB_WR_awready  (),
    .S_AXI_FB_WR_awsize   (3'd3),
    .S_AXI_FB_WR_awvalid  (1'b0),
    .S_AXI_FB_WR_bready   (1'b1),
    .S_AXI_FB_WR_bresp    (),
    .S_AXI_FB_WR_bvalid   (),
    .S_AXI_FB_WR_rdata    (),
    .S_AXI_FB_WR_rlast    (),
    .S_AXI_FB_WR_rready   (1'b1),
    .S_AXI_FB_WR_rresp    (),
    .S_AXI_FB_WR_rvalid   (),
    .S_AXI_FB_WR_wdata    (64'd0),
    .S_AXI_FB_WR_wlast    (1'b0),
    .S_AXI_FB_WR_wready   (),
    .S_AXI_FB_WR_wstrb    (8'd0),
    .S_AXI_FB_WR_wvalid   (1'b0),
    .pl_axi_aclk          (pl_axi_aclk),
    .pl_axi_aresetn       (pl_axi_aresetn),
    .pixel_clk_in         (pixel_clk),
    .pixel_aresetn_in     (pixel_aresetn),
    .vid_data             (bd_vid_data),
    .vid_hsync            (vid_hsync),
    .vid_vsync            (vid_vsync),
    .vid_active           (vid_active),
    // no ray marcher — tie off frame handshake
    .frame_ready_valid    (1'b0),
    .frame_ready_bank     (1'b0),
    .frame_ack            (),
    // lookat/cam_origin/sdf_params/frame_base unused in UI mode
    .lookat_flat          (),
    .cam_origin_flat      (),
    .frame_base_0         (),
    .frame_base_1         (),
    // EMIO buttons
    .GPIO_0_tri_i         (btns),
    .GPIO_0_tri_o         (),
    .GPIO_0_tri_t         ()
);

rgb2dvi_0 inst_rgb2dvi (
    .PixelClk   (clk_pixel),
    .SerialClk  (clk_tmds_5x),
    .aRst       (rst),
    .vid_pData  (hdmi_data),
    .vid_pHSync (vid_hsync),
    .vid_pVSync (vid_vsync),
    .vid_pVDE   (vid_active),
    .TMDS_Clk_p (hdmi_tx_clk_p),
    .TMDS_Clk_n (hdmi_tx_clk_n),
    .TMDS_Data_p(hdmi_tx_data_p),
    .TMDS_Data_n(hdmi_tx_data_n)
);

endmodule
