module top_ps (
    input  logic        clk,
    input  logic        rst_n,
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
    inout  logic        FIXED_IO_ps_srstb,

    inout  logic        IIC_0_scl_io,
    inout  logic        IIC_0_sda_io
);

logic         pl_axi_aclk;
logic         pl_axi_aresetn;
logic         pixel_clk_out;
logic         pixel_aresetn_out;
logic [242:0] lookat_flat;
logic [80:0]  cam_origin_flat;
logic [80:0]  cam_origin_right_flat;
logic [31:0]  frame_base_0;
logic [31:0]  frame_base_1;
logic [31:0]  vid_data;
logic [23:0]  bd_vid_data;
logic         vid_hsync;
logic         vid_vsync;
logic         vid_active;
logic [31:0]  m_axi_fb_awaddr;
logic [3:0]   m_axi_fb_awlen;
logic [2:0]   m_axi_fb_awsize;
logic [1:0]   m_axi_fb_awburst;
logic [3:0]   m_axi_fb_awcache;
logic [2:0]   m_axi_fb_awprot;
logic         m_axi_fb_awvalid;
logic         m_axi_fb_awready;
logic [63:0]  m_axi_fb_wdata;
logic [7:0]   m_axi_fb_wstrb;
logic         m_axi_fb_wlast;
logic         m_axi_fb_wvalid;
logic         m_axi_fb_wready;
logic [1:0]   m_axi_fb_bresp;
logic         m_axi_fb_bvalid;
logic         m_axi_fb_bready;
logic         frame_ack;
logic [0:0]   bd_frame_ack;
logic         frame_ready_valid;
logic         frame_ready_bank;

assign vid_data = {8'd0, bd_vid_data};
assign frame_ack = bd_frame_ack[0];

control_bd_wrapper inst1_ps_bd (
    .DDR_addr(DDR_addr),
    .DDR_ba(DDR_ba),
    .DDR_cas_n(DDR_cas_n),
    .DDR_ck_n(DDR_ck_n),
    .DDR_ck_p(DDR_ck_p),
    .DDR_cke(DDR_cke),
    .DDR_cs_n(DDR_cs_n),
    .DDR_dm(DDR_dm),
    .DDR_dq(DDR_dq),
    .DDR_dqs_n(DDR_dqs_n),
    .DDR_dqs_p(DDR_dqs_p),
    .DDR_odt(DDR_odt),
    .DDR_ras_n(DDR_ras_n),
    .DDR_reset_n(DDR_reset_n),
    .DDR_we_n(DDR_we_n),
    .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
    .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
    .FIXED_IO_mio(FIXED_IO_mio),
    .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
    .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
    .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
    .S_AXI_FB_WR_araddr(32'd0),
    .S_AXI_FB_WR_arburst(2'b01),
    .S_AXI_FB_WR_arcache(4'd0),
    .S_AXI_FB_WR_arlen(8'd0),
    .S_AXI_FB_WR_arlock(1'b0),
    .S_AXI_FB_WR_arprot(3'd0),
    .S_AXI_FB_WR_arqos(4'd0),
    .S_AXI_FB_WR_arready(),
    .S_AXI_FB_WR_arsize(3'd3),
    .S_AXI_FB_WR_arvalid(1'b0),
    .S_AXI_FB_WR_awaddr(m_axi_fb_awaddr),
    .S_AXI_FB_WR_awburst(m_axi_fb_awburst),
    .S_AXI_FB_WR_awcache(m_axi_fb_awcache),
    .S_AXI_FB_WR_awlen({4'd0, m_axi_fb_awlen}),
    .S_AXI_FB_WR_awlock(1'b0),
    .S_AXI_FB_WR_awprot(m_axi_fb_awprot),
    .S_AXI_FB_WR_awqos(4'd0),
    .S_AXI_FB_WR_awready(m_axi_fb_awready),
    .S_AXI_FB_WR_awsize(m_axi_fb_awsize),
    .S_AXI_FB_WR_awvalid(m_axi_fb_awvalid),
    .S_AXI_FB_WR_bready(m_axi_fb_bready),
    .S_AXI_FB_WR_bresp(m_axi_fb_bresp),
    .S_AXI_FB_WR_bvalid(m_axi_fb_bvalid),
    .S_AXI_FB_WR_rdata(),
    .S_AXI_FB_WR_rlast(),
    .S_AXI_FB_WR_rready(1'b1),
    .S_AXI_FB_WR_rresp(),
    .S_AXI_FB_WR_rvalid(),
    .S_AXI_FB_WR_wdata(m_axi_fb_wdata),
    .S_AXI_FB_WR_wlast(m_axi_fb_wlast),
    .S_AXI_FB_WR_wready(m_axi_fb_wready),
    .S_AXI_FB_WR_wstrb(m_axi_fb_wstrb),
    .S_AXI_FB_WR_wvalid(m_axi_fb_wvalid),
    .pl_axi_aclk(pl_axi_aclk),
    .pl_axi_aresetn(pl_axi_aresetn),
    .lookat_flat(lookat_flat),
    .cam_origin_flat(cam_origin_flat),
    .cam_origin_right_flat(cam_origin_right_flat),
    .frame_base_0(frame_base_0),
    .frame_base_1(frame_base_1),
    .pixel_clk_in(pixel_clk_out),
    .pixel_aresetn_in(pixel_aresetn_out),
    .vid_data(bd_vid_data),
    .vid_hsync(vid_hsync),
    .vid_vsync(vid_vsync),
    .vid_active(vid_active),
    .frame_ready_valid(frame_ready_valid),
    .frame_ready_bank(frame_ready_bank),
    .frame_ack(bd_frame_ack),
    .IIC_0_scl_io(IIC_0_scl_io),
    .IIC_0_sda_io(IIC_0_sda_io)
);

top inst1_top (
    .clk(clk),
    .rst_n(rst_n),
    .lookat_flat(lookat_flat),
    .cam_origin_flat(cam_origin_flat),
    .cam_origin_right_flat(cam_origin_right_flat),
    .frame_base_0(frame_base_0),
    .frame_base_1(frame_base_1),
    .ctrl_clk_out(pl_axi_aclk),
    .ctrl_aresetn_out(pl_axi_aresetn),
    .pixel_clk_out(pixel_clk_out),
    .pixel_aresetn_out(pixel_aresetn_out),
    .vid_data(vid_data),
    .vid_hsync(vid_hsync),
    .vid_vsync(vid_vsync),
    .vid_active(vid_active),
    .m_axi_fb_awaddr(m_axi_fb_awaddr),
    .m_axi_fb_awlen(m_axi_fb_awlen),
    .m_axi_fb_awsize(m_axi_fb_awsize),
    .m_axi_fb_awburst(m_axi_fb_awburst),
    .m_axi_fb_awcache(m_axi_fb_awcache),
    .m_axi_fb_awprot(m_axi_fb_awprot),
    .m_axi_fb_awvalid(m_axi_fb_awvalid),
    .m_axi_fb_awready(m_axi_fb_awready),
    .m_axi_fb_wdata(m_axi_fb_wdata),
    .m_axi_fb_wstrb(m_axi_fb_wstrb),
    .m_axi_fb_wlast(m_axi_fb_wlast),
    .m_axi_fb_wvalid(m_axi_fb_wvalid),
    .m_axi_fb_wready(m_axi_fb_wready),
    .m_axi_fb_bresp(m_axi_fb_bresp),
    .m_axi_fb_bvalid(m_axi_fb_bvalid),
    .m_axi_fb_bready(m_axi_fb_bready),
    .frame_ack(frame_ack),
    .frame_ready_valid(frame_ready_valid),
    .frame_ready_bank(frame_ready_bank),
    .hdmi_tx_clk_p(hdmi_tx_clk_p),
    .hdmi_tx_clk_n(hdmi_tx_clk_n),
    .hdmi_tx_data_p(hdmi_tx_data_p),
    .hdmi_tx_data_n(hdmi_tx_data_n)
);

endmodule
