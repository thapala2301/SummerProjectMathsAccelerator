`timescale 1ns / 1ps

module fft_bridge(
    input  wire             aclk,
    input  wire             aresetn,
    //cordic output
    input  wire [63:0]      s_axis_tdata,
    input  wire             s_axis_tlast,
    input  wire             s_axis_tvalid,
    output wire             s_axis_tready,
    //input from pixel_dispatch.sv
    input  wire [10:0]      x_pixel,
    input  wire [9:0]       y_pixel,
    // Output to scene_sdf.v (Geometry)
    output wire [26:0] out_b_fp,      // Box Scale  (bass)
    output wire [26:0] out_e_fp,      // Edge Thickness (mid)

    // Output to Camera / Global control
    output wire [26:0] out_cam_speed, // Camera Speed  (total energy)
    output wire [26:0] out_flash,     // Flashing Rate (treble)

    // Output to iter_to_rgb.sv (Color)
    output wire [26:0] out_color_r,   // Red   (Driven by Bass)
    output wire [26:0] out_color_g,   // Green (Driven by Mid)
    output wire [26:0] out_color_b    // Blue  (Driven by Treble)
);

assign s_axis_tready = 1'b1;

// =========================================================
// PROCESS 1: Bin counter (tracks which FFT bin is arriving)
// =========================================================
reg [8:0] bin_counter;
always @(posedge aclk) begin
    if (!aresetn) begin
        bin_counter <= 9'd0;
    end
    else if (s_axis_tvalid && s_axis_tready) begin
        if (s_axis_tlast)
            bin_counter <= 9'd0;
        else
            bin_counter <= bin_counter + 9'd1;
    end
end

// =========================================================
// PROCESS 2: Energy accumulation per frequency band
//
// Accumulators are cleared at the START of every frame
// (x=0, y=0). This is the same moment the output registers
// below are latched, so the pipeline is:
//   frame N accumulates during scan → latch at (0,0) →
//   outputs hold for all of frame N+1 → clear for frame N+2
// =========================================================
localparam [8:0] BASS_MAX   = 9'd10;
localparam [8:0] MID_MAX    = 9'd150;

reg [39:0] bass, mid, treble, E_total;

always @(posedge aclk) begin
    if (!aresetn) begin
        bass    <= 40'd0;
        mid     <= 40'd0;
        treble  <= 40'd0;
        E_total <= 40'd0;
    end
    else if (x_pixel == 11'd0 && y_pixel == 10'd0) begin
        // Start of new frame: clear ready for next accumulation
        bass    <= 40'd0;
        mid     <= 40'd0;
        treble  <= 40'd0;
        E_total <= 40'd0;
    end
    else if (s_axis_tvalid && s_axis_tready) begin
        E_total <= E_total + {13'd0, s_axis_tdata[26:0]};
        if (bin_counter <= BASS_MAX)
            bass   <= bass   + {13'd0, s_axis_tdata[26:0]};
        else if (bin_counter <= MID_MAX)
            mid    <= mid    + {13'd0, s_axis_tdata[26:0]};
        else
            treble <= treble + {13'd0, s_axis_tdata[26:0]};
    end
end

// =========================================================
// PROCESS 3: Sensitivity slices
// Tweak these bit ranges in the lab if effects are
// too strong (shift higher) or too weak (shift lower).
// =========================================================
wire [31:0] slice_bass   = bass[35:4];    // 11  bins, >>4
wire [31:0] slice_mid    = mid[35:4];     // 140 bins, >>4
wire [31:0] slice_treble = treble[33:2];  // 361 bins, >>2  (treble usually quieter)
wire [31:0] slice_total  = E_total[38:7]; // 512 bins, >>7  (very large number)

// =========================================================
// PROCESS 4: Integer → floating-point conversion
// Internal combinational wires (not stable across frame)
// =========================================================
wire [26:0] comb_b_fp, comb_e_fp, comb_cam_speed, comb_flash;
wire [26:0] comb_color_r, comb_color_g, comb_color_b;

// --- Geometry ---
int2fp conv_scale  (.in(slice_bass),   .out(comb_b_fp));
int2fp conv_thick  (.in(slice_mid),    .out(comb_e_fp));

// --- Camera & Effects ---
int2fp conv_camera (.in(slice_total),  .out(comb_cam_speed));
int2fp conv_flash  (.in(slice_treble), .out(comb_flash));

// --- RGB colour mapping ---
int2fp conv_red    (.in(slice_bass),   .out(comb_color_r));
int2fp conv_green  (.in(slice_mid),    .out(comb_color_g));
int2fp conv_blue   (.in(slice_treble), .out(comb_color_b));

// =========================================================
// PROCESS 5: Frame-stable output registers
//
// Latched once per frame at pixel (0,0) so every pixel in
// the ray-marcher pipeline sees the SAME audio snapshot.
// Default values match scene_sdf's original hardcoded
// constants so the sponge looks correct before audio starts.
// =========================================================
reg [26:0] out_b_fp_r, out_e_fp_r, out_cam_speed_r, out_flash_r;
reg [26:0] out_color_r_r, out_color_g_r, out_color_b_r;

always @(posedge aclk) begin
    if (!aresetn) begin
        out_b_fp_r      <= {1'b0, 8'd127, 18'h00000}; // 1.0  (original b)
        out_e_fp_r      <= {1'b0, 8'd124, 18'h0CCCD}; // 0.15 (original e)
        out_cam_speed_r <= 27'd0;
        out_flash_r     <= 27'd0;
        out_color_r_r   <= 27'd0;
        out_color_g_r   <= 27'd0;
        out_color_b_r   <= 27'd0;
    end
    else if (x_pixel == 11'd0 && y_pixel == 10'd0) begin
        // Latch the just-finished frame's accumulated values
        out_b_fp_r      <= comb_b_fp;
        out_e_fp_r      <= comb_e_fp;
        out_cam_speed_r <= comb_cam_speed;
        out_flash_r     <= comb_flash;
        out_color_r_r   <= comb_color_r;
        out_color_g_r   <= comb_color_g;
        out_color_b_r   <= comb_color_b;
    end
end

// Drive stable registered values to output ports
assign out_b_fp      = out_b_fp_r;
assign out_e_fp      = out_e_fp_r;
assign out_cam_speed = out_cam_speed_r;
assign out_flash     = out_flash_r;
assign out_color_r   = out_color_r_r;
assign out_color_g   = out_color_g_r;
assign out_color_b   = out_color_b_r;

endmodule
