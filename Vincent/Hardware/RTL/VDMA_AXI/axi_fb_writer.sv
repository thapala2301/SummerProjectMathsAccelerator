/*
A complicated module, AXI handshake not easy..
Take completed pixels from march_core, writes them to DDR3 via AXI4
inputs: AXI4 transaction signals; if pixel is done (marched fully, ready to send to VDMA) pix_done, the id of px out_pix_id, iter_count, render_bank (which frame rendered to)
Outputs: AXI4 transaction signals, data on pixel to send to VDMA

Know: AXI4:
PRODUCER : asserts valid
CONSUMER : asserts ready

The module axi_fb_writer is master, it initiates all transactions. DDR3 is slave
AW : module producer, DDR3 consumer (master sends adr+burst info)
W : module producer, DDR3 consumer (master sends data + strb)
B : DDR3 producer, module consumer (slave is sending back)
*/

module axi_fb_writer(
    input logic clk,
    input logic rst,
    input logic pix_done,
    input logic [19:0] out_pix_id,
    input logic [7:0] out_iter,
    input logic [26:0] out_dist,
    input logic render_bank,
    input logic [31:0] frame_base_0,
    input logic [31:0] frame_base_1,
    output logic fifo_almost_full,
    output logic drained,

    //outupt axi4 write master AW chan, W chan, B chan DDR3 controller
    //AW Chan - Address Write
    output logic [31:0] AWADDR,
    output logic AWVALID, //producer side - march_core
    input logic AWREADY, //consumer side - DDR
    //W Chan
    output logic [63:0] WDATA,
    output logic [7:0] WSTRB,
    output logic WVALID, //producer side - march_core
    input logic WREADY, //consumer side - DDR
    //B Chan
    input logic [1:0] BRESP,
    input logic BVALID, //producer side - DDR
    output logic BREADY, // consumer side - march_core

    //AXI housekeeping signals
    output logic [7:0] AWLEN_out,
    output logic [2:0] AWSIZE_out,
    output logic [1:0] AWBURST_out,
    output logic [3:0] AWCACHE_out,
    output logic [2:0] AWPROT_out
);
//housekeeping for axi transaction
localparam AWLEN   = 8'd0;      // single beat
localparam AWSIZE  = 3'd3;      // 4 bytes
localparam AWBURST = 2'd1;      
localparam AWCACHE = 4'b0011;   
localparam AWPROT  = 3'b000;    
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
    .curr_dist(out_dist),
    .rgb(rgb_col)
);

logic [19:0] pix_id_d2;
logic render_bank_d2;
//palette takes 3 clk to output rgb_col, and its signal is needed for pixel_data
//we must delay the other signals pix_id and render_bank
state_pipe #(.WIDTH(20), .DEPTH(3)) u_pipe_id   (.clk(clk), .in(out_pix_id),   .out(pix_id_d2));
state_pipe #(.WIDTH(1),  .DEPTH(3)) u_pipe_bank (.clk(clk), .in(render_bank),  .out(render_bank_d2));
state_pipe #(.WIDTH(1), .DEPTH(3)) u_pipe_pixdone (.clk(clk), .in(pix_done), .out(pix_done_d2));

assign pixel_data = {pix_id_d2, render_bank_d2, rgb_col};
assign BREADY = 1'b1;

//FIFO decouples the two different rates of march_core and AXI
//march_core pushes a pixel in whenever it is done marching, and it can push two pix one after the other in 2 clk
//AXI needs more than 1 clk to send transaction, so need backpressure handling through FIFO to handle both rates. AXI bus still busy with first pix when 2nd arrives, store in FIFO
pixel_fifo u_fifo_axi (
    .clk(clk), .rst(rst),
    .wr_en(pix_done_d2),
    .wr_data(pixel_data),
    .rd_en(rd_en), //what drive?
    .rd_data(send_pixel_data), 
    .full(fifo_full),
    .empty(fifo_empty)
);

//AXI4 master fsm
/*
S_IDLE: nothing to send. If FIFO has a px, read out, put adr and data on bus,
assert AWVALID and WVALID, move to S_ADDR (State Address/ Sending state)
S_ADDR: waiting for DDR3 controller to accept. AWREADY and AWVALID can come on different clk.
When both channels are done (AW and W), DDR3 controller has accepted both address and data, has everything needed to preform write
This means controller has taken ownership of transaction, this confirmed by B channel response later
*/
typedef enum logic [0:0] {S_IDLE, S_ADDR} state_t;
state_t state;


always_ff @ (posedge clk) begin
    if(rst) begin state <= S_IDLE; AWVALID <= 0; WVALID <= 1'b0; rd_en <= 1'b0; end
    else begin
        rd_en <= 1'b0;
        case (state)
        S_IDLE: begin
            //dequeu a pixel waiting in the FIFO
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
            /*
            When we enter S_ADDR state, AWVALID and WVALID are set already.
            If DDR3 Controller send AWREADY, that means it's ready to recieve an address. The AXI FSM directly sends the address,
            thus resetting AWVALID
            Same for WREADY

            Partial handshakes:
            if ( DDR3 controller sends that it is ready to write adress,  or that AWVALID is reset (indicating prior transaction)) AND (DDR3 Controller sends that it's ready to write data, or that WVALID is reset (indicating prior transaction))
            then go back to idle

            AWREADY means the DDR3 controller is ready to accept a write address 
            it's the consumer's side of the AW handshake. When AWVALID and AWREADY are both high on the same clock edge,
            the address is transferred.
            */
            if(AWREADY) AWVALID <= 1'b0;
            if(WREADY) WVALID <= 1'b0;
            //handles partial handshakes: stays in S_ADDR until both AW and W are accepted, even if they complete on different cycles.
            if ((AWREADY || !AWVALID) && (WREADY || !WVALID)) //hardest line of module
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