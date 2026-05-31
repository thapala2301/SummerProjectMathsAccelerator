`timescale 1ns/1ps
`default_nettype none

module ray_gen #(
    parameter int IMG_W = 1280,
    parameter int IMG_H = 720,
    parameter int PIX_ID_W = 20,
    parameter logic [26:0] FOV_Z_CONST = 27'h1FC0000
) (
    input wire logic clk,
    input wire logic rst_n,

    input wire logic [10:0] pix_x,
    input wire logic [9:0] pix_y,
    input wire logic [PIX_ID_W-1:0] pix_id_in,
    input wire logic valid_in,

    input wire logic [26:0] lookat [0:8],
    input wire logic [26:0] cam_origin [0:2],


    output logic [26:0] ray_orig [0:2],
    output logic [26:0] ray_dir [0:2],
    output logic [PIX_ID_W-1:0] pix_id_out,
    output logic valid_out,
    output logic pipeline_ready
);

    localparam int HALF_W = IMG_W / 2;
    localparam int HALF_H = IMG_H / 2;
    localparam int ISQRT_LAT = 5;
    localparam int PIPE_LATENCY = 11;

    function automatic logic [26:0] fp_mul(
        input logic [26:0] a,
        input logic [26:0] b
    );
        logic s;
        logic [7:0] ea, eb, exp_r;
        logic [18:0] ma, mb;
        logic [37:0] prod;
        logic [17:0] frac_r;

        if (a[25:18] == 8'h00 || b[25:18] == 8'h00) return 27'h0;

        s = a[26] ^ b[26];
        ea = a[25:18];
        eb = b[25:18];
        ma = {1'b1, a[17:0]};
        mb = {1'b1, b[17:0]};
        prod = ma * mb;

        if(prod[37]) begin
            frac_r = prod[36:19];
            exp_r = ea + eb - 127 + 1;
        end else begin
            frac_r = prod[35:18];
            exp_r = ea + eb - 127;
        end

        if(exp_r == 8'h00 || exp_r >= 8'hFF) return 27'h0;
        return {s, exp_r, frac_r};
    endfunction

    function automatic logic [26:0] fp_add(
        input logic [26:0] a,
        input logic [26:0] b
    );
        logic [7:0] ea, eb, er;
        logic [18:0] ma, mb;
        logic [7:0] exp_diff;
        logic [19:0] sr;
        logic sign_a, sign_b, sign_r;
        logic [4:0] lz;

        if (a[25:18] == 8'h00) return b;
        if (b[25:18] == 8'h00) return a;

        sign_a = a[26]; ea = a[25:18]; ma = {1'b1, a[17:0]};
        sign_b = b[26]; eb = b[25:18]; mb = {1'b1, b[17:0]};

        if(eb > ea) begin
            {sign_a, ea, ma, sign_b, eb, mb} = {sign_b, eb, mb, sign_a, ea, ma};
        end

        exp_diff = ea - eb;
        if(exp_diff >= 19) mb = 19'h0;
        else mb = mb >> exp_diff;
        er = ea;

        if(sign_a == sign_b) begin
            sr = {1'b0, ma} + {1'b0, mb};
            sign_r = sign_a;
            if(sr[19]) begin
                sr = sr >> 1;
                er = er + 1;
            end
        end else begin
            sr = {1'b0, ma} - {1'b0, mb};
            sign_r = sign_a;
            lz = 0;
            for(int i = 18; i >= 1; i--) begin
                if(!sr[i]) lz = lz + 1;
                else break;
            end
            sr = sr << lz;
            if(er >= lz) er = er - lz;
            else begin er = 0; return 27'h0; end
        end

        if(er == 8'h00 || sr[18:1] == 18'h0) return 27'h0;
        return {sign_r, er, sr[17:0]};
    endfunction

    function automatic logic [26:0] fp_int2fp(input logic signed [15:0] n);
        logic sign;
        logic [15:0] mag;
        logic [7:0] exp;
        logic [4:0] lz;
        logic [16:0] shifted;

        if(n == 0) return 27'h0;

        sign = n[15];
        mag = sign ? 16'(-n) : 16'(n);

        lz = 0;
        for(int i = 15; i >= 0; i--) begin
            if(!mag[i]) lz = lz + 1;
            else break;
        end

        exp = 8'(142 - lz);
        shifted = {mag, 1'b0} << lz;
        return {sign, exp, shifted[16:1], 2'b0};
    endfunction

    // S0 register inputs
    logic [10:0] s0_px;
    logic [9:0] s0_py;
    logic [PIX_ID_W-1:0] s0_id;
    logic s0_v;
    logic [26:0] s0_lk [0:8];
    logic [26:0] s0_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s0_v <= 1'b0;
        else begin
            s0_px <= pix_x;
            s0_py <= pix_y;
            s0_id <= pix_id_in;
            s0_v <= valid_in;
            s0_lk <= lookat;
            s0_orig <= cam_origin;
        end
    end

    // S1 pixel offset from centre
    logic signed [15:0] s1_dx, s1_dy;
    logic [26:0] s1_dz;
    logic [PIX_ID_W-1:0] s1_id;
    logic s1_v;
    logic [26:0] s1_lk [0:8];
    logic [26:0] s1_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s1_v <= 1'b0;
        else begin
            s1_dx <= 16'($signed({1'b0, s0_px}) - $signed(16'(HALF_W)));
            s1_dy <= 16'($signed(16'(HALF_H)) - $signed({1'b0, s0_py}));
            s1_dz <= FOV_Z_CONST;
            s1_id <= s0_id;
            s1_v <= s0_v;
            s1_lk <= s0_lk;
            s1_orig <= s0_orig;
        end
    end

    // S2 integer to float
    logic [26:0] s2_dx, s2_dy, s2_dz;
    logic [PIX_ID_W-1:0] s2_id;
    logic s2_v;
    logic [26:0] s2_lk [0:8];
    logic [26:0] s2_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s2_v <= 1'b0;
        else begin
            s2_dx <= fp_int2fp(s1_dx);
            s2_dy <= fp_int2fp(s1_dy);
            s2_dz <= s1_dz;
            s2_id <= s1_id;
            s2_v <= s1_v;
            s2_lk <= s1_lk;
            s2_orig <= s1_orig;
        end
    end

    // S3 squared components
    logic [26:0] s3_dx, s3_dy, s3_dz;
    logic [26:0] s3_dx2, s3_dy2, s3_dz2;
    logic [PIX_ID_W-1:0] s3_id;
    logic s3_v;
    logic [26:0] s3_lk [0:8];
    logic [26:0] s3_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s3_v <= 1'b0;
        else begin
            s3_dx <= s2_dx;
            s3_dy <= s2_dy;
            s3_dz <= s2_dz;
            s3_dx2 <= fp_mul(s2_dx, s2_dx);
            s3_dy2 <= fp_mul(s2_dy, s2_dy);
            s3_dz2 <= fp_mul(s2_dz, s2_dz);
            s3_id <= s2_id;
            s3_v <= s2_v;
            s3_lk <= s2_lk;
            s3_orig <= s2_orig;
        end
    end

    // S4 sum of squares
    logic [26:0] s4_mag2;
    logic [26:0] s4_dx, s4_dy, s4_dz;
    logic [PIX_ID_W-1:0] s4_id;
    logic s4_v;
    logic [26:0] s4_lk [0:8];
    logic [26:0] s4_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s4_v <= 1'b0;
        else begin
            s4_mag2 <= fp_add(fp_add(s3_dx2, s3_dy2), s3_dz2);
            s4_dx <= s3_dx;
            s4_dy <= s3_dy;
            s4_dz <= s3_dz;
            s4_id <= s3_id;
            s4_v <= s3_v;
            s4_lk <= s3_lk;
            s4_orig <= s3_orig;
        end
    end

    // delay chains through isqrt
    logic [26:0] dl_dx [0:ISQRT_LAT];
    logic [26:0] dl_dy [0:ISQRT_LAT];
    logic [26:0] dl_dz [0:ISQRT_LAT];
    logic [PIX_ID_W-1:0] dl_id [0:ISQRT_LAT];
    logic [26:0] dl_lk [0:ISQRT_LAT][0:8];
    logic [26:0] dl_orig [0:ISQRT_LAT][0:2];

    assign dl_dx[0] = s4_dx;
    assign dl_dy[0] = s4_dy;
    assign dl_dz[0] = s4_dz;
    assign dl_id[0] = s4_id;
    assign dl_lk[0] = s4_lk;
    assign dl_orig[0] = s4_orig;

    genvar gi;
    generate
        for(gi = 0; gi < ISQRT_LAT; gi++) begin : gen_delay
            always_ff @(posedge clk) begin
                dl_dx[gi+1] <= dl_dx[gi];
                dl_dy[gi+1] <= dl_dy[gi];
                dl_dz[gi+1] <= dl_dz[gi];
                dl_id[gi+1] <= dl_id[gi];
                dl_lk[gi+1] <= dl_lk[gi];
                dl_orig[gi+1] <= dl_orig[gi];
            end
        end
    endgenerate

    logic [26:0] inv_mag;
    logic isqrt_v_out;

    isqrt_pipe u_isqrt (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(s4_mag2),
        .valid_in(s4_v),
        .y_out(inv_mag),
        .valid_out(isqrt_v_out)
    );

    // S10 normalise
    logic [26:0] s10_dnx, s10_dny, s10_dnz;
    logic [PIX_ID_W-1:0] s10_id;
    logic s10_v;
    logic [26:0] s10_lk [0:8];
    logic [26:0] s10_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s10_v <= 1'b0;
        else begin
            s10_dnx <= fp_mul(dl_dx[ISQRT_LAT], inv_mag);
            s10_dny <= fp_mul(dl_dy[ISQRT_LAT], inv_mag);
            s10_dnz <= fp_mul(dl_dz[ISQRT_LAT], inv_mag);
            s10_id <= dl_id[ISQRT_LAT];
            s10_v <= isqrt_v_out;
            s10_lk <= dl_lk[ISQRT_LAT];
            s10_orig <= dl_orig[ISQRT_LAT];
        end
    end

    // S11 matrix partial products
    logic [26:0] s11_p [0:8];
    logic [PIX_ID_W-1:0] s11_id;
    logic s11_v;
    logic [26:0] s11_orig [0:2];

    always_ff @(posedge clk) begin
        if(!rst_n) s11_v <= 1'b0;
        else begin
            for(int r = 0; r < 3; r++) begin
                s11_p[r*3+0] <= fp_mul(s10_lk[r*3+0], s10_dnx);
                s11_p[r*3+1] <= fp_mul(s10_lk[r*3+1], s10_dny);
                s11_p[r*3+2] <= fp_mul(s10_lk[r*3+2], s10_dnz);
            end
            s11_id <= s10_id;
            s11_v <= s10_v;
            s11_orig <= s10_orig;
        end
    end

    // S12 row sums and output
    always_ff @(posedge clk) begin
        if(!rst_n) valid_out <= 1'b0;
        else begin
            for(int r = 0; r < 3; r++)
                ray_dir[r] <= fp_add(fp_add(s11_p[r*3+0], s11_p[r*3+1]), s11_p[r*3+2]);
            ray_orig[0] <= s11_orig[0];
            ray_orig[1] <= s11_orig[1];
            ray_orig[2] <= s11_orig[2];
            pix_id_out <= s11_id;
            valid_out <= s11_v;
        end
    end

    assign pipeline_ready = 1'b1;

    initial $display("ray_gen PIPE_LATENCY = %0d", PIPE_LATENCY);

endmodule


`default_nettype wire //otherwise error bleed
