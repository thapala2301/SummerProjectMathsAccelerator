//for points not describe in BRAM, we must interpolate / take average of all neighbooring points
//must lerp (https://www.youtube.com/watch?v=YJB1QnEmlTs) to blend along all axis

module trilinear_interp(
    input logic clk,
    input logic rst,
    input logic [26:0] x,
    input logic [26:0] y,
    input logic [26:0] z,
    input logic query_valid,

    output logic [26:0] distance,
    output logic dist_valid,

    input logic [26:0] bram_dout,
    output logic [14:0] bram_addr

);

//convert xyz to grid coords
//IN FP
 // scaling factor. Scene coords range from -2 to 2. Grid indices range from 0 to 63
 //constants needed : 63/4 = 15.75 , and 2
localparam [26:0] FP_7_75 = {1'b0, 8'd129, 18'b111100000000000000};

localparam [26:0] FP_2_0   = {1'b0, 8'd128, 18'b0};
logic [26:0] ix_float;
logic [26:0] x_2_intermed;
logic [5:0] ix ; //range from 0-63
wire query_valid_d;
wire [26:0] ix_int_fp;
wire [26:0] tx;
logic [5:0] ix_d;
wire [26:0] ix_float_d1;
//by the time ix_float valid, 6 clk hove passed
state_pipe #(.WIDTH(1), .DEPTH(6)) sp_valid (.clk(clk), .in(query_valid), .out(query_valid_d));
fp_add inst1_add_x_2 (.clk(clk), .a(x), .b(FP_2_0), .out(x_2_intermed));
fp_mul inst1_mul_x_2_scaling (.clk(clk), .a(x_2_intermed), .b(FP_7_75), .out(ix_float));

always @ (posedge clk) begin
    ix <=  ({1'b1, ix_float[17:0]} >> (18-(ix_float[25:18]-127)))[5:0];
end

//covert 6 bit int ix to FP27
//fp sub gives fract part in FP27
state_pipe #(.WIDTH(6), .DEPTH(4)) ix_delay(.clk(clk), .in(ix), .out(ix_d));
state_pipe #(.WIDTH(27), .DEPTH(1)) sp_ixf(.clk(clk), .in(ix_float), .out(ix_float_d1));
int2fp inst_ix_to_fp (.in({{26{1'b0}}, ix}), .out(ix_int_fp));
fp_sub inst_tx (.clk(clk), .a(ix_float_d1), .b(ix_int_fp), .out(tx));



logic [26:0] iy_float;
logic [26:0] y_2_intermed;
logic [5:0] iy;
wire [26:0] iy_int_fp;
wire[26:0] ty;
wire [5:0] iy_d;
wire [26:0] iy_float_d1;
fp_add inst1_add_y_2 (.clk(clk), .a(y), .b(FP_2_0), .out(y_2_intermed));
fp_mul inst1_mul_y_2_scaling (.clk(clk), .a(y_2_intermed), .b(FP_7_75), .out(iy_float));
always @ (posedge clk) begin

    iy <=  ({1'b1, iy_float[17:0]} >> (18-(iy_float[25:18]-127)))[5:0];
end

//covert 6 bit int ix to FP27
//fp sub gives fract part in FP27
state_pipe #(.WIDTH(6), .DEPTH(4)) iy_delay(.clk(clk), .in(iy), .out(iy_d));
state_pipe #(.WIDTH(27), .DEPTH(1)) sp_iyf(.clk(clk), .in(iy_float), .out(iy_float_d1));
int2fp inst_iy_to_fp (.in({{26{1'b0}}, iy}), .out(iy_int_fp));
fp_sub inst_ty (.clk(clk), .a(iy_float_d1), .b(iy_int_fp), .out(ty));



logic [26:0] iz_float;
logic [5:0] iz;
logic [26:0] z_2_intermed;
wire [26:0] iz_int_fp;
wire[26:0] tz;
wire [5:0] iz_d;
wire [26:0] iz_float_d1;
fp_add inst1_add_z_2 (.clk(clk), .a(z), .b(FP_2_0), .out(z_2_intermed));
fp_mul inst1_mul_z_2_scaling (.clk(clk), .a(z_2_intermed), .b(FP_7_75), .out(iz_float));

always @ (posedge clk) begin
    iz <=  ({1'b1, iz_float[17:0]} >> (18-(iz_float[25:18]-127)))[5:0];
end

state_pipe #(.WIDTH(6), .DEPTH(4)) iz_delay(.clk(clk), .in(iz), .out(iz_d));
state_pipe #(.WIDTH(27), .DEPTH(1)) sp_izf(.clk(clk), .in(iz_float), .out(iz_float_d1));
int2fp inst_iz_to_fp (.in({{26{1'b0}}, iz}), .out(iz_int_fp));
fp_sub inst_tz (.clk(clk), .a(iz_float_d1), .b(iz_int_fp), .out(tz));


//have all tx,ty,tz: those are the fract bits of the cubes (for interp!) and ix_d, iy_d, iz_d are which cube it is closest to
//now read 8 BRAM corners (cube has 8 summits, see diagram on goodnotes)
//address are Ints , the 32 * 32 * 32 cubes. The values stored at the addresses are FP27 distance values!
//lerp compoute is FP27

//now blend along all axis, see goodnotes  page 10
//define BRAM somewhere... is it not better to do shifts then 32 *32 mult.?
logic [26:0] v_corners [0:7]; //store all values corresponding to a_corners
logic [14:0] a_corners [0:7]; //corner_000_addr, corner_100_addr, corner_110_addr, corner_010_addr, corner_111_addr, corner_011_addr, corner_001_addr, corner_101_addr
//front face
assign a_corners[0] = iz_d*32*32+iy_d*32 + ix_d;
assign a_corners[1] = iz_d*32*32+iy_d*32 + (ix_d+1);
assign a_corners[2] = iz_d*32*32+(iy_d+1)*32 + (ix_d+1);
assign a_corners[3] = iz_d*32*32+(iy_d+1)*32 + ix_d;

//top face
assign a_corners[4] = (iz_d+1)*32*32 + (iy_d+1)*32 + (ix_d+1);
assign a_corners[5] = (iz_d+1)*32*32 + (iy_d+1)*32 + ix_d;

//back face
assign a_corners[6] = (iz_d+1)*32*32+iy_d*32+ix_d;
assign a_corners[7] = (iz_d+1)*32*32+iy_d*32 + (ix_d+1);
assign bram_addr = a_corners[rd_count];
logic [3:0] rd_count;
logic reading;
always_ff @ (posedge clk) begin
    if (rst) begin
        reading <= 0;
        rd_count <= 0;
    end
    else if (query_valid_d) begin reading <= 1; rd_count <= 0; end

    else if(reading) begin
        if (rd_count == 8 ) begin
            v_corners[7] <= bram_dout;
            reading <= 0;
        end

        else begin
            if (rd_count > 0) v_corners[rd_count-1] <= bram_dout; //store previous clk result
            rd_count <= rd_count +1;
        end

    end
end


logic [26:0] c00, c10, c11, c01, c0, c1, result;

//7 lerps with FP lib

//along x
//BRAM handle FSM

blend_lerp u_lerp_d000_d100_tx (.clk(clk), .rst(rst), .a(v_corners[0]) , .b(v_corners[1]), .t(tx), .out_blend(c00));
blend_lerp u_lerp_d010_d110_tx (.clk(clk), .rst(rst), .a(v_corners[2]) , .b(v_corners[3]), .t(tx), .out_blend(c10));
blend_lerp u_lerp_d011_d111_tx (.clk(clk), .rst(rst), .a(v_corners[4]) , .b(v_corners[5]), .t(tx), .out_blend(c11));
blend_lerp u_lerp_d001_d101_tx (.clk(clk), .rst(rst), .a(v_corners[6]) , .b(v_corners[7]), .t(tx), .out_blend(c01));

//collapse to y square
blend_lerp u_lerp_c00_c10_ty (.clk(clk), .rst(rst), .a(c00) , .b(c10), .t(ty), .out_blend(c0));
blend_lerp u_lerp_c01_c11_ty (.clk(clk), .rst(rst), .a(c01) , .b(c11), .t(ty), .out_blend(c1));

//collapse to z line
blend_lerp u_lerp_c0_c1_tx (.clk(clk), .rst(rst), .a(c0) , .b(c1), .t(tz), .out_blend(result));

assign distance = result;
wire reads_done = (rd_count == 8) & reading; //fires when last BRAM read finishes 
wire dist_valid_w;

state_pipe #(.WIDTH(1), .DEPTH(10)) sp_dv (.clk(clk), .in(reads_done), .out(dist_valid_w));
assign dist_valid = dist_valid_w


endmodule