/*
Normal synchronous FIFO, to store data on all the mid marching pixels
Input data element and enable write read, output read data and empty/full flags
*/

module FIFO #(
    parameter WIDTH = 247,
    parameter DEPTH = 128,
    parameter ALMOST_FULL_LEVEL = DEPTH
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              wr_en,
    input  logic [WIDTH-1:0]  wr_data,
    input  logic              rd_en,
    output logic [WIDTH-1:0]  rd_data,
    output logic              FIFO_FULL,
    output logic              FIFO_EMPTY,
    output logic FIFO_ALMOST_FULL
);
    //infer as BRAM, saves 2200 luts and we have lots of bram headroom
    // TO INFER AS BRAM : IN FRONT: (* ram_style = "block" *) 
    logic [WIDTH-1:0] mem [0:DEPTH-1];


    logic [$clog2(DEPTH)-1:0] write_ptr;
    logic [$clog2(DEPTH)-1:0] read_ptr;
    logic [$clog2(DEPTH):0]   count;

    //charlie what do these do? UNDERSTAND
    localparam int COUNT_W = $clog2(DEPTH+1); // nb of bits needed to hold value DEPTH
    localparam logic [COUNT_W-1:0] DEPTH_COUNT = DEPTH;
    localparam logic [COUNT_W-1:0] ALMOST_FULL_COUNT = ALMOST_FULL_LEVEL;

    logic wr_fire;
    logic rd_fire;

    assign rd_fire = rd_en && !FIFO_EMPTY;
    assign wr_fire = wr_en && (!FIFO_FULL || rd_fire);

    // Write 
    always_ff @(posedge clk) begin
        if (rst) begin
            write_ptr <= 1'b0;
        end else begin
            if (wr_fire) begin
                mem[write_ptr] <= wr_data;
                write_ptr <= write_ptr + 1'b1;
            end
        end
    end

    // Read
    always_ff @(posedge clk) begin
        if (rst) begin
            read_ptr <= 1'b0;
        end else begin
            if (rd_fire) begin
                read_ptr <= read_ptr + 1'b1;
            end
        end
    end
    
    assign rd_data = mem[read_ptr]; 

    // Full and empty flags
    assign FIFO_FULL  = (count == DEPTH_COUNT);
    assign FIFO_EMPTY = (count == 1'b0);
    assign FIFO_ALMOST_FULL = (count >= ALMOST_FULL_COUNT);

    always_ff @(posedge clk) begin
    if (rst) begin
        count <= 1'b0;
    end else begin
        case ({wr_fire, rd_fire})
            2'b10: count <= count+1'b1;
            2'b01: count <= count -1'b1;
            default : count <= count;
        endcase
    end
end

endmodule