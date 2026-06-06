module axi_fb_writer(
    input logic clk,
    input logic rst,
    input logic pix_done,
    input logic [19:0] out_pix_id,
    input logic [7:0] out_iter,
    input logic render_bank,

    //outupt axi4 write master AW chan, W chan, B chan DDR3 controller
    //AW Chan
    output logic [31:0] AWADDR,
    output logic AWVALID,
    input logic AWREADY,
    //W Chan
    output logic [31:0] WDATA,
    output logic [3:0] WSTRB,
    output logic WVALID,
    input logic WREADY,
    //B Chan
    input logic [1:0] BRESP,
    input logic BVALID,
    output logic BREADY,

    output logic [7:0] AWLEN_out,
    output logic [2:0] AWSIZE_out,
    output logic [1:0] AWBURST_out,
    output logic [3:0] AWCACHE_out,
    output logic [2:0] AWPROT_out
);
//housekeeping for axi transaction
localparam AWLEN   = 8'd0;      // single beat
localparam AWSIZE  = 3'd2;      // 4 bytes
localparam AWBURST = 2'd1;      
localparam AWCACHE = 4'b0011;   
localparam AWPROT  = 3'b000;    


localparam frame_base_0 = 32'h1E00_0000; //frame buffer 0 in DDR
localparam frame_base_1 = 32'h1E38_4000; //frame buffer 1, offset by res 1270 x 740 x 4 = 3.7 Mb
wire rst_n = ~rst;
logic [23:0] rgb_col;
logic pix_done_d2;
logic [44:0] pixel_data;
logic [44:0] send_pixel_data;
logic fifo_empty, fifo_full;
logic rd_en;
//palette inst
palette u_palette(
    .clk(clk), .rst_n(rst_n),
    .iter(out_iter),
    .rgb(rgb_col)
);
logic [19:0] pix_id_d2;
logic render_bank_d2;
state_pipe #(.WIDTH(20), .DEPTH(2)) u_pipe_id   (.clk(clk), .in(out_pix_id),   .out(pix_id_d2));
state_pipe #(.WIDTH(1),  .DEPTH(2)) u_pipe_bank (.clk(clk), .in(render_bank),  .out(render_bank_d2));
state_pipe #(.WIDTH(1), .DEPTH(2)) u_pipe_pixdone (.clk(clk), .in(pix_done), .out(pix_done_d2));

assign pixel_data = {pix_id_d2, render_bank_d2, rgb_col};
assign BREADY = 1'b1;//fifo inst, must delay pix done 
pixel_fifo u_fifo_axi (
    .clk(clk), .rst(rst),
    .wr_en(pix_done_d2),
    .wr_data(pixel_data),
    .rd_en(rd_en), //what drive?
    .rd_data(send_pixel_data), 
    .full(fifo_full),
    .empty(fifo_empty)
);

//Axi 4 master fsm
typedef enum logic [0:0] {S_IDLE, S_ADDR} state_t;
state_t state;


always_ff @ (posedge clk) begin
    if(rst) begin state <= S_IDLE; AWVALID <= 0; WVALID <= 1'b0; rd_en <= 1'b0; end
    else begin
        rd_en <= 1'b0;
        case (state)
        S_IDLE: begin
            //dequeu px??
            if (!fifo_empty) begin
                rd_en <= 1'b1;
                //bit 24 is render bank. if render_bank = 1, use frame_base_1
                //AWADDR[31:22] = upper frame_base bits. like concat bc offset never overflows into its bits
                AWADDR <= (send_pixel_data[24] ? frame_base_1 : frame_base_0)+ {10'b0, send_pixel_data[44:25], 2'b00}; //mult by 4 for correct addr
                WDATA <= {8'b0, send_pixel_data[23:0]};
                WSTRB <= 4'b1111;
                AWVALID <= 1'b1;
                WVALID <= 1'b1;
                state <= S_ADDR;
            end
        end
        S_ADDR: begin
            if(AWREADY) AWVALID <= 1'b0;
            if(WREADY) WVALID <= 1'b0;
            //handles partial handshakes: stays in S_ADDR until both AW and W are accepted, even if they complete on different cycles.
            if ((AWREADY || !AWVALID) && (WREADY || !WVALID))
                state <= S_IDLE;
        end
        endcase
    end  
end

assign AWLEN_out = AWLEN;
assign AWSIZE_out = AWSIZE;
assign AWBURST_out = AWBURST;
assign AWCACHE_out = AWCACHE;
assign AWPROT_out = AWPROT;

endmodule