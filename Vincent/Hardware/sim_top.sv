//for sim on screen through pm
module sim_top(
    input logic clk,
    input logic rst_n,
    output logic pix_done,
    output logic [19:0]pix_id,
    output logic [7:0]pix_iter 

);

wire rst = ~rst_n;
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

//pixel scanner, counter
logic [10:0] pd_x;
logic[9:0] pd_y;
logic[19:0] pd_pix_id;
logic pd_valid;
logic fc_stall;

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

assign pd_pix_id = (pd_y>>1) * 10'd640 + (pd_x >> 1);
assign pd_valid = rst_n;

//cntr: step x by 2, y by 2, wrap at 1278/718
always_ff @ (posedge clk) begin
    if(rst) begin
        pd_x <= 0;
        pd_y <= 0;
    end else if (~fc_stall) begin
        if(pd_x >= 11'd1278 && pd_y >= 10'd718) begin
            pd_x <= 0; 
            pd_y<= 0;
        end
        else if (pd_x>=11'd1278) begin
            pd_x<= 0;
            pd_y <= pd_y+10'd2;
        end
        else begin
            pd_x <= pd_x + 11'd2;
        end
    end
    
end


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
    .clk(clk),
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

    .pix_done(pix_done),
    .out_pix_id(pix_id),
    .out_iter(pix_iter),

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

endmodule