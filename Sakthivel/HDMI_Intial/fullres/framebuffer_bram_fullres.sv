`timescale 1ns / 1ps

module framebuffer_bram (
    input  logic        clka,
    input  logic        wea,
    input  logic [20:0] addra,
    input  logic [7:0]  dina,
    
    input  logic        clkb,
    input  logic [20:0] addrb,
    output logic [7:0]  doutb
);

    logic [20:0] MEM_DEPTH = 21'd1843200;

    (* ram_style = "block" *) logic [7:0] ram [0:1843199];

    always_ff @(posedge clka)
        if (wea)
            ram[addra] <= dina;

    always_ff @(posedge clkb)
        doutb <= ram[addrb];

endmodule
