`timescale 1ns/1ps
`default_nettype none

module tb_fp_ops;

logic clk = 0;
always #5 clk = ~clk;

function automatic real fp27(input logic [26:0] f);
    real m; int e;
    if (f[25:18] == 0) return 0.0;
    e = int'(f[25:18]) - 127;
    m = 1.0 + real'(f[17:0]) / 262144.0;
    return f[26] ? -(m * (2.0**e)) : (m * (2.0**e));
endfunction

localparam logic [26:0] FP_ZERO     = 27'h0000000;
localparam logic [26:0] FP_ONE      = 27'h1FC0000;
localparam logic [26:0] FP_TWO      = 27'h2000000;
localparam logic [26:0] FP_THREE    = 27'h2020000;
localparam logic [26:0] FP_HALF     = 27'h1F80000;
localparam logic [26:0] FP_NEG_HALF = 27'h5F80000;
localparam logic [26:0] FP_NEG_ONE  = 27'h5FC0000;
localparam logic [26:0] FP_1P5      = 27'h1FE0000;
localparam logic [26:0] FP_3P5      = 27'h2030000;
localparam logic [26:0] FP_4P5      = 27'h2048000;
localparam logic [26:0] FP_FOUR     = 27'h2040000;

task check_fp(input string label, input logic [26:0] got, input real expected, input real tol);
    real g, err;
    g = fp27(got);
    err = g - expected;
    if (err < 0) err = -err;
    if (err <= tol)
        $display("  PASS  %s = %.6f (expected %.6f)", label, g, expected);
    else
        $display("  FAIL  %s = %.6f (expected %.6f, err %.6f)", label, g, expected, err);
endtask

logic [26:0] mul_a, mul_b, mul_out;
fp_mul u_mul (.clk(clk), .a(mul_a), .b(mul_b), .out(mul_out));

logic [26:0] add_a, add_b, add_out;
fp_add u_add (.clk(clk), .a(add_a), .b(add_b), .out(add_out));

logic [26:0] sub_a, sub_b, sub_out;
fp_sub u_sub (.clk(clk), .a(sub_a), .b(sub_b), .out(sub_out));

logic [26:0] isqrt_in, isqrt_out;
fp_isqrt u_isqrt (.clk(clk), .a(isqrt_in), .out(isqrt_out));

logic [31:0] int_in;
logic [26:0] int_out;
int2fp u_int2fp (.in(int_in), .out(int_out));

initial begin
    mul_a = 27'h0; mul_b = 27'h0;
    add_a = 27'h0; add_b = 27'h0;
    sub_a = 27'h0; sub_b = 27'h0;
    isqrt_in = 27'h0;
    int_in = 32'h0;

    repeat(4) @(posedge clk);

    $display("\nTEST fp_mul");
    mul_a <= FP_TWO; mul_b <= FP_THREE;
    @(posedge clk); @(posedge clk); @(posedge clk);
    check_fp("2.0 * 3.0", mul_out, 6.0, 0.01);

    mul_a <= FP_HALF; mul_b <= FP_HALF;
    @(posedge clk); @(posedge clk); @(posedge clk);
    check_fp("0.5 * 0.5", mul_out, 0.25, 0.001);

    mul_a <= FP_NEG_ONE; mul_b <= FP_4P5;
    @(posedge clk); @(posedge clk); @(posedge clk);
    check_fp("-1.0 * 4.5", mul_out, -4.5, 0.01);

    $display("\nTEST fp_add");
    add_a <= FP_ONE; add_b <= FP_TWO;
    repeat(5) @(posedge clk);
    check_fp("1.0 + 2.0", add_out, 3.0, 0.01);

    add_a <= FP_HALF; add_b <= FP_NEG_HALF;
    repeat(5) @(posedge clk);
    check_fp("0.5 + (-0.5)", add_out, 0.0, 0.001);

    add_a <= FP_1P5; add_b <= FP_TWO;
    repeat(5) @(posedge clk);
    check_fp("1.5 + 2.0", add_out, 3.5, 0.01);

    $display("\nTEST fp_sub");
    sub_a <= FP_1P5; sub_b <= FP_HALF;
    repeat(5) @(posedge clk);
    check_fp("1.5 - 0.5", sub_out, 1.0, 0.01);

    sub_a <= FP_TWO; sub_b <= FP_THREE;
    repeat(5) @(posedge clk);
    check_fp("2.0 - 3.0", sub_out, -1.0, 0.01);

    $display("\nTEST fp_isqrt");
    @(posedge clk); isqrt_in <= FP_ONE;
    @(posedge clk); isqrt_in <= FP_ZERO;
    repeat(10) @(posedge clk);
    check_fp("1/sqrt(1.0)", isqrt_out, 1.0, 0.01);

    @(posedge clk); isqrt_in <= FP_FOUR;
    @(posedge clk); isqrt_in <= FP_ZERO;
    repeat(10) @(posedge clk);
    check_fp("1/sqrt(4.0)", isqrt_out, 0.5, 0.01);

    $display("\nTEST int2fp");
    int_in = 32'sd536870912; #1;
    check_fp("int2fp(1.0)", int_out, 1.0, 0.01);

    int_in = 32'sd268435456; #1;
    check_fp("int2fp(0.5)", int_out, 0.5, 0.01);

    int_in = -32'sd536870912; #1;
    check_fp("int2fp(-1.0)", int_out, -1.0, 0.01);

    int_in = 32'd0; #1;
    check_fp("int2fp(0.0)", int_out, 0.0, 0.01);

    $display("\nAll FP tests done");
    $finish;
end

endmodule

`default_nettype wire
