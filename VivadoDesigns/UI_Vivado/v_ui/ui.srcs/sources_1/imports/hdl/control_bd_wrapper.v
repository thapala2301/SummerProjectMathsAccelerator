//Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2020.2 (win64) Build 3064766 Wed Nov 18 09:12:45 MST 2020
//Date        : Fri Jun 12 14:12:16 2026
//Host        : DESKTOP-MTTTRGV running 64-bit major release  (build 9200)
//Command     : generate_target control_bd_wrapper.bd
//Design      : control_bd_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module control_bd_wrapper
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    S_AXI_FB_WR_araddr,
    S_AXI_FB_WR_arburst,
    S_AXI_FB_WR_arcache,
    S_AXI_FB_WR_arlen,
    S_AXI_FB_WR_arlock,
    S_AXI_FB_WR_arprot,
    S_AXI_FB_WR_arqos,
    S_AXI_FB_WR_arready,
    S_AXI_FB_WR_arsize,
    S_AXI_FB_WR_arvalid,
    S_AXI_FB_WR_awaddr,
    S_AXI_FB_WR_awburst,
    S_AXI_FB_WR_awcache,
    S_AXI_FB_WR_awlen,
    S_AXI_FB_WR_awlock,
    S_AXI_FB_WR_awprot,
    S_AXI_FB_WR_awqos,
    S_AXI_FB_WR_awready,
    S_AXI_FB_WR_awsize,
    S_AXI_FB_WR_awvalid,
    S_AXI_FB_WR_bready,
    S_AXI_FB_WR_bresp,
    S_AXI_FB_WR_bvalid,
    S_AXI_FB_WR_rdata,
    S_AXI_FB_WR_rlast,
    S_AXI_FB_WR_rready,
    S_AXI_FB_WR_rresp,
    S_AXI_FB_WR_rvalid,
    S_AXI_FB_WR_wdata,
    S_AXI_FB_WR_wlast,
    S_AXI_FB_WR_wready,
    S_AXI_FB_WR_wstrb,
    S_AXI_FB_WR_wvalid,
    btns,
    cam_origin_flat,
    frame_ack,
    frame_base_0,
    frame_base_1,
    frame_ready_bank,
    frame_ready_valid,
    lookat_flat,
    pixel_aresetn_in,
    pixel_clk_in,
    pl_axi_aclk,
    pl_axi_aresetn,
    vid_active,
    vid_data,
    vid_hsync,
    vid_vsync);
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  input [31:0]S_AXI_FB_WR_araddr;
  input [1:0]S_AXI_FB_WR_arburst;
  input [3:0]S_AXI_FB_WR_arcache;
  input [7:0]S_AXI_FB_WR_arlen;
  input [0:0]S_AXI_FB_WR_arlock;
  input [2:0]S_AXI_FB_WR_arprot;
  input [3:0]S_AXI_FB_WR_arqos;
  output S_AXI_FB_WR_arready;
  input [2:0]S_AXI_FB_WR_arsize;
  input S_AXI_FB_WR_arvalid;
  input [31:0]S_AXI_FB_WR_awaddr;
  input [1:0]S_AXI_FB_WR_awburst;
  input [3:0]S_AXI_FB_WR_awcache;
  input [7:0]S_AXI_FB_WR_awlen;
  input [0:0]S_AXI_FB_WR_awlock;
  input [2:0]S_AXI_FB_WR_awprot;
  input [3:0]S_AXI_FB_WR_awqos;
  output S_AXI_FB_WR_awready;
  input [2:0]S_AXI_FB_WR_awsize;
  input S_AXI_FB_WR_awvalid;
  input S_AXI_FB_WR_bready;
  output [1:0]S_AXI_FB_WR_bresp;
  output S_AXI_FB_WR_bvalid;
  output [63:0]S_AXI_FB_WR_rdata;
  output S_AXI_FB_WR_rlast;
  input S_AXI_FB_WR_rready;
  output [1:0]S_AXI_FB_WR_rresp;
  output S_AXI_FB_WR_rvalid;
  input [63:0]S_AXI_FB_WR_wdata;
  input S_AXI_FB_WR_wlast;
  output S_AXI_FB_WR_wready;
  input [7:0]S_AXI_FB_WR_wstrb;
  input S_AXI_FB_WR_wvalid;
  input [2:0]btns;
  output [80:0]cam_origin_flat;
  output [0:0]frame_ack;
  output [31:0]frame_base_0;
  output [31:0]frame_base_1;
  input frame_ready_bank;
  input frame_ready_valid;
  output [242:0]lookat_flat;
  input pixel_aresetn_in;
  input pixel_clk_in;
  input pl_axi_aclk;
  input pl_axi_aresetn;
  output vid_active;
  output [23:0]vid_data;
  output vid_hsync;
  output vid_vsync;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire [31:0]S_AXI_FB_WR_araddr;
  wire [1:0]S_AXI_FB_WR_arburst;
  wire [3:0]S_AXI_FB_WR_arcache;
  wire [7:0]S_AXI_FB_WR_arlen;
  wire [0:0]S_AXI_FB_WR_arlock;
  wire [2:0]S_AXI_FB_WR_arprot;
  wire [3:0]S_AXI_FB_WR_arqos;
  wire S_AXI_FB_WR_arready;
  wire [2:0]S_AXI_FB_WR_arsize;
  wire S_AXI_FB_WR_arvalid;
  wire [31:0]S_AXI_FB_WR_awaddr;
  wire [1:0]S_AXI_FB_WR_awburst;
  wire [3:0]S_AXI_FB_WR_awcache;
  wire [7:0]S_AXI_FB_WR_awlen;
  wire [0:0]S_AXI_FB_WR_awlock;
  wire [2:0]S_AXI_FB_WR_awprot;
  wire [3:0]S_AXI_FB_WR_awqos;
  wire S_AXI_FB_WR_awready;
  wire [2:0]S_AXI_FB_WR_awsize;
  wire S_AXI_FB_WR_awvalid;
  wire S_AXI_FB_WR_bready;
  wire [1:0]S_AXI_FB_WR_bresp;
  wire S_AXI_FB_WR_bvalid;
  wire [63:0]S_AXI_FB_WR_rdata;
  wire S_AXI_FB_WR_rlast;
  wire S_AXI_FB_WR_rready;
  wire [1:0]S_AXI_FB_WR_rresp;
  wire S_AXI_FB_WR_rvalid;
  wire [63:0]S_AXI_FB_WR_wdata;
  wire S_AXI_FB_WR_wlast;
  wire S_AXI_FB_WR_wready;
  wire [7:0]S_AXI_FB_WR_wstrb;
  wire S_AXI_FB_WR_wvalid;
  wire [2:0]btns;
  wire [80:0]cam_origin_flat;
  wire [0:0]frame_ack;
  wire [31:0]frame_base_0;
  wire [31:0]frame_base_1;
  wire frame_ready_bank;
  wire frame_ready_valid;
  wire [242:0]lookat_flat;
  wire pixel_aresetn_in;
  wire pixel_clk_in;
  wire pl_axi_aclk;
  wire pl_axi_aresetn;
  wire vid_active;
  wire [23:0]vid_data;
  wire vid_hsync;
  wire vid_vsync;

  control_bd control_bd_i
       (.DDR_addr(DDR_addr),
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
        .S_AXI_FB_WR_araddr(S_AXI_FB_WR_araddr),
        .S_AXI_FB_WR_arburst(S_AXI_FB_WR_arburst),
        .S_AXI_FB_WR_arcache(S_AXI_FB_WR_arcache),
        .S_AXI_FB_WR_arlen(S_AXI_FB_WR_arlen),
        .S_AXI_FB_WR_arlock(S_AXI_FB_WR_arlock),
        .S_AXI_FB_WR_arprot(S_AXI_FB_WR_arprot),
        .S_AXI_FB_WR_arqos(S_AXI_FB_WR_arqos),
        .S_AXI_FB_WR_arready(S_AXI_FB_WR_arready),
        .S_AXI_FB_WR_arsize(S_AXI_FB_WR_arsize),
        .S_AXI_FB_WR_arvalid(S_AXI_FB_WR_arvalid),
        .S_AXI_FB_WR_awaddr(S_AXI_FB_WR_awaddr),
        .S_AXI_FB_WR_awburst(S_AXI_FB_WR_awburst),
        .S_AXI_FB_WR_awcache(S_AXI_FB_WR_awcache),
        .S_AXI_FB_WR_awlen(S_AXI_FB_WR_awlen),
        .S_AXI_FB_WR_awlock(S_AXI_FB_WR_awlock),
        .S_AXI_FB_WR_awprot(S_AXI_FB_WR_awprot),
        .S_AXI_FB_WR_awqos(S_AXI_FB_WR_awqos),
        .S_AXI_FB_WR_awready(S_AXI_FB_WR_awready),
        .S_AXI_FB_WR_awsize(S_AXI_FB_WR_awsize),
        .S_AXI_FB_WR_awvalid(S_AXI_FB_WR_awvalid),
        .S_AXI_FB_WR_bready(S_AXI_FB_WR_bready),
        .S_AXI_FB_WR_bresp(S_AXI_FB_WR_bresp),
        .S_AXI_FB_WR_bvalid(S_AXI_FB_WR_bvalid),
        .S_AXI_FB_WR_rdata(S_AXI_FB_WR_rdata),
        .S_AXI_FB_WR_rlast(S_AXI_FB_WR_rlast),
        .S_AXI_FB_WR_rready(S_AXI_FB_WR_rready),
        .S_AXI_FB_WR_rresp(S_AXI_FB_WR_rresp),
        .S_AXI_FB_WR_rvalid(S_AXI_FB_WR_rvalid),
        .S_AXI_FB_WR_wdata(S_AXI_FB_WR_wdata),
        .S_AXI_FB_WR_wlast(S_AXI_FB_WR_wlast),
        .S_AXI_FB_WR_wready(S_AXI_FB_WR_wready),
        .S_AXI_FB_WR_wstrb(S_AXI_FB_WR_wstrb),
        .S_AXI_FB_WR_wvalid(S_AXI_FB_WR_wvalid),
        .btns(btns),
        .cam_origin_flat(cam_origin_flat),
        .frame_ack(frame_ack),
        .frame_base_0(frame_base_0),
        .frame_base_1(frame_base_1),
        .frame_ready_bank(frame_ready_bank),
        .frame_ready_valid(frame_ready_valid),
        .lookat_flat(lookat_flat),
        .pixel_aresetn_in(pixel_aresetn_in),
        .pixel_clk_in(pixel_clk_in),
        .pl_axi_aclk(pl_axi_aclk),
        .pl_axi_aresetn(pl_axi_aresetn),
        .vid_active(vid_active),
        .vid_data(vid_data),
        .vid_hsync(vid_hsync),
        .vid_vsync(vid_vsync));
endmodule
