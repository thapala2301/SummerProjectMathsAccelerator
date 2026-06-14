module repeat_mod_cell(
    input  logic        clk,
    input  logic [26:0] p,
    input  logic [26:0] cell_sz,
    input  logic [26:0] half_cell,
    output logic [26:0] q
);

    logic [26:0] p_shifted;
    logic [26:0] p_wrapped;
    logic [26:0] p_centred;

    fp_add inst_add_half(.clk(clk), .a(p), .b(half_cell), .out(p_shifted));
    fp_mod inst_mod_p(.clk(clk), .a(p_shifted), .b(cell_sz), .rem(p_wrapped));
    fp_sub inst_sub_half(.clk(clk), .a(p_wrapped), .b(half_cell), .out(p_centred));

    always_comb begin
        q = p_centred;
    end

endmodule
