/* When a pixel is finished being dealt with, we need to get its colour 
from Sakthi`s colour map and write to correct address in framebuffer
BRAM
Not used in VDMA design
*/

module fb_write(
    input logic        clk,
    input logic        rst,

    input logic [19:0] pix_id,
    input logic        pix_done,
    input logic        hit, 

    input logic [23:0] rgb,

    output logic [19:0] bram_addr,
    output logic [23:0] bram_data_in,
    output logic        bram_we
);

assign bram_we = pix_done;
assign bram_addr = pix_id;
assign bram_data_in = rgb;

endmodule