module top(
    input  logic       clk,
    input  logic       rst_n,
    output logic       hdmi_tx_clk_p,
    output logic       hdmi_tx_clk_n,
    output logic [2:0] hdmi_tx_data_p,
    output logic [2:0] hdmi_tx_data_n,
    
    // AXI4-Lite Slave Interface (connected to Zynq PS)
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [5:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [5:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready
);

// Raw outputs from axi_camera_regs (clocked by s_axi_aclk = 50 MHz)
logic [26:0] lookat[0:8];
logic [26:0] cam_origin[0:2];
logic [26:0] cam_origin_right[0:2];

// 2-FF synchronizers to cross into sys_clk (148.5 MHz).
// Camera params change at ~60 Hz so single-bit metastability per cycle is
// acceptable; any glitch lasts one frame at most.
logic [26:0] lookat_meta[0:8],          lookat_sync[0:8];
logic [26:0] cam_origin_meta[0:2],       cam_origin_sync[0:2];
logic [26:0] cam_origin_right_meta[0:2], cam_origin_right_sync[0:2];

axi_camera_regs axi_regs_inst(
    .aclk(s_axi_aclk),
    .aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr[5:0]),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr[5:0]),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .cam_origin_right(cam_origin_right)
);

logic sys_clk;
logic clk_pixel;
logic locked;
logic btn_reset;
logic rst;

  clk_wiz_0 inst1_clkwiz(
      .clk_in1(clk),
      .reset(btn_reset),
      .clk_out1(sys_clk),
      .clk_out2(clk_pixel),
      .locked(locked)
  );

assign btn_reset = rst_n;
assign rst = btn_reset | ~locked;

// 2-FF CDC synchronizer: s_axi_aclk → sys_clk
always_ff @(posedge sys_clk) begin
    lookat_meta           <= lookat;
    lookat_sync           <= lookat_meta;
    cam_origin_meta       <= cam_origin;
    cam_origin_sync       <= cam_origin_meta;
    cam_origin_right_meta <= cam_origin_right;
    cam_origin_right_sync <= cam_origin_right_meta;
end

localparam [26:0] FP_ONE     = 27'h1FC0000;
localparam [26:0] FP_ZERO    = 27'h0000000;
localparam [26:0] FP_NEG_ONE = 27'h5FC0000;
localparam [26:0] FP_P015    = 27'h1F0CCCD;
localparam [26:0] FP_P45     = 27'h2048000;

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

logic [18:0] bram_addrb;
logic [7:0]  bram_doutb;

logic        hdmi_hsync;
logic        hdmi_vsync;
logic        hdmi_active;
logic [23:0] hdmi_rgb;

logic        bram_wea;
logic [18:0] bram_addra;
logic [7:0]  bram_dina;
logic        dispatch_pipeline_ready;
logic        render_bank;
logic        display_bank;
logic        dispatch_enable;
logic [19:0] dispatch_count;
logic [19:0] done_count;

localparam [19:0] FRAME_RAY_COUNT = 20'd921600;

logic        bram_wea_reg;
logic [18:0] bram_addra_reg;
logic [7:0]  bram_dina_reg;

always_ff @(posedge sys_clk) begin
    bram_wea_reg <= mc_pix_done;
    bram_addra_reg <= render_bank ? (19'd230400 + mc_out_pix_id[18:0]) : mc_out_pix_id[18:0];
    bram_dina_reg <= mc_out_iter;
end

assign bram_wea = bram_wea_reg;
assign bram_addra = bram_addra_reg;
assign bram_dina = bram_dina_reg;
assign dispatch_pipeline_ready = ~fc_stall & dispatch_enable;

always_ff @(posedge sys_clk) begin
    if (rst) begin
        render_bank <= 1'b0;
        display_bank <= 1'b1;
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
                display_bank <= render_bank;
                render_bank <= ~render_bank;
                dispatch_enable <= 1'b1;
            end else begin
                done_count <= done_count + 1'b1;
            end
        end
    end
end

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
    .lookat(lookat_sync),
    .cam_origin(cam_origin_sync),
    .cam_origin_right(cam_origin_right_sync),
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

scan_out isnt1_scan_out(
    .clk_74_25(clk_pixel),
    .rst_n(~rst),
    .write_bank(display_bank),
    .color_thresh_1(8'd20),
    .color_thresh_2(8'd40),
    .color_thresh_3(8'd60),
    .color_shift_1(3'd2),
    .color_shift_2(3'd2),
    .bram_addrb(bram_addrb),
    .bram_doutb(bram_doutb),
    .hdmi_hsync(hdmi_hsync),
    .hdmi_vsync(hdmi_vsync),
    .hdmi_active(hdmi_active),
    .hdmi_rgb(hdmi_rgb)
);

framebuffer_bram inst1_bram(
    .clka(sys_clk),
    .wea(bram_wea),
    .addra(bram_addra),
    .dina(bram_dina),
    .clkb(clk_pixel),
    .addrb(bram_addrb),
    .doutb(bram_doutb)
);

rgb2dvi_0 inst1_rgb2dvi(
    .PixelClk(clk_pixel),
    .aRst(rst),
    .vid_pData(hdmi_rgb),
    .vid_pHSync(hdmi_hsync),
    .vid_pVSync(hdmi_vsync),
    .vid_pVDE(hdmi_active),
    .TMDS_Clk_p(hdmi_tx_clk_p),
    .TMDS_Clk_n(hdmi_tx_clk_n),
    .TMDS_Data_p(hdmi_tx_data_p),
    .TMDS_Data_n(hdmi_tx_data_n)
);

endmodule
