`timescale 1ns/1ps

module isqrt_pipe (
    input logic clk,
    input logic rst_n,
    input logic [26:0] x_in,
    input logic valid_in,
    output logic [26:0] y_out,
    output logic valid_out
);
    localparam int LAT = 5;

    // valid tracking
    logic [LAT-1:0] valid_sr;
    always_ff @(posedge clk) begin
        if (!rst_n) valid_sr <= '0;
        else valid_sr <= {valid_sr[LAT-2:0], valid_in};
    end
    assign valid_out = valid_sr[LAT-1];

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

    localparam logic [26:0] MAGIC = 27'h2FDFBF0;
    localparam logic [26:0] ONE_POINT_FIVE = 27'h1FE0000;
    localparam logic [26:0] HALF = 27'h1F80000;

    // stage 1 magic seed
    logic [26:0] st1_guess, st1_x;

    always_ff @(posedge clk) begin
        st1_x <= x_in;
        st1_guess <= MAGIC - {1'b0, x_in[26:1]};
    end

    // stage 2 0.5 * x * y0^2
    logic [26:0] st2_corr_raw, st2_y0;

    always_ff @(posedge clk) begin
        automatic logic [26:0] y0_sq, half_x;
        y0_sq = fp_mul(st1_guess, st1_guess);
        half_x = fp_mul(HALF, st1_x);
        st2_corr_raw <= fp_mul(half_x, y0_sq);
        st2_y0 <= st1_guess;
    end

    // stage 3 fp_add alignment for 1.5 - corr_raw
    logic [7:0] st3_exp;
    logic [19:0] st3_sig_big, st3_sig_sml;
    logic st3_sign_big, st3_sign_sml;
    logic [26:0] st3_y0;

    always_ff @(posedge clk) begin
        automatic logic [26:0] b_neg;
        automatic logic [7:0] ea, eb, exp_diff;
        automatic logic [18:0] ma, mb;
        automatic logic sa, sb;

        b_neg = {~st2_corr_raw[26], st2_corr_raw[25:0]};

        sa = ONE_POINT_FIVE[26]; ea = ONE_POINT_FIVE[25:18]; ma = {1'b1, ONE_POINT_FIVE[17:0]};
        sb = b_neg[26]; eb = b_neg[25:18]; mb = {1'b1, b_neg[17:0]};

        if(eb > ea) begin
            automatic logic [7:0] tmp_e;
            automatic logic [18:0] tmp_m;
            automatic logic tmp_s;
            tmp_e = ea; tmp_m = ma; tmp_s = sa;
            ea = eb; ma = mb; sa = sb;
            eb = tmp_e; mb = tmp_m; sb = tmp_s;
        end

        exp_diff = ea - eb;
        if(exp_diff >= 19) mb = 19'h0;
        else mb = mb >> exp_diff;

        st3_exp <= ea;
        st3_sign_big <= sa;
        st3_sign_sml <= sb;
        st3_sig_big <= {1'b0, ma};
        st3_sig_sml <= {1'b0, mb};
        st3_y0 <= st2_y0;
    end

    // stage 4 fp_add normalise then y1 = y0 * correction
    always_ff @(posedge clk) begin
        automatic logic [19:0] sr;
        automatic logic sign_r;
        automatic logic [7:0] er;
        automatic logic [4:0] lz;
        automatic logic [26:0] correction;

        er = st3_exp;

        if(st3_sign_big == st3_sign_sml) begin
            sr = st3_sig_big + st3_sig_sml;
            sign_r = st3_sign_big;
            if(sr[19]) begin
                sr = sr >> 1;
                er = er + 1;
            end
        end else begin
            sr = st3_sig_big - st3_sig_sml;
            sign_r = st3_sign_big;
            lz = 0;
            for(int i = 18; i >= 1; i--) begin
                if(!sr[i]) lz = lz + 1;
                else break;
            end
            sr = sr << lz;
            if(er >= lz) er = er - lz;
            else begin er = 0; end
        end

        if(er == 8'h00 || sr[18:1] == 18'h0)
            correction = 27'h0;
        else
            correction = {sign_r, er, sr[17:0]};

        y_out <= fp_mul(st3_y0, correction);
    end

endmodule
