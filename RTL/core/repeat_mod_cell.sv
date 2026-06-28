/*
True mod repeat cell.
The SDF evaluated is defined around the origin, eg sphere SDF is length(p)-r: expects p to be near 0,0,0
fp_mod only returns positive values. 17[10]=7, same as -3[10]=7: both positive: breaks SDF, bc expects positions centered at 0, not cell cell_sz/2
SDF are built around (0,0,0)
repeating cell size 10 and just doing mod (p,10), get p in [0,10] so geom in every cell is centered at 5, not 0. Repeats, but looks shifted

half_cell fixes the shift so objects sit in middle of each cell. Without this, cell boundary cuts through in middle of obj
With half_cell, get [-5,5]: object appears at pos 0 in every cell: fully inside cell, empty space on both edges
 
TLDR: the module fixes mod doing 3[5]=-2 AND world origin at 0;0;0 accounting
*/

module repeat_mod_cell(
    input  logic        clk,
    input  logic [26:0] p,
    input  logic [26:0] cell_sz,
    input  logic [26:0] half_cell,
    output logic [26:0] q
);


    logic [26:0] p_shifted; //p + half cells: shifts p so mod boundaries align correctly
    logic [26:0] p_wrapped; //mod (p_shifted, cell_sz) folds into 0, cell sz
    logic [26:0] p_centred; // p_wrapped - half_cell, shifts back to [-half_cell, +half_cell]
    logic [26:0] abs_centred; //check if overshoot by owerflow?
    logic [26:0] p_centred_d; 
    logic [26:0] p_minus_cell;
    logic [26:0] p_plus_cell;
    logic        needs_recentre; //abs_centred > half_cell: true if p_centered outside cell, hppens bc fp_mod on negative inputs can return neg remainder
    logic        needs_recentre_d;
    logic        centred_neg_d;

    fp_add inst_add_half(.clk(clk), .a(p), .b(half_cell), .out(p_shifted));
    // fp_mod2 inst_mod_p(.clk(clk), .a(p_shifted), .b(cell_sz), .rem(p_wrapped)); // faster, less luts less dsp
    fp_mod inst_mod_p(.clk(clk), .a(p_shifted), .rem(p_wrapped)); 
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
