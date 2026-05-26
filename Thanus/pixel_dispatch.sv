module pixel_dispatch(
    input  logic        clk,
    input  logic        rst,
    input  logic        pipeline_ready,
    output logic [10:0] x_pixel,
    output logic [9:0]  y_pixel,
    output logic        valid,
    output logic [19:0] pix_id
);

assign pix_id = (y_pixel * 1280) + x_pixel;

always_ff @(posedge clk) begin
    if (rst) begin
        x_pixel <= 1'b0;
        y_pixel <= 1'b0;
        valid   <= 1'b0;
    end
    else if (pipeline_ready) begin
        valid <= 1'b1;
        if (x_pixel == 11'd1279 && y_pixel == 10'd719) begin
            x_pixel <= 1'b0;
            y_pixel <= 1'b0;
        end
        else if (x_pixel == 11'd1279) begin
            x_pixel <= 1'b0;
            y_pixel <= y_pixel + 1'b1;
        end
        else begin
            x_pixel <= x_pixel + 1'b1;
        end
    end
end

endmodule