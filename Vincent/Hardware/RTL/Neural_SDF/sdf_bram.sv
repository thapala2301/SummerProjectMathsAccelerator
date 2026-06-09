module sdf_bram(
    input  logic        clka,
    input  logic        wea,
    input  logic [14:0] addra,
    input  logic [26:0] dina,

    input  logic        clkb,
    input  logic [17:0] addrb,
    output logic [26:0] doutb
);

(* ram_style = "block" *) logic [26:0] ram [0:32767]; // 32³

always_ff @(posedge clka) if (wea) ram[addra] <= dina;
always_ff @(posedge clkb) doutb <= ram[addrb];

endmodule
