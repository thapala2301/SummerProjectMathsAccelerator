module ray_gen #(
    parameter int W           = 32, // fixed-point word width
    parameter int FRAC        = 29, // fractional bits
    parameter int IMG_W       = 1280,   // image width in pixels
    parameter int IMG_H       = 720,    // image height in pixels
    // FOV_Z in Q2.29: 1.0 → 90° hFOV.  Decrease for narrower, increase for wider.
    parameter logic signed [31:0] FOV_Z_CONST = 32'h2000_0000,  // 1.0 in Q2.29, normalised to screen half-width
    parameter int ISQRT_ITER  = 3,  // Newton-Raphson iterations for inv-sqrt (3 → ~28 bits accurate)
    parameter int PIX_ID_W    = 20   // log2(1280*720) < 20
) (
    input  logic                    clk,
    input  logic                    rst_n,          // active-low sync reset

    input  logic [10:0]             pix_x,          // 0 .. IMG_W-1  (11 bits)
    input  logic [9:0]              pix_y,          // 0 .. IMG_H-1  (10 bits)
    input  logic [PIX_ID_W-1:0]    pix_id_in,
    input  logic                    valid_in,

    // ---- Lookat matrix + origin from axi_camera_regs ----
    // lookat[row*3+col], Q2.29 signed
    input  logic signed [W-1:0]    lookat   [0:8],
    input  logic signed [W-1:0]    cam_origin [0:2],  // passed straight to output

    // ---- Output to march_core ----
    output logic signed [W-1:0]    ray_orig [0:2],   // = cam_origin, delayed
    output logic signed [W-1:0]    ray_dir  [0:2],   // unit direction in world space
    output logic [PIX_ID_W-1:0]    pix_id_out,
    output logic                    valid_out,

    output logic                    pipeline_ready
);

   
    localparam int HALF_W   = IMG_W / 2;   // screen centre x = 640
    localparam int HALF_H   = IMG_H / 2;   // screen centre y = 360
    // Stages: 1(reg) + 1(offset) + 1(raw dir) + 2(sq) + 1(sum) + ISQRT_cyc + 1(scale) + 3(matmul) + 1(out)
    localparam int ISQRT_CYC     = 2 + ISQRT_ITER * 2;  // initial guess(2) + iter*2
    localparam int PIPE_LATENCY  = 11 + ISQRT_CYC;


    function automatic logic signed [W-1:0] qmul (
        input logic signed [W-1:0] a,
        input logic signed [W-1:0] b
    );
        logic signed [2*W-1:0] prod;
        prod = a * b;
        return prod[W + FRAC - 1 : FRAC];
    endfunction

    // Input registration
    logic [10:0]          s0_px;
    logic [9:0]           s0_py;
    logic [PIX_ID_W-1:0]  s0_id;
    logic                 s0_v;
    logic signed [W-1:0]  s0_lk [0:8];
    logic signed [W-1:0]  s0_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s0_v <= 1'b0;
        end else begin
            s0_px   <= pix_x;
            s0_py   <= pix_y;
            s0_id   <= pix_id_in;
            s0_v    <= valid_in;
            s0_lk   <= lookat;
            s0_orig <= cam_origin;
        end
    end

    // STAGE 1 — Screen-space offset from image centre

    logic signed [W-1:0]  s1_dx, s1_dy;   // pixel-space, signed
    logic signed [W-1:0]  s1_fov_z;        // constant FOV component
    logic [PIX_ID_W-1:0]  s1_id;
    logic                 s1_v;
    logic signed [W-1:0]  s1_lk [0:8];
    logic signed [W-1:0]  s1_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s1_v <= 1'b0;
        end else begin
            // Store as simple signed integers (not yet Q2.29 scaled).
            s1_dx    <= $signed({1'b0, s0_px}) - $signed(HALF_W[W-1:0]);
            s1_dy    <= $signed(HALF_H[W-1:0]) - $signed({1'b0, s0_py});
            s1_fov_z <= FOV_Z_CONST;   // Q2.29 constant, represents 1.0 * HALF_W
            s1_id    <= s0_id;
            s1_v     <= s0_v;
            s1_lk    <= s0_lk;
            s1_orig  <= s0_orig;
        end
    end

    // STAGE 2 — Raw direction vector registered

    logic signed [W-1:0]  s2_dx, s2_dy, s2_dz;
    logic [PIX_ID_W-1:0]  s2_id;
    logic                 s2_v;
    logic signed [W-1:0]  s2_lk [0:8];
    logic signed [W-1:0]  s2_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) s2_v <= 1'b0;
        else begin
            s2_dx   <= s1_dx;
            s2_dy   <= s1_dy;
            s2_dz   <= s1_fov_z;   // z component is the FOV constant
            s2_id   <= s1_id;
            s2_v    <= s1_v;
            s2_lk   <= s1_lk;
            s2_orig <= s1_orig;
        end
    end

    // STAGE 3 — Squared components  (dx², dy², dz²)

    localparam int COORD_SHIFT = FRAC - 10;   // 19 for Q2.29

    logic signed [W-1:0]  s3_dx_q, s3_dy_q, s3_dz_q;
    logic signed [W-1:0]  s3_dx2,  s3_dy2,  s3_dz2;
    logic [PIX_ID_W-1:0]  s3_id;
    logic                 s3_v;
    logic signed [W-1:0]  s3_lk [0:8];
    logic signed [W-1:0]  s3_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) s3_v <= 1'b0;
        else begin
            // Shift pixel coords into Q2.29 normalised space
            s3_dx_q <= s2_dx <<< COORD_SHIFT;
            s3_dy_q <= s2_dy <<< COORD_SHIFT;
            s3_dz_q <= s2_dz;                   // already Q2.29 (FOV constant)

            // Squared magnitudes (Q2.29 × Q2.29 → Q2.29)
            s3_dx2  <= qmul(s2_dx <<< COORD_SHIFT, s2_dx <<< COORD_SHIFT);
            s3_dy2  <= qmul(s2_dy <<< COORD_SHIFT, s2_dy <<< COORD_SHIFT);
            s3_dz2  <= qmul(s2_dz,                 s2_dz);

            s3_id   <= s2_id;
            s3_v    <= s2_v;
            s3_lk   <= s2_lk;
            s3_orig <= s2_orig;
        end
    end

    // STAGE 4 — Sum of squares → |d|²
    logic signed [W-1:0]  s4_dx_q, s4_dy_q, s4_dz_q;
    logic signed [W-1:0]  s4_mag2;
    logic [PIX_ID_W-1:0]  s4_id;
    logic                 s4_v;
    logic signed [W-1:0]  s4_lk [0:8];
    logic signed [W-1:0]  s4_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) s4_v <= 1'b0;
        else begin
            s4_dx_q  <= s3_dx_q;
            s4_dy_q  <= s3_dy_q;
            s4_dz_q  <= s3_dz_q;
            s4_mag2  <= s3_dx2 + s3_dy2 + s3_dz2;
            s4_id    <= s3_id;
            s4_v     <= s3_v;
            s4_lk    <= s3_lk;
            s4_orig  <= s3_orig;
        end
    end

    // STAGES 5..4+ISQRT_CYC — Iterative inverse square root (Newton-Raphson)

    // Signals entering the isqrt pipe
    logic signed [W-1:0]  isqrt_x_in;
    logic                 isqrt_v_in;

    // Companion data that must be delay-matched through the isqrt pipe.
    logic signed [W-1:0]  isqrt_dx_q_delayed [0:ISQRT_CYC];
    logic signed [W-1:0]  isqrt_dy_q_delayed [0:ISQRT_CYC];
    logic signed [W-1:0]  isqrt_dz_q_delayed [0:ISQRT_CYC];
    logic [PIX_ID_W-1:0]  isqrt_id_delayed   [0:ISQRT_CYC];
    logic signed [W-1:0]  isqrt_lk_delayed   [0:ISQRT_CYC][0:8];
    logic signed [W-1:0]  isqrt_orig_delayed [0:ISQRT_CYC][0:2];

    // Drive the head of each delay chain from stage 4
    assign isqrt_dx_q_delayed[0]   = s4_dx_q;
    assign isqrt_dy_q_delayed[0]   = s4_dy_q;
    assign isqrt_dz_q_delayed[0]   = s4_dz_q;
    assign isqrt_id_delayed[0]     = s4_id;
    assign isqrt_lk_delayed[0]     = s4_lk;
    assign isqrt_orig_delayed[0]   = s4_orig;

    genvar gi2;
    generate
        for (gi2 = 0; gi2 < ISQRT_CYC; gi2++) begin : gen_delay
            always_ff @(posedge clk) begin
                isqrt_dx_q_delayed[gi2+1]   <= isqrt_dx_q_delayed[gi2];
                isqrt_dy_q_delayed[gi2+1]   <= isqrt_dy_q_delayed[gi2];
                isqrt_dz_q_delayed[gi2+1]   <= isqrt_dz_q_delayed[gi2];
                isqrt_id_delayed  [gi2+1]   <= isqrt_id_delayed[gi2];
                isqrt_lk_delayed  [gi2+1]   <= isqrt_lk_delayed[gi2];
                isqrt_orig_delayed[gi2+1]   <= isqrt_orig_delayed[gi2];
            end
        end
    endgenerate

    // Outputs from isqrt_pipe
    logic signed [W-1:0]  inv_mag;     // 1/|d| in Q2.29
    logic                 isqrt_v_out;

    isqrt_pipe #(
        .W          (W),
        .FRAC       (FRAC),
        .NUM_ITER   (ISQRT_ITER)
    ) u_isqrt (
        .clk        (clk),
        .rst_n      (rst_n),
        .x_in       (s4_mag2),
        .valid_in   (s4_v),
        .y_out      (inv_mag),
        .valid_out  (isqrt_v_out)
    );

    // STAGE 5+ISQRT_CYC — Scale: d_norm = d × inv_mag  (3 multiplies)
    logic signed [W-1:0]  s6_dnx, s6_dny, s6_dnz;   // normalised direction
    logic [PIX_ID_W-1:0]  s6_id;
    logic                 s6_v;
    logic signed [W-1:0]  s6_lk [0:8];
    logic signed [W-1:0]  s6_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) s6_v <= 1'b0;
        else begin
            s6_dnx  <= qmul(isqrt_dx_q_delayed[ISQRT_CYC], inv_mag);
            s6_dny  <= qmul(isqrt_dy_q_delayed[ISQRT_CYC], inv_mag);
            s6_dnz  <= qmul(isqrt_dz_q_delayed[ISQRT_CYC], inv_mag);
            s6_id   <= isqrt_id_delayed  [ISQRT_CYC];
            s6_v    <= isqrt_v_out;
            s6_lk   <= isqrt_lk_delayed  [ISQRT_CYC];
            s6_orig <= isqrt_orig_delayed[ISQRT_CYC];
        end
    end

    // STAGES 7–9 — 3×3 matrix multiply: ray_dir = lookat × d_norm
    // | r0 r1 r2 |   | dnx |   | row0·d |
    // | r3 r4 r5 | × | dny | = | row1·d |
    // | r6 r7 r8 |   | dnz |   | row2·d |

    // --- Stage 7: partial products ---
    logic signed [W-1:0]  s7_p [0:8];   // p[row*3+col] = lookat[row*3+col] * d[col]
    logic [PIX_ID_W-1:0]  s7_id;
    logic                 s7_v;
    logic signed [W-1:0]  s7_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) s7_v <= 1'b0;
        else begin
            for (int r = 0; r < 3; r++) begin
                s7_p[r*3+0] <= qmul(s6_lk[r*3+0], s6_dnx);
                s7_p[r*3+1] <= qmul(s6_lk[r*3+1], s6_dny);
                s7_p[r*3+2] <= qmul(s6_lk[r*3+2], s6_dnz);
            end
            s7_id   <= s6_id;
            s7_v    <= s6_v;
            s7_orig <= s6_orig;
        end
    end

    // --- Stage 8: row sums ---
    logic signed [W-1:0]  s8_rd [0:2];  // ray direction components
    logic [PIX_ID_W-1:0]  s8_id;
    logic                 s8_v;
    logic signed [W-1:0]  s8_orig [0:2];

    always_ff @(posedge clk) begin
        if (!rst_n) s8_v <= 1'b0;
        else begin
            for (int r = 0; r < 3; r++)
                s8_rd[r] <= s7_p[r*3+0] + s7_p[r*3+1] + s7_p[r*3+2];
            s8_id   <= s7_id;
            s8_v    <= s7_v;
            s8_orig <= s7_orig;
        end
    end

    // STAGE 9 — Output registration
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else begin
            ray_dir[0]  <= s8_rd[0];
            ray_dir[1]  <= s8_rd[1];
            ray_dir[2]  <= s8_rd[2];
            ray_orig[0] <= s8_orig[0];
            ray_orig[1] <= s8_orig[1];
            ray_orig[2] <= s8_orig[2];
            pix_id_out  <= s8_id;
            valid_out   <= s8_v;
        end
    end

    // pipeline_ready: always 1 — this pipeline never stalls
    assign pipeline_ready = 1'b1;

    // Pipeline latency assertion (synthesis-time check)
    initial begin
        $display("ray_gen: PIPE_LATENCY = %0d cycles", PIPE_LATENCY);
        $display("ray_gen: ISQRT_CYC    = %0d cycles", ISQRT_CYC);
    end

endmodule

