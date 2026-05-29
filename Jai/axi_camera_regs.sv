`timescale 1ns/1ps

module axi_camera_regs #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 6
) (
    input logic aclk,
    input logic aresetn,

    input logic [ADDR_W-1:0] s_axi_awaddr,
    input logic s_axi_awvalid,
    output logic s_axi_awready,

    input logic [DATA_W-1:0] s_axi_wdata,
    input logic [DATA_W/8-1:0] s_axi_wstrb,
    input logic s_axi_wvalid,
    output logic s_axi_wready,

    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input logic s_axi_bready,

    input logic [ADDR_W-1:0] s_axi_araddr,
    input logic s_axi_arvalid,
    output logic s_axi_arready,

    output logic [DATA_W-1:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input logic s_axi_rready,

    output logic [26:0] lookat [0:8],
    output logic [26:0] cam_origin [0:2]
);

    localparam logic [26:0] FP_ONE = 27'h1FC0000;
    localparam logic [26:0] FP_NEG_ONE = 27'h3FC0000;

    logic [DATA_W-1:0] regfile [0:11];

    genvar gi;
    generate
        for (gi = 0; gi < 9; gi++) begin : gen_lookat
            assign lookat[gi] = regfile[gi][26:0];
        end
        for (gi = 0; gi < 3; gi++) begin : gen_origin
            assign cam_origin[gi] = regfile[9 + gi][26:0];
        end
    endgenerate

    logic [ADDR_W-1:0] aw_addr_latch;
    logic aw_pending;
    logic w_pending;
    logic [DATA_W-1:0] w_data_latch;
    logic [DATA_W/8-1:0] w_strb_latch;

    assign s_axi_awready = ~aw_pending;
    assign s_axi_wready = ~w_pending;
    assign s_axi_bresp = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            s_axi_bvalid <= 1'b0;
            regfile[0] <= {5'h0, FP_ONE};
            regfile[1] <= '0;
            regfile[2] <= '0;
            regfile[3] <= '0;
            regfile[4] <= {5'h0, FP_ONE};
            regfile[5] <= '0;
            regfile[6] <= '0;
            regfile[7] <= '0;
            regfile[8] <= {5'h0, FP_NEG_ONE};
            regfile[9] <= '0;
            regfile[10] <= '0;
            regfile[11] <= '0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_addr_latch <= s_axi_awaddr;
                aw_pending <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_data_latch <= s_axi_wdata;
                w_strb_latch <= s_axi_wstrb;
                w_pending <= 1'b1;
            end
            if (aw_pending && w_pending) begin
                automatic int word_idx = int'(aw_addr_latch[ADDR_W-1:2]);
                if (word_idx < 12) begin
                    for (int b = 0; b < 4; b++) begin
                        if (w_strb_latch[b])
                            regfile[word_idx][b*8 +: 8] <= w_data_latch[b*8 +: 8];
                    end
                end
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    assign s_axi_arready = 1'b1;
    assign s_axi_rresp = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= '0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                automatic int ridx = int'(s_axi_araddr[ADDR_W-1:2]);
                s_axi_rdata <= (ridx < 12) ? regfile[ridx] : '0;
                s_axi_rvalid <= 1'b1;
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule
