`timescale 1ns / 1ps

module scan_out (
    input  logic        clk_74_25,
    input  logic        rst_n,
    input  logic        write_bank, 
    
    // Params
    input  logic [7:0]  color_thresh_1,
    input  logic [7:0]  color_thresh_2,
    input  logic [7:0]  color_thresh_3,
    input  logic [2:0]  color_shift_1,
    input  logic [2:0]  color_shift_2,
    
    // Memory
    output logic [20:0] bram_addrb,
    input  logic [7:0]  bram_doutb,
    
    // HDMI
    output logic        hdmi_hsync,
    output logic        hdmi_vsync,
    output logic        hdmi_active,
    output logic [23:0] hdmi_rgb
);

    logic        timing_hsync;
    logic        timing_vsync;
    logic        timing_active;
    logic [11:0] pixel_x;
    logic [11:0] pixel_y;

    // Timing
    hdmi_timing u_timing (
        .clk_74_25    (clk_74_25),
        .rst_n        (rst_n),
        .hsync        (timing_hsync),
        .vsync        (timing_vsync),
        .active_video (timing_active),
        .pixel_x      (pixel_x),
        .pixel_y      (pixel_y)
    );

    // Buffering
    logic read_bank;
    logic timing_vsync_prev;
    
    always_ff @(posedge clk_74_25)
        if (!rst_n) begin
            read_bank         <= 1'b0;
            timing_vsync_prev <= 1'b0;
            end
        else begin
            timing_vsync_prev <= timing_vsync;
            if (timing_vsync && !timing_vsync_prev)
                read_bank <= write_bank;
            end

    // Mapping (Teammate's full resolution version)
    logic [20:0] offset;
    assign offset = (pixel_y * 21'd1280) + pixel_x;

    // Pipeline 1
    logic hsync_d1, vsync_d1, active_d1;
    
    always_ff @(posedge clk_74_25)
        if (!rst_n) begin
            bram_addrb <= 21'd0;
            hsync_d1   <= 1'b0;
            vsync_d1   <= 1'b0;
            active_d1  <= 1'b0;
            end
        else begin
            if (read_bank)
                bram_addrb <= 21'd921600 + offset;
            else
                bram_addrb <= offset;
            
            hsync_d1  <= timing_hsync;
            vsync_d1  <= timing_vsync;
            active_d1 <= timing_active;
            end

    // Pipeline 2
    logic hsync_d2, vsync_d2, active_d2;

    always_ff @(posedge clk_74_25)
        if (!rst_n) begin
            hsync_d2   <= 1'b0;
            vsync_d2   <= 1'b0;
            active_d2  <= 1'b0;
            end
        else begin
            hsync_d2   <= hsync_d1;
            vsync_d2   <= vsync_d1;
            active_d2  <= active_d1;
            end

    // Pipeline 3
    always_ff @(posedge clk_74_25)
        if (!rst_n) begin
            hdmi_hsync   <= 1'b0;
            hdmi_vsync   <= 1'b0;
            hdmi_active  <= 1'b0;
            hdmi_rgb     <= 24'd0;
            end
        else begin
            hdmi_hsync   <= hsync_d2;
            hdmi_vsync   <= vsync_d2;
            hdmi_active  <= active_d2;
            
            if (active_d2)
                hdmi_rgb <= mapped_rgb;
            else
                hdmi_rgb <= 24'd0;
            end

    // Colors
    logic [23:0] mapped_rgb;
    
    iter_to_rgb u_color_map (
        .iter      (bram_doutb),
        .thresh_1  (color_thresh_1),
        .thresh_2  (color_thresh_2),
        .thresh_3  (color_thresh_3),
        .shift_1   (color_shift_1),
        .shift_2   (color_shift_2),
        .rgb       (mapped_rgb)
    );

endmodule
