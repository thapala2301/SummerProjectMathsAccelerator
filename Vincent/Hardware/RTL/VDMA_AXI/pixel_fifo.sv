module pixel_fifo(
    input logic clk, rst,
    input logic wr_en, 
    input logic [44:0] wr_data,
    input logic rd_en,
    output logic [44:0] rd_data,
    output logic full,
    output logic empty
);

//fifo depth 16 entries
reg [44:0] mem [0:15];
logic [4:0] wr_ptr, rd_ptr;



always_ff @ (posedge clk) begin
    if (rst) wr_ptr <= 5'd0; 

    else if(wr_en && !full) begin
        mem[wr_ptr[3:0]] <= wr_data;
        wr_ptr <= wr_ptr +1;
    end
end
        
always_ff @ (posedge clk) begin
    if (rst) rd_ptr <= 5'd0;
    else if (rd_en && !empty)
        rd_ptr <= rd_ptr+1;
end

assign rd_data = mem[rd_ptr[3:0]];
assign empty = (wr_ptr == rd_ptr);
assign full  = (wr_ptr[3:0] == rd_ptr[3:0]) && (wr_ptr[4] != rd_ptr[4]);
endmodule
