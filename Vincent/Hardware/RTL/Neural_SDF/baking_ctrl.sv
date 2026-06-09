module baking_ctrl(
    input logic clk, rst,
    input logic start, //PS pulses this to begin the baking
    output logic done, //high when all points hv been baked

    //sdf_nn  interface
    output logic [26:0] x,y,z,
    output logic xyz_valid,
    input logic sdf_valid,
    input logic [26:0] sdf_dist,
    //BRAM write
    output logic [17:0] bram_addr, //sample space in 64 x 64 x 64 cubes so 18 bits
    output logic [26:0] bram_wdata,
    output logic bram_we
);

logic [5:0] ix, iy, iz; //0-63 as we just have 63 x 63 x 63 point grid
typedef enum logic [1:0] {IDLE, SEND, WAIT, DONE}  t_state ; //baking is send + wait
t_state curr_state;
t_state next_state;
always_ff @ (posedge clk) begin
    xyz_valid <= 0;
    bram_we <= 0 ; 
    if (rst) begin
        curr_state <= IDLE; next_state <= IDLE;
        ix <= 0; iy<= 0; iz<=0;
        done <= 0; xyz_valid <= 0; bram_we <= 0;
    end else begin
        case (curr_state)

        IDLE : if(start) next_state <= SEND;

        SEND: begin xyz_valid <= 1'b1; next_state <= WAIT; end

        //wait for SDF to compute, once its done send off to bram
        WAIT : begin
            if (sdf_valid) begin
                //got sdf, send it off!!
                bram_wdata <= sdf_dist;
                bram_we <= 1;
                bram_addr <= iz*64*64+iy*64+ix;
                //move next pt
                if (ix < 31) begin
                    ix <= ix+1;
                    next_state <= SEND;
                end
                else if (iy <31) begin
                    ix <= 0;
                    iy <= iy+1;
                    next_state <= SEND;
                end
                else if (iz < 31) begin
                    ix<=0;
                    iy <= 0;
                    iz<=iz+1;
                    next_state <= SEND;
                end
                else 
                    next_state <= DONE;
                end
        end

        DONE : begin done <= 1'b1; next_state <= IDLE; end

        default : next_state <= IDLE;
        endcase
        curr_state <= next_state;

    end
end

//convert ix iy iz to FP
int2fp inst1_x (.in({{26{1'b0}}, ix}), .out(x));
int2fp inst1_y (.in({{26{1'b0}}, iy}), .out(y));
int2fp inst1_z (.in({{26{1'b0}}, iz}), .out(z));

endmodule