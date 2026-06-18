`timescale 1ns / 1ps

module palette (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  iter,
    input  logic [23:0] bg_rgb,
    input  logic [23:0] shape_rgb,
    output logic [23:0] rgb
);

    logic [7:0] iter_d1;
    logic [7:0] iter_d2;
    logic [23:0] palette_rom [0:255];
    logic [23:0] palette_rgb_d1;
    logic [23:0] shape_rgb_d1;
    logic [23:0] tinted_rgb;
    integer idx;

    function automatic [23:0] tint_rgb(input [23:0] base_rgb, input [23:0] tint);
        reg [15:0] red_mul;
        reg [15:0] green_mul;
        reg [15:0] blue_mul;
        begin
            red_mul = base_rgb[23:16] * tint[23:16];
            green_mul = base_rgb[15:8] * tint[15:8];
            blue_mul = base_rgb[7:0] * tint[7:0];
            tint_rgb = {red_mul[15:8], green_mul[15:8], blue_mul[15:8]};
        end
    endfunction

    function automatic [23:0] palette_value(input integer step);
        integer rem_r;
        integer rem_g;
        integer rem_b;
        integer out_r;
        integer out_g;
        integer out_b;
        begin
            if (step >= 128) begin
                palette_value = 24'h000000;
            end else begin
                rem_r = step % 50;
                rem_g = (step * 13) % 1000;
                rem_b = (step * 7) % 1000;

                out_r = (rem_r * 255) / 50;
                out_g = (rem_g * 255) / 1000;
                out_b = (rem_b * 255) / 1000;

                palette_value = {out_r[7:0], out_b[7:0], out_g[7:0]};
            end
        end
    endfunction

    initial begin
        for (idx = 0; idx < 256; idx = idx + 1) begin
            palette_rom[idx] = palette_value(idx);
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            iter_d1 <= 8'd0;
            iter_d2 <= 8'd0;
            palette_rgb_d1 <= 24'd0;
            shape_rgb_d1 <= 24'd0;
            tinted_rgb <= 24'd0;
        end else begin
            iter_d1 <= iter;
            iter_d2 <= iter_d1;
            palette_rgb_d1 <= palette_rom[iter];
            shape_rgb_d1 <= shape_rgb;
            tinted_rgb <= tint_rgb(palette_rgb_d1, shape_rgb_d1);
        end
    end

    always_comb begin
        rgb = (iter_d2 >= 8'd128) ? bg_rgb : tinted_rgb;
    end

endmodule
