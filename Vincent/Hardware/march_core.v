module march_core(
    input clk,
    input rst_n,
    //from feedback_ctrl
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [19:0] in_pix_id,
    input wire [31:0] in_pos_x, in_pos_y, in_pos_z,
    input wire [31:0] in_ray_dir_x, in_ray_dir_y, in_ray_dir_z,
    input wire [7:0] in_iter,
    input wire in_valid,
    //feedback to feedback_ctrl
    output wire [19:0] fb_pix_id,
    output wire [31:0] fb_pos_x, fb_pos_y, fb_pos_z,
    output wire [31:0] fb_ray_dir_x, fb_ray_dir_y, fb_ray_dir_z,
    output wire [7:0] fb_iter,
    output wire fb_valid,
    //to fb_write, iter_to_rgb
    output wire [19:0] out_pix_id,
    output wire [7:0] out_iter,
    output wire pix_done
);

endmodule