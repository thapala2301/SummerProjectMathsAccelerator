module pixel_dispatch_tb;

logic        clk;
logic        rst;
logic        pipeline_ready;

logic [10:0] x_pixel;
logic [9:0]  y_pixel;
logic [19:0] pix_id;
logic        valid;

logic        seen [0:921599];
integer      counter;
integer      errors;

// Instantiation
pixel_dispatch dut (
    .clk(clk),
    .rst(rst),
    .pipeline_ready(pipeline_ready),
    .x_pixel(x_pixel),
    .y_pixel(y_pixel),
    .pix_id(pix_id),
    .valid(valid)
);

// Clock Gen
initial clk = 1'b0;
always #5 clk = ~clk;

// Waveform Dump
initial begin
    $dumpfile("tb_pixel_dispatch.vcd");
    $dumpvars(0, pixel_dispatch_tb);
end

// Stimulus
initial begin
    errors         = 0;
    rst            = 1'b1;
    pipeline_ready = 1'b0;

    for (counter = 0; counter <= 921599; counter = counter + 1)
        seen[counter] = 1'b0;

    repeat(4) @(posedge clk);
    rst = 1'b0;
    pipeline_ready = 1'b1;

    @(posedge clk);

    // Checking for duplicate pixels
    repeat(921600) begin
        @(negedge clk);
        if (valid) begin
            if (seen[pix_id]) begin
                $display("Duplicate pixel: %0d x=%0d y=%0d", pix_id, x_pixel, y_pixel);
                errors = errors + 1;
            end else begin
                seen[pix_id] = 1'b1;
            end
        end
    end

    // Final Check
    for (counter = 0; counter <= 921599; counter = counter + 1) begin
        if (!seen[counter]) begin
            $display("Error: pixel %0d never emitted", counter);
            errors = errors + 1;
        end
    end

    if (errors == 0)
        $display("PASS: all 921600 pixels emitted exactly once");
    else
        $display("FAIL: %0d errors found", errors);

    $finish;
end

endmodule