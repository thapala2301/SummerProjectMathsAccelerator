`timescale 1ns/1ps

/*instantiates the camera registers from PS to PL through AXI Lite transactions
through GP0 port.
Takes as inputs AXILite signals from GP0 port from PS.
Oututs packed array lookat containing 3 xyz vectors for the world's basis
and packed array camorigin containing xyz coordinates for world origin,
as well as AXILite transaction signals
*/

module axi_camera_regs #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 7
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
    output logic [26:0] cam_origin [0:2],
    output logic [26:0] cam_origin_right [0:2],
    output logic [26:0] sdf_params [0:7]
    /*in sdf params:
    0->cell sz
    1->b_fp
    2->e_fp
    3->fog_density
    4->march_epsilon
    5->palette shift value
    6,7->morph blend
    Extend if needed
    */
);

    // 1.0:  sign=0, exp=127=0x7F, frac=0  -> {1'b0, 8'h7F, 18'h0} = 27'h1FC0000
    // -1.0: sign=1, exp=127=0x7F, frac=0  -> {1'b1, 8'h7F, 18'h0} = 27'h5FC0000
    localparam logic [26:0] FP_ONE = 27'h1FC0000;
    localparam logic [26:0] FP_NEG_ONE = 27'h5FC0000;

    // Regfile layout:
    //  [0:8]   lookat (9 entries)
    //  [9:11]  cam_origin left eye (3 entries)
    //  [12:14] cam_origin right eye (3 entries)
    //  [15:22] sdf_params (8 entries)
    logic [DATA_W-1:0] regfile [0:22];

    genvar gi;
    generate
        for (gi = 0; gi < 9; gi++) begin : gen_lookat
            assign lookat[gi] = regfile[gi][26:0];
        end
        for (gi = 0; gi < 3; gi++) begin : gen_origin
            assign cam_origin[gi]       = regfile[9  + gi][26:0];
            assign cam_origin_right[gi] = regfile[12 + gi][26:0];
        end
        for (gi = 0; gi < 8; gi++) begin : gen_sdf_params
            assign sdf_params[gi] = regfile[15 + gi][26:0];
        end
    endgenerate

    //latch different AXI Lite components: A, AW, B, R signals to keep them while waiting for all other AXI Lite components to be valid
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
            regfile[12] <= '0;  // cam_origin_right x
            regfile[13] <= '0;  // cam_origin_right y
            regfile[14] <= '0;  // cam_origin_right z
            regfile[15] <= {5'h0, 27'h2090000}; // cell_sz default 10.0
            regfile[16] <= {5'h0, 27'h2048000}; // b_fp default 4.5
            regfile[17] <= {5'h0, 27'h1F0CCCD}; // e_fp default 0.15
            regfile[18] <= '0;
            regfile[19] <= '0;
            regfile[20] <= '0;
            regfile[21] <= '0;
            regfile[22] <= '0;
        end else begin
            //if slave (PL) ready to accept adress and adress is valid, latch it and wait for other components to be ready
            if (s_axi_awvalid && s_axi_awready) begin
                aw_addr_latch <= s_axi_awaddr;
                aw_pending <= 1'b1;
            end
            //if slave (PL) ready to accept write data and data is valid, latch it and wait for other components to be ready
            if (s_axi_wvalid && s_axi_wready) begin
                w_data_latch <= s_axi_wdata;
                w_strb_latch <= s_axi_wstrb;
                w_pending <= 1'b1;
            end
            //if slave (PL) is pending on adress write and have write data, start writing to regfile
            if (aw_pending && w_pending) begin
                //convert the adress to an int for accessing element of packed array reg file
                //automatic keyword: instantiation of word_idx contained to for loop
                automatic int word_idx = int'(aw_addr_latch[ADDR_W-1:2]);
                if (word_idx < 23) begin
                    for (int b = 0; b < 4; b++) begin
                        if (w_strb_latch[b])
                            //w_strb strobe masks bytes if 0
                            //copy one byte byte after byte, but only those that aren't masked
                            regfile[word_idx][b*8 +: 8] <= w_data_latch[b*8 +: 8];
                    end
                end
                //at end of transaction
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            //reset valid after end of transaction
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    //always assume ready to read, and that read response is ok
    assign s_axi_arready = 1'b1;
    assign s_axi_rresp = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= '0;
        end else begin
            //if have both adress for reading and ready to read
            if (s_axi_arvalid && s_axi_arready) begin
                automatic int ridx = int'(s_axi_araddr[ADDR_W-1:2]);
                s_axi_rdata <= (ridx < 23) ? regfile[ridx] : '0;
                s_axi_rvalid <= 1'b1;
            end
            //if read transaction done
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule
