//computes sqrt(x^2+y^2+z^2): length of vector/norm
//use that sqrtx = isqrtx * x, only need fp_mull on top of isqrt
//true sqrtx from newton raphson requires division, far too expensive.
//total clk: 22
module fp_length(
    input clk,
    input wire [26:0] x,
    input wire [26:0] y,
    input wire [26:0] z,
    output wire [26:0] out
);
wire [26:0] x2, y2, z2, tempadd_x2_y2, sum_x2_y2_z2, isqrt_sum, sqrt_sum, sum_delayed;


fp_mul mul_x_x (.clk(clk), .a(x), .b(x), .out(x2));
fp_mul mul_y_y (.clk(clk), .a(y), .b(y), .out(y2));
fp_mul mul_z_z (.clk(clk), .a(z), .b(z), .out(z2));
//2clk latency, parallel
fp_add add_x2_y2 (.clk(clk), .a(x2), .b(y2), .out(tempadd_x2_y2));
fp_add add_tempx2y2_z2(.clk(clk), .a(tempadd_x2_y2), .b(z2), .out(sum_x2_y2_z2));
//8 clk latency


//TOTAL up to here : 10 clk latency. so need value 10 clk later
//delay but 10 clk, then sum_x2_y2_z2 matches isqrt_sum delay
state_pipe #(.WIDTH(27), .DEPTH(10)) pipe_sum(.clk(clk), .in(sum_x2_y2_z2), .out(sum_delayed));
//compute isqrt
fp_isqrt inst_isqrt_sum(.clk(clk), .a(sum_x2_y2_z2), .out(isqrt_sum));
//mul (sqrtx)^-1 * x
fp_mul mul_final (.clk(clk), .a(isqrt_sum), .b(sum_delayed), .out(sqrt_sum));

assign out = sqrt_sum;



endmodule