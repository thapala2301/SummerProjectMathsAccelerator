module ddr_rgb_writer #(
    parameter int FIFO_DEPTH = 4096,
    parameter int FIFO_ALMOST_FULL = FIFO_DEPTH - 512,
    parameter int MAX_OUTSTANDING = 8
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] frame_base_0,
    input  logic [31:0] frame_base_1,
    input  logic        pix_done,
    input  logic [19:0] out_pix_id,
    input  logic [7:0]  out_iter,
    input  logic        render_bank,
    output logic        fifo_almost_full,
    output logic        drained,
    output logic [31:0] m_axi_awaddr,
    output logic [3:0]  m_axi_awlen,
    output logic [2:0]  m_axi_awsize,
    output logic [1:0]  m_axi_awburst,
    output logic [3:0]  m_axi_awcache,
    output logic [2:0]  m_axi_awprot,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [63:0] m_axi_wdata,
    output logic [7:0]  m_axi_wstrb,
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] debug_status
);

    localparam int ENTRY_W = 45;
    localparam logic [19:0] FRAME_RAY_COUNT = 20'd153600;
    localparam int OUTSTANDING_W = (MAX_OUTSTANDING <= 1) ? 1 : $clog2(MAX_OUTSTANDING + 1);

    function automatic logic [31:0] entry_addr_top(input logic [ENTRY_W-1:0] entry);
        logic [31:0] base_addr;
        logic [19:0] pix_id;
        begin
            base_addr = entry[44] ? frame_base_1 : frame_base_0;
            pix_id = entry[43:24];
            entry_addr_top = base_addr + {8'd0, pix_id[19:9], 13'b0} + {20'd0, pix_id[8:0], 3'b0};
        end
    endfunction

    function automatic logic [63:0] entry_data64(input logic [ENTRY_W-1:0] entry);
        begin
            entry_data64 = {{8'h00, entry[23:0]}, {8'h00, entry[23:0]}};
        end
    endfunction

    logic        rst_n;
    logic [23:0] rgb_col;
    logic        pix_done_d1;
    logic        pix_done_d2;
    logic [19:0] pix_id_d1;
    logic [19:0] pix_id_d2;
    logic        render_bank_d1;
    logic        render_bank_d2;
    logic        frame_base_valid_d;
    logic        fifo_wr_en;
    logic        fifo_rd_en;
    logic [ENTRY_W-1:0] fifo_wr_data;
    logic [ENTRY_W-1:0] fifo_rd_data;
    logic        fifo_full;
    logic        fifo_empty;

    logic        row_sel;
    logic        beat_valid;
    logic [31:0] beat_addr;
    logic [63:0] beat_data;
    logic        aw_sent;
    logic        w_sent;
    logic [OUTSTANDING_W-1:0] outstanding_count;

    logic [31:0] fifo_addr0;
    logic [31:0] fifo_addr1;
    logic [63:0] fifo_data64;

    logic        aw_fire;
    logic        w_fire;
    logic        aw_sent_next;
    logic        w_sent_next;
    logic        beat_done_now;
    logic        b_handshake;
    logic [OUTSTANDING_W-1:0] outstanding_count_next;
    logic        source_available;
    logic        can_load_beat;

    assign rst_n = ~rst;

    palette inst_palette(
        .clk(clk),
        .rst_n(rst_n),
        .iter(out_iter),
        .rgb(rgb_col)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            pix_done_d1 <= 1'b0;
            pix_done_d2 <= 1'b0;
            pix_id_d1 <= '0;
            pix_id_d2 <= '0;
            render_bank_d1 <= 1'b0;
            render_bank_d2 <= 1'b0;
            frame_base_valid_d <= 1'b0;
        end else begin
            pix_done_d1 <= pix_done;
            pix_done_d2 <= pix_done_d1;
            pix_id_d1 <= out_pix_id;
            pix_id_d2 <= pix_id_d1;
            render_bank_d1 <= render_bank;
            render_bank_d2 <= render_bank_d1;
            frame_base_valid_d <= (frame_base_0 != 32'd0) && (frame_base_1 != 32'd0);
        end
    end

    assign fifo_wr_en = pix_done_d2 & (pix_id_d2 < FRAME_RAY_COUNT) & frame_base_valid_d;
    assign fifo_wr_data = {render_bank_d2, pix_id_d2, rgb_col};

    FIFO #(
        .WIDTH(ENTRY_W),
        .DEPTH(FIFO_DEPTH),
        .ALMOST_FULL_LEVEL(FIFO_ALMOST_FULL)
    ) inst_result_fifo (
        .clk(clk),
        .rst(rst),
        .wr_en(fifo_wr_en),
        .wr_data(fifo_wr_data),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .FIFO_FULL(fifo_full),
        .FIFO_EMPTY(fifo_empty),
        .FIFO_ALMOST_FULL(fifo_almost_full)
    );

    assign fifo_addr0 = entry_addr_top(fifo_rd_data);
    assign fifo_addr1 = fifo_addr0 + 32'd4096;
    assign fifo_data64 = entry_data64(fifo_rd_data);

    assign m_axi_awaddr = beat_addr;
    assign m_axi_awlen = 4'd0;
    assign m_axi_awsize = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 3'b000;
    assign m_axi_awvalid = beat_valid & ~aw_sent;
    assign m_axi_wdata = beat_data;
    assign m_axi_wstrb = 8'hFF;
    assign m_axi_wlast = 1'b1;
    assign m_axi_wvalid = beat_valid & ~w_sent;
    assign m_axi_bready = 1'b1;
    assign debug_status = 32'd0;

    assign aw_fire = m_axi_awvalid & m_axi_awready;
    assign w_fire = m_axi_wvalid & m_axi_wready;
    assign aw_sent_next = aw_sent | aw_fire;
    assign w_sent_next = w_sent | w_fire;
    assign beat_done_now = beat_valid & aw_sent_next & w_sent_next;
    assign b_handshake = m_axi_bvalid & m_axi_bready;
    assign source_available = row_sel | !fifo_empty;
    assign can_load_beat = (!beat_valid || beat_done_now) &&
                           (outstanding_count_next < MAX_OUTSTANDING) &&
                           source_available;
    assign fifo_rd_en = can_load_beat & row_sel;
    assign drained = fifo_empty & ~row_sel & ~beat_valid & (outstanding_count == '0) &
                     ~pix_done_d1 & ~pix_done_d2;

    always_comb begin
        outstanding_count_next = outstanding_count;

        if (b_handshake && (outstanding_count_next != '0)) begin
            outstanding_count_next = outstanding_count_next - 1'b1;
        end

        if (beat_done_now) begin
            outstanding_count_next = outstanding_count_next + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            row_sel <= 1'b0;
            beat_valid <= 1'b0;
            beat_addr <= '0;
            beat_data <= '0;
            aw_sent <= 1'b0;
            w_sent <= 1'b0;
            outstanding_count <= '0;
        end else begin
            outstanding_count <= outstanding_count_next;

            if (can_load_beat) begin
                beat_valid <= 1'b1;
                beat_addr <= row_sel ? fifo_addr1 : fifo_addr0;
                beat_data <= fifo_data64;
                aw_sent <= 1'b0;
                w_sent <= 1'b0;
                row_sel <= ~row_sel;
            end else if (beat_done_now) begin
                beat_valid <= 1'b0;
                aw_sent <= 1'b0;
                w_sent <= 1'b0;
            end else if (beat_valid) begin
                aw_sent <= aw_sent_next;
                w_sent <= w_sent_next;
            end
        end
    end

endmodule
