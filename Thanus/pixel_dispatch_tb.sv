module pixel_dispatch_tb;

logic        clk;
logic        rst;
logic        pipeline_ready;

logic [10:0] x_pixel;
logic [9:0]  y_pixel;
logic [19:0] pix_id;
logic        valid;

logic        seen [0:230399];
integer      counter;
integer      errors;

pixel_dispatch dut (
    .clk(clk),
    .rst(rst),
    .pipeline_ready(pipeline_ready),
    .x_pixel(x_pixel),
    .y_pixel(y_pixel),
    .pix_id(pix_id),
    .valid(valid)
);

initial clk = 1'b0;
always #5 clk = ~clk;

initial begin
    $dumpfile("tb_pixel_dispatch.vcd");
    $dumpvars(0, pixel_dispatch_tb);
end

initial begin
    errors         = 0;
    rst            = 1'b1;
    pipeline_ready = 1'b0;

    for (counter = 0; counter <= 230399; counter = counter + 1)
        seen[counter] = 1'b0;

    repeat(4) @(posedge clk);
    rst = 1'b0;
    pipeline_ready = 1'b1;

    @(posedge clk);

    repeat(921600) begin
        @(negedge clk);
        if (valid) begin
            seen[pix_id] = 1'b1;
        end
    end

    for (counter = 0; counter <= 230399; counter = counter + 1) begin
        if (!seen[counter]) begin
            $display("Error: pix_id %0d never emitted", counter);
            errors = errors + 1;
        end
    end

    if (errors == 0)
        $display("PASS: all 230400 BRAM addresses covered");
    else
        $display("FAIL: %0d errors found", errors);

    $finish;
end

endmodule