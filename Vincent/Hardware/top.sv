//lookat has three axis: right, up, forward. Each is a dir in 3D space, so takes 3 numbers
//hence 9 numbers total
module top(

    input logic clk, //PL clk 
    input logic rst_n, //don't use this 
    output logic hdmi_tx_clk_p, hdmi_tx_clk_n, //diff clock pair
    output logic [2:0] hdmi_tx_data_p, hdmi_tx_data_n //3 diff data channel
    
);

logic sys_clk, clk_pixel, locked;
//Xilinx clk IP
clk_wiz_0 inst1_clkwiz(
    .clk_in1(clk),
    .clk_out1(sys_clk),
    .clk_out2(clk_pixel),
    .locked(locked)
);

//use this reset throughout as forces PLL VCO locking
wire rst = ~rst_n | ~locked; //reset design till PLL locked phase and clocks are pure


/*
identity lookat: right = (1,0,0), up = (0,1,0) up is y axis, forward = (0,0,1) look along z
45° rotation around Y:
right   = ( 0.707, 0, -0.707)  // right is now front-right diagonal
up      = ( 0,     1,  0    )  // up unchanged
forward = ( 0.707, 0,  0.707)  // cam look toward +x and +z simultaneously
*/
// clk_pixel : feeds scan_out, bram port B
localparam [26:0] FP_ONE = 27'h1FC0000; //=1.0
localparam [26:0] FP_ZERO = 27'h0;
localparam[26:0] FP_NEG3 = 27'h6020000; //=-3.0
localparam[26:0] FP_707 = 27'h1F9A800; // =0.707
localparam [26:0] FP_N707 = 27'h5F9A800; //=-0.707

logic [26:0] lookat[0:8];
assign lookat[0] = FP_707; assign lookat[1] =FP_ZERO; assign lookat[2]= FP_N707;
assign lookat[3]=FP_ZERO; assign lookat[4]=FP_ONE; assign lookat[5] = FP_ZERO;
assign lookat[6] =FP_707; assign lookat[7]=FP_ZERO; assign lookat[8] = FP_707;

logic[26:0] cam_origin [0:2];
assign cam_origin[0] = FP_NEG3;
assign cam_origin[1]=FP_ZERO;
assign cam_origin[2] = FP_NEG3;
//cam (-3 0 3) look diagonal

//px dispatch out
logic[10:0] pd_x;
logic[9:0] pd_y;
logic[19:0] pd_pix_id;
logic pd_valid;
logic fc_stall; //from feedback_ctrl???

//feedback ctrl to march core
logic [10:0] fc_x;
logic [9:0] fc_y;
logic [19:0] fc_pix_id;
logic [26:0] fc_pos_x, fc_pos_y, fc_pos_z;
logic[26:0] fc_dir_x, fc_dir_y, fc_dir_z;
logic [7:0] fc_iter;
logic fc_valid;

//from march core to feedback ctrl, feedback path
logic [19:0] mc_fb_pix_id;
logic [26:0] mc_fb_pos_x, mc_fb_pos_y, mc_fb_pos_z;
logic [26:0] mc_fb_dir_x, mc_fb_dir_y, mc_fb_dir_z;
logic [7:0] mc_fb_iter;
logic mc_fb_valid;

//march core to bram
logic mc_pix_done;
logic[19:0] mc_out_pix_id;
logic[7:0] mc_out_iter;

//bram to scanout and back
logic [18:0] bram_addrb;
logic [7:0] bram_doutb;

//scanout to RGB2DVI and back (IP in vivado)
logic hdmi_hsync, hdmi_vsync, hdmi_active;
logic[23:0] hdmi_rgb;

pixel_dispatch inst1_px_disp(
    .clk(sys_clk),
    .rst(rst),
    .pipeline_ready(~fc_stall),
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
    .stall (fc_stall)    
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

scan_out isnt1_scan_out(
    .clk_74_25(clk_pixel),
    .rst_n(~rst),
    .write_bank(1'b0),//single bank??
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

//handle CDC later
framebuffer_bram inst1_bram(
    .clka(sys_clk),
    .wea(mc_pix_done),
    .addra(mc_out_pix_id[18:0]),
    .dina(mc_out_iter),

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
