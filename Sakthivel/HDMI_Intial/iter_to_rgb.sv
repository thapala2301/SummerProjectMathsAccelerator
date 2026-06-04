`timescale 1ns / 1ps

module iter_to_rgb (
    input  logic [7:0]  iter,
    
    // Params
    input  logic [7:0]  thresh_1, 
    input  logic [7:0]  thresh_2, 
    input  logic [7:0]  thresh_3, 
    input  logic [2:0]  shift_1,  
    input  logic [2:0]  shift_2,  
    
    output logic [23:0] rgb
);

    logic [7:0] r, g, b;
    
    // Colors
    always_comb begin
        if (iter < thresh_1) begin
            r = 8'h00;
        end else if (iter < thresh_2) begin
            r = (iter - thresh_1) << shift_1;
        end else begin
            r = 8'hFF;
        end
        
        if (iter < thresh_2) begin
            g = 8'h00;
        end else if (iter < thresh_3) begin
            g = (iter - thresh_2) << shift_2;
        end else begin
            g = 8'hFF;
        end
        
        if (iter < thresh_1) begin
            b = iter << shift_1;
        end else begin
            b = 8'hFF;
        end
        
        rgb = {r, g, b};
    end

endmodule
