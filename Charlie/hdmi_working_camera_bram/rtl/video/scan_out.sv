`timescale 1ns / 1ps

module scan_out (
    input  logic        clk_74_25,
    input  logic        rst_n,
    input  logic        write_bank,
    input  logic [7:0]  color_thresh_1,
    input  logic [7:0]  color_thresh_2,
    input  logic [7:0]  color_thresh_3,
    input  logic [2:0]  color_shift_1,
    input  logic [2:0]  color_shift_2,
    output logic [18:0] bram_addrb,
    input  logic [7:0]  bram_doutb,
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
logic        read_bank;
logic        timing_vsync_prev;
(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic write_bank_sync1;
(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) logic write_bank_sync2;
logic [9:0]  map_x;
logic [9:0]  map_y;
logic [18:0] offset;
logic        hsync_d1;
logic        vsync_d1;
logic        active_d1;
logic [11:0] pixel_x_d1;
logic [11:0] pixel_y_d1;
logic        hsync_d2;
logic        vsync_d2;
logic        active_d2;
logic [11:0] pixel_x_d2;
logic [11:0] pixel_y_d2;
logic        hsync_d3;
logic        vsync_d3;
logic        active_d3;
logic [11:0] pixel_x_d3;
logic [11:0] pixel_y_d3;
logic [23:0] palette_rgb;

hdmi_timing u_timing(
    .clk_74_25(clk_74_25),
    .rst_n(rst_n),
    .hsync(timing_hsync),
    .vsync(timing_vsync),
    .active_video(timing_active),
    .pixel_x(pixel_x),
    .pixel_y(pixel_y)
);

always_ff @(posedge clk_74_25) begin
    if (!rst_n) begin
        write_bank_sync1 <= 1'b0;
        write_bank_sync2 <= 1'b0;
        read_bank <= 1'b0;
        timing_vsync_prev <= 1'b0;
    end else begin
        write_bank_sync1 <= write_bank;
        write_bank_sync2 <= write_bank_sync1;
        timing_vsync_prev <= timing_vsync;
        if (timing_vsync && !timing_vsync_prev) begin
            read_bank <= write_bank_sync2;
        end
    end
end

assign map_x = pixel_x[11:1];
assign map_y = pixel_y[11:1];
assign offset = (map_y * 19'd512) + map_x;

always_ff @(posedge clk_74_25) begin
    if (!rst_n) begin
        bram_addrb <= 19'd0;
        hsync_d1 <= 1'b0;
        vsync_d1 <= 1'b0;
        active_d1 <= 1'b0;
        pixel_x_d1 <= 12'd0;
        pixel_y_d1 <= 12'd0;
    end else begin
        if (read_bank) begin
            bram_addrb <= 19'd153600 + offset;
        end else begin
            bram_addrb <= offset;
        end
        hsync_d1 <= timing_hsync;
        vsync_d1 <= timing_vsync;
        active_d1 <= timing_active;
        pixel_x_d1 <= pixel_x;
        pixel_y_d1 <= pixel_y;
    end
end

always_ff @(posedge clk_74_25) begin
    if (!rst_n) begin
        hsync_d2 <= 1'b0;
        vsync_d2 <= 1'b0;
        active_d2 <= 1'b0;
        pixel_x_d2 <= 12'd0;
        pixel_y_d2 <= 12'd0;
    end else begin
        hsync_d2 <= hsync_d1;
        vsync_d2 <= vsync_d1;
        active_d2 <= active_d1;
        pixel_x_d2 <= pixel_x_d1;
        pixel_y_d2 <= pixel_y_d1;
    end
end

always_ff @(posedge clk_74_25) begin
    if (!rst_n) begin
        hsync_d3 <= 1'b0;
        vsync_d3 <= 1'b0;
        active_d3 <= 1'b0;
        pixel_x_d3 <= 12'd0;
        pixel_y_d3 <= 12'd0;
    end else begin
        hsync_d3 <= hsync_d2;
        vsync_d3 <= vsync_d2;
        active_d3 <= active_d2;
        pixel_x_d3 <= pixel_x_d2;
        pixel_y_d3 <= pixel_y_d2;
    end
end

palette u_palette(
    .clk(clk_74_25),
    .rst_n(rst_n),
    .iter(bram_doutb),
    .rgb(palette_rgb)
);

always_ff @(posedge clk_74_25) begin
    if (!rst_n) begin
        hdmi_hsync <= 1'b0;
        hdmi_vsync <= 1'b0;
        hdmi_active <= 1'b0;
        hdmi_rgb <= 24'd0;
    end else begin
        hdmi_hsync <= hsync_d3;
        hdmi_vsync <= vsync_d3;
        hdmi_active <= active_d3;
        if (active_d3) begin
            hdmi_rgb <= palette_rgb;
        end else begin
            hdmi_rgb <= 24'd0;
        end
    end
end

endmodule
