module ddr_rgb_writer #(
    parameter int FIFO_DEPTH = 4096,
    parameter int FIFO_ALMOST_FULL = 512,
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
    output logic        m_axi_bready
);

    localparam int ENTRY_W = 45;
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
    logic        fifo_wr_en;
    logic        fifo_rd_en;
    logic [ENTRY_W-1:0] fifo_wr_data;
    logic [ENTRY_W-1:0] fifo_rd_data;
    logic        fifo_full;
    logic        fifo_empty;

    logic [ENTRY_W-1:0] current_entry;
    logic        current_entry_valid;
    logic        current_row_sel;
    logic        issue_active;
    logic [OUTSTANDING_W-1:0] outstanding_count;

    logic [31:0] addr_top;
    logic [31:0] addr_bottom;
    logic [31:0] issue_addr;
    logic [63:0] data64;
    logic [31:0] fifo_out_addr_top;
    logic [63:0] fifo_out_data64;
    logic [31:0] fifo_out_addr_top_q;
    logic [63:0] fifo_out_data64_q;

    logic aw_complete_now;
    logic w_complete_now;
    logic beat_complete_now;
    logic b_handshake;
    logic [OUTSTANDING_W-1:0] outstanding_count_next;
    logic        can_issue_now;
    logic        can_issue_next;

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
        end else begin
            pix_done_d1 <= pix_done;
            pix_done_d2 <= pix_done_d1;
            pix_id_d1 <= out_pix_id;
            pix_id_d2 <= pix_id_d1;
            render_bank_d1 <= render_bank;
            render_bank_d2 <= render_bank_d1;
        end
    end

    assign fifo_wr_en = pix_done_d2 & ~fifo_full;
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

    assign addr_top = entry_addr_top(current_entry);
    assign addr_bottom = addr_top + 32'd4096;
    assign issue_addr = current_row_sel ? addr_bottom : addr_top;
    assign data64 = entry_data64(current_entry);
    assign fifo_out_addr_top = entry_addr_top(fifo_rd_data);
    assign fifo_out_data64   = entry_data64(fifo_rd_data);

    // Pipeline register: breaks the read_ptr→RAMD64E→CARRY4→FF critical path.
    // Safe because fifo_rd_en is never asserted the cycle before these are consumed.
    always_ff @(posedge clk) begin
        fifo_out_addr_top_q <= fifo_out_addr_top;
        fifo_out_data64_q   <= fifo_out_data64;
    end


    assign m_axi_awlen   = 4'd0;
    assign m_axi_awsize  = 3'd3;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_wstrb   = 8'hFF;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_bready  = 1'b1;
    assign drained       = fifo_empty & ~current_entry_valid & ~issue_active &
                           ~pix_done_d1 & ~pix_done_d2 & (outstanding_count == '0);

    assign aw_complete_now   = (~m_axi_awvalid) | (m_axi_awvalid & m_axi_awready);
    assign w_complete_now    = (~m_axi_wvalid) | (m_axi_wvalid & m_axi_wready);
    assign beat_complete_now = aw_complete_now & w_complete_now;
    assign b_handshake       = m_axi_bvalid & m_axi_bready;
    assign can_issue_now     = (outstanding_count < MAX_OUTSTANDING);
    assign can_issue_next    = (outstanding_count_next < MAX_OUTSTANDING);

    always_comb begin
        outstanding_count_next = outstanding_count;

        if (b_handshake && (outstanding_count_next != '0)) begin
            outstanding_count_next = outstanding_count_next - 1'b1;
        end

        if (issue_active && beat_complete_now) begin
            outstanding_count_next = outstanding_count_next + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            current_entry <= '0;
            current_entry_valid <= 1'b0;
            current_row_sel <= 1'b0;
            issue_active <= 1'b0;
            outstanding_count <= '0;
            fifo_rd_en <= 1'b0;
            m_axi_awaddr <= '0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= '0;
            m_axi_wvalid <= 1'b0;
        end else begin
            outstanding_count <= outstanding_count_next;
            fifo_rd_en <= 1'b0;

            if (issue_active) begin
                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                end
                if (m_axi_wvalid && m_axi_wready) begin
                    m_axi_wvalid <= 1'b0;
                end

                if (beat_complete_now) begin
                    if (current_row_sel) begin
                        current_row_sel <= 1'b0;

                        if (!fifo_empty) begin
                            current_entry <= fifo_rd_data;
                            current_entry_valid <= 1'b1;
                            fifo_rd_en <= 1'b1;

                            if (can_issue_next) begin
                                m_axi_awaddr <= fifo_out_addr_top_q;
                                m_axi_wdata <= fifo_out_data64_q;
                                m_axi_awvalid <= 1'b1;
                                m_axi_wvalid <= 1'b1;
                                issue_active <= 1'b1;
                            end else begin
                                issue_active <= 1'b0;
                            end
                        end
                        else begin
                            current_entry_valid <= 1'b0;
                            issue_active <= 1'b0;
                        end
                    end else begin
                        current_row_sel <= 1'b1;

                        if (can_issue_next) begin
                            m_axi_awaddr <= addr_bottom;
                            m_axi_wdata <= data64;
                            m_axi_awvalid <= 1'b1;
                            m_axi_wvalid <= 1'b1;
                            issue_active <= 1'b1;
                        end else begin
                            issue_active <= 1'b0;
                        end
                    end
                end
            end else if (current_entry_valid && can_issue_now) begin
                m_axi_awaddr <= issue_addr;
                m_axi_wdata <= data64;
                m_axi_awvalid <= 1'b1;
                m_axi_wvalid <= 1'b1;
                issue_active <= 1'b1;
            end else if (!current_entry_valid && !fifo_empty) begin
                current_entry       <= fifo_rd_data;
                current_entry_valid <= 1'b1;
                current_row_sel     <= 1'b0;
                fifo_rd_en          <= 1'b1;

                if (can_issue_now) begin
                    m_axi_awaddr <= fifo_out_addr_top_q;
                    m_axi_wdata <= fifo_out_data64_q;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wvalid <= 1'b1;
                    issue_active <= 1'b1;
                end
            end
        end
    end

endmodule
