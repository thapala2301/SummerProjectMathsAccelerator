/*
Generates stream of pixel coords, counts through every px in frame in raster order
outputs x,y, pix_id, valid
one pixel per clk when pipeline_ready is high
x : 0 -> 127, y increments each row, pix_id = y*1280 + x
pipeline_ready low: pause
*/
module pixel_dispatch(
    input  logic        clk,
    input  logic        rst,
    input  logic        pipeline_ready,
    
    output logic [10:0] x_pixel,
    output logic [9:0]  y_pixel,
    output logic        valid,
    output logic [19:0] pix_id
);

//PIXEL RES PARAMS
assign pix_id = ((y_pixel) * 512) + (x_pixel); //compute pix_id at half resolution; *512 due to pix_id = row * W + col, grid of width W
assign valid  = ~rst & pipeline_ready;

//raster order  scan
always_ff @(posedge clk) begin
    if (rst) begin
        x_pixel <= 1'b0;
        y_pixel <= 1'b0;
    end
    else if (pipeline_ready) begin
        if (x_pixel == 11'd511 && y_pixel == 10'd299) begin
            x_pixel <= 1'b0;
            y_pixel <= 1'b0;
        end
        else if (x_pixel == 11'd511) begin
            x_pixel <= 1'b0;
            y_pixel <= y_pixel + 1'b1;
        end
        else begin
            x_pixel <= x_pixel + 1'b1;
        end
    end
end

endmodule
