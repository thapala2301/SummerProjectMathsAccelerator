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

wire[26:0] temp_max, temp_maxv0_maxv1_v2;
fp_max inst1_max(.a(vy), .b(vz), .out(temp_max) );
fp_max inst2_max(.a(vx), .b(temp_max), .out(temp_maxv0_maxv1_v2));
//clamped neg holds:max(v0,max(v1,v2)),0

//second term
//clamped neg holds:max(v0,max(v1,v2)),0
wire [26:0] clamped_neg = temp_maxv0_maxv1_v2[26] ? temp_maxv0_maxv1_v2 : 27'b0;


//for final add must wait 22 clk for length to finish, clamped is fully comb 0 clk. 
//store clamped for 22 clk
wire [26:0] clamped_neg_delayed;
state_pipe #(.WIDTH(27), .DEPTH(22)) pipe_clamped_neg(.clk(clk), .in(clamped_neg), .out(clamped_neg_delayed));
fp_add final_add (.clk(clk), .a(len), .b(clamped_neg_delayed), .out(out));

endmodule