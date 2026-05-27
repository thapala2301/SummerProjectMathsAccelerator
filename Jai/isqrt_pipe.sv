//pipelined inverse square root  y = 1 / sqrt(x)
//newton-Raphson iteration y_{n+1} = y_n * (1.5 - 0.5 * x * y_n²)
//Latency 2 (initial guess) + NUM_ITER * 2 cycles
// Fixed point Q2.29 signed

module isqrt_pipe #(
    parameter int W        = 32,
    parameter int FRAC     = 29,
    parameter int NUM_ITER = 3
) (
    input  logic              clk,
    input  logic              rst_n,

    input  logic signed [W-1:0]  x_in,       // Q2.29, must be positive
    input  logic                 valid_in,

    output logic signed [W-1:0]  y_out,       // Q2.29 ≈ 1/sqrt(x_in)
    output logic                 valid_out
);

    //Q2.29 multiply
    function automatic logic signed [W-1:0] qmul (
        input logic signed [W-1:0] a,
        input logic signed [W-1:0] b
    );
        logic signed [2*W-1:0] p;
        p = a * b;
        return p[W + FRAC - 1 : FRAC];
    endfunction

    // Constants in Q2.29
    localparam logic signed [W-1:0] ONE_POINT_FIVE = 32'h3000_0000; // 1.5
    localparam logic signed [W-1:0] HALF           = 32'h1000_0000; // 0.5

    //Initial guess
    logic                 st0_v;

    // Leading-zero count
    logic [4:0] lzc;
    always_comb begin : lzc_block
        lzc = 5'd31;
        for (int b = W-2; b >= 0; b--) begin
            if (x_in[b]) lzc = 5'(W - 1 - b);
        end
    end

    function automatic logic signed [W-1:0] seed_lut(input logic [4:0] lz);
        // 1/sqrt(value) ~ 2^(-(lz-FRAC+1)/2) in Q2.29
        // = 2^(FRAC - (lz-FRAC+1)/2) in integer terms
        case (lz)
            5'd0:  return 32'h0800_0000;  // ~0.25  (x≈4)
            5'd1:  return 32'h0B50_4F33;  // ~0.354
            5'd2:  return 32'h1000_0000;  // ~0.5
            5'd3:  return 32'h16A0_9E66;  // ~0.707
            5'd4:  return 32'h2000_0000;  // ~1.0
            5'd5:  return 32'h2D41_3CCD;  // ~1.414
            5'd6:  return 32'h4000_0000;  // ~2.0    (x≈0.016)
            default: return 32'h2000_0000;
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) st0_v <= 1'b0;
        else begin
            st0_x    <= x_in;
            st0_seed <= seed_lut(lzc);
            st0_v    <= valid_in;
        end
    end

    //Newton-Raphson iteration

    // Arrays of pipeline regs for x and y
    logic signed [W-1:0] iter_x [0:NUM_ITER];
    logic signed [W-1:0] iter_y [0:NUM_ITER];
    logic                iter_v [0:NUM_ITER];

    // Intermediate per-iteration register (between stage A and B)
    logic signed [W-1:0] mid_x  [0:NUM_ITER-1];
    logic signed [W-1:0] mid_y  [0:NUM_ITER-1];
    logic signed [W-1:0] mid_c  [0:NUM_ITER-1];  // correction = 1.5 - 0.5*x*y²
    logic                mid_v  [0:NUM_ITER-1];

    // Seed feeds iteration 0
    assign iter_x[0] = st0_x;
    assign iter_y[0] = st0_seed;
    assign iter_v[0] = st0_v;

    generate
        genvar it;
        for (it = 0; it < NUM_ITER; it++) begin : gen_nr

            // Stage A: y² then 0.5*x*y²,  correction = 1.5 - 0.5*x*y²
            always_ff @(posedge clk) begin
                if (!rst_n) mid_v[it] <= 1'b0;
                else begin
                    automatic logic signed [W-1:0] y2, half_x_y2;
                    y2          = qmul(iter_y[it], iter_y[it]);
                    half_x_y2   = qmul(qmul(HALF, iter_x[it]), y2);
                    mid_c[it]   <= ONE_POINT_FIVE - half_x_y2;
                    mid_y[it]   <= iter_y[it];
                    mid_x[it]   <= iter_x[it];
                    mid_v[it]   <= iter_v[it];
                end
            end

            // Stage B: y_new = y * correction
            always_ff @(posedge clk) begin
                if (!rst_n) iter_v[it+1] <= 1'b0;
                else begin
                    iter_y[it+1] <= qmul(mid_y[it], mid_c[it]);
                    iter_x[it+1] <= mid_x[it];
                    iter_v[it+1] <= mid_v[it];
                end
            end

        end
    endgenerate

    // Output
    assign y_out    = iter_y[NUM_ITER];
    assign valid_out = iter_v[NUM_ITER];

endmodule

