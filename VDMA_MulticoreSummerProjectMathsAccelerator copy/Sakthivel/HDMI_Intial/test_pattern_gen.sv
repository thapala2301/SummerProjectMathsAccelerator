`timescale 1ns / 1ps

module test_pattern_gen(
    input  logic        clk_74_25,
    input  logic        rst_n,
    
    output logic [19:0] bram_addr,
    output logic [23:0] bram_data_in,
    output logic        bram_we
);

    logic [10:0] x_pixel;
    logic [9:0]  y_pixel;

    always_ff @(posedge clk_74_25) begin
        if (!rst_n) begin
            x_pixel <= 0;
            y_pixel <= 0;
            bram_we <= 0;
            bram_addr <= 0;
            bram_data_in <= 0;
        end else begin
            // Continuously scan and write a gradient test pattern
            bram_we <= 1'b1;
            bram_addr <= (y_pixel * 20'd1280) + x_pixel;
            
            // Create a cool colour gradient that changes across X and Y
            bram_data_in <= {x_pixel[7:0], y_pixel[7:0], (x_pixel[7:0] ^ y_pixel[7:0])};
            
            if (x_pixel == 1279) begin
                x_pixel <= 0;
                if (y_pixel == 719) begin
                    y_pixel <= 0;
                end else begin
                    y_pixel <= y_pixel + 1;
                end
            end else begin
                x_pixel <= x_pixel + 1;
            end
        end
    end

endmodule
