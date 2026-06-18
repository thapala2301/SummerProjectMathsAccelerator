module sim_top(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        axi_awready,
    input  logic        axi_wready,
    input  logic        axi_bvalid,
    output logic        axi_awvalid,
    output logic [31:0] axi_awaddr,
    output logic        axi_wvalid,
    output logic [63:0] axi_wdata,
    output logic        axi_bready,
    output logic        frame_done,
    output logic [19:0] dispatch_count,
    output logic [19:0] done_count
);

wire rst = ~rst_n;
localparam [19:0] FRAME_RAY_COUNT = 20'd153600;

localparam [26:0] FP_ONE      = 27'h1FC0000; // 1.0
localparam [26:0] FP_ZERO     = 27'h0;
localparam [26:0] FP_NEG_ONE  = 27'h5FC0000; // -1.0
localparam [26:0] FP_P015     = 27'h1F0CCCD; // 0.15
localparam [26:0] FP_P45      = 27'h2048000; // 4.5
localparam [26:0] FP_CELL_SZ  = 27'h2000000; // 2.0
localparam [26:0] FP_HALF_CELL= 27'h1FC0000; // 1.0
localparam [26:0] FP_SHAPE_SZ = 27'h1FC0000; // 1.0
localparam [26:0] FP_SHAPE_EX = 27'h0;

// Camera: identity lookat, origin at (0, 0.15, 4.5)
logic [26:0] lookat[0:8];
assign lookat[0] = FP_ONE;  assign lookat[1] = FP_ZERO; assign lookat[2] = FP_ZERO;
assign lookat[3] = FP_ZERO; assign lookat[4] = FP_ONE;  assign lookat[5] = FP_ZERO;
assign lookat[6] = FP_ZERO; assign lookat[7] = FP_ZERO; assign lookat[8] = FP_NEG_ONE;

logic [26:0] cam_origin[0:2];
assign cam_origin[0] = FP_ZERO;
assign cam_origin[1] = FP_P015;
assign cam_origin[2] = FP_P45;

// Ray gen outputs
logic [26:0] rg_dir [0:2];
logic [26:0] rg_orig[0:2];
logic [19:0] rg_pix_id;
logic        rg_valid;

logic [10:0] pd_x;
logic [9:0]  pd_y;
logic [19:0] pd_pix_id;
logic        pd_valid;
logic        fc_stall;

logic [10:0] fc_x;
logic [9:0]  fc_y;
logic [19:0] fc_pix_id;
logic [26:0] fc_pos_x, fc_pos_y, fc_pos_z;
logic [26:0] fc_dir_x, fc_dir_y, fc_dir_z;
logic [7:0]  fc_iter;
logic        fc_valid;

logic [19:0] mc_fb_pix_id;
logic [26:0] mc_fb_pos_x, mc_fb_pos_y, mc_fb_pos_z;
logic [26:0] mc_fb_dir_x, mc_fb_dir_y, mc_fb_dir_z;
logic [7:0]  mc_fb_iter;
logic        mc_fb_valid;

logic        mc_pix_done;
logic [19:0] mc_out_pix_id;
logic [7:0]  mc_out_iter;

logic        dispatch_enable;
logic        frame_drain_wait;
logic        writer_fifo_almost_full;
logic        writer_drained;
logic        dispatch_pipeline_ready;

assign dispatch_pipeline_ready = ~fc_stall & dispatch_enable & ~writer_fifo_almost_full;

always_ff @(posedge clk) begin
    if (rst) begin
        dispatch_enable  <= 1'b1;
        frame_drain_wait <= 1'b0;
        frame_done       <= 1'b0;
        dispatch_count   <= 20'd0;
        done_count       <= 20'd0;
    end else if (!frame_done) begin
        if (dispatch_enable && pd_valid) begin
            if (dispatch_count == FRAME_RAY_COUNT - 1'b1) begin
                dispatch_count  <= 20'd0;
                dispatch_enable <= 1'b0;
            end else begin
                dispatch_count <= dispatch_count + 1'b1;
            end
        end

        if (mc_pix_done) begin
            if (done_count == FRAME_RAY_COUNT - 1'b1) begin
                done_count       <= 20'd0;
                frame_drain_wait <= 1'b1;
            end else begin
                done_count <= done_count + 1'b1;
            end
        end

        if (frame_drain_wait && writer_drained) begin
            frame_drain_wait <= 1'b0;
            frame_done       <= 1'b1;
        end
    end
end

pixel_dispatch inst1_px_disp(
    .clk(clk),
    .rst(rst),
    .pipeline_ready(dispatch_pipeline_ready),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid),
    .pix_id(pd_pix_id)
);

ray_gen #(
    .IMG_W(512),
    .IMG_H(600)
) u0_raygen (
    .clk(clk),
    .rst_n(rst_n),
    .pix_x(pd_x),
    .pix_y(pd_y),
    .pix_id_in(pd_pix_id),
    .valid_in(pd_valid),
    .lookat(lookat),
    .cam_origin_left(cam_origin),
    .cam_origin_right(cam_origin),
    .ray_orig(rg_orig),
    .ray_dir(rg_dir),
    .pix_id_out(rg_pix_id),
    .valid_out(rg_valid),
    .pipeline_ready()
);

feedback_ctrl inst1_fb_ctrl(
    .clk(clk),
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
    .fb_dist(27'h0),
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
    .out_dist(),
    .out_validity(fc_valid),
    .stall(fc_stall)
);

march_core inst1_mc(
    .clk(clk),
    .rst_n(rst_n),
    .in_pix_id(fc_pix_id),
    .in_pos_x(fc_pos_x),
    .in_pos_y(fc_pos_y),
    .in_pos_z(fc_pos_z),
    .in_ray_dir_x(fc_dir_x),
    .in_ray_dir_y(fc_dir_y),
    .in_ray_dir_z(fc_dir_z),
    .in_iter(fc_iter),
    .in_dist(27'h0),
    .in_valid(fc_valid),
    .rg_dir(rg_dir),
    .rg_orig(rg_orig),
    .rg_pix_id(rg_pix_id),
    .rg_valid(rg_valid),
    .scene_cell_sz(FP_CELL_SZ),
    .scene_half_cell(FP_HALF_CELL),
    .scene_shape_size(FP_SHAPE_SZ),
    .scene_shape_extra(FP_SHAPE_EX),
    .pix_done(mc_pix_done),
    .out_pix_id(mc_out_pix_id),
    .out_iter(mc_out_iter),
    .out_dist(),
    .fb_iter(mc_fb_iter),
    .fb_ray_dir_x(mc_fb_dir_x),
    .fb_ray_dir_y(mc_fb_dir_y),
    .fb_ray_dir_z(mc_fb_dir_z),
    .fb_pos_x(mc_fb_pos_x),
    .fb_pos_y(mc_fb_pos_y),
    .fb_pos_z(mc_fb_pos_z),
    .fb_pix_id(mc_fb_pix_id),
    .fb_dist(),
    .fb_valid(mc_fb_valid)
);

ddr_rgb_writer #(
    .FIFO_DEPTH(4096),
    .FIFO_ALMOST_FULL(512),
    .MAX_OUTSTANDING(8)
) inst1_ddr_writer (
    .clk(clk),
    .rst(rst),
    .frame_base_0(32'd0),
    .frame_base_1(32'h00258000),
    .bg_rgb(24'h000810),
    .shape_rgb(24'h00E5CC),
    .pix_done(mc_pix_done),
    .out_pix_id(mc_out_pix_id),
    .out_iter(mc_out_iter),
    .render_bank(1'b0),
    .fifo_almost_full(writer_fifo_almost_full),
    .drained(writer_drained),
    .m_axi_awaddr(axi_awaddr),
    .m_axi_awlen(),
    .m_axi_awsize(),
    .m_axi_awburst(),
    .m_axi_awcache(),
    .m_axi_awprot(),
    .m_axi_awvalid(axi_awvalid),
    .m_axi_awready(axi_awready),
    .m_axi_wdata(axi_wdata),
    .m_axi_wstrb(),
    .m_axi_wlast(),
    .m_axi_wvalid(axi_wvalid),
    .m_axi_wready(axi_wready),
    .m_axi_bresp(2'b00),
    .m_axi_bvalid(axi_bvalid),
    .m_axi_bready(axi_bready)
);

endmodule
