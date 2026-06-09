/*
Feedback loop with march core. Decides whether to send new pixel into march core
or re send an existing ray that needs another march iteration. Has internal FIFO.
if ray is not done yet, fb_valid is high from mc and ray is pushed into FIFO.
Next clk its possed from FIFO; and only when FIFO empty are new pixels accepted from dispatch
stall is high if FIFO full, tell dispatch to wait

Inputs: x,y, pix_id, valid and all mc signals.
Outputs: complete ray descriptor per clk, when valid
*/

module feedback_ctrl (
    input logic        clk,
    input logic        rst,

// Comes from pixel dispatch
    input logic [10:0] x_pixel,
    input logic [9:0]  y_pixel,
    input logic        valid,
    input logic [19:0] pix_id,

//Comes from Vincent if next iteration required (feedback loop)
    input logic [19:0] fb_pix_id,
    input logic [31:0] fb_pos_x,
    input logic [31:0] fb_pos_y,
    input logic [31:0] fb_pos_z,
    input logic [31:0] fb_ray_dir_x,
    input logic [31:0] fb_ray_dir_y,
    input logic [31:0] fb_ray_dir_z,
    input logic [7:0]  fb_iteration_count,
    input logic        fb_validity,

    input logic        pipeline_ready,

//Goes to Vincent
    output logic [10:0] out_x, //px coords, for ray gen on first iter
    output logic [9:0]  out_y,
    output logic [19:0] out_pix_id, 
    output logic [26:0] out_pos_x, //current 3d pos of ray tip
    output logic [26:0] out_pos_y,
    output logic [26:0] out_pos_z, 
    output logic [26:0] out_ray_dir_x, //ray dir, normalized
    output logic [26:0] out_ray_dir_y,
    output logic [26:0] out_ray_dir_z,
    output logic [7:0]  out_iteration_count, //how many steps so far
    output logic        out_validity, //whether output is valid ray to process

    output logic        stall //backpressure for dispatch
);

    //pix id: 20 bits, pos_x,y,z: 27*3==81 bits, dir_x,y,z = 27*3 = 81 bits, iter count : 8 bits
    //total 190 bits, each FIFO entry holds all these entries needed to resume a ray mid marching
    logic [189:0] fifo_rd_data; 
    logic         fifo_full;
    logic         fifo_empty;

    //fifo inst
    FIFO #(
        .WIDTH(190),
        .DEPTH(128)
    ) fifo_inst (
        .clk(clk),
        .rst(rst),
        .wr_en(fb_validity),
        .wr_data({fb_pix_id, fb_pos_x[26:0], fb_pos_y[26:0], fb_pos_z[26:0],
                  fb_ray_dir_x[26:0], fb_ray_dir_y[26:0], fb_ray_dir_z[26:0],
                  fb_iteration_count}),
        .rd_en(pipeline_ready && !fifo_empty),
        .rd_data(fifo_rd_data),
        .FIFO_FULL(fifo_full),
        .FIFO_EMPTY(fifo_empty)
    );

    assign stall = !fifo_empty || fifo_full;

    always_ff @(posedge clk) begin
        if (rst) begin
            out_x               <= 1'b0;
            out_y               <= 1'b0;
            out_pix_id          <= 1'b0;
            out_pos_x           <= 1'b0;
            out_pos_y           <= 1'b0;
            out_pos_z           <= 1'b0;
            out_ray_dir_x       <= 1'b0;
            out_ray_dir_y       <= 1'b0;
            out_ray_dir_z       <= 1'b0;
            out_iteration_count <= 1'b0;
            out_validity        <= 1'b0;
        end
        else if (!fifo_empty && pipeline_ready) begin
            //existing pixel (already marched) dispatch
            out_x               <= 1'b0; //0 placeholder for X/don't care: we have already marched the ray so don't care about initial pos on screen
            out_y               <= 1'b0;
            out_pix_id          <= fifo_rd_data[189:170]; //send the actual data to continue marching
            out_pos_x           <= fifo_rd_data[169:143];
            out_pos_y           <= fifo_rd_data[142:116];
            out_pos_z           <= fifo_rd_data[115:89];
            out_ray_dir_x       <= fifo_rd_data[88:62];
            out_ray_dir_y       <= fifo_rd_data[61:35];
            out_ray_dir_z       <= fifo_rd_data[34:8];
            out_iteration_count <= fifo_rd_data[7:0];
            out_validity        <= 1'b1;
        end
        else if (fifo_empty && pipeline_ready && valid) begin
            //new pixel coming in, store only its coordinates on the screen as it has not been marched yet (this will be fed to ray gen).
            out_x               <= x_pixel;
            out_y               <= y_pixel;
            out_pix_id          <= pix_id;
            out_pos_x           <= 1'b0;
            out_pos_y           <= 1'b0;
            out_pos_z           <= 1'b0;
            out_ray_dir_x       <= 1'b0;
            out_ray_dir_y       <= 1'b0;
            out_ray_dir_z       <= 1'b0;
            out_iteration_count <= 1'b0;
            out_validity        <= 1'b1;
        end
        else begin
            out_validity        <= 1'b0;
        end
    end

endmodule