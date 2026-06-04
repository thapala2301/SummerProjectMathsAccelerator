`timescale 1ns / 1ps

module framebuffer_bram (
    input  logic        clka,
    input  logic        wea,
    input  logic [19:0] addra, 
    input  logic [23:0] dina,
    
    input  logic        clkb,
    input  logic [19:0] addrb,
    output logic [23:0] doutb
);

    logic [19:0] MEM_DEPTH = 20'd460800;

    // We store the 8-bit compressed RGB332 in the BRAM to fit within PYNQ limits
    (* ram_style = "block" *) logic [7:0] ram [0:460799];

    initial begin
        for (int i = 0; i < 460800; i++) begin
            ram[i] = 8'd0;
        end
    end

    // Write
    always_ff @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
        end
    end

    // Port B (Read from scan_out)
    logic [7:0] raw_doutb;

    always_ff @(posedge clkb) begin
        doutb <= ram[addrb];
    end

    // Decompress 8-bit RGB332 back to 24-bit RGB
    assign doutb = {
        raw_doutb[7:5], raw_doutb[7:5], 2'b00,
        raw_doutb[4:2], raw_doutb[4:2], 2'b00,
        raw_doutb[1:0], raw_doutb[1:0], raw_doutb[1:0], 2'b00
    };

endmodule
