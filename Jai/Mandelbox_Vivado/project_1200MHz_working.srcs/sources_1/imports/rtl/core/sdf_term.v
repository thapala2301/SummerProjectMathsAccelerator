//computes 
// length(max((v0,v1,v2),0.))+ min(max(v0,max(v1,v2)),0)
module sdf_term(
    input clk,
    input wire[26:0] vx,
    input wire [26:0] vy,
    input wire [26:0] vz,
    output wire [26:0] out
);

    //clip to 0 if neg for max((v0,v1,v2),0
    wire [26:0] cx = vx[26] ? 27'b0 : vx;
    wire [26:0] cy = vy[26] ? 27'b0 : vy;
    wire [26:0] cz = vz[26] ? 27'b0 : vz;

    //get length(max((v0,v1,v2),0.))
    wire [26:0] len;
    fp_length inst_len (.clk(clk), .x(cx), .y(cy), .z(cz), .out(len));

    //second term

    wire[26:0] temp_max;
    fp_max inst1_max(.a(vy), .b(vz), .out(temp_max) );

    reg [26:0] temp_max_reg;
    reg [26:0] vx_reg;
    always @(posedge clk) begin
        temp_max_reg <= temp_max;
        vx_reg <= vx;
    end

    wire [26:0] temp_maxv0_maxv1_v2;
    fp_max inst2_max(.a(vx_reg), .b(temp_max_reg), .out(temp_maxv0_maxv1_v2));
    //clamped neg holds:max(v0,max(v1,v2)),0

    //second term
    //clamped neg holds:max(v0,max(v1,v2)),0
    wire [26:0] clamped_neg = temp_maxv0_maxv1_v2[26] ? temp_maxv0_maxv1_v2 : 27'b0;


    //fp_length now 40 cycles (fp_mul=5, fp_isqrt=20, fp_add=5)
    //clamped_neg calculation now takes 1 cycle, so pipe depth is 39 to align with len output (39 + 1 = 40)
    wire [26:0] clamped_neg_delayed;
    state_pipe #(.WIDTH(27), .DEPTH(39)) pipe_clamped_neg(.clk(clk), .in(clamped_neg), .out(clamped_neg_delayed));
    fp_add final_add (.clk(clk), .a(len), .b(clamped_neg_delayed), .out(out));

endmodule