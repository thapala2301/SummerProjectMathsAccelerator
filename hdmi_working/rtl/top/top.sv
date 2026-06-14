module top #(
    parameter int FP_W = 27
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [9*FP_W-1:0] lookat_flat,
    input  logic [3*FP_W-1:0] cam_origin_flat,
    input  logic [31:0] frame_base_0,
    input  logic [31:0] frame_base_1,
    input  logic [319:0] scene_ctrl_flat,
    output logic       ctrl_clk_out,
    output logic       ctrl_aresetn_out,
    output logic       pixel_clk_out,
    output logic       pixel_aresetn_out,
    input  logic [31:0] vid_data,
    input  logic       vid_hsync,
    input  logic       vid_vsync,
    input  logic       vid_active,
    output logic [31:0] m_axi_fb_awaddr,
    output logic [3:0] m_axi_fb_awlen,
    output logic [2:0] m_axi_fb_awsize,
    output logic [1:0] m_axi_fb_awburst,
    output logic [3:0] m_axi_fb_awcache,
    output logic [2:0] m_axi_fb_awprot,
    output logic       m_axi_fb_awvalid,
    input  logic       m_axi_fb_awready,
    output logic [63:0] m_axi_fb_wdata,
    output logic [7:0] m_axi_fb_wstrb,
    output logic       m_axi_fb_wlast,
    output logic       m_axi_fb_wvalid,
    input  logic       m_axi_fb_wready,
    input  logic [1:0] m_axi_fb_bresp,
    input  logic       m_axi_fb_bvalid,
    output logic       m_axi_fb_bready,
    input  logic       frame_ack,
    output logic [1:0] frame_status,
    output logic       hdmi_tx_clk_p,
    output logic       hdmi_tx_clk_n,
    output logic [2:0] hdmi_tx_data_p,
    output logic [2:0] hdmi_tx_data_n
);

logic sys_clk;
logic clk_pixel;
logic clk_tmds_5x;
logic locked;
logic btn_reset;
logic rst;
logic [23:0] hdmi_data;

logic [26:0] lookat[0:8];
logic [26:0] cam_origin[0:2];
logic [26:0] lookat_frame[0:8];
logic [26:0] cam_origin_frame[0:2];
logic [26:0] scene_cell_sz;
logic [26:0] scene_half_cell;
logic [26:0] scene_frame_extent;
logic [26:0] scene_frame_thickness;
logic [23:0] scene_bg_rgb;
logic [23:0] scene_bar_rgb;
logic [26:0] scene_beat_pulse;
logic [26:0] scene_loudness;
logic [26:0] scene_brightness;
logic [26:0] scene_roughness;
logic [26:0] scene_cell_sz_frame;
logic [26:0] scene_half_cell_frame;
logic [26:0] scene_frame_extent_frame;
logic [26:0] scene_frame_thickness_frame;
logic [23:0] scene_bg_rgb_frame;
logic [23:0] scene_bar_rgb_frame;
logic [26:0] scene_beat_pulse_frame;
logic [26:0] scene_loudness_frame;
logic [26:0] scene_brightness_frame;
logic [26:0] scene_roughness_frame;
genvar g;
generate
    for (g = 0; g < 9; g++) begin : gen_lookat_unpack
        assign lookat[g] = lookat_flat[g*FP_W +: FP_W];
    end
    for (g = 0; g < 3; g++) begin : gen_origin_unpack
        assign cam_origin[g] = cam_origin_flat[g*FP_W +: FP_W];
    end
endgenerate

assign scene_cell_sz = scene_ctrl_flat[26:0];
assign scene_half_cell = scene_ctrl_flat[58:32];
assign scene_frame_extent = scene_ctrl_flat[90:64];
assign scene_frame_thickness = scene_ctrl_flat[122:96];
assign scene_bg_rgb = scene_ctrl_flat[151:128];
assign scene_bar_rgb = scene_ctrl_flat[183:160];
assign scene_beat_pulse = scene_ctrl_flat[218:192];
assign scene_loudness = scene_ctrl_flat[250:224];
assign scene_brightness = scene_ctrl_flat[282:256];
assign scene_roughness = scene_ctrl_flat[314:288];

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
logic        frame_drain_wait;
logic [19:0] dispatch_count;
logic [19:0] done_count;
logic        writer_fifo_almost_full;
logic        writer_drained;
logic        frame_base_valid;
logic        frame_ack_d;
logic        frame_ready_valid;
logic        frame_ready_bank;
integer      cam_i;

localparam [19:0] FRAME_RAY_COUNT = 20'd153600;
clk_wiz_0 inst1_clkwiz(
    .clk_in1(clk),
    .reset(btn_reset),
    .clk_out1(sys_clk),
    .clk_out2(clk_pixel),
    .clk_out3(clk_tmds_5x),
    .locked(locked)
);

assign btn_reset = rst_n;
assign rst = btn_reset | ~locked;
assign ctrl_clk_out = sys_clk;
assign ctrl_aresetn_out = ~rst;
assign pixel_clk_out = clk_pixel;
assign pixel_aresetn_out = ~rst;
assign dispatch_pipeline_ready = ~fc_stall & dispatch_enable & ~writer_fifo_almost_full;
assign frame_base_valid = (frame_base_0 != 32'd0) && (frame_base_1 != 32'd0);
assign frame_status = {frame_ready_valid, frame_ready_bank};
assign hdmi_data = vid_active ? vid_data[23:0] : 24'd0;

always_ff @(posedge sys_clk) begin
    if (rst) begin
        render_bank <= 1'b1;
        dispatch_enable <= 1'b0;
        frame_drain_wait <= 1'b0;
        dispatch_count <= 20'd0;
        done_count <= 20'd0;
        frame_ack_d <= 1'b0;
        frame_ready_valid <= 1'b0;
        frame_ready_bank <= 1'b0;
        scene_cell_sz_frame <= '0;
        scene_half_cell_frame <= '0;
        scene_frame_extent_frame <= '0;
        scene_frame_thickness_frame <= '0;
        scene_bg_rgb_frame <= '0;
        scene_bar_rgb_frame <= '0;
        scene_beat_pulse_frame <= '0;
        scene_loudness_frame <= '0;
        scene_brightness_frame <= '0;
        scene_roughness_frame <= '0;
        for (cam_i = 0; cam_i < 9; cam_i = cam_i + 1) begin
            lookat_frame[cam_i] <= '0;
        end
        for (cam_i = 0; cam_i < 3; cam_i = cam_i + 1) begin
            cam_origin_frame[cam_i] <= '0;
        end
    end else if (!frame_base_valid) begin
        render_bank <= 1'b1;
        dispatch_enable <= 1'b0;
        frame_drain_wait <= 1'b0;
        dispatch_count <= 20'd0;
        done_count <= 20'd0;
        frame_ack_d <= frame_ack;
        frame_ready_valid <= 1'b0;
        frame_ready_bank <= 1'b0;
        scene_cell_sz_frame <= '0;
        scene_half_cell_frame <= '0;
        scene_frame_extent_frame <= '0;
        scene_frame_thickness_frame <= '0;
        scene_bg_rgb_frame <= '0;
        scene_bar_rgb_frame <= '0;
        scene_beat_pulse_frame <= '0;
        scene_loudness_frame <= '0;
        scene_brightness_frame <= '0;
        scene_roughness_frame <= '0;
    end else begin
        frame_ack_d <= frame_ack;

        if (!dispatch_enable && !frame_drain_wait && !frame_ready_valid &&
            (dispatch_count == 20'd0) && (done_count == 20'd0)) begin
            for (cam_i = 0; cam_i < 9; cam_i = cam_i + 1) begin
                lookat_frame[cam_i] <= lookat[cam_i];
            end
            for (cam_i = 0; cam_i < 3; cam_i = cam_i + 1) begin
                cam_origin_frame[cam_i] <= cam_origin[cam_i];
            end
            scene_cell_sz_frame <= scene_cell_sz;
            scene_half_cell_frame <= scene_half_cell;
            scene_frame_extent_frame <= scene_frame_extent;
            scene_frame_thickness_frame <= scene_frame_thickness;
            scene_bg_rgb_frame <= scene_bg_rgb;
            scene_bar_rgb_frame <= scene_bar_rgb;
            scene_beat_pulse_frame <= scene_beat_pulse;
            scene_loudness_frame <= scene_loudness;
            scene_brightness_frame <= scene_brightness;
            scene_roughness_frame <= scene_roughness;
            dispatch_enable <= 1'b1;
        end

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
                frame_drain_wait <= 1'b1;
            end else begin
                done_count <= done_count + 1'b1;
            end
        end

        if (frame_drain_wait && writer_drained) begin
            frame_drain_wait <= 1'b0;
            frame_ready_valid <= 1'b1;
            frame_ready_bank <= render_bank;
        end

        if (frame_ready_valid && frame_ack && !frame_ack_d) begin
            frame_ready_valid <= 1'b0;
            render_bank <= ~render_bank;
            for (cam_i = 0; cam_i < 9; cam_i = cam_i + 1) begin
                lookat_frame[cam_i] <= lookat[cam_i];
            end
            for (cam_i = 0; cam_i < 3; cam_i = cam_i + 1) begin
                cam_origin_frame[cam_i] <= cam_origin[cam_i];
            end
            scene_cell_sz_frame <= scene_cell_sz;
            scene_half_cell_frame <= scene_half_cell;
            scene_frame_extent_frame <= scene_frame_extent;
            scene_frame_thickness_frame <= scene_frame_thickness;
            scene_bg_rgb_frame <= scene_bg_rgb;
            scene_bar_rgb_frame <= scene_bar_rgb;
            scene_beat_pulse_frame <= scene_beat_pulse;
            scene_loudness_frame <= scene_loudness;
            scene_brightness_frame <= scene_brightness;
            scene_roughness_frame <= scene_roughness;
            dispatch_enable <= 1'b1;
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
    .lookat(lookat_frame),
    .cam_origin(cam_origin_frame),
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

ddr_rgb_writer #(
    .MAX_OUTSTANDING(8)
) inst1_ddr_writer (
    .clk(sys_clk),
    .rst(rst),
    .frame_base_0(frame_base_0),
    .frame_base_1(frame_base_1),
    .bg_rgb(scene_bg_rgb_frame),
    .pix_done(mc_pix_done),
    .out_pix_id(mc_out_pix_id),
    .out_iter(mc_out_iter),
    .render_bank(render_bank),
    .fifo_almost_full(writer_fifo_almost_full),
    .drained(writer_drained),
    .m_axi_awaddr(m_axi_fb_awaddr),
    .m_axi_awlen(m_axi_fb_awlen),
    .m_axi_awsize(m_axi_fb_awsize),
    .m_axi_awburst(m_axi_fb_awburst),
    .m_axi_awcache(m_axi_fb_awcache),
    .m_axi_awprot(m_axi_fb_awprot),
    .m_axi_awvalid(m_axi_fb_awvalid),
    .m_axi_awready(m_axi_fb_awready),
    .m_axi_wdata(m_axi_fb_wdata),
    .m_axi_wstrb(m_axi_fb_wstrb),
    .m_axi_wlast(m_axi_fb_wlast),
    .m_axi_wvalid(m_axi_fb_wvalid),
    .m_axi_wready(m_axi_fb_wready),
    .m_axi_bresp(m_axi_fb_bresp),
    .m_axi_bvalid(m_axi_fb_bvalid),
    .m_axi_bready(m_axi_fb_bready)
);

rgb2dvi_0 inst1_rgb2dvi(
    .PixelClk(clk_pixel),
    .SerialClk(clk_tmds_5x),
    .aRst(rst),
    .vid_pData(hdmi_data),
    .vid_pHSync(vid_hsync),
    .vid_pVSync(vid_vsync),
    .vid_pVDE(vid_active),
    .TMDS_Clk_p(hdmi_tx_clk_p),
    .TMDS_Clk_n(hdmi_tx_clk_n),
    .TMDS_Data_p(hdmi_tx_data_p),
    .TMDS_Data_n(hdmi_tx_data_n)
);

endmodule
