`timescale 1ns / 1ps

module tb_march_core;

    reg clk;
    reg rst_n;
    
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end
    
    initial begin
        rst_n = 0;
        #20 rst_n = 1;
    end
    
    integer cycle_cnt = 0;
    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
    end

    reg [10:0] in_x;
    reg [9:0] in_y;
    reg [19:0] in_pix_id;
    reg [26:0] in_pos_x, in_pos_y, in_pos_z;
    reg [26:0] in_ray_dir_x, in_ray_dir_y, in_ray_dir_z;
    reg [7:0] in_iter;
    reg in_valid;

    reg [26:0] lookat [0:8];
    reg [26:0] cam_origin [0:2];

    wire pix_done;
    wire [19:0] out_pix_id;
    wire [7:0] out_iter;

    wire [7:0] fb_iter;
    wire [26:0] fb_ray_dir_x, fb_ray_dir_y, fb_ray_dir_z;
    wire [26:0] fb_pos_x, fb_pos_y, fb_pos_z;
    wire [19:0] fb_pix_id;
    wire fb_valid;

    // Instances
    march_core dut(
        .clk(clk),
        .rst_n(rst_n),
        
        .in_x(in_x),
        .in_y(in_y),
        .in_pix_id(in_pix_id),
        .in_pos_x(in_pos_x),
        .in_pos_y(in_pos_y),
        .in_pos_z(in_pos_z),
        .in_ray_dir_x(in_ray_dir_x),
        .in_ray_dir_y(in_ray_dir_y),
        .in_ray_dir_z(in_ray_dir_z),
        .in_iter(in_iter),
        .in_valid(in_valid),
        
        .lookat(lookat),
        .cam_origin(cam_origin),
        
        .pix_done(pix_done),
        .out_pix_id(out_pix_id),
        .out_iter(out_iter),
        
        .fb_iter(fb_iter),
        .fb_ray_dir_x(fb_ray_dir_x),
        .fb_ray_dir_y(fb_ray_dir_y),
        .fb_ray_dir_z(fb_ray_dir_z),
        .fb_pos_x(fb_pos_x),
        .fb_pos_y(fb_pos_y),
        .fb_pos_z(fb_pos_z),
        .fb_pix_id(fb_pix_id),
        .fb_valid(fb_valid)
    );

    integer pixel_start_cycle [0:1023];
    reg pixel_is_valid [0:1023];
    
    integer lat_min = 999999;
    integer lat_max = 0;
    integer pixels_done = 0;
    
    reg inject_pixel = 0;
    reg [10:0] inject_x;
    reg [9:0] inject_y;
    reg [19:0] inject_pix_id;
    
    integer p;
    initial begin
        for (p = 0; p < 1024; p = p + 1) begin
            pixel_is_valid[p] = 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (inject_pixel) begin
                in_valid <= 1;
                in_iter <= 0;
                in_x <= inject_x;
                in_y <= inject_y;
                in_pix_id <= inject_pix_id;
                in_pos_x <= 0; in_pos_y <= 0; in_pos_z <= 0;
                in_ray_dir_x <= 0; in_ray_dir_y <= 0; in_ray_dir_z <= 0;
            end else if (fb_valid) begin
                in_valid <= 1;
                in_iter <= fb_iter;
                in_pos_x <= fb_pos_x;
                in_pos_y <= fb_pos_y;
                in_pos_z <= fb_pos_z;
                in_ray_dir_x <= fb_ray_dir_x;
                in_ray_dir_y <= fb_ray_dir_y;
                in_ray_dir_z <= fb_ray_dir_z;
                in_pix_id <= fb_pix_id;
            end else begin
                in_valid <= 0;
            end
        end
    end



    integer lat;
    always @(posedge clk) begin
        if (pix_done) begin
            if (pixel_is_valid[out_pix_id]) begin
                lat = cycle_cnt - pixel_start_cycle[out_pix_id];
                if (lat < lat_min) lat_min = lat;
                if (lat > lat_max) lat_max = lat;
                pixels_done = pixels_done + 1;
                $display("Pixel %0d finished in %0d iterations, latency = %0d cycles.", out_pix_id, out_iter, lat);
            end else begin
                $display("Error: Pixel %0d finished", out_pix_id);
                $stop;
            end
        end
    end

    always @(posedge clk) begin
        if (cycle_cnt > 1000000) begin
            $display("Error: Simulation Timed out");
            $stop;
        end
    end

    initial begin
        in_valid = 0;
        in_iter = 0;
        
        lookat[0] = 27'h0FC0000; lookat[1] = 0;          lookat[2] = 0;
        lookat[3] = 0;          lookat[4] = 27'h0FC0000; lookat[5] = 0;
        lookat[6] = 0;          lookat[7] = 0;          lookat[8] = 27'h0FC0000;
        
        cam_origin[0] = 0;
        cam_origin[1] = 0;
        cam_origin[2] = {1'b1, 8'd129, 18'b010000000000000000}; 
        
        @(posedge rst_n);
        @(posedge clk);
        
        inject_x = 11'd640;
        inject_y = 10'd360;
        inject_pix_id = 20'd1;
        inject_pixel = 1;
        pixel_start_cycle[1] = cycle_cnt + 2;
        pixel_is_valid[1] = 1;
        
        @(posedge clk);
        inject_pixel = 0; 
        
        wait(pixels_done == 1);
        
        inject_x = 11'd10;
        inject_y = 10'd10;
        inject_pix_id = 20'd2;
        inject_pixel = 1;
        pixel_start_cycle[2] = cycle_cnt + 2;
        pixel_is_valid[2] = 1;
        
        @(posedge clk);
        inject_pixel = 0;
        
        wait(pixels_done == 2);
        
        cam_origin[0] = 0;
        cam_origin[1] = 0;
        cam_origin[2] = 0; 
        inject_x = 11'd20;
        inject_y = 10'd20;
        inject_pix_id = 20'd3;
        inject_pixel = 1;
        pixel_start_cycle[3] = cycle_cnt + 2;
        pixel_is_valid[3] = 1;
        
        @(posedge clk);
        inject_pixel = 0;
        wait(pixels_done == 3);

        cam_origin[0] = 0;
        cam_origin[1] = 0;
        cam_origin[2] = {1'b0, 8'd134, 18'h00000}; 
        inject_x = 11'd30;
        inject_y = 10'd30;
        inject_pix_id = 20'd4;
        inject_pixel = 1;
        pixel_start_cycle[4] = cycle_cnt + 2;
        pixel_is_valid[4] = 1;
        
        @(posedge clk);
        inject_pixel = 0;
        wait(pixels_done == 4);
        
        $display("LATENCY REPORT");
        $display("MARCH_CORE : Min %0d cycles, Max %0d cycles", lat_min, lat_max);
        
        $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
