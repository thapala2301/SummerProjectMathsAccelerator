module fb_write_tb;

logic        clk;
logic        rst;

logic [19:0] pix_id;
logic        pix_done;
logic        hit;

logic [23:0] rgb;
logic        rgb_valid;

logic [19:0] bram_addr;
logic [23:0] bram_data_in;
logic        bram_we;

// Instantiation
fb_write dut (
    .clk(clk),
    .rst(rst),
    .pix_id(pix_id),
    .pix_done(pix_done),
    .hit(hit),
    .rgb(rgb),
    .rgb_valid(rgb_valid),
    .bram_addr(bram_addr),
    .bram_data_in(bram_data_in),
    .bram_we(bram_we)
);

// Clock Gen
initial clk = 1'b0;
always #5 clk = ~clk;

// Waveform Dump
initial begin
    $dumpfile("fb_write_tb.vcd");
    $dumpvars(0, fb_write_tb);
end

// Stimulus
initial begin
    rst = 1'b1;
    @(posedge clk);
    @(posedge clk);
    rst = 1'b0;

    pix_done  = 1'b1;
    rgb_valid = 1'b1;
    pix_id    = 20'd6969;
    rgb       = 24'hFF0000;
    @(posedge clk);

    if (bram_we)
        $display("PASS: bram_we correct");
    else
        $display("FAIL: bram_we should be high");

    if (bram_addr == pix_id)
        $display("PASS: bram_addr correct");
    else
        $display("FAIL: bram_addr wrong");

    if (bram_data_in == rgb)
        $display("PASS: bram_data_in correct");
    else
        $display("FAIL: bram_data_in wrong");

    pix_done  = 1'b0;
    rgb_valid = 1'b1;
    @(posedge clk);

    if (!bram_we)
        $display("PASS: bram_we correct");
    else
        $display("FAIL: bram_we should be low");

    if (bram_addr == pix_id)
        $display("PASS: bram_addr correct");
    else
        $display("FAIL: bram_addr wrong");

    if (bram_data_in == rgb)
        $display("PASS: bram_data_in correct");
    else
        $display("FAIL: bram_data_in wrong");

    pix_done  = 1'b1;
    rgb_valid = 1'b0;
    @(posedge clk);

    if (!bram_we)
        $display("PASS: bram_we correct");
    else
        $display("FAIL: bram_we should be low");

    if (bram_addr == pix_id)
        $display("PASS: bram_addr correct");
    else
        $display("FAIL: bram_addr wrong");

    if (bram_data_in == rgb)
        $display("PASS: bram_data_in correct");
    else
        $display("FAIL: bram_data_in wrong");

    pix_done  = 1'b0;
    rgb_valid = 1'b0;
    @(posedge clk);

    if (!bram_we)
        $display("PASS: bram_we correct");
    else
        $display("FAIL: bram_we should be low");

    if (bram_addr == pix_id)
        $display("PASS: bram_addr correct");
    else
        $display("FAIL: bram_addr wrong");

    if (bram_data_in == rgb)
        $display("PASS: bram_data_in correct");
    else
        $display("FAIL: bram_data_in wrong");

    $finish;

end

endmodule