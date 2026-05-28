`timescale 1ns / 1ps

module hdmi_timing (
    input  logic clk_74_25,      
    input  logic rst_n,          
    
    output logic hsync,
    output logic vsync,
    output logic active_video,
    output logic [11:0] pixel_x,
    output logic [11:0] pixel_y
);

    logic [11:0] H_ACTIVE  = 12'd1280;
    logic [11:0] H_FRONT   = 12'd110;
    logic [11:0] H_SYNC    = 12'd40;
    logic [11:0] H_BACK    = 12'd220;
    logic [11:0] H_TOTAL   = 12'd1650;

    logic [11:0] V_ACTIVE  = 12'd720;
    logic [11:0] V_FRONT   = 12'd5;
    logic [11:0] V_SYNC    = 12'd5;
    logic [11:0] V_BACK    = 12'd20;
    logic [11:0] V_TOTAL   = 12'd750;

    logic [11:0] H_SYNC_START = H_ACTIVE + H_FRONT;
    logic [11:0] H_SYNC_END   = H_SYNC_START + H_SYNC;
    
    logic [11:0] V_SYNC_START = V_ACTIVE + V_FRONT;
    logic [11:0] V_SYNC_END   = V_SYNC_START + V_SYNC;

    logic [11:0] h_count;
    logic [11:0] v_count;

    // Counters
    always_ff @(posedge clk_74_25)
        if (!rst_n) begin
            h_count <= 12'd0;
            v_count <= 12'd0;
            end
        else begin
            if (h_count == H_TOTAL - 12'd1) begin
                h_count <= 12'd0;
                if (v_count == V_TOTAL - 12'd1)
                    v_count <= 12'd0;
                else
                    v_count <= v_count + 12'd1;
                end
            else
                h_count <= h_count + 12'd1;
            end

    // Syncs
    always_ff @(posedge clk_74_25)
        if (!rst_n) begin
            hsync <= 1'b0;
            vsync <= 1'b0;
            active_video <= 1'b0;
            end
        else begin
            if ((h_count >= H_SYNC_START) && (h_count < H_SYNC_END))
                hsync <= 1'b1;
            else
                hsync <= 1'b0;
            
            if ((v_count >= V_SYNC_START) && (v_count < V_SYNC_END))
                vsync <= 1'b1;
            else
                vsync <= 1'b0;
                     
            if ((h_count < H_ACTIVE) && (v_count < V_ACTIVE))
                active_video <= 1'b1;
            else
                active_video <= 1'b0;
            end

    // Coords
    assign pixel_x = h_count;
    assign pixel_y = v_count;

endmodule
