`timescale 1ns/1ps
`default_nettype none

/*
Takes in pixel coordinates pix_x 0 to 2027 , pix_y 0 to 1023
as well as pixel id: 1280 x 720 = 921 600 pixels so 2^20 values : 20 bits
as well as lookat camera matrix for world basis orthornormal vectors, camera origin

Ouputs the ray orig (simple pass of cam origin through pipeline), pix_id (pass)
and the ray_dir x y z in world space (after lookat matrix multiplication),
as well as pipeline ready signal held high as no stall condition
*/
module ray_gen #(
    parameter int IMG_W = 1280,
    parameter int IMG_H = 720,
    parameter int PIX_ID_W = 20, //pix id wire, w for width
    parameter logic [26:0] FOV_Z_CONST = 27'h1FC0000  // = FP_ONE
)(
    input wire clk,
    input wire rst_n,

    input wire [10:0] pix_x,
    input wire [9:0] pix_y,
    input wire [PIX_ID_W-1:0] pix_id_in,
    input wire valid_in,

    input wire [26:0] lookat [0:8],
    input wire [26:0] cam_origin[0:2],

    output logic [26:0] ray_orig[0:2],
    output logic [26:0] ray_dir [0:2],
    output logic [PIX_ID_W-1:0] pix_id_out,
    output logic valid_out,
    output logic pipeline_ready
);

    //lookout for this, could easily be critical path**

    //takes a 16 bit pixel coordinate: x or y. 16 bits chosen for good headroom
    function automatic logic [26:0] fp_int2fp(input logic signed [15:0] n);
        logic sign;
        logic [15:0] mag;
        int lead;
        logic [7:0] exp;
        logic [17:0] mant;
        logic [15:0] mag_no_msb;
        if (n == 0) return 27'h0;
        sign = n[15];
        mag = sign ? $unsigned(-n) : $unsigned(n); //equivalent of doing 2s complement +1, cleaner
        lead = 0;
        for (int j = 0; j < 16; j++) begin
            if (mag[j]) lead = j; //find leading 1 in the 16 bit number
        end
        exp = 8'(lead + 127); //get exponent, biased by 127 for FP
        //we must exclude the implicit leading 1 always present in FP. must get mag[lead-1:0], use mask for bottom N bits trick (1<<N)-1
        //get leading 1s followed by lead0s, and substract 1 to generate exactly lead1s.
        //then and with magnitude (after masking) to obtain the first 1 in the mantissa
        mag_no_msb = mag & ((16'h1 << lead) - 16'h1); 
        mant = 18'(mag_no_msb) << (18 - lead);
        return {sign, exp, mant};
    endfunction

    localparam int PIPE_LAT = 48;
    //scale entire camera space / world by 2 as: center of 1280 px img is 639.5 px, not int
    //true center: 639.5 * 2 = 1279

    //fov is z because camera is always same dist to screen along z axis.
    //increase z: angle to edges of screen smaller, smaller FOV
    localparam logic [26:0] FOV_Z_CONST_X2 = {
        FOV_Z_CONST[26],
        FOV_Z_CONST[25:18] + 8'd1,
        FOV_Z_CONST[17:0]
    };

    //valid shift reg 34
    localparam int VSR_DEPTH = PIPE_LAT - 1;
    logic valid_sr_out;
    state_pipe #(.WIDTH(1), .DEPTH(VSR_DEPTH)) u_vsr(.clk(clk), .in(valid_in), .out(valid_sr_out));


    //s0 register inputs
    logic [10:0] s0_px;
    logic [9:0] s0_py;
    logic [PIX_ID_W-1:0] s0_id;
    logic [26:0] s0_lookat [0:8];
    logic [26:0] s0_orig [0:2];

    //latch inputs into s0
    always_ff @(posedge clk) begin
        s0_px <= pix_x;
        s0_py <= pix_y;
        s0_id <= pix_id_in;
        s0_lookat <= lookat;
        s0_orig <= cam_origin;
    end

    //s1
    logic [31:0] s1_dx, s1_dy;
    logic [26:0] s1_dz;

    always_ff @(posedge clk) begin
        //following the scaling of entire camera space, get xcoord*2 and substract 1279. 
        //as we want pixel 0 to give -1279 and pixel 1279 to give 1279, perfect sym around 0 
        s1_dx <= ({ {20{1'b0}}, s0_px, 1'b0 }) - 32'(IMG_W - 1);
        //same here, but invert the Y coordinate such that py=0 maps to positive 3D axis. py = 719 should map to negative 3D Y
        //px range 0 to 719: px 0 -> 719, pix 719 -> -719
        s1_dy <= 32'(IMG_H - 1) - ({ {21{1'b0}}, s0_py, 1'b0 });
        s1_dz <= FOV_Z_CONST_X2; //carry through scaling
    end

    //s2 fp_int2fp convert int offset to 27bit float
    logic [26:0] s2_dx_f, s2_dy_f, s2_dz_f;
    always_ff @(posedge clk) begin
        s2_dx_f <= fp_int2fp(s1_dx[15:0]);
        s2_dy_f <= fp_int2fp(s1_dy[15:0]);
        s2_dz_f <= s1_dz;
    end

    //obtain the normalized vector for dx,dy,dz : dirx, diry, dz. vec/norm computation
    //MAKE MODULE FOR 1/length
    //s3 square and normalise
    wire [26:0] s3_dx2, s3_dy2, s3_dz2;
    fp_mul dx2(.clk(clk), .a(s2_dx_f), .b(s2_dx_f), .out(s3_dx2));
    fp_mul dy2(.clk(clk), .a(s2_dy_f), .b(s2_dy_f), .out(s3_dy2));
    fp_mul dz2(.clk(clk), .a(s2_dz_f), .b(s2_dz_f), .out(s3_dz2));

    //delay floats 2 cycles to stay in sync
    wire [26:0] s3_dx_dl, s3_dy_dl, s3_dz_dl;
    state_pipe #(.WIDTH(27), .DEPTH(2)) pipe_dx_f (.clk(clk), .in(s2_dx_f), .out(s3_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(2)) pipe_dy_f (.clk(clk), .in(s2_dy_f), .out(s3_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(2)) pipe_dz_f (.clk(clk), .in(s2_dz_f), .out(s3_dz_dl));

    //s4 add squares
    wire [26:0] s4_sum;
    fp_add add_xy (.clk(clk), .a(s3_dx2), .b(s3_dy2), .out(s4_sum));

    //delay by 4 cyc to allign with s4_sum 
    wire [26:0] s4_dz2_dl;
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dz2(.clk(clk), .in(s3_dz2), .out(s4_dz2_dl));

    //delay dx,y,z byt 4 cycles
    wire [26:0] s4_dx_dl, s4_dy_dl, s4_dz_dl;
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dx_f2(.clk(clk), .in(s3_dx_dl), .out(s4_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dy_f2(.clk(clk), .in(s3_dy_dl), .out(s4_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dz_f2(.clk(clk), .in(s3_dz_dl), .out(s4_dz_dl));

    //s5 sum_xy + dz^2  = mag^2
    wire [26:0] s5_mag2;
    fp_add add_xyz (.clk(clk), .a(s4_sum), .b(s4_dz2_dl), .out(s5_mag2));

    wire [26:0] s5_dx_dl, s5_dy_dl, s5_dz_dl;
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dx_f3(.clk(clk), .in(s4_dx_dl), .out(s5_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dy_f3(.clk(clk), .in(s4_dy_dl), .out(s5_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_dz_f3(.clk(clk), .in(s4_dz_dl), .out(s5_dz_dl));

    //s6 fp_isqrt 10cyc
    wire [26:0] s6_inv_mag;
    fp_isqrt isqrt(.clk(clk), .a(s5_mag2), .out(s6_inv_mag));
    wire [26:0] s6_dx_dl, s6_dy_dl, s6_dz_dl;
    //18cycle delay
    state_pipe #(.WIDTH(27), .DEPTH(18)) pipe_dx_f4(.clk(clk), .in(s5_dx_dl), .out(s6_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(18)) pipe_dy_f4(.clk(clk), .in(s5_dy_dl), .out(s6_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(18)) pipe_dz_f4(.clk(clk), .in(s5_dz_dl), .out(s6_dz_dl));


    //s7 normalise 2cycle
    wire [26:0] s7_dx, s7_dy, s7_dz;
    fp_mul norm_x(.clk(clk), .a(s6_inv_mag), .b(s6_dx_dl), .out(s7_dx));
    fp_mul norm_y(.clk(clk), .a(s6_inv_mag), .b(s6_dy_dl), .out(s7_dy));
    fp_mul norm_z(.clk(clk), .a(s6_inv_mag), .b(s6_dz_dl), .out(s7_dz));

    //WRITE PACKED ARRAY STATE PIPE
    //delay lookat and origin from s0
    localparam int DELAY = 34;
    wire [26:0] lk_dl [0:8];
    wire [26:0] orig_dl [0:2];
    wire [PIX_ID_W-1:0] id_dl;

    genvar i;
    generate
        for(i=0; i < 9; i++) begin : gen_lk_delay
            state_pipe #(.WIDTH(27), .DEPTH(DELAY)) pipe_lk(.clk(clk), .in(s0_lookat[i]), .out(lk_dl[i]));
        end
        for(i = 0; i < 3; i++) begin : gen_orig_delay
            state_pipe #(.WIDTH(27), .DEPTH(DELAY)) pipe_orig(.clk(clk), .in(s0_orig[i]), .out(orig_dl[i]));
        end
    endgenerate
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(DELAY)) pipe_id(.clk(clk), .in(s0_id), .out(id_dl));

    //have lookat set of 3 vectors, all orthonormal- each represent axis in world space: x,y,z
    //multiply by the dirx, diry, dirz vector: obtain rotation/projection along the world axis
    //this gives true dir vector: already unit vector because unit vec* orthonormal mtx = unit vec. length preserved by transform
    
    //s8 9matx partial products 2cycle
    wire [26:0] s8_p [0:8];
    fp_mul p0(.clk(clk), .a(lk_dl[0]), .b(s7_dx), .out(s8_p[0]));
    fp_mul p1(.clk(clk), .a(lk_dl[1]), .b(s7_dy), .out(s8_p[1]));
    fp_mul p2(.clk(clk), .a(lk_dl[2]), .b(s7_dz), .out(s8_p[2]));
    fp_mul p3(.clk(clk), .a(lk_dl[3]), .b(s7_dx), .out(s8_p[3]));
    fp_mul p4(.clk(clk), .a(lk_dl[4]), .b(s7_dy), .out(s8_p[4]));
    fp_mul p5(.clk(clk), .a(lk_dl[5]), .b(s7_dz), .out(s8_p[5]));
    fp_mul p6(.clk(clk), .a(lk_dl[6]), .b(s7_dx), .out(s8_p[6]));
    fp_mul p7(.clk(clk), .a(lk_dl[7]), .b(s7_dy), .out(s8_p[7]));
    fp_mul p8(.clk(clk), .a(lk_dl[8]), .b(s7_dz), .out(s8_p[8]));

    //delay org and id by 4 for s8
    wire [26:0] orig_dl2 [0:2];
    wire [PIX_ID_W-1:0] id_dl2;
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_ox2(.clk(clk), .in(orig_dl[0]), .out(orig_dl2[0]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_oy2(.clk(clk), .in(orig_dl[1]), .out(orig_dl2[1]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_oz2(.clk(clk), .in(orig_dl[2]), .out(orig_dl2[2]));
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(4)) pipe_id2(.clk(clk), .in(id_dl), .out(id_dl2));

    //s9 col0 +col1 for each row
    wire [26:0] s9_sum [0:2];
    fp_add add_r0(.clk(clk), .a(s8_p[0]), .b(s8_p[1]), .out(s9_sum[0]));
    fp_add add_r1(.clk(clk), .a(s8_p[3]), .b(s8_p[4]), .out(s9_sum[1]));
    fp_add add_r2(.clk(clk), .a(s8_p[6]), .b(s8_p[7]), .out(s9_sum[2]));

    wire [26:0] s9_col2 [0:2];
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_col2_r0(.clk(clk), .in(s8_p[2]), .out(s9_col2[0]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_col2_r1(.clk(clk), .in(s8_p[5]), .out(s9_col2[1]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_col2_r2(.clk(clk), .in(s8_p[8]), .out(s9_col2[2]));

    //delay  org and id by 4 s9
    wire [26:0] orig_dl3 [0:2];
    wire [PIX_ID_W-1:0] id_dl3;
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_ox3(.clk(clk), .in(orig_dl2[0]), .out(orig_dl3[0]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_oy3(.clk(clk), .in(orig_dl2[1]), .out(orig_dl3[1]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_oz3(.clk(clk), .in(orig_dl2[2]), .out(orig_dl3[2]));
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(4)) pipe_id3(.clk(clk), .in(id_dl2), .out(id_dl3));

    //s10 sum + col2=ray direction
    wire [26:0] s10_rd [0:2];
    fp_add add_rd0(.clk(clk), .a(s9_sum[0]), .b(s9_col2[0]), .out(s10_rd[0]));
    fp_add add_rd1(.clk(clk), .a(s9_sum[1]), .b(s9_col2[1]), .out(s10_rd[1]));
    fp_add add_rd2(.clk(clk), .a(s9_sum[2]), .b(s9_col2[2]), .out(s10_rd[2]));

    wire [26:0] orig_dl4 [0:2];
    wire [PIX_ID_W-1:0] id_dl4;
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_ox4(.clk(clk), .in(orig_dl3[0]), .out(orig_dl4[0]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_oy4(.clk(clk), .in(orig_dl3[1]), .out(orig_dl4[1]));
    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_oz4(.clk(clk), .in(orig_dl3[2]), .out(orig_dl4[2]));
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(4)) pipe_id4(.clk(clk), .in(id_dl3), .out(id_dl4));

    //s11 reg out
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            valid_out <= 0;
        end else begin
            ray_orig[0] <= orig_dl4[0];
            ray_orig[1] <= orig_dl4[1];
            ray_orig[2] <= orig_dl4[2];
            ray_dir[0] <= s10_rd[0];
            ray_dir[1] <= s10_rd[1];
            ray_dir[2] <= s10_rd[2];
            pix_id_out <= id_dl4;
            valid_out <= valid_sr_out;
        end
    end

    assign pipeline_ready = 1'b1;

endmodule

`default_nettype wire
