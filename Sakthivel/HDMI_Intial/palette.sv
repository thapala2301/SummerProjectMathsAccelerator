`timescale 1ns / 1ps

/*
Takes iteration count in, outputs color.
At compile time, bakes a rom of color values for a nice repeating pattern over 6144 bits
Should use distance encoding instead, iter is bad proxy for depth
*/
module palette (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  iter,
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
                //choice of coprime numbers so that take long time to fully repeat
                //cycling gives repeated color bands, object at different depths show different colors
                //makes the scene more interesting, allows to see structure in SDF
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

    //initialise BRAM so values get baked in bitstream and have wide range of colors
    //256 entries * 24 bits = 6144 bits- Vivado uses BRAM
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
            rgb <= palette_rom[iter_d1];
        end
    end

endmodule
