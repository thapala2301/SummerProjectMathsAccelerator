`timescale 1ns / 1ps

module config_sender(
    input  wire       aclk,
    input  wire       aresetn,
    input  wire       s_axis_config_tready,
    output reg        s_axis_config_tvalid,
    output reg  [7:0] s_axis_config_tdata,
    output reg        done
);

    // Constant for the configuration data
    localparam [7:0] FFT_CONFIG = 8'h01;

    // These MUST be localparam so Vivado knows they are constants for the case statement
    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] SEND = 2'b01;
    localparam [1:0] DONE = 2'b10;

    reg [1:0] state;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state                <= IDLE;
            s_axis_config_tvalid <= 1'b0;
            s_axis_config_tdata  <= 8'd0;
            done                 <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    state                <= SEND;
                    s_axis_config_tvalid <= 1'b0;
                    s_axis_config_tdata  <= 8'd0;
                    done                 <= 1'b0;
                end

                SEND: begin
                    s_axis_config_tvalid <= 1'b1;
                    s_axis_config_tdata  <= FFT_CONFIG;
                    done                 <= 1'b0;
                    if (s_axis_config_tready)
                        state <= DONE;
                    else
                        state <= SEND;
                end

                DONE: begin
                    state                <= DONE;
                    s_axis_config_tvalid <= 1'b0;
                    s_axis_config_tdata  <= 8'd0;
                    done                 <= 1'b1;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule