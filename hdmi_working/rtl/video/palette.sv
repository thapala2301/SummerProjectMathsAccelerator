`timescale 1ns / 1ps

module palette (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  iter,
    input  logic [23:0] bg_rgb,
    output logic [23:0] rgb
);

    logic [7:0] iter_d1;
    logic [23:0] palette_rom [0:255];
    integer idx;

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
            rgb <= 24'd0;
        end else begin
            iter_d1 <= iter;
            rgb <= (iter_d1 >= 8'd128) ? bg_rgb : palette_rom[iter_d1];
        end
    end

endmodule
