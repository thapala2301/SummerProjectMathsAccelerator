`timescale 1ns / 1ps

module framebuffer_bram (
    input  logic        clka,
    input  logic        wea,
    input  logic [18:0] addra, 
    input  logic [7:0]  dina,
    
    input  logic        clkb,
    input  logic [18:0] addrb,
    output logic [7:0]  doutb
);

    logic [19:0] MEM_DEPTH = 20'd460800;

    (* ram_style = "block" *) logic [7:0] ram [0:460799];

    // Write
    always_ff @(posedge clka) begin
        if (wea) begin
            if (addra < MEM_DEPTH[18:0]) begin
                ram[addra] <= dina;
            end
        end
    end

    // Read
    always_ff @(posedge clkb) begin
        if (addrb < MEM_DEPTH[18:0]) begin
            doutb <= ram[addrb];
        end else begin
            doutb <= 8'd0;
        end
    end

endmodule
