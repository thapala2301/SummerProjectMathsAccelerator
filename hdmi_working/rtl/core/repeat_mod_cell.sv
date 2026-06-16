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
    logic [26:0] abs_centred;
    logic [26:0] p_centred_d;
    logic [26:0] p_minus_cell;
    logic [26:0] p_plus_cell;
    logic        needs_recentre;
    logic        needs_recentre_d;
    logic        centred_neg_d;

    fp_add inst_add_half(.clk(clk), .a(p), .b(half_cell), .out(p_shifted));
    fp_mod inst_mod_p(.clk(clk), .a(p_shifted), .b(cell_sz), .rem(p_wrapped));
    fp_sub inst_sub_half(.clk(clk), .a(p_wrapped), .b(half_cell), .out(p_centred));
    fp_abs inst_abs_centred(.in(p_centred), .out(abs_centred));

    assign needs_recentre = (abs_centred > half_cell);

    fp_sub inst_sub_cell(.clk(clk), .a(p_centred), .b(cell_sz), .out(p_minus_cell));
    fp_add inst_add_cell(.clk(clk), .a(p_centred), .b(cell_sz), .out(p_plus_cell));

    state_pipe #(.WIDTH(27), .DEPTH(4)) pipe_centred (.clk(clk), .in(p_centred),        .out(p_centred_d));
    state_pipe #(.WIDTH(1),  .DEPTH(4)) pipe_recentre(.clk(clk), .in(needs_recentre),   .out(needs_recentre_d));
    state_pipe #(.WIDTH(1),  .DEPTH(4)) pipe_sign    (.clk(clk), .in(p_centred[26]),    .out(centred_neg_d));

    always_comb begin
        if (!needs_recentre_d)
            q = p_centred_d;
        else if (centred_neg_d)
            q = p_plus_cell;
        else
            q = p_minus_cell;
    end

endmodule
