`timescale 1ns / 1ps


module test_pattern_gen_wrapper(
    input  wire        clk_74_25,
    input  wire        rst_n,
    output wire [19:0] bram_addr,
    output wire [23:0] bram_data_in,
    output wire        bram_we
);
    test_pattern_gen inst(
        .clk_74_25(clk_74_25),
        .rst_n(rst_n),
        .bram_addr(bram_addr),
        .bram_data_in(bram_data_in),
        .bram_we(bram_we)
    );
endmodule

module framebuffer_bram_wrapper(
    input  wire        clka,
    input  wire        wea,
    input  wire [19:0] addra, 
    input  wire [23:0] dina,
    
    input  wire        clkb,
    input  wire [19:0] addrb,
    output wire [23:0] doutb
);
    framebuffer_bram inst(
        .clka(clka),
        .wea(wea),
        .addra(addra),
        .dina(dina),
        .clkb(clkb),
        .addrb(addrb),
        .doutb(doutb)
    );
endmodule

module scan_out_wrapper(
    input  wire        clk_74_25,
    input  wire        rst_n,
    output wire [19:0] bram_addrb,
    input  wire [23:0] bram_doutb,
    output wire        hdmi_hsync,
    output wire        hdmi_vsync,
    output wire        hdmi_active,
    output wire [23:0] hdmi_rgb
);
    scan_out inst(
        .clk_74_25(clk_74_25),
        .rst_n(rst_n),
        .bram_addrb(bram_addrb),
        .bram_doutb(bram_doutb),
        .hdmi_hsync(hdmi_hsync),
        .hdmi_vsync(hdmi_vsync),
        .hdmi_active(hdmi_active),
        .hdmi_rgb(hdmi_rgb)
    );
endmodule
