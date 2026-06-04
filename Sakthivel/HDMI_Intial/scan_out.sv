`timescale 1ns / 1ps

module scan_out (
    input  logic        clk_74_25,
    input  logic        rst_n,
    
    // Memory
    output logic [19:0] bram_addrb,
    input  logic [23:0] bram_doutb,
    
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

    // Mapping (Reverse the downsampling)
    // Map the 1280x720 coordinate to the 640x720 compressed array
    logic [19:0] linear_idx;
    assign linear_idx = (pixel_y * 20'd1280) + pixel_x;

    // Pipeline 1
    logic hsync_d1, vsync_d1, active_d1;
    
    always_ff @(posedge clk_74_25) begin
        if (!rst_n) begin
            bram_addrb <= 20'd0;
            hsync_d1   <= 1'b0;
            vsync_d1   <= 1'b0;
            active_d1  <= 1'b0;
        end else begin
            bram_addrb <= linear_idx[19:1]; // Divide by 2 to match BRAM compression
            
            hsync_d1  <= timing_hsync;
            vsync_d1  <= timing_vsync;
            active_d1 <= timing_active;
        end
    end

    // Pipeline 2
    logic hsync_d2, vsync_d2, active_d2;

    always_ff @(posedge clk_74_25) begin
        if (!rst_n) begin
            hsync_d2   <= 1'b0;
            vsync_d2   <= 1'b0;
            active_d2  <= 1'b0;
        end else begin
            hsync_d2   <= hsync_d1;
            vsync_d2   <= vsync_d1;
            active_d2  <= active_d1;
        end
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

    // Pipeline 3
    always_ff @(posedge clk_74_25) begin
        if (!rst_n) begin
            hdmi_hsync   <= 1'b0;
            hdmi_vsync   <= 1'b0;
            hdmi_active  <= 1'b0;
            hdmi_rgb     <= 24'd0;
        end else begin
            hdmi_hsync   <= hsync_d2;
            hdmi_vsync   <= vsync_d2;
            hdmi_active  <= active_d2;
            
            if (active_d2) begin
                hdmi_rgb <= bram_doutb; // Already decompressed to 24-bit RGB from the BRAM module
            end else begin
                hdmi_rgb <= 24'd0;
            end
        end
    end

endmodule
