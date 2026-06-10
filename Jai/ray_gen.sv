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
    logic [26:0] posvec3_in [0:2];
    logic [26:0] dirvec3_out [0:2];
    assign posvec3_in[0] = s2_dx_f;
    assign posvec3_in[1] = s2_dy_f;
    assign posvec3_in[2] = s2_dz_f;

    fp_normalize u_normalize(.clk(clk), .vec3_in(posvec3_in), .vec3_out(dirvec3_out));

    //WRITE PACKED ARRAY STATE PIPE
    //delay lookat and origin from s0
    localparam int DELAY = 34;
    wire [26:0] lk_dl [0:8];
    wire [26:0] orig_dl [0:2];
    wire [PIX_ID_W-1:0] id_dl;

    state_pipe_packed_array #(.WIDTH(27), .NB_ELEMENTS(9), .DEPTH(DELAY)) pipe_lk (.clk(clk), .in(s0_lookat), .out(lk_dl)); // delay lookat 34 cycles to align with s7 normalised direction
    state_pipe_packed_array #(.WIDTH(27), .NB_ELEMENTS(3), .DEPTH(DELAY)) pipe_orig (.clk(clk), .in(s0_orig), .out(orig_dl)); // delay cam_origin 34 cycles to align with matrix multiply input

    //have lookat set of 3 vectors, all orthonormal- each represent axis in world space: x,y,z
    //multiply by the dirx, diry, dirz vector: obtain rotation/projection along the world axis
    //this gives true dir vector: already unit vector because unit vec* orthonormal mtx = unit vec. length preserved by transform
    wire [26:0] s10_rd [0:2];
    wire [26:0] orig_final [0:2];
    wire [PIX_ID_W-1:0] id_final;
    fp_mul_vec3_mat33 u_mulvecmat (.clk(clk), .mtx(lk_dl), .vec_in(dirvec3_out), .vec_out(s10_rd));
    state_pipe # (.WIDTH(PIX_ID_W), .DEPTH(DELAY)) u_state_pipe_pix_id (.clk(clk), .in(s0_id), .out(id_dl)); // delay pix_id 34 cycles to align with matrix multiply input
    state_pipe_packed_array # (.WIDTH(27), .NB_ELEMENTS(3), .DEPTH(12)) u_state_pipe_orig_dl (.clk(clk), .in(orig_dl), .out(orig_final)); // delay cam_origin further 12 cycles to align with matrix multiply output
    state_pipe # (.WIDTH(PIX_ID_W), .DEPTH(12)) u_state_pipe_id_dl (.clk(clk), .in(id_dl), .out(id_final)); // delay pix_id further 12 cycles to align with matrix multiply output

    always_ff @(posedge clk) begin
        if(!rst_n) begin
            valid_out <= 0;
        end else begin
            ray_orig[0] <= orig_final[0];
            ray_orig[1] <= orig_final[1];
            ray_orig[2] <= orig_final[2];
            ray_dir[0] <= s10_rd[0];
            ray_dir[1] <= s10_rd[1];
            ray_dir[2] <= s10_rd[2];
            pix_id_out <= id_final;
            valid_out <= valid_sr_out;
        end
    end

    assign pipeline_ready = 1'b1;

endmodule

`default_nettype wire
