module feedback_ctrl_tb;

logic        clk;
logic        rst;

logic [10:0] x_pixel;
logic [9:0]  y_pixel;
logic        valid;
logic [19:0] pix_id;

logic [19:0] fb_pix_id;
logic [31:0] fb_pos_x;
logic [31:0] fb_pos_y;
logic [31:0] fb_pos_z;
logic [31:0] fb_ray_dir_x;
logic [31:0] fb_ray_dir_y;
logic [31:0] fb_ray_dir_z;
logic [7:0]  fb_iteration_count;
logic        fb_validity;

logic        pipeline_ready;

logic [10:0] out_x;
logic [9:0]  out_y;
logic [19:0] out_pix_id;
logic [31:0] out_pos_x;
logic [31:0] out_pos_y;
logic [31:0] out_pos_z;
logic [31:0] out_ray_dir_x;
logic [31:0] out_ray_dir_y;
logic [31:0] out_ray_dir_z;
logic [7:0]  out_iteration_count;
logic        out_validity;

logic        stall;

feedback_ctrl dut (
    .clk(clk),
    .rst(rst),
    .x_pixel(x_pixel),
    .y_pixel(y_pixel),
    .valid(valid),
    .pix_id(pix_id),
    .fb_pix_id(fb_pix_id),
    .fb_pos_x(fb_pos_x),
    .fb_pos_y(fb_pos_y),
    .fb_pos_z(fb_pos_z),
    .fb_ray_dir_x(fb_ray_dir_x),
    .fb_ray_dir_y(fb_ray_dir_y),
    .fb_ray_dir_z(fb_ray_dir_z),
    .fb_iteration_count(fb_iteration_count),
    .fb_validity(fb_validity),
    .pipeline_ready(pipeline_ready),
    .out_x(out_x),
    .out_y(out_y),
    .out_pix_id(out_pix_id),
    .out_pos_x(out_pos_x),
    .out_pos_y(out_pos_y),
    .out_pos_z(out_pos_z),
    .out_ray_dir_x(out_ray_dir_x),
    .out_ray_dir_y(out_ray_dir_y),
    .out_ray_dir_z(out_ray_dir_z),
    .out_iteration_count(out_iteration_count),
    .out_validity(out_validity),
    .stall(stall)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    $dumpfile("feedback_ctrl_tb.vcd");
    $dumpvars(0, feedback_ctrl_tb);
end

initial begin
    clk                = 1'b0;
    pipeline_ready     = 1'b0;
    valid              = 1'b0;
    x_pixel            = 11'd0;
    y_pixel            = 10'd0;
    pix_id             = 20'd0;
    fb_validity        = 1'b0;
    fb_pix_id          = 20'd0;
    fb_pos_x           = 32'd0;
    fb_pos_y           = 32'd0;
    fb_pos_z           = 32'd0;
    fb_ray_dir_x       = 32'd0;
    fb_ray_dir_y       = 32'd0;
    fb_ray_dir_z       = 32'd0;
    fb_iteration_count = 8'd0;

    rst = 1'b1;
    @(posedge clk);
    @(posedge clk);
    rst = 1'b0;

    // Scenario 1 - Fresh pixels only
    pipeline_ready     = 1'b1;
    valid              = 1'b1;
    x_pixel            = 11'd1000;
    y_pixel            = 10'd500;
    pix_id             = 20'd641000;
    fb_validity        = 1'b0;
    fb_pix_id          = 20'd0;
    fb_pos_x           = 32'd0;
    fb_pos_y           = 32'd0;
    fb_pos_z           = 32'd0;
    fb_ray_dir_x       = 32'd0;
    fb_ray_dir_y       = 32'd0;
    fb_ray_dir_z       = 32'd0;
    fb_iteration_count = 8'd0;
    @(posedge clk);
    @(negedge clk);

    if (out_x == x_pixel)
        $display("PASS: Output X is correct!");
    else
        $display("FAIL: Output X is incorrect!");

    if (out_y == y_pixel)
        $display("PASS: Output Y is correct!");
    else
        $display("FAIL: Output Y is incorrect!");

    if (out_pix_id == pix_id)
        $display("PASS: Output ID is correct!");
    else
        $display("FAIL: Output ID is incorrect!");

    if (out_validity)
        $display("PASS: Output Validity is correct!");
    else
        $display("FAIL: Output Validity is incorrect!");

    if (!stall)
        $display("PASS: FIFO is empty, no stall needed!");
    else
        $display("FAIL: Incorrect stall signal!");

    // Scenario 2 - Returning pixels only
    pipeline_ready     = 1'b1;
    valid              = 1'b0;
    x_pixel            = 11'd1000;
    y_pixel            = 10'd500;
    pix_id             = 20'd641000;
    fb_validity        = 1'b1;
    fb_pix_id          = 20'd641000;
    fb_pos_x           = 32'h3F800000;
    fb_pos_y           = 32'h40000000;
    fb_pos_z           = 32'h40400000;
    fb_ray_dir_x       = 32'h3F000000;
    fb_ray_dir_y       = 32'h3F000000;
    fb_ray_dir_z       = 32'h3F000000;
    fb_iteration_count = 8'd5;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    @(negedge clk);

    if (out_pix_id == fb_pix_id)
        $display("PASS: Output ID is correct!");
    else
        $display("FAIL: Output ID is incorrect!");

    if (out_validity)
        $display("PASS: Output Validity is correct!");
    else
        $display("FAIL: Output Validity is incorrect!");

    if (stall)
        $display("PASS: FIFO is not empty, stall correct!");
    else
        $display("FAIL: Incorrect stall signal!");

    // Scenario 3 - Mixed, returning pixels should take priority
    pipeline_ready     = 1'b1;
    valid              = 1'b1;
    x_pixel            = 11'd200;
    y_pixel            = 10'd100;
    pix_id             = 20'd128200;
    fb_validity        = 1'b1;
    fb_pix_id          = 20'd641000;
    fb_pos_x           = 32'h3F800000;
    fb_pos_y           = 32'h40000000;
    fb_pos_z           = 32'h40400000;
    fb_ray_dir_x       = 32'h3F000000;
    fb_ray_dir_y       = 32'h3F000000;
    fb_ray_dir_z       = 32'h3F000000;
    fb_iteration_count = 8'd10;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    @(negedge clk);

    if (out_pix_id == fb_pix_id)
        $display("PASS: Returning pixel took priority!");
    else
        $display("FAIL: Fresh pixel wrongly took priority!");

    if (out_x == 1'b0)
        $display("PASS: out_x correct for returning pixel!");
    else
        $display("FAIL: out_x should be 0 for returning pixel!");

    if (out_validity)
        $display("PASS: out_validity correct!");
    else
        $display("FAIL: out_validity incorrect!");

    if (stall)
        $display("PASS: stall correct - FIFO not empty!");
    else
        $display("FAIL: stall should be high!");

    $finish;

end

endmodule