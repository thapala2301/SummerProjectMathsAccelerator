`timescale 1ns / 1ps

/*
Takes iteration and dist in, outputs color with fogging effect.
This module replicates the GSLS code: 
float fog_factor = exp(-dist * fog_density);  // exponential fog
vec3 final_color = mix(fog_color, surface_color, fog_factor);

mix(a, b, t) = a*(1-t) + b*t (like lerp, see neural sdf trilinear)
fog_factor = 1 (close, dist ~0) mix returns surface_color - no fog
fog_factor = 0 (far) mix returns fog_color - full fog

Latency: 3 clk
*/
module palette (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  iter,
    input logic [26:0] curr_dist,
    output logic [23:0] rgb
);

    logic [7:0] fog_lut[0:255];
    initial $readmemh("fog_lut.mem", fog_lut);



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

    logic [7:0] fog_d1, fog_d2, iter_d1;
    logic [23:0] palette_rom [0:255];
    logic [23:0] palette_color;
    localparam [7:0] fog_R = 8'h00, fog_G = 8'h00, fog_B = 8'h33; //deep blue change ltr
    integer idx;
    
    //stage 1
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            iter_d1 <= 0;
            fog_d1 <= 0;
            fog_d2 <= 0;
            palette_color <=0;
            rgb <= 0;
        end
        iter_d1 <= iter;
        fog_d1 <= fog_lut[curr_dist[25:18]]; //comb read no clk
    end

    //stage 2
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            iter_d1 <= 0;
            fog_d1 <= 0;
            fog_d2 <= 0;
            palette_color <=0;
            rgb <= 0;
        end
        palette_color <= palette_rom[iter_d1];
        fog_d2 <= fog_d1;
    end

    //stage 3
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            iter_d1 <= 0;
            fog_d1 <= 0;
            fog_d2 <= 0;
            palette_color <=0;
            rgb <= 0;
        end
        rgb[23:16] <= ((palette_color[23:16]*fog_d2) + (fog_R*(8'd255-fog_d2)))>>8; //16 bit result back to 8 bits
        rgb[15:8]  <= ((palette_color[15:8]  * fog_d2) + (fog_G * (8'd255 - fog_d2))) >> 8;//16 bit result back to 8 bits 
        rgb[7:0]   <= ((palette_color[7:0]   * fog_d2) + (fog_B * (8'd255 - fog_d2))) >> 8; //16 bit result back to 8 bits
    end

endmodule
