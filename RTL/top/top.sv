/*
The PL design, instantiate everything
*/

module top #(
    parameter int FP_W = 27
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [9*FP_W-1:0] lookat_flat, // AXI regs can only transfer plain flat bit vectors, no unpacked arrays
    //ps writes to AXI regs, which output lookat_flat as single wide buses. AXI reg interface must be flat bus
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
localparam int RG_LAT = 49;          // +1 extra reg in ray_gen s1->s2 path
localparam int REPEAT_LAT = 18;      // fp_mod2 (6 cycles): 4+6+4+4=18
localparam int SCENE_CORE_LAT = 83; // menger_sdf: fp_min split + combine 2-stage
localparam int SDF_LAT = REPEAT_LAT + SCENE_CORE_LAT;
localparam int STEP_LAT = 8;
localparam int MAX_ITER = 128;
localparam [26:0] HIT_THRESH = {1'b0, 8'd117, 18'h01893};
localparam [26:0] HALF_IPD = 27'h1E7AE14;

// lookat[0:2] is the camera right vector; stereo is a parallel sideways offset.
fp_mul inst_eye_offset_x(.clk(sys_clk), .a(lookat_frame[0]), .b(HALF_IPD), .out(eye_offset[0]));
fp_mul inst_eye_offset_y(.clk(sys_clk), .a(lookat_frame[1]), .b(HALF_IPD), .out(eye_offset[1]));
fp_mul inst_eye_offset_z(.clk(sys_clk), .a(lookat_frame[2]), .b(HALF_IPD), .out(eye_offset[2]));

fp_sub inst_left_eye_x(.clk(sys_clk), .a(cam_origin_frame[0]), .b(eye_offset[0]), .out(cam_origin_left[0]));
fp_sub inst_left_eye_y(.clk(sys_clk), .a(cam_origin_frame[1]), .b(eye_offset[1]), .out(cam_origin_left[1]));
fp_sub inst_left_eye_z(.clk(sys_clk), .a(cam_origin_frame[2]), .b(eye_offset[2]), .out(cam_origin_left[2]));

fp_add inst_right_eye_x(.clk(sys_clk), .a(cam_origin_frame[0]), .b(eye_offset[0]), .out(cam_origin_right[0]));
fp_add inst_right_eye_y(.clk(sys_clk), .a(cam_origin_frame[1]), .b(eye_offset[1]), .out(cam_origin_right[1]));
fp_add inst_right_eye_z(.clk(sys_clk), .a(cam_origin_frame[2]), .b(eye_offset[2]), .out(cam_origin_right[2]));


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
logic [26:0] scene_shape_size;
logic [26:0] scene_shape_extra;
logic [23:0] scene_bg_rgb;
logic [23:0] scene_shape_rgb;
logic [26:0] scene_beat_pulse;
logic [26:0] scene_level;
logic [26:0] scene_spectral;
logic [26:0] scene_noise;
logic [26:0] scene_cell_sz_frame;
logic [26:0] scene_half_cell_frame;
logic [26:0] scene_shape_size_frame;
logic [26:0] scene_shape_extra_frame;
logic [23:0] scene_bg_rgb_frame;
logic [23:0] scene_shape_rgb_frame;
logic [26:0] scene_beat_pulse_frame;
logic [26:0] scene_level_frame;
logic [26:0] scene_spectral_frame;
logic [26:0] scene_noise_frame;
genvar g;
generate
    for (g = 0; g < 9; g++) begin : gen_lookat_unpack
        assign lookat[g] = lookat_flat[g*FP_W +: FP_W];
    end
    for (g = 0; g < 3; g++) begin : gen_origin_unpack
        assign cam_origin[g] = cam_origin_flat[g*FP_W +: FP_W];
    end
endgenerate

//for ray gen
logic [26:0] eye_offset[0:2];
logic [26:0] cam_origin_left[0:2];
logic [26:0] cam_origin_right[0:2];
// = 0.032 approx. 
//Half Inter Pupillary Distance, IPD is phys gap btw the two eyes: 63mm, so half is 31.5mm: how far each eye is offset left or right from center of head
//to render stereo, need two diff cam positions, one per eye: shift each one sideways along cam right vector
//stereo separation is purely horizontal; so only offset along right ie x in xyz
//eye_offset = HALF_IPD × (right_x, right_y, right_z)
// lookat[0:2] is the camera right vector; stereo is a parallel sideways offset.
//stage 1: ray gen, rg_lat = 48

//all shared by single ray gen output
logic [26:0] rg_dir [0:2];
logic [26:0] rg_orig [0:2];
logic [19:0] rg_pix_id;
logic rg_valid;

//core arbitrage
logic core_sel, core_sel_d;
logic arb_pix_done;
ray_gen u0_raygen (
    .clk(sys_clk),
    .rst_n(~rst), // was rst_n (port=0 when button unpressed, kept ray_gen valid_out=0 forever)
    .pix_x(pd_x),
    .pix_y(pd_y),
    .pix_id_in(pd_pix_id),
    .valid_in(pd_valid),
    .lookat(lookat_frame),
    .cam_origin_left(cam_origin_left), //problem not latched
    .cam_origin_right(cam_origin_right),
    .ray_orig(rg_orig),
    .ray_dir(rg_dir),
    .pix_id_out(rg_pix_id),
    .valid_out(rg_valid),
    .pipeline_ready()
);


// top_ps.sv hardwires scene_ctrl_flat='0, so these would all be 0:
// - half_cell=0 breaks repeat_mod_cell centering (p folds to [0,2) not [-1,1))
// - scene_shape_size=0 makes menger box SDF = |p| (never hits)
// -> hardcode Menger sponge constants until scene_ctrl AXI is wired.
// cell_sz=2.0 matches fp_mod2 which does mod 2.0 exactly.
// Restore original assigns below when scene_ctrl AXI is wired:
// assign scene_cell_sz    = scene_ctrl_flat[26:0];
// assign scene_half_cell  = scene_ctrl_flat[58:32];
// assign scene_shape_size = scene_ctrl_flat[90:64];
// assign scene_shape_extra = scene_ctrl_flat[122:96];
assign scene_cell_sz    = 27'h2000000; // FP27 2.0
assign scene_half_cell  = 27'h1FC0000; // FP27 1.0
assign scene_shape_size = 27'h1FC0000; // FP27 1.0 (Menger box half-extent)
assign scene_shape_extra = 27'h0;      // unused by menger_sdf
assign scene_bg_rgb = scene_ctrl_flat[151:128];
assign scene_shape_rgb = scene_ctrl_flat[183:160];
assign scene_beat_pulse = scene_ctrl_flat[218:192];
assign scene_level = scene_ctrl_flat[250:224];
assign scene_spectral = scene_ctrl_flat[282:256];
assign scene_noise = scene_ctrl_flat[314:288];

logic [10:0] pd_x;
logic [9:0]  pd_y;
logic [19:0] pd_pix_id, arb_out_pix_id;
logic [7:0] arb_out_iter;
logic        pd_valid;
logic        fc_stall_0, fc_stall_1;

//inst 0,1,2
logic [10:0] fc_x_0, fc_x_1;
logic [9:0]  fc_y_0, fc_y_1;
logic [19:0] fc_pix_id_0, fc_pix_id_1;
logic [26:0] fc_pos_x_0, fc_pos_x_1;
logic [26:0] fc_pos_y_0, fc_pos_y_1;
logic [26:0] fc_pos_z_0, fc_pos_z_1;
logic [26:0] fc_dir_x_0, fc_dir_x_1;
logic [26:0] fc_dir_y_0, fc_dir_y_1;
logic [26:0] fc_dir_z_0, fc_dir_z_1;
logic [7:0]  fc_iter_0, fc_iter_1;
logic        fc_valid_0, fc_valid_1;

logic [19:0] mc_fb_pix_id_0, mc_fb_pix_id_1;
logic [26:0] mc_fb_pos_x_0, mc_fb_pos_x_1;
logic [26:0] mc_fb_pos_y_0, mc_fb_pos_y_1;
logic [26:0] mc_fb_pos_z_0, mc_fb_pos_z_1;
logic [26:0] mc_fb_dir_x_0, mc_fb_dir_x_1;
logic [26:0] mc_fb_dir_y_0, mc_fb_dir_y_1;
logic [26:0] mc_fb_dir_z_0, mc_fb_dir_z_1;
logic [7:0]  mc_fb_iter_0, mc_fb_iter_1;
logic        mc_fb_valid_0, mc_fb_valid_1;

logic        mc_pix_done_0, mc_pix_done_1;
logic [19:0] mc_out_pix_id_0, mc_out_pix_id_1;
logic [7:0]  mc_out_iter_0, mc_out_iter_1;

logic        dispatch_pipeline_ready;
logic        render_bank;
logic        dispatch_enable;
logic        frame_drain_wait;
logic [19:0] dispatch_count; //counts pixels sent from pixel dispatch this frame.
//when hits frameraycount , all px dispatches: disable dispatch
logic [19:0] done_count; //counts pix done signals back from march cores
//when hits frameraycount, all px rendered -> start drain wait
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
assign dispatch_pipeline_ready = ~fc_stall_0 & dispatch_enable & ~writer_fifo_almost_full;
assign frame_base_valid = (frame_base_0 != 32'd0) && (frame_base_1 != 32'd0);
assign frame_status = {frame_ready_valid, frame_ready_bank};
assign hdmi_data = vid_active ? vid_data[23:0] : 24'd0;

always_ff @(posedge sys_clk) begin
    if (rst) begin
        core_sel <= 2'b0;
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
        scene_shape_size_frame <= '0;
        scene_shape_extra_frame <= '0;
        scene_bg_rgb_frame <= '0;
        scene_shape_rgb_frame <= '0;
        scene_beat_pulse_frame <= '0;
        scene_level_frame <= '0;
        scene_spectral_frame <= '0;
        scene_noise_frame <= '0;
        for (cam_i = 0; cam_i < 9; cam_i = cam_i + 1) begin
            lookat_frame[cam_i] <= '0;
        end
        for (cam_i = 0; cam_i < 3; cam_i = cam_i + 1) begin
            cam_origin_frame[cam_i] <= '0;
        end
    end else if (!frame_base_valid) begin
        core_sel <= 2'b0;
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
        scene_shape_size_frame <= '0;
        scene_shape_extra_frame <= '0;
        scene_bg_rgb_frame <= '0;
        scene_shape_rgb_frame <= '0;
        scene_beat_pulse_frame <= '0;
        scene_level_frame <= '0;
        scene_spectral_frame <= '0;
        scene_noise_frame <= '0;
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
            scene_shape_size_frame <= scene_shape_size;
            scene_shape_extra_frame <= scene_shape_extra;
            scene_bg_rgb_frame <= scene_bg_rgb;
            scene_shape_rgb_frame <= scene_shape_rgb;
            scene_beat_pulse_frame <= scene_beat_pulse;
            scene_level_frame <= scene_level;
            scene_spectral_frame <= scene_spectral;
            scene_noise_frame <= scene_noise;
            dispatch_enable <= 1'b1;
        end

        if (dispatch_enable && pd_valid) begin
            // core_sel <= (core_sel ==2'd1) ? 2'd0 : core_sel + 1'b1; // 2-core alternation
            core_sel <= 2'd0;
            if (dispatch_count == FRAME_RAY_COUNT - 1'b1) begin
                dispatch_count <= 20'd0;
                dispatch_enable <= 1'b0;

            end else begin
                dispatch_count <= dispatch_count + 1'b1;
            end
        end

        if (arb_pix_done) begin
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
            scene_shape_size_frame <= scene_shape_size;
            scene_shape_extra_frame <= scene_shape_extra;
            scene_bg_rgb_frame <= scene_bg_rgb;
            scene_shape_rgb_frame <= scene_shape_rgb;
            scene_beat_pulse_frame <= scene_beat_pulse;
            scene_level_frame <= scene_level;
            scene_spectral_frame <= scene_spectral;
            scene_noise_frame <= scene_noise;

            dispatch_enable <= 1'b1;
        end
    end
end

assign arb_pix_done = mc_pix_done_0 | mc_pix_done_1;

state_pipe #(.WIDTH(1), .DEPTH(RG_LAT)) pipe_core_sel(.clk(sys_clk), .in(core_sel), .out(core_sel_d));

pixel_dispatch inst1_px_disp(
    .clk(sys_clk),
    .rst(rst),
    .pipeline_ready(dispatch_pipeline_ready),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid),
    .pix_id(pd_pix_id)
);
feedback_ctrl inst0_fb_ctrl(
    .clk(sys_clk),
    .rst(rst),
    .x_pixel(pd_x),
    .y_pixel(pd_y),
    .valid(pd_valid), // was: pd_valid & (core_sel == 2'd0)
    .pix_id(pd_pix_id),
    .fb_pix_id(mc_fb_pix_id_0),
    .fb_pos_x({5'b0, mc_fb_pos_x_0}),
    .fb_pos_y({5'b0, mc_fb_pos_y_0}),
    .fb_pos_z({5'b0, mc_fb_pos_z_0}),
    .fb_ray_dir_x({5'b0, mc_fb_dir_x_0}),
    .fb_ray_dir_y({5'b0, mc_fb_dir_y_0}),
    .fb_ray_dir_z({5'b0, mc_fb_dir_z_0}),
    .fb_iteration_count(mc_fb_iter_0),
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
    .out_validity(fc_valid_0),
    .stall(fc_stall_0)
);

// feedback_ctrl inst1_fb_ctrl( // 2-core: commented out for 1-core build
//     .clk(sys_clk),
//     .rst(rst),
//     .x_pixel(pd_x),
//     .y_pixel(pd_y),
//     .valid(pd_valid & (core_sel == 2'd1)),
//     .pix_id(pd_pix_id),
//     .fb_pix_id(mc_fb_pix_id_1),
//     .fb_pos_x({5'b0, mc_fb_pos_x_1}),
//     .fb_pos_y({5'b0, mc_fb_pos_y_1}),
//     .fb_pos_z({5'b0, mc_fb_pos_z_1}),
//     .fb_ray_dir_x({5'b0, mc_fb_dir_x_1}),
//     .fb_ray_dir_y({5'b0, mc_fb_dir_y_1}),
//     .fb_ray_dir_z({5'b0, mc_fb_dir_z_1}),
//     .fb_iteration_count(mc_fb_iter_1),
//     .fb_validity(mc_fb_valid_1),
//     .pipeline_ready(1'b1),
//     .out_x(fc_x_1),
//     .out_y(fc_y_1),
//     .out_pix_id(fc_pix_id_1),
//     .out_pos_x(fc_pos_x_1),
//     .out_pos_y(fc_pos_y_1),
//     .out_pos_z(fc_pos_z_1),
//     .out_ray_dir_x(fc_dir_x_1),
//     .out_ray_dir_y(fc_dir_y_1),
//     .out_ray_dir_z(fc_dir_z_1),
//     .out_iteration_count(fc_iter_1),
//     .out_validity(fc_valid_1),
//     .stall(fc_stall_1)
// );
assign fc_stall_1 = 1'b0;

march_core inst0_mc(
    .clk(sys_clk),
    .rst_n(~rst),
    .in_pix_id(fc_pix_id_0),
    .in_pos_x(fc_pos_x_0),
    .in_pos_y(fc_pos_y_0),
    .in_pos_z(fc_pos_z_0),
    .in_ray_dir_x(fc_dir_x_0),
    .in_ray_dir_y(fc_dir_y_0),
    .in_ray_dir_z(fc_dir_z_0),
    .in_iter(fc_iter_0),
    .in_valid(fc_valid_0),
    .rg_dir(rg_dir),
    .rg_orig(rg_orig),
    .rg_pix_id(rg_pix_id),
    .rg_valid(rg_valid), // was: rg_valid & (core_sel_d == 2'd0)
    .scene_cell_sz(scene_cell_sz_frame),
    .scene_half_cell(scene_half_cell_frame),
    .scene_shape_size(scene_shape_size_frame),
    .scene_shape_extra(scene_shape_extra_frame),
    .pix_done(mc_pix_done_0),
    .out_pix_id(mc_out_pix_id_0),
    .out_iter(mc_out_iter_0),
    .fb_iter(mc_fb_iter_0),
    .fb_ray_dir_x(mc_fb_dir_x_0),
    .fb_ray_dir_y(mc_fb_dir_y_0),
    .fb_ray_dir_z(mc_fb_dir_z_0),
    .fb_pos_x(mc_fb_pos_x_0),
    .fb_pos_y(mc_fb_pos_y_0),
    .fb_pos_z(mc_fb_pos_z_0),
    .fb_pix_id(mc_fb_pix_id_0),
    .fb_valid(mc_fb_valid_0),
    .in_dist(27'h0)
);

// march_core inst1_mc( // 2-core: commented out for 1-core build
//     .clk(sys_clk),
//     .rst_n(~rst),
//     .in_pix_id(fc_pix_id_1),
//     .in_pos_x(fc_pos_x_1),
//     .in_pos_y(fc_pos_y_1),
//     .in_pos_z(fc_pos_z_1),
//     .in_ray_dir_x(fc_dir_x_1),
//     .in_ray_dir_y(fc_dir_y_1),
//     .in_ray_dir_z(fc_dir_z_1),
//     .in_iter(fc_iter_1),
//     .in_valid(fc_valid_1),
//     .rg_dir(rg_dir),
//     .rg_orig(rg_orig),
//     .rg_pix_id(rg_pix_id),
//     .rg_valid(rg_valid & (core_sel_d == 2'd1)),
//     .scene_cell_sz(scene_cell_sz_frame),
//     .scene_half_cell(scene_half_cell_frame),
//     .scene_shape_size(scene_shape_size_frame),
//     .scene_shape_extra(scene_shape_extra_frame),
//     .pix_done(mc_pix_done_1),
//     .out_pix_id(mc_out_pix_id_1),
//     .out_iter(mc_out_iter_1),
//     .fb_iter(mc_fb_iter_1),
//     .fb_ray_dir_x(mc_fb_dir_x_1),
//     .fb_ray_dir_y(mc_fb_dir_y_1),
//     .fb_ray_dir_z(mc_fb_dir_z_1),
//     .fb_pos_x(mc_fb_pos_x_1),
//     .fb_pos_y(mc_fb_pos_y_1),
//     .fb_pos_z(mc_fb_pos_z_1),
//     .fb_pix_id(mc_fb_pix_id_1),
//     .fb_valid(mc_fb_valid_1),
//     .in_dist(27'h0)
// );
assign mc_pix_done_1   = 1'b0;
assign mc_out_pix_id_1 = 20'h0;
assign mc_out_iter_1   = 8'h0;

assign arb_out_pix_id = mc_pix_done_0 ? mc_out_pix_id_0 : mc_out_pix_id_1;
assign arb_out_iter   = mc_pix_done_0 ? mc_out_iter_0   : mc_out_iter_1;



ddr_rgb_writer #(
    .MAX_OUTSTANDING(8)
) inst1_ddr_writer (
    .clk(sys_clk),
    .rst(rst),
    .frame_base_0(frame_base_0),
    .frame_base_1(frame_base_1),
    .bg_rgb(scene_bg_rgb_frame),
    .shape_rgb(scene_shape_rgb_frame),
    .pix_done(arb_pix_done),
    .out_pix_id(arb_out_pix_id),
    .out_iter(arb_out_iter),
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
