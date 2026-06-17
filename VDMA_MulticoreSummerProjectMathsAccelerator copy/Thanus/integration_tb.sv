// pixel_dispatch -> feedback_ctrl -> fb_write
// Currently skeleton - needs Vincent's hit/miss logic to come through

// 1: Jai takes pixel coordinates from me and converts into 3D ray directions
// Main thing is that he sends pipeline_ready back to me so we know to
// accept the next pixel

// 2: Vincent is gonna take the ray from Jai and march it thru to the
// Menger Sponge. He is the one that evaluates distances and calculates
// how much to step by. His HIT/MISS logic will dictate whether I need to
// iterate through the pixels again via feedback loop or call upon the
// next fresh pixel.

// 3: Sakthi converts iteration count to RGB colour and sends it to
// fb_write. fb_write then writes that colour to the correct BRAM address.

module integration_tb;

logic        clk;
logic        rst;

// pixel_dispatch -> feedback_ctrl
logic [10:0] x_pixel;
logic [9:0]  y_pixel;
logic        valid;
logic [19:0] pix_id;

// Vincent -> feedback_ctrl (feedback path)
logic [19:0] fb_pix_id;
logic [31:0] fb_pos_x;
logic [31:0] fb_pos_y;
logic [31:0] fb_pos_z;
logic [31:0] fb_ray_dir_x;
logic [31:0] fb_ray_dir_y;
logic [31:0] fb_ray_dir_z;
logic [7:0]  fb_iteration_count;
logic        fb_validity;

// Jai -> feedback_ctrl
logic        pipeline_ready;

// feedback_ctrl -> Vincent
logic [10:0] out_x;
logic [9:0]  out_y;
logic [19:0] out_pix_id;
logic [26:0] out_pos_x;
logic [26:0] out_pos_y;
logic [26:0] out_pos_z;
logic [26:0] out_ray_dir_x;
logic [26:0] out_ray_dir_y;
logic [26:0] out_ray_dir_z;
logic [7:0]  out_iteration_count;
logic        out_validity;
logic        stall;

// Vincent -> fb_write
logic [19:0] done_pix_id;
logic        pix_done;
logic        hit;

// Sakthi Colour Stuff -> fb_write
logic [23:0] rgb;

// fb_write -> BRAM
logic [19:0] bram_addr;
logic [23:0] bram_data_in;
logic        bram_we;

// BRAM
logic [23:0] bram [0:230399];

// Seen array for checking
logic        seen [0:230399];
integer      counter;

// Module instantiations
pixel_dispatch dispatch_inst (
    .clk(clk),
    .rst(rst),
    .pipeline_ready(pipeline_ready),
    .x_pixel(x_pixel),
    .y_pixel(y_pixel),
    .pix_id(pix_id),
    .valid(valid)
);

feedback_ctrl feedback_inst (
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

fb_write fb_write_inst (
    .clk(clk),
    .rst(rst),
    .pix_id(done_pix_id),
    .pix_done(pix_done),
    .hit(hit),
    .rgb(rgb),
    .bram_addr(bram_addr),
    .bram_data_in(bram_data_in),
    .bram_we(bram_we)
);

// Clock Gen
initial clk = 1'b0;
always #5 clk = ~clk;

// Waveform Dump
initial begin
    $dumpfile("integration_tb.vcd");
    $dumpvars(0, integration_tb);
end

// Sakthi
always @(posedge clk) begin
    rgb <= 24'hFF0000;
end

// BRAM write and seen tracking
always @(posedge clk) begin
    if (bram_we) begin
        bram[bram_addr] <= bram_data_in;
        seen[bram_addr] <= 1;
    end
end

// Stimulus
initial begin
    pipeline_ready     = 1'b0;
    fb_validity        = 1'b0;
    fb_pix_id          = 20'd0;
    fb_pos_x           = 32'd0;
    fb_pos_y           = 32'd0;
    fb_pos_z           = 32'd0;
    fb_ray_dir_x       = 32'd0;
    fb_ray_dir_y       = 32'd0;
    fb_ray_dir_z       = 32'd0;
    fb_iteration_count = 8'd0;
    pix_done           = 1'b0;
    hit                = 1'b0;
    done_pix_id        = 20'd0;
    rgb                = 24'd0;

    for (counter = 0; counter <= 230399; counter = counter + 1)
        seen[counter] = 0;

    rst = 1'b1;
    @(posedge clk);
    @(posedge clk);
    rst = 1'b0;

    pipeline_ready = 1'b1;

    // TODO: Add Vincent stub here when ready
    // feedback_ctrl sends out_pix_id, out_pos, out_ray and out_iter to Vincent
    // Vincent will do either one or the other:
    // a) HIT/MISS → send pix_done, done_pix_id and hit flag to fb_write
    // b) FEEDBACK → send fb_validity + all fb_ signals back to feedback_ctrl

    repeat(2000000) @(posedge clk);

    // Final check
    for (counter = 0; counter <= 230399; counter = counter + 1) begin
        if (!seen[counter])
            $display("Error: pixel %0d never written to BRAM", counter);
    end
    $display("Integration check complete");
    $finish;

end

endmodule