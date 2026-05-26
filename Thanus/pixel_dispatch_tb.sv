module pixel_dispatch_tb;

// Signal Declarations
logic        clk;
logic        rst;
logic        pipeline_ready;

logic [10:0] x_pixel;
logic [9:0]  y_pixel;
logic [19:0] pix_id;
logic        valid;

logic        seen [0:921599];
integer      counter;

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

// Clock Generation
initial clk = 1'b0;
always #5 clk = ~clk;

// Waveform Dump
initial begin
    $dumpfile("tb_pixel_dispatch.vcd");
    $dumpvars(0, pixel_dispatch_tb);
end

// Initialise seen array
initial begin
    for (counter = 0; counter <= 921599; counter = counter + 1) begin
        seen[counter] = 1'b0;
    end
end

// Stimulus
initial begin
    rst            = 1'b1;
    pipeline_ready = 1'b0;
    @(posedge clk);
    @(posedge clk);
    rst = 1'b0;

    pipeline_ready = 1'b1;
    repeat(922600) @(posedge clk);

    // Final check
    for (counter = 0; counter <= 921599; counter = counter + 1) begin
        if (!seen[counter])
            $display("Error: pixel %0d never emitted", counter);
    end
    $display("Check complete");
    $finish;
end

// Duplicate checking
always @(posedge clk) begin
    if (valid) begin
        if (seen[pix_id])
            $display("Duplicate pixel: %0d", pix_id);
        else
            seen[pix_id] = 1'b1;
    end
end

endmodule