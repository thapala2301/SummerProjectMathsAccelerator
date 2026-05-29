module march_core(
    input logic clk,
    input logic rst_n,
    //from feedback_ctrl
    input logic [10:0] in_x,
    input logic [9:0] in_y,
    input logic [19:0] in_pix_id,
    input logic [31:0] in_pos_x, in_pos_y, in_pos_z,
    input logic [31:0] in_ray_dir_x, in_ray_dir_y, in_ray_dir_z,
    input logic [7:0] in_iter,
    input logic in_valid,
    input logic signed [31:0] lookat[0:8], //9 elements: lookat is 3x3 camera rot matrix. 9 values
    /*
    lookat[0,1,2] = right   vector (x,y,z)
    lookat[3,4,5] = up      vector (x,y,z)
    lookat[6,7,8] = forward vector (x,y,z)
    */

    input logic signed [31:0] cam_origin [0:2],
    //feedback to feedback_ctrl
    output logic [19:0] fb_pix_id,
    output logic [31:0] fb_pos_x, fb_pos_y, fb_pos_z,
    output logic [31:0] fb_ray_dir_x, fb_ray_dir_y, fb_ray_dir_z,
    output logic [7:0] fb_iter,
    output logic fb_valid,
    //to fb_write, iter_to_rgb
    output logic [19:0] out_pix_id,
    output logic [7:0] out_iter,
    output logic pix_done
);

//Stage 1
//Ray_gen inst + delay pipes
localparam int RG_LAT = 19;
logic signed [31:0] rg_orig[0:2], rg_dir[0:2];
logic rg_valid;

ray_gen #(.W(32), .FRAC(29), .IMG_W(1280), .IMG_H(720), .ISQRT_ITER(3))
u_ray_gen(
    .clk(clk), .rst_n(rst_n),
    .pix_x(in_x), .pix_y(in_y),
    .pix_id_in(in_pix_id), .valid_in(in_valid),
    .lookat(lookat), .cam_origin(cam_origin),
    .ray_orig(rg_orig), .ray_dir(rg_dir),
    .pix_id_out(), .valid_out(rg_valid),
    .pipeline_ready()
);

//every clk pkt enters march_core with x,y, pos, dir, iter, pix_id
//ray gen takes x,y and spends 19 clk computing actual ray dir for px
//pos: curr pos in world space x,y,z. starts at cam origin, moves at each iter
//pix_id: unique int per pixel, used so fb_write knows which adress in framebuffer BRAM to write final color to

logic [31:0] d_pos_x, d_pos_y, d_pos_z;
logic [31:0] d_dir_x, d_dir_y, d_dir_z;
logic [7:0] d_iter;
logic [19:0] d_pix_id;
state_pipe #(.WIDTH(32), .DEPTH(RG_LAT)) pipe_pos_x(.clk(clk), .in(in_pos_x), .out(d_pos_x));
state_pipe #(.WIDTH(32), .DEPTH(RG_LAT)) pipe_pos_y(.clk(clk), .in(in_pos_y), .out(d_pos_y));
state_pipe #(.WIDTH(32), .DEPTH(RG_LAT)) pipe_pos_z(.clk(clk), .in(in_pos_z), .out(d_pos_z));
state_pipe #(.WIDTH(32), .DEPTH(RG_LAT)) pipe_dir_x(.clk(clk), .in(in_ray_dir_x), .out(d_dir_x));
state_pipe #(.WIDTH(32), .DEPTH(RG_LAT)) pipe_dir_y(.clk(clk), .in(in_ray_dir_y), .out(d_dir_y));
state_pipe #(.WIDTH(32), .DEPTH(RG_LAT)) pipe_dir_z(.clk(clk), .in(in_ray_dir_z), .out(d_dir_z));
state_pipe #(.WIDTH(8),  .DEPTH(RG_LAT)) pipe_iter (.clk(clk), .in(in_iter),      .out(d_iter));
state_pipe #(.WIDTH(20), .DEPTH(RG_LAT)) pipe_pid  (.clk(clk), .in(in_pix_id),    .out(d_pix_id));

// Convert ray_gen Q2.29 outputs to 1.8.18 FP
wire [26:0] rg_pos_x_fp, rg_pos_y_fp, rg_pos_z_fp;
wire [26:0] rg_dir_x_fp, rg_dir_y_fp, rg_dir_z_fp;
int2fp u_i2f_px(.in(rg_orig[0]), .out(rg_pos_x_fp));
int2fp u_i2f_py(.in(rg_orig[1]), .out(rg_pos_y_fp));
int2fp u_i2f_pz(.in(rg_orig[2]), .out(rg_pos_z_fp));
int2fp u_i2f_dx(.in(rg_dir[0]),  .out(rg_dir_x_fp));
int2fp u_i2f_dy(.in(rg_dir[1]),  .out(rg_dir_y_fp));
int2fp u_i2f_dz(.in(rg_dir[2]),  .out(rg_dir_z_fp));

// iter==0: new pixel, use ray_gen. iter>0: feedback, use delayed pos/dir (FP in [26:0])
wire [26:0] s1_pos_x = (d_iter == '0) ? rg_pos_x_fp : d_pos_x[26:0]; //d_pos_x is new_pos in 1.8.18 FP fed to feedback_ctrl, sat in FIFO
wire [26:0] s1_pos_y = (d_iter == '0) ? rg_pos_y_fp : d_pos_y[26:0];
wire [26:0] s1_pos_z = (d_iter == '0) ? rg_pos_z_fp : d_pos_z[26:0];
wire [26:0] s1_dir_x = (d_iter == '0) ? rg_dir_x_fp : d_dir_x[26:0];
wire [26:0] s1_dir_y = (d_iter == '0) ? rg_dir_y_fp : d_dir_y[26:0];
wire [26:0] s1_dir_z = (d_iter == '0) ? rg_dir_z_fp : d_dir_z[26:0];
wire        s1_valid  = rg_valid;
wire [7:0]  s1_iter   = d_iter;
wire [19:0] s1_pix_id = d_pix_id;


// Stage 2: SDF evaluation — 38 cycles
localparam int SDF_LAT = 38;

wire [26:0] sdf_dist;
scene_sdf u_scene_sdf(
    .clk(clk),
    .px(s1_pos_x), .py(s1_pos_y), .pz(s1_pos_z),
    .dist(sdf_dist)
);

// Delay everything to align with sdf_dist output
//new_pos is ready 6 clk afte sdf_dist and d2_* arrive, d2_* being all d2 signals ie d2_dist, d2_iter, d2_pix_id, ..


wire [26:0] d2_pos_x, d2_pos_y, d2_pos_z;
wire [26:0] d2_dir_x, d2_dir_y, d2_dir_z;
wire [7:0]  d2_iter;
wire [19:0] d2_pix_id;
wire        d2_valid;
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) pipe2_pos_x(.clk(clk), .in(s1_pos_x), .out(d2_pos_x));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) pipe2_pos_y(.clk(clk), .in(s1_pos_y), .out(d2_pos_y));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) pipe2_pos_z(.clk(clk), .in(s1_pos_z), .out(d2_pos_z));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) pipe2_dir_x(.clk(clk), .in(s1_dir_x), .out(d2_dir_x));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) pipe2_dir_y(.clk(clk), .in(s1_dir_y), .out(d2_dir_y));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) pipe2_dir_z(.clk(clk), .in(s1_dir_z), .out(d2_dir_z));
state_pipe #(.WIDTH(8),  .DEPTH(SDF_LAT)) pipe2_iter (.clk(clk), .in(s1_iter),  .out(d2_iter));
state_pipe #(.WIDTH(20), .DEPTH(SDF_LAT)) pipe2_pid  (.clk(clk), .in(s1_pix_id),.out(d2_pix_id));
state_pipe #(.WIDTH(1),  .DEPTH(SDF_LAT)) pipe2_valid(.clk(clk), .in(s1_valid), .out(d2_valid));


// Stage 3: step + decide — 6 cycles
localparam int STEP_LAT = 6;

wire [26:0] step_x, step_y, step_z;
fp_mul u_mul_x(.clk(clk), .a(sdf_dist), .b(d2_dir_x), .out(step_x));
fp_mul u_mul_y(.clk(clk), .a(sdf_dist), .b(d2_dir_y), .out(step_y));
fp_mul u_mul_z(.clk(clk), .a(sdf_dist), .b(d2_dir_z), .out(step_z));

wire [26:0] new_pos_x, new_pos_y, new_pos_z;
wire [26:0] d2_pos_x_d, d2_pos_y_d, d2_pos_z_d;
state_pipe #(.WIDTH(27), .DEPTH(2)) pipe_pxd(.clk(clk), .in(d2_pos_x), .out(d2_pos_x_d));
state_pipe #(.WIDTH(27), .DEPTH(2)) pipe_pyd(.clk(clk), .in(d2_pos_y), .out(d2_pos_y_d));
state_pipe #(.WIDTH(27), .DEPTH(2)) pipe_pzd(.clk(clk), .in(d2_pos_z), .out(d2_pos_z_d));

fp_add u_add_x(.clk(clk), .a(d2_pos_x_d), .b(step_x), .out(new_pos_x));
fp_add u_add_y(.clk(clk), .a(d2_pos_y_d), .b(step_y), .out(new_pos_y));
fp_add u_add_z(.clk(clk), .a(d2_pos_z_d), .b(step_z), .out(new_pos_z));


wire [26:0] d3_dir_x, d3_dir_y, d3_dir_z;
wire [26:0] d3_dist;
wire [7:0]  d3_iter;
wire [19:0] d3_pix_id;
wire        d3_valid;
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) pipe3_dir_x(.clk(clk), .in(d2_dir_x),  .out(d3_dir_x));
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) pipe3_dir_y(.clk(clk), .in(d2_dir_y),  .out(d3_dir_y));
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) pipe3_dir_z(.clk(clk), .in(d2_dir_z),  .out(d3_dir_z));
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) pipe3_dist (.clk(clk), .in(sdf_dist),  .out(d3_dist));
state_pipe #(.WIDTH(8),  .DEPTH(STEP_LAT)) pipe3_iter (.clk(clk), .in(d2_iter),   .out(d3_iter));
state_pipe #(.WIDTH(20), .DEPTH(STEP_LAT)) pipe3_pid  (.clk(clk), .in(d2_pix_id), .out(d3_pix_id));
state_pipe #(.WIDTH(1),  .DEPTH(STEP_LAT)) pipe3_valid(.clk(clk), .in(d2_valid),  .out(d3_valid));

// Stage 4: output — combinational
localparam logic [26:0] HIT_THRESH = {1'b0, 8'd117, 18'h01893}; // ~0.001 in 1.8.18
localparam int MAX_ITER = 64;

wire hit  = (d3_dist < HIT_THRESH);
wire miss = (d3_iter >= MAX_ITER);
wire done = hit | miss;

// to fb_write / iter_to_rgb
assign pix_done  = d3_valid & done;
assign out_pix_id = d3_pix_id;
assign out_iter   = d3_iter;

// feedback to feedback_ctrl (zero-extend 27-bit FP into 32-bit fields)
assign fb_valid     = d3_valid & ~done;
assign fb_pix_id    = d3_pix_id;
assign fb_pos_x     = {5'b0, new_pos_x};
assign fb_pos_y     = {5'b0, new_pos_y};
assign fb_pos_z     = {5'b0, new_pos_z};
assign fb_ray_dir_x = {5'b0, d3_dir_x};
assign fb_ray_dir_y = {5'b0, d3_dir_y};
assign fb_ray_dir_z = {5'b0, d3_dir_z};
assign fb_iter      = d3_iter + 8'd1;


endmodule