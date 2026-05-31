`timescale 1ns/1ps
`default_nettype none

module tb_ray_gen;

localparam int PIPE_LAT = 35;

logic clk = 0;
always #5 clk = ~clk;

logic rst_n;
initial begin
    rst_n = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
end

logic [10:0] pix_x;
logic [9:0]  pix_y;
logic [19:0] pix_id_in;
logic valid_in;

logic [26:0] lookat [0:8];
logic [26:0] cam_origin [0:2];

logic [26:0] ray_orig [0:2];
logic [26:0] ray_dir  [0:2];
logic [19:0] pix_id_out;
logic valid_out;
logic pipeline_ready;

ray_gen dut (
    .clk(clk),
    .rst_n(rst_n),
    .pix_x(pix_x),
    .pix_y(pix_y),
    .pix_id_in(pix_id_in),
    .valid_in(valid_in),
    .lookat(lookat),
    .cam_origin(cam_origin),
    .ray_orig(ray_orig),
    .ray_dir(ray_dir),
    .pix_id_out(pix_id_out),
    .valid_out(valid_out),
    .pipeline_ready(pipeline_ready)
);

// decode 27-bit float
function automatic real fp27(input logic [26:0] f);
    real m; int e;
    if (f[25:18] == 0) return 0.0;
    e = int'(f[25:18]) - 127;
    m = 1.0 + real'(f[17:0]) / 262144.0;
    return f[26] ? -(m*(2.0**e)) : (m*(2.0**e));
endfunction

// hardcoded 27-bit float constants (xsim does not support $ln)
// 1.0:   {1'b0, 8'h7F, 18'h0}     = 27'h1FC0000
// -1.0:  {1'b1, 8'h7F, 18'h0}     = 27'h5FC0000
// 2.0:   {1'b0, 8'h80, 18'h0}     = 27'h2000000
// 0.0:   27'h0
localparam logic [26:0] FP_ONE    = 27'h1FC0000;
localparam logic [26:0] FP_NEG1   = 27'h5FC0000;
localparam logic [26:0] FP_TWO    = 27'h2000000;
localparam logic [26:0] FP_ZERO   = 27'h0;

// set identity camera (looking down -Z, origin at z=2)
task set_identity_camera();
    lookat[0] <= FP_ONE;  lookat[1] <= FP_ZERO; lookat[2] <= FP_ZERO;
    lookat[3] <= FP_ZERO; lookat[4] <= FP_ONE;  lookat[5] <= FP_ZERO;
    lookat[6] <= FP_ZERO; lookat[7] <= FP_ZERO; lookat[8] <= FP_NEG1;
    cam_origin[0] <= FP_ZERO;
    cam_origin[1] <= FP_ZERO;
    cam_origin[2] <= FP_TWO;
endtask

// send one pixel and wait for output
task send_pixel(
    input [10:0] px, input [9:0] py, input [19:0] pid,
    input string label,
    input real exp_dx, input real exp_dy, input real exp_dz
);
    real dx, dy, dz, mag, err;
    @(posedge clk);
    pix_x    <= px;
    pix_y    <= py;
    pix_id_in <= pid;
    valid_in <= 1;
    @(posedge clk);
    valid_in <= 0;
    repeat(PIPE_LAT) @(posedge clk);

    if (!valid_out) begin
        $display("  FAIL  %s: valid_out not asserted at cycle %0d", label, PIPE_LAT);
        return;
    end

    dx = fp27(ray_dir[0]);
    dy = fp27(ray_dir[1]);
    dz = fp27(ray_dir[2]);
    mag = $sqrt(dx*dx + dy*dy + dz*dz);

    // check unit length
    err = mag - 1.0; if (err < 0) err = -err;
    if (err < 0.02)
        $display("  PASS  %s unit length |ray|=%.4f", label, mag);
    else
        $display("  FAIL  %s unit length |ray|=%.4f (expected 1.0)", label, mag);

    // check direction if expected provided
    if (!(exp_dx == 0.0 && exp_dy == 0.0 && exp_dz == 0.0)) begin
        err = dx - exp_dx; if (err<0) err=-err;
        if (err < 0.02) $display("  PASS  %s dir.x=%.4f (expected %.4f)", label, dx, exp_dx);
        else            $display("  FAIL  %s dir.x=%.4f (expected %.4f)", label, dx, exp_dx);
        err = dy - exp_dy; if (err<0) err=-err;
        if (err < 0.02) $display("  PASS  %s dir.y=%.4f (expected %.4f)", label, dy, exp_dy);
        else            $display("  FAIL  %s dir.y=%.4f (expected %.4f)", label, dy, exp_dy);
        err = dz - exp_dz; if (err<0) err=-err;
        if (err < 0.02) $display("  PASS  %s dir.z=%.4f (expected %.4f)", label, dz, exp_dz);
        else            $display("  FAIL  %s dir.z=%.4f (expected %.4f)", label, dz, exp_dz);
    end

    // check pix_id passthrough
    if (pix_id_out === pid)
        $display("  PASS  %s pix_id=%0d correct", label, pid);
    else
        $display("  FAIL  %s pix_id=%0d (expected %0d)", label, pix_id_out, pid);
endtask

initial begin
    pix_x=0; pix_y=0; pix_id_in=0; valid_in=0;
    lookat[0]=27'h0; lookat[1]=27'h0; lookat[2]=27'h0;
    lookat[3]=27'h0; lookat[4]=27'h0; lookat[5]=27'h0;
    lookat[6]=27'h0; lookat[7]=27'h0; lookat[8]=27'h0;
    cam_origin[0]=27'h0; cam_origin[1]=27'h0; cam_origin[2]=27'h0;

    @(posedge rst_n);
    repeat(2) @(posedge clk);
    set_identity_camera();
    repeat(3) @(posedge clk);

    $display("\nTEST 1 pipeline_ready always 1");
    if (pipeline_ready === 1)
        $display("  PASS  pipeline_ready = 1");
    else
        $display("  FAIL  pipeline_ready = %0b", pipeline_ready);

    // centre pixel (640,360) with identity camera points straight forward = (0,0,-1)
    $display("\nTEST 2 centre pixel (640,360) expect (0,0,-1)");
    send_pixel(640, 360, 20'd1, "centre", 0.0, 0.0, -1.0);

    repeat(2) @(posedge clk);

    // top-left (0,0) should have x<0, y>0, z<0
    $display("\nTEST 3 top-left pixel (0,0) unit length check");
    send_pixel(0, 0, 20'd0, "top-left", 0.0, 0.0, 0.0);

    repeat(2) @(posedge clk);

    // bottom-right (1279,719) unit length
    $display("\nTEST 4 bottom-right (1279,719) unit length check");
    send_pixel(1279, 719, 20'd921599, "bot-right", 0.0, 0.0, 0.0);

    repeat(2) @(posedge clk);

    // camera origin passes through unchanged
    $display("\nTEST 5 cam_origin passes through");
    @(posedge clk);
    pix_x <= 640; pix_y <= 360; pix_id_in <= 20'd99; valid_in <= 1;
    @(posedge clk); valid_in <= 0;
    repeat(PIPE_LAT) @(posedge clk);
    begin
        real oz, err;
        oz = fp27(ray_orig[2]);
        err = oz - 2.0; if (err<0) err=-err;
        if (err < 0.01)
            $display("  PASS  ray_orig.z=%.4f (expected 2.0)", oz);
        else
            $display("  FAIL  ray_orig.z=%.4f (expected 2.0)", oz);
    end

    repeat(2) @(posedge clk);

    // monitor block checks every valid_out for unit length
    $display("\nAll ray_gen tests done");
    $finish;
end

// continuous monitor — print any output with valid_out=1
always_ff @(posedge clk) begin
    if (valid_out) begin
        real dx, dy, dz, mag, err;
        dx = fp27(ray_dir[0]);
        dy = fp27(ray_dir[1]);
        dz = fp27(ray_dir[2]);
        mag = $sqrt(dx*dx + dy*dy + dz*dz);
        err = mag - 1.0; if (err<0) err=-err;
        if (err >= 0.02)
            $display("  WARN  [monitor] pix=%0d |ray|=%.4f NOT unit length", pix_id_out, mag);
    end
end

endmodule

`default_nettype wire
