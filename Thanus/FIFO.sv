/*
Normal synchronous FIFO, to store data on all the mid marching pixels
Input data element and enable write read, output read data and empty/full flags
*/

module FIFO #(
    parameter WIDTH = 247,
    parameter DEPTH = 128
)(
    input  logic              clk,
    input  logic              rst,
    input  logic              wr_en,
    input  logic [WIDTH-1:0]  wr_data,
    input  logic              rd_en,
    output logic [WIDTH-1:0]  rd_data,
    output logic              FIFO_FULL,
    output logic              FIFO_EMPTY
);
    //infer as BRAM, saves 2200 luts and we have lots of bram headroom
    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];


    logic [$clog2(DEPTH)-1:0] write_ptr;
    logic [$clog2(DEPTH)-1:0] read_ptr;
    logic [$clog2(DEPTH):0]   count;

    // Write 
    always_ff @(posedge clk) begin
        if (rst) begin
            write_ptr <= 1'b0;
        end else begin
            if (wr_en && !FIFO_FULL) begin
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
            if (rd_en && !FIFO_EMPTY) begin
                read_ptr <= read_ptr + 1'b1;
            end
        end
    end
    
    assign rd_data = mem[read_ptr]; 

    // Full and empty flags
    assign FIFO_FULL  = (count == DEPTH);
    assign FIFO_EMPTY = (count == 1'b0);

    always_ff @(posedge clk) begin
    if (rst) begin
        count <= 1'b0;
    end else begin
        if (wr_en && !rd_en && !FIFO_FULL) begin
            count <= count + 1'b1;
        end else if (rd_en && !wr_en && !FIFO_EMPTY) begin
            count <= count - 1'b1;
        end
    end
end

endmodule