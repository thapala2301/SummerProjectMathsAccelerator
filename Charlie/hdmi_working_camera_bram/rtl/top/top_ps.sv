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
    inout  logic        FIXED_IO_ps_srstb
);

logic         pl_axi_aclk;
logic         pl_axi_aresetn;
logic [242:0] lookat_flat;
logic [80:0]  cam_origin_flat;

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
    .pl_axi_aclk(pl_axi_aclk),
    .pl_axi_aresetn(pl_axi_aresetn),
    .lookat_flat(lookat_flat),
    .cam_origin_flat(cam_origin_flat)
);

top inst1_top (
    .clk(clk),
    .rst_n(rst_n),
    .lookat_flat(lookat_flat),
    .cam_origin_flat(cam_origin_flat),
    .ctrl_clk_out(pl_axi_aclk),
    .ctrl_aresetn_out(pl_axi_aresetn),
    .hdmi_tx_clk_p(hdmi_tx_clk_p),
    .hdmi_tx_clk_n(hdmi_tx_clk_n),
    .hdmi_tx_data_p(hdmi_tx_data_p),
    .hdmi_tx_data_n(hdmi_tx_data_n)
);

endmodule
