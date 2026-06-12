`timescale 1ns/1ps
`default_nettype none

module ray_gen #(
    parameter int IMG_W = 1280,
    parameter int IMG_H = 720,
    parameter int PIX_ID_W = 20,
    parameter logic [26:0] FOV_Z_CONST = 27'h1FC0000
)(
    input wire clk,
    input wire rst_n,

    input wire [10:0] pix_x,
    input wire [9:0] pix_y,
    input wire [PIX_ID_W-1:0] pix_id_in,
    input wire valid_in,

    input wire [26:0] lookat [0:8],
    input wire [26:0] cam_origin[0:2],
    input wire [26:0] cam_origin_right[0:2],

    output logic [26:0] ray_orig[0:2],
    output logic [26:0] ray_dir [0:2],
    output logic [PIX_ID_W-1:0] pix_id_out,
    output logic valid_out,
    output logic pipeline_ready
);

    // fp_int2fp is now split across three pipeline stages (s1a, s1b, s2) to
    // break the original 9-level LUT chain that violated 148.5 MHz timing.

    // Stage s1b helper: priority encoder — finds highest set bit in a 16-bit mag.
    function automatic logic [3:0] leading_one16(input logic [15:0] m);
        logic [3:0] l;
        l = 4'd0;
        for (int k = 0; k < 16; k++) if (m[k]) l = 4'(k);
        return l;
    endfunction

    // Stage s2 helper: build fp27 from already-registered sign/mag/lead.
    function automatic logic [26:0] lead2fp27(
        input logic        sign,
        input logic [15:0] mag,
        input logic [3:0]  lead,
        input logic        is_zero
    );
        logic [7:0]  exp;
        logic [15:0] mag_frac;
        logic [17:0] mant;
        if (is_zero) return 27'h0;
        exp      = 8'(lead) + 8'd127;
        mag_frac = mag & ((16'h1 << lead) - 16'h1);
        mant     = 18'(mag_frac) << (5'd18 - {1'b0, lead});
        return {sign, exp, mant};
    endfunction

    localparam int HALF_W = IMG_W / 2;
    localparam int HALF_H = IMG_H / 2;
    localparam int PIPE_LAT = 60;  // +2 for s1a/s1b pipeline stages, and synchronized to fp_isqrt=20, fp_add=5, fp_mul=5
    localparam logic [26:0] FOV_Z_CONST_X2 = {
        FOV_Z_CONST[26],
        FOV_Z_CONST[25:18] + 8'd1,
        FOV_Z_CONST[17:0]
    };

    //valid shift reg 34
    localparam int VSR_DEPTH = PIPE_LAT - 1;
    logic [VSR_DEPTH-1:0] valid_sr;
    always_ff @(posedge clk)begin
        if(!rst_n) valid_sr <= '0;
        else valid_sr <= {valid_sr[VSR_DEPTH-2:0], valid_in};
    end

    //s0 register inputs
    logic [10:0] s0_px;
    logic [9:0] s0_py;
    logic [PIX_ID_W-1:0] s0_id;
    logic [26:0] s0_lookat [0:8];
    // Pre-register the right-half comparison so only a 1-bit signal fans to
    // the cam_origin mux, rather than the raw comparison result fanning to
    // all 81 SRL32 D-inputs and creating a 6+ ns routing path.
    logic s0_pix_right;
    // SHREG_EXTRACT=no prevents Vivado absorbing these FFs into the SRL32
    // delay chain, which would recreate the high-fanout path on the mux LUT.
    (* SHREG_EXTRACT = "no" *) logic [26:0] s0_orig [0:2];

    always_ff @(posedge clk) begin
        s0_px       <= pix_x;
        s0_py       <= pix_y;
        s0_id       <= pix_id_in;
        s0_lookat   <= lookat;
        s0_pix_right <= (pix_x >= 11'd320);
    end
    // s0_orig is registered one cycle AFTER s0_lookat/s0_px using the
    // already-registered s0_pix_right.  gen_orig_delay uses DELAY-1 below
    // to compensate so orig_dl still arrives aligned with lk_dl.
    always_ff @(posedge clk) begin
        s0_orig[0] <= s0_pix_right ? cam_origin_right[0] : cam_origin[0];
        s0_orig[1] <= s0_pix_right ? cam_origin_right[1] : cam_origin[1];
        s0_orig[2] <= s0_pix_right ? cam_origin_right[2] : cam_origin[2];
    end

    //s1
    logic [31:0] s1_dx, s1_dy;
    logic [26:0] s1_dz;

    logic [10:0] local_px;
    assign local_px = (s0_px >= 11'd320) ? (s0_px - 11'd320) : s0_px;

    always_ff @(posedge clk) begin
        // local_px goes 0 to 319. Multiply by 2 and subtract 319 to go from -319 to +319.
        s1_dx <= ({ {20{1'b0}}, local_px, 1'b0 }) - 32'd319;
        s1_dy <= 32'(IMG_H - 1) - ({ {21{1'b0}}, s0_py, 1'b0 });
        s1_dz <= FOV_Z_CONST_X2;
    end

    //s1a extract sign and mag
    logic s1a_dx_sign, s1a_dy_sign;
    logic [15:0] s1a_dx_mag, s1a_dy_mag;
    logic s1a_dx_zero, s1a_dy_zero;
    logic [26:0] s1a_dz;
    always_ff @(posedge clk) begin
        s1a_dx_sign <= s1_dx[31];
        s1a_dx_mag  <= s1_dx[31] ? -s1_dx[15:0] : s1_dx[15:0];
        s1a_dx_zero <= (s1_dx == 0);

        s1a_dy_sign <= s1_dy[31];
        s1a_dy_mag  <= s1_dy[31] ? -s1_dy[15:0] : s1_dy[15:0];
        s1a_dy_zero <= (s1_dy == 0);
        
        s1a_dz <= s1_dz;
    end

    //s1b finding leading one
    logic s1b_dx_sign, s1b_dy_sign;
    logic [15:0] s1b_dx_mag, s1b_dy_mag;
    logic [3:0] s1b_dx_lead, s1b_dy_lead;
    logic s1b_dx_zero, s1b_dy_zero;
    logic [26:0] s1b_dz;
    always_ff @(posedge clk) begin
        s1b_dx_sign <= s1a_dx_sign;
        s1b_dx_mag  <= s1a_dx_mag;
        s1b_dx_lead <= leading_one16(s1a_dx_mag);
        s1b_dx_zero <= s1a_dx_zero;

        s1b_dy_sign <= s1a_dy_sign;
        s1b_dy_mag  <= s1a_dy_mag;
        s1b_dy_lead <= leading_one16(s1a_dy_mag);
        s1b_dy_zero <= s1a_dy_zero;

        s1b_dz <= s1a_dz;
    end

    //s2 fp_int2fp convert int offset to 27bit float
    logic [26:0] s2_dx_f, s2_dy_f, s2_dz_f;
    always_ff @(posedge clk) begin
        s2_dx_f <= lead2fp27(s1b_dx_sign, s1b_dx_mag, s1b_dx_lead, s1b_dx_zero);
        s2_dy_f <= lead2fp27(s1b_dy_sign, s1b_dy_mag, s1b_dy_lead, s1b_dy_zero);
        s2_dz_f <= s1b_dz;
    end

    //s3 square and normalise
    wire [26:0] s3_dx2, s3_dy2, s3_dz2;
    fp_mul dx2(.clk(clk), .a(s2_dx_f), .b(s2_dx_f), .out(s3_dx2));
    fp_mul dy2(.clk(clk), .a(s2_dy_f), .b(s2_dy_f), .out(s3_dy2));
    fp_mul dz2(.clk(clk), .a(s2_dz_f), .b(s2_dz_f), .out(s3_dz2));

    //delay floats 5 cycles to stay in sync
    wire [26:0] s3_dx_dl, s3_dy_dl, s3_dz_dl;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dx_f (.clk(clk), .in(s2_dx_f), .out(s3_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dy_f (.clk(clk), .in(s2_dy_f), .out(s3_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dz_f (.clk(clk), .in(s2_dz_f), .out(s3_dz_dl));

    //s4 add squares
    wire [26:0] s4_sum;
    fp_add add_xy (.clk(clk), .a(s3_dx2), .b(s3_dy2), .out(s4_sum));

    //delay by 5 cyc to allign with s4_sum 
    wire [26:0] s4_dz2_dl;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dz2(.clk(clk), .in(s3_dz2), .out(s4_dz2_dl));

    //delay dx,y,z by 5 cycles
    wire [26:0] s4_dx_dl, s4_dy_dl, s4_dz_dl;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dx_f2(.clk(clk), .in(s3_dx_dl), .out(s4_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dy_f2(.clk(clk), .in(s3_dy_dl), .out(s4_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dz_f2(.clk(clk), .in(s3_dz_dl), .out(s4_dz_dl));

    //s5 sum_xy + dz^2  = mag^2
    wire [26:0] s5_mag2;
    fp_add add_xyz (.clk(clk), .a(s4_sum), .b(s4_dz2_dl), .out(s5_mag2));

    wire [26:0] s5_dx_dl, s5_dy_dl, s5_dz_dl;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dx_f3(.clk(clk), .in(s4_dx_dl), .out(s5_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dy_f3(.clk(clk), .in(s4_dy_dl), .out(s5_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_dz_f3(.clk(clk), .in(s4_dz_dl), .out(s5_dz_dl));

    //s6 fp_isqrt 10cyc
    wire [26:0] s6_inv_mag;
    fp_isqrt isqrt(.clk(clk), .a(s5_mag2), .out(s6_inv_mag));
    wire [26:0] s6_dx_dl, s6_dy_dl, s6_dz_dl;
    //20 cycle delay for isqrt
    state_pipe #(.WIDTH(27), .DEPTH(20)) pipe_dx_f4(.clk(clk), .in(s5_dx_dl), .out(s6_dx_dl));
    state_pipe #(.WIDTH(27), .DEPTH(20)) pipe_dy_f4(.clk(clk), .in(s5_dy_dl), .out(s6_dy_dl));
    state_pipe #(.WIDTH(27), .DEPTH(20)) pipe_dz_f4(.clk(clk), .in(s5_dz_dl), .out(s6_dz_dl));


    //s7 normalise 2cycle
    wire [26:0] s7_dx, s7_dy, s7_dz;
    fp_mul norm_x(.clk(clk), .a(s6_inv_mag), .b(s6_dx_dl), .out(s7_dx));
    fp_mul norm_y(.clk(clk), .a(s6_inv_mag), .b(s6_dy_dl), .out(s7_dy));
    fp_mul norm_z(.clk(clk), .a(s6_inv_mag), .b(s6_dz_dl), .out(s7_dz));

    //delay lookat and origin from s0
    localparam int DELAY = 44;
    wire [26:0] lk_dl [0:8];
    wire [26:0] orig_dl [0:2];
    wire [PIX_ID_W-1:0] id_dl;

    genvar i;
    generate
        for(i=0; i < 9; i++) begin : gen_lk_delay
            state_pipe #(.WIDTH(27), .DEPTH(DELAY)) pipe_lk(.clk(clk), .in(s0_lookat[i]), .out(lk_dl[i]));
        end
        for(i = 0; i < 3; i++) begin : gen_orig_delay
            // DELAY-1 because s0_orig is registered one cycle later than s0_lookat
            state_pipe #(.WIDTH(27), .DEPTH(DELAY-1)) pipe_orig(.clk(clk), .in(s0_orig[i]), .out(orig_dl[i]));
        end
    endgenerate
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(DELAY)) pipe_id(.clk(clk), .in(s0_id), .out(id_dl));

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

    //delay org and id by 5 for s8
    wire [26:0] orig_dl2 [0:2];
    wire [PIX_ID_W-1:0] id_dl2;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_ox2(.clk(clk), .in(orig_dl[0]), .out(orig_dl2[0]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_oy2(.clk(clk), .in(orig_dl[1]), .out(orig_dl2[1]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_oz2(.clk(clk), .in(orig_dl[2]), .out(orig_dl2[2]));
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(5)) pipe_id2(.clk(clk), .in(id_dl), .out(id_dl2));

    //s9 col0 +col1 for each row
    wire [26:0] s9_sum [0:2];
    fp_add add_r0(.clk(clk), .a(s8_p[0]), .b(s8_p[1]), .out(s9_sum[0]));
    fp_add add_r1(.clk(clk), .a(s8_p[3]), .b(s8_p[4]), .out(s9_sum[1]));
    fp_add add_r2(.clk(clk), .a(s8_p[6]), .b(s8_p[7]), .out(s9_sum[2]));

    wire [26:0] s9_col2 [0:2];
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_col2_r0(.clk(clk), .in(s8_p[2]), .out(s9_col2[0]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_col2_r1(.clk(clk), .in(s8_p[5]), .out(s9_col2[1]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_col2_r2(.clk(clk), .in(s8_p[8]), .out(s9_col2[2]));

    //delay org and id by 5 for s9
    wire [26:0] orig_dl3 [0:2];
    wire [PIX_ID_W-1:0] id_dl3;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_ox3(.clk(clk), .in(orig_dl2[0]), .out(orig_dl3[0]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_oy3(.clk(clk), .in(orig_dl2[1]), .out(orig_dl3[1]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_oz3(.clk(clk), .in(orig_dl2[2]), .out(orig_dl3[2]));
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(5)) pipe_id3(.clk(clk), .in(id_dl2), .out(id_dl3));

    //s10 sum + col2=ray direction
    wire [26:0] s10_rd [0:2];
    fp_add add_rd0(.clk(clk), .a(s9_sum[0]), .b(s9_col2[0]), .out(s10_rd[0]));
    fp_add add_rd1(.clk(clk), .a(s9_sum[1]), .b(s9_col2[1]), .out(s10_rd[1]));
    fp_add add_rd2(.clk(clk), .a(s9_sum[2]), .b(s9_col2[2]), .out(s10_rd[2]));

    wire [26:0] orig_dl4 [0:2];
    wire [PIX_ID_W-1:0] id_dl4;
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_ox4(.clk(clk), .in(orig_dl3[0]), .out(orig_dl4[0]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_oy4(.clk(clk), .in(orig_dl3[1]), .out(orig_dl4[1]));
    state_pipe #(.WIDTH(27), .DEPTH(5)) pipe_oz4(.clk(clk), .in(orig_dl3[2]), .out(orig_dl4[2]));
    state_pipe #(.WIDTH(PIX_ID_W), .DEPTH(5)) pipe_id4(.clk(clk), .in(id_dl3), .out(id_dl4));

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
            valid_out <= valid_sr[VSR_DEPTH-1];
        end
    end

    assign pipeline_ready = 1'b1;

endmodule

`default_nettype wire
