module march_core(

    input logic clk,
    input logic rst_n,

    //from feedback_ctrl
    input logic [10:0] in_x,
    input logic [9:0]in_y,
    input logic [19:0]in_pix_id,
    input logic [26:0]in_pos_x,
    input logic [26:0]in_pos_y,
    input logic [26:0]in_pos_z,
    input logic [26:0]in_ray_dir_x,
    input logic [26:0]in_ray_dir_y,
    input logic [26:0]in_ray_dir_z,
    input logic [7:0]in_iter,
    input logic in_valid,

    //from axi_camera_regs
    input logic  [26:0]lookat [0:8],
    input logic [26:0] cam_origin [0:2],

    //OBSOLETE?
    //output to fb_write
    output logic pix_done,
    output logic [19:0]out_pix_id,
    output logic [7:0]out_iter ,

    //output to feedback_ctrl
    output logic [7:0]fb_iter,
    output logic [26:0]fb_ray_dir_x,
    output logic [26:0]fb_ray_dir_y,
    output logic [26:0]fb_ray_dir_z,
    output logic [26:0]fb_pos_x,
    output logic [26:0]fb_pos_y,
    output logic [26:0]fb_pos_z,
    output logic [19:0]fb_pix_id,
    output logic fb_valid
);

localparam [26:0] HIT_THRESH = {1'b0, 8'd117, 18'h01893};
localparam MAX_ITER = 128;



//stage 1: ray gen, rg_lat = 48
logic [26:0] rg_dir[0:2];
logic [26:0] rg_orig[0:2];
logic rg_valid;
logic [19:0] rg_pix_id;
logic s1_is_new_ray;
logic d1_valid;
localparam RG_LAT = 48; //48 clk latency in ray gen dir det, ray gen takes longer at 150Mhz
ray_gen #(
    .IMG_W(1280),
    .IMG_H(720),
    .FOV_Z_CONST(27'h221A000) //720 so like 83.3° angle FOV
) inst1_ray_gen (
    //inputs
    .clk(clk),
    .rst_n(rst_n),
    .pix_x(in_x),
    .pix_y(in_y),
    .pix_id_in(in_pix_id),
    .valid_in(in_valid),
    .lookat(lookat),
    .cam_origin(cam_origin),
    //outputs
    .valid_out(rg_valid),
    .ray_dir(rg_dir),
    .ray_orig(rg_orig),
    .pix_id_out(rg_pix_id),
    .pipeline_ready()
);

wire[26:0] rg_dir_x=rg_dir[0];
wire[26:0] rg_dir_y=rg_dir[1];
wire[26:0] rg_dir_z=rg_dir[2];
//must hold for RG_LAT clk values of in_pos, in_dir, in_iter, in_pix_id
logic [26:0] d1_pos_x, d1_pos_y, d1_pos_z, d1_dir_x, d1_dir_y, d1_dir_z;
logic [26:0] s1_pos_x, s1_pos_y, s1_pos_z, s1_dir_x, s1_dir_y, s1_dir_z;
logic [7:0] d1_iter;
logic [19:0] d1_pix_id;
logic [7:0] s1_iter;
logic [19:0] s1_pix_id;
logic s1_valid;
state_pipe #(.WIDTH(27), .DEPTH(RG_LAT)) inst1_in_pos_x (.clk(clk), .in(in_pos_x), .out(d1_pos_x));
state_pipe #(.WIDTH(27), .DEPTH(RG_LAT)) inst1_in_pos_y(.clk(clk), .in(in_pos_y), .out(d1_pos_y));
state_pipe #(.WIDTH(27), .DEPTH(RG_LAT)) inst1_in_pos_z(.clk(clk), .in(in_pos_z), .out(d1_pos_z));

state_pipe #(.WIDTH(27), .DEPTH(RG_LAT)) inst1_in_dir_x(.clk(clk), .in(in_ray_dir_x), .out(d1_dir_x));
state_pipe #(.WIDTH(27), .DEPTH(RG_LAT)) inst1_in_dir_y(.clk(clk), .in(in_ray_dir_y), .out(d1_dir_y));
state_pipe #(.WIDTH(27), .DEPTH(RG_LAT)) inst1_in_dir_z(.clk(clk), .in(in_ray_dir_z), .out(d1_dir_z));

state_pipe #(.WIDTH(8), .DEPTH(RG_LAT)) inst1_in_iter(.clk(clk), .in(in_iter), .out(d1_iter));
state_pipe #(.WIDTH(20), .DEPTH(RG_LAT)) inst1_in_pix_id(.clk(clk), .in(in_pix_id), .out(d1_pix_id));

//if iter is 0, direction is rg output and pos is camera origin
//combinatorial mux select ray origin on first iteration, feedback pos otw
wire [26:0] s1_pos_x_comb = (d1_iter == 8'd0) ? rg_orig[0] : d1_pos_x;
wire [26:0] s1_pos_y_comb = (d1_iter == 8'd0) ? rg_orig[1] : d1_pos_y;
wire [26:0] s1_pos_z_comb = (d1_iter == 8'd0) ? rg_orig[2] : d1_pos_z;
wire [26:0] s1_dir_x_comb = (d1_iter == 8'd0) ? rg_dir[0]  : d1_dir_x;
wire [26:0] s1_dir_y_comb = (d1_iter == 8'd0) ? rg_dir[1]  : d1_dir_y;
wire [26:0] s1_dir_z_comb = (d1_iter == 8'd0) ? rg_dir[2]  : d1_dir_z;
wire [26:0] s1_is_new_ray_comb = (d1_iter==8'd0);

always_ff @ (posedge clk) begin
    s1_pos_x     <= s1_pos_x_comb;
    s1_pos_y     <= s1_pos_y_comb;
    s1_pos_z     <= s1_pos_z_comb;
    s1_dir_x     <= s1_dir_x_comb;
    s1_dir_y     <= s1_dir_y_comb;
    s1_dir_z     <= s1_dir_z_comb;
    s1_is_new_ray <= s1_is_new_ray_comb;
    s1_valid     <= s1_is_new_ray_comb ? rg_valid  : d1_valid;
    s1_iter      <= d1_iter;
    s1_pix_id    <= s1_is_new_ray_comb ? rg_pix_id : d1_pix_id;
end

state_pipe #(.WIDTH(1), .DEPTH(RG_LAT)) inst1_in_valid(.clk(clk), .in(in_valid), .out(d1_valid));


//Stage 2: scene_sdf, 55 clk delay pipeline on 150Mhz
localparam SDF_LAT=55;
logic [26:0] sdf_dist;
scene_sdf inst1_scene_sdf(
    .clk(clk),
    .px(s1_pos_x),
    .py(s1_pos_y),
    .pz(s1_pos_z),
    .sdf_out(sdf_dist)
);

//wire [26:0] sdf_dist = 27'h1FC0000; // constant 1.0
logic [26:0] d2_pos_x, d2_pos_y, d2_pos_z, d2_dir_x, d2_dir_y, d2_dir_z;
logic [7:0] d2_iter;
logic [19:0] d2_pix_id;
logic d2_valid;

//must hold for SDF_LAT clks the values that arrive with sdf_dist
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) inst1_d2_pos_x(.clk(clk), .in(s1_pos_x), .out(d2_pos_x));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) inst1_d2_pos_y(.clk(clk), .in(s1_pos_y), .out(d2_pos_y));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) inst1_d2_pos_z(.clk(clk), .in(s1_pos_z), .out(d2_pos_z));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) inst1_d2_dir_x(.clk(clk), .in(s1_dir_x), .out(d2_dir_x));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) inst1_d2_dir_y(.clk(clk), .in(s1_dir_y), .out(d2_dir_y));
state_pipe #(.WIDTH(27), .DEPTH(SDF_LAT)) inst1_d2_dir_z(.clk(clk), .in(s1_dir_z), .out(d2_dir_z));
state_pipe #(.WIDTH(8), .DEPTH(SDF_LAT)) inst1_d2_iter(.clk(clk), .in(s1_iter), .out(d2_iter));
state_pipe #(.WIDTH(20), .DEPTH(SDF_LAT)) inst1_d2_pix_id(.clk(clk), .in(s1_pix_id), .out(d2_pix_id));
state_pipe #(.WIDTH(1), .DEPTH(SDF_LAT)) inst1_d2_valid(.clk(clk), .in(s1_valid), .out(d2_valid));

//Stage 3: step forward after computing sdf
//sdf_dist * dir for xyz
logic [26:0] step_x, step_y, step_z;

//fp mul 4 clk delay
fp_mul inst1_mul_x (.clk(clk), .a(sdf_dist), .b(d2_dir_x), .out(step_x));
fp_mul inst1_mul_y (.clk(clk), .a(sdf_dist), .b(d2_dir_y), .out(step_y));
fp_mul inst1_mul_z (.clk(clk), .a(sdf_dist), .b(d2_dir_z), .out(step_z));

//then do total dist = curr dist + sdf_dist*dir
//fp add 4 clk delay ON 150MHZ

//while d2_pos_x,y,z is available NOW, step_x,y,z still needs 4 clk to be computed, so delay d2_pos_x,y,z by 4 clk
logic [26:0] new_pos_x, new_pos_y, new_pos_z, d2_pos_x_d, d2_pos_y_d, d2_pos_z_d;
state_pipe #(.WIDTH(27), .DEPTH(4)) inst1_d2_pos_x_d(.clk(clk), .in(d2_pos_x), .out(d2_pos_x_d));
state_pipe #(.WIDTH(27), .DEPTH(4)) inst1_d2_pos_y_d(.clk(clk), .in(d2_pos_y), .out(d2_pos_y_d));
state_pipe #(.WIDTH(27), .DEPTH(4)) inst1_d2_pos_z_d(.clk(clk), .in(d2_pos_z), .out(d2_pos_z_d));

//march the ray in all 3 directions: compute new position, using newpos = old pos + step along x,y,z
fp_add inst1_add_x(.clk(clk), .a(d2_pos_x_d), .b(step_x), .out(new_pos_x));
fp_add inst1_add_y(.clk(clk), .a(d2_pos_y_d), .b(step_y), .out(new_pos_y));
fp_add inst1_add_z(.clk(clk), .a(d2_pos_z_d), .b(step_z), .out(new_pos_z));


logic [26:0] d3_dir_x, d3_dir_y, d3_dir_z, d3_dist;
logic [7:0] d3_iter;
logic [19:0] d3_pix_id;
logic d3_valid;
localparam STEP_LAT = 8; //total 8 clk from old pos to new pos (add + product step compute)
//all other signals dir, dist, iter, pix_id, valid that aren't computed need to be delayed by same 8 clcyles so that they align with new_pos when comes out
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) inst_d3_dir_x(.clk(clk), .in(d2_dir_x),  .out(d3_dir_x));
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) inst_d3_dir_y(.clk(clk), .in(d2_dir_y),  .out(d3_dir_y));
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) inst_d3_dir_z(.clk(clk), .in(d2_dir_z),  .out(d3_dir_z));
state_pipe #(.WIDTH(27), .DEPTH(STEP_LAT)) inst_d3_dist (.clk(clk), .in(sdf_dist),  .out(d3_dist));
state_pipe #(.WIDTH(8),  .DEPTH(STEP_LAT)) inst_d3_iter (.clk(clk), .in(d2_iter),   .out(d3_iter));
state_pipe #(.WIDTH(20), .DEPTH(STEP_LAT)) inst_d3_pid  (.clk(clk), .in(d2_pix_id), .out(d3_pix_id));
state_pipe #(.WIDTH(1),  .DEPTH(STEP_LAT)) inst_d3_valid(.clk(clk), .in(d2_valid),  .out(d3_valid));

wire hit_comb = d3_valid & (d3_dist[26] | (d3_dist < HIT_THRESH)); //if sign bit is set, dist negative, we are inside an object so clearly we hit it
wire miss_comb = d3_valid & (d3_iter >= MAX_ITER);
wire done_comb = hit_comb | miss_comb;

always_ff @ (posedge clk) begin
    pix_done     <= d3_valid & done_comb; //ray is done, send to fb_write
    fb_pix_id    <= d3_pix_id;
    fb_pos_x     <= new_pos_x;
    fb_pos_y     <= new_pos_y;
    fb_pos_z     <= new_pos_z;
    fb_ray_dir_x <= d3_dir_x;
    fb_ray_dir_y <= d3_dir_y;
    fb_ray_dir_z <= d3_dir_z;
    fb_iter      <= d3_iter + 8'd1;
    fb_valid     <= d3_valid & ~done_comb; //if set, ray is not done yet, must feed back for another march iteration
    out_pix_id   <= d3_pix_id;
    out_iter     <= d3_iter;
end

endmodule
