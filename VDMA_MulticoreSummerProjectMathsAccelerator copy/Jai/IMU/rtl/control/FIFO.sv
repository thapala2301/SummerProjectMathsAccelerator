module FIFO #(
    parameter WIDTH = 220,
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
    output logic              FIFO_ALMOST_FULL
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [$clog2(DEPTH)-1:0] write_ptr;
    logic [$clog2(DEPTH)-1:0] read_ptr;
    logic [$clog2(DEPTH):0]   count;
    localparam int COUNT_W = $clog2(DEPTH + 1);
    localparam logic [COUNT_W-1:0] DEPTH_COUNT = DEPTH;
    localparam logic [COUNT_W-1:0] ALMOST_FULL_COUNT = ALMOST_FULL_LEVEL;

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
    assign FIFO_FULL  = (count == DEPTH_COUNT);
    assign FIFO_EMPTY = (count == 1'b0);
    assign FIFO_ALMOST_FULL = (count >= ALMOST_FULL_COUNT);

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
