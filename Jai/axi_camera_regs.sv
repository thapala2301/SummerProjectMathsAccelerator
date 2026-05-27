// Register Map (word-addressed, 32-bit each):
//   0x00  lookat[0][0]  — row0, col0   (right.x)
//   0x04  lookat[0][1]  — row0, col1   (right.y)
//   0x08  lookat[0][2]  — row0, col2   (right.z)
//   0x0C  lookat[1][0]  — row1, col0   (up.x)
//   0x10  lookat[1][1]  — row1, col1   (up.y)
//   0x14  lookat[1][2]  — row1, col2   (up.z)
//   0x18  lookat[2][0]  — row2, col0   (forward.x)
//   0x1C  lookat[2][1]  — row2, col1   (forward.y)
//   0x20  lookat[2][2]  — row2, col2   (forward.z)
//   0x24  cam_origin.x
//   0x28  cam_origin.y
//   0x2C  cam_origin.z

module axi_camera_regs #(
    parameter int DATA_W = 32,          // AXI data bus width
    parameter int ADDR_W = 6            // 6-bit address space covers 0x00–0x2C
) (
    // AXI4-Lite clock / reset
    input  logic                aclk,
    input  logic                aresetn,        // active-low synchronous reset

    //Write address channel
    input  logic [ADDR_W-1:0]   s_axi_awaddr,
    input  logic                s_axi_awvalid,
    output logic                s_axi_awready,

    //Write Data Channel
    input  logic [DATA_W-1:0]   s_axi_wdata,
    input  logic [DATA_W/8-1:0] s_axi_wstrb,
    input  logic                s_axi_wvalid,
    output logic                s_axi_wready,

    //Write Response Channel
    output logic [1:0]          s_axi_bresp,
    output logic                s_axi_bvalid,
    input  logic                s_axi_bready,

    //Read Address Channe
    input  logic [ADDR_W-1:0]   s_axi_araddr,
    input  logic                s_axi_arvalid,
    output logic                s_axi_arready,

    //Read Data Channel
    output logic [DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]          s_axi_rresp,
    output logic                s_axi_rvalid,
    input  logic                s_axi_rready,

    //Register outputs to ray_gen pipeline
    // Lookat matrix as a flat array: lookat[row][col] = mat[row*3+col]
    output logic signed [DATA_W-1:0] lookat [0:8],   // 9 entries
    output logic signed [DATA_W-1:0] cam_origin [0:2] // x, y, z
);

    // Internal register file — 12 x 32-bit words
    logic [DATA_W-1:0] regfile [0:11];

    // Map flat regfile to named outputs
    // Lookat rows: right(0-2), up(3-5), forward(6-8)
    genvar gi;
    generate
        for (gi = 0; gi < 9; gi++) begin : gen_lookat
            assign lookat[gi] = $signed(regfile[gi]);
        end
        for (gi = 0; gi < 3; gi++) begin : gen_origin
            assign cam_origin[gi] = $signed(regfile[9 + gi]);
        end
    endgenerate

    // Write path
    logic [ADDR_W-1:0] aw_addr_latch;
    logic              aw_pending;     // address received, waiting for data
    logic              w_pending;      // data received, waiting for address
    logic [DATA_W-1:0] w_data_latch;
    logic [DATA_W/8-1:0] w_strb_latch;

    // AW ready: accept a new address whenever we are not already holding one
    assign s_axi_awready = ~aw_pending;
    // W  ready: accept new data whenever we are not already holding data
    assign s_axi_wready  = ~w_pending;

    // Write-response: OKAY, no error model needed
    assign s_axi_bresp = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            aw_pending   <= 1'b0;
            w_pending    <= 1'b0;
            s_axi_bvalid <= 1'b0;
            // Default identity lookat matrix (camera looking down -Z, standard right-hand)
            // Right   = [1, 0, 0]
            regfile[0] <= 32'h2000_0000; // 1.0 in Q2.29
            regfile[1] <= 32'h0;
            regfile[2] <= 32'h0;
            // Up      = [0, 1, 0]
            regfile[3] <= 32'h0;
            regfile[4] <= 32'h2000_0000;
            regfile[5] <= 32'h0;
            // Forward = [0, 0, -1]
            regfile[6] <= 32'h0;
            regfile[7] <= 32'h0;
            regfile[8] <= 32'hE000_0000; // -1.0 in Q2.29 (two's complement)
            // Origin  = [0, 0, 0]
            regfile[9]  <= 32'h0;
            regfile[10] <= 32'h0;
            regfile[11] <= 32'h0;
        end else begin
            //Capture write address
            if (s_axi_awvalid && s_axi_awready) begin
                aw_addr_latch <= s_axi_awaddr;
                aw_pending    <= 1'b1;
            end

            //Capture write data
            if (s_axi_wvalid && s_axi_wready) begin
                w_data_latch  <= s_axi_wdata;
                w_strb_latch  <= s_axi_wstrb;
                w_pending     <= 1'b1;
            end

            //Perform write when both address and data are available
            if (aw_pending && w_pending) begin
                automatic int word_idx = int'(aw_addr_latch[ADDR_W-1:2]); // byte→word
                if (word_idx < 12) begin
                    // Byte-enable support
                    for (int b = 0; b < 4; b++) begin
                        if (w_strb_latch[b])
                            regfile[word_idx][b*8 +: 8] <= w_data_latch[b*8 +: 8];
                    end
                end
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end

            //Clear bvalid once master accepts
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    // Read path 1 cycle
    assign s_axi_arready = 1'b1;   // always ready to accept read address
    assign s_axi_rresp   = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                automatic int ridx = int'(s_axi_araddr[ADDR_W-1:2]);
                s_axi_rdata  <= (ridx < 12) ? regfile[ridx] : '0;
                s_axi_rvalid <= 1'b1;
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule

