`timescale 1ns / 1ps

module test_pattern_gen (
    input  logic        clk,         
    input  logic        rst_n,
    output logic        wea,
    output logic [20:0] addra,
    output logic [7:0]  dina,
    output logic        write_bank
);

    logic [20:0] PIXELS_PER_FRAME = 21'd921600;

    // States
    typedef enum logic [1:0] {
        IDLE,
        WRITE_BRAM,
        DONE
    } my_state;

    my_state current_state, next_state;
    logic [20:0] write_addr;

    logic write_bank_reg;
    assign write_bank = write_bank_reg;

    // Registers
    always_ff @(posedge clk)
        if (!rst_n) begin
            current_state  <= IDLE;
            write_addr     <= 21'd0;
            write_bank_reg <= 1'b0;
            end
        else begin
            current_state <= next_state;
            
            if (current_state == WRITE_BRAM) begin
                if (write_addr >= PIXELS_PER_FRAME - 21'd1) begin
                    write_addr <= 21'd0;
                    write_bank_reg <= ~write_bank_reg;
                    end
                else
                    write_addr <= write_addr + 21'd1;
                end
            else if (current_state == IDLE)
                write_addr <= 21'd0;
            end

    // Next
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE:
                next_state = WRITE_BRAM;
            WRITE_BRAM:
                if (write_addr >= PIXELS_PER_FRAME - 21'd1)
                    next_state = IDLE; // Loop forever to test double buffering
            DONE:
                next_state = DONE;
            default:
                next_state = IDLE;
        endcase
    end

    // Outputs
    always_comb begin
        wea        = 1'b0;
        addra      = 21'd0;
        dina       = 8'd0;

        case (current_state)
            WRITE_BRAM: begin
                wea   = 1'b1;
                addra = write_addr;
                dina  = write_addr[7:0] ^ write_addr[15:8];
            end
            default: begin
                wea        = 1'b0;
                addra      = 21'd0;
                dina       = 8'd0;
            end
        endcase
    end

endmodule
