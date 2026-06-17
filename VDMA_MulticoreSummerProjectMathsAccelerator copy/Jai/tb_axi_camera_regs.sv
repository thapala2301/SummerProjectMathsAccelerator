`timescale 1ns/1ps
`default_nettype none

module tb_axi_camera_regs;

logic clk = 0;
always #5 clk = ~clk;

logic aresetn;
initial begin
    aresetn = 0;
    repeat(4) @(posedge clk);
    aresetn = 1;
end

logic [5:0]  awaddr;
logic        awvalid;
logic        awready;
logic [31:0] wdata;
logic [3:0]  wstrb;
logic        wvalid;
logic        wready;
logic [1:0]  bresp;
logic        bvalid;
logic        bready;
logic [5:0]  araddr;
logic        arvalid;
logic        arready;
logic [31:0] rdata;
logic [1:0]  rresp;
logic        rvalid;
logic        rready;

logic [26:0] lookat [0:8];
logic [26:0] cam_origin [0:2];

axi_camera_regs dut (
    .aclk(clk),
    .aresetn(aresetn),
    .s_axi_awaddr(awaddr),   .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata),     .s_axi_wstrb(wstrb),     .s_axi_wvalid(wvalid),  .s_axi_wready(wready),
    .s_axi_bresp(bresp),     .s_axi_bvalid(bvalid),   .s_axi_bready(bready),
    .s_axi_araddr(araddr),   .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata),     .s_axi_rresp(rresp),     .s_axi_rvalid(rvalid),  .s_axi_rready(rready),
    .lookat(lookat),
    .cam_origin(cam_origin)
);

function automatic real fp27_to_real(input logic [26:0] f);
    real mantissa;
    int exp_unbiased;
    if (f[25:18] == 8'h00) return 0.0;
    exp_unbiased = int'(f[25:18]) - 127;
    // 1.0 + fraction/262144.0 restores the implicit leading 1
    mantissa = 1.0 + real'(f[17:0]) / 262144.0;
    if (f[26])
        return -(mantissa * (2.0 ** exp_unbiased));
    else
        return  (mantissa * (2.0 ** exp_unbiased));
endfunction

localparam logic [26:0] FP27_POS_ONE  = 27'h1FC0000; // 1.0
localparam logic [26:0] FP27_NEG_ONE  = 27'h5FC0000; // -1.0
// 0.70711 = 1.41421*2^-1, exp=126=0x7E, frac=int(0.41421*262144)=0x1A827
localparam logic [26:0] FP27_0707     = 27'h1F9A827; // ~0.70711
localparam logic [26:0] FP27_4P5      = 27'h2048000; // 4.5

task axi_write(input [5:0] addr, input [31:0] data);
    @(posedge clk);
    awaddr  <= addr;   awvalid <= 1;
    wdata   <= data;   wstrb   <= 4'hF;   wvalid <= 1;
    bready  <= 1;
    @(posedge clk);
    while (!(awready && wready)) @(posedge clk);
    awvalid <= 0;   wvalid <= 0;
    while (!bvalid) @(posedge clk);
    @(posedge clk);
    bready <= 0;
endtask

task axi_read(input [5:0] addr, output logic [31:0] data);
    @(posedge clk);
    araddr  <= addr;   arvalid <= 1;
    rready  <= 1;
    @(posedge clk);
    while (!rvalid) @(posedge clk);
    data    = rdata;
    arvalid <= 0;
    @(posedge clk);
    rready <= 0;
endtask

task check(input string label, input logic [26:0] got, input real expected);
    real g, err;
    g = fp27_to_real(got);
    err = g - expected;
    if (err < 0) err = -err;
    if (err < 0.002)
        $display("  PASS  %s = %f (expected %f)", label, g, expected);
    else
        $display("  FAIL  %s = %f (expected %f)", label, g, expected);
endtask

logic [31:0] rd;

initial begin
    awvalid=0; wvalid=0; bready=0;
    arvalid=0; rready=0;
    awaddr=0; wdata=0; wstrb=0; araddr=0;

    @(posedge aresetn);
    repeat(2) @(posedge clk);

    $display("\nTEST 1 reset defaults (identity camera)");
    check("right.x",   lookat[0],     1.0);
    check("right.y",   lookat[1],     0.0);
    check("right.z",   lookat[2],     0.0);
    check("up.x",      lookat[3],     0.0);
    check("up.y",      lookat[4],     1.0);
    check("up.z",      lookat[5],     0.0);
    check("fwd.x",     lookat[6],     0.0);
    check("fwd.y",     lookat[7],     0.0);
    check("fwd.z",     lookat[8],    -1.0);
    check("origin.x",  cam_origin[0], 0.0);
    check("origin.y",  cam_origin[1], 0.0);
    check("origin.z",  cam_origin[2], 0.0);

    $display("\nTEST 2 write 0.707 to lookat[0] (right.x)");
    axi_write(6'h00, {5'h0, FP27_0707});
    @(posedge clk);
    check("lookat[0] after write", lookat[0], 0.707);

    $display("\nTEST 3 write cam_origin.z = 4.5");
    axi_write(6'h2C, {5'h0, FP27_4P5});
    @(posedge clk);
    check("cam_origin.z after write", cam_origin[2], 4.5);


    $display("\nTEST 4 AXI read back lookat[0]");
    axi_read(6'h00, rd);
    check("AXI read lookat[0]", rd[26:0], 0.707);

    $display("\nTEST 5 out-of-range address 0x30 is ignored");
    axi_write(6'h30, 32'hDEADBEEF);
    @(posedge clk);
    check("lookat[0] unchanged", lookat[0], 0.707);


    $display("\nTEST 6 write full identity matrix");
    axi_write(6'h00, {5'h0, FP27_POS_ONE});
    axi_write(6'h04, 32'h0);
    axi_write(6'h08, 32'h0);
    axi_write(6'h0C, 32'h0);
    axi_write(6'h10, {5'h0, FP27_POS_ONE});
    axi_write(6'h14, 32'h0);
    axi_write(6'h18, 32'h0);
    axi_write(6'h1C, 32'h0);
    axi_write(6'h20, {5'h0, FP27_NEG_ONE});
    axi_write(6'h24, 32'h0);
    axi_write(6'h28, 32'h0);
    axi_write(6'h2C, 32'h0);
    @(posedge clk);
    check("right.x",  lookat[0],  1.0);
    check("up.y",     lookat[4],  1.0);
    check("fwd.z",    lookat[8], -1.0);
    check("origin.z", cam_origin[2], 0.0);

    $display("\nAll axi_camera_regs tests done");
    $finish;
end

endmodule

`default_nettype wire
