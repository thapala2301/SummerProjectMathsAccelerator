# RTL/top — Top-Level Integration

Wires every submodule together into a single synthesisable design and provides the PS interface.

---

## `top.sv`

The main FPGA top module. Everything plugs in here.

**Key responsibilities:**

- Unpacks the flat AXI-Lite input buses (`lookat_flat`, `cam_origin_flat`, `scene_ctrl_flat`) into structured arrays for use by `march_core`.
- Manages frame double-buffering: the renderer alternates between two DDR3 frame buffers (`frame_base_0` and `frame_base_1`). The active render bank is tracked by `render_bank`; when a frame completes the VDMA gets a `frame_ack` and swaps to the new buffer.
- Instantiates and connects: `pixel_dispatch` → `feedback_ctrl` → `march_core` → `ddr_rgb_writer`, plus the HDMI output path (`rgb2dvi` IP).
- Generates clocks: `clk_wiz_0` produces the 125 MHz system clock and the 371.25 MHz TMDS clock (5× pixel clock) for `rgb2dvi`.

**Frame dispatch gate:**

```verilog
assign frame_base_valid = (frame_base_0 != 32'd0) && (frame_base_1 != 32'd0);
assign dispatch_enable  = frame_base_valid && ~writer_fifo_almost_full;
```

Both DDR3 frame base addresses must be written by the PS before the renderer starts. If either is zero (unset), `dispatch_enable` stays low and no pixels are dispatched. This is the most common cause of a black screen after bitstream load — the Python script must write both `FRAME_BASE0_REG` and `FRAME_BASE1_REG` to valid DDR3 addresses before rendering starts.

**Scene parameters:**

`scene_ctrl_flat` is a 320-bit flat bus from the AXI-Lite register block carrying 10 scene parameters. `top.sv` unpacks these, latches them per-frame (so parameters update cleanly between frames rather than mid-render), and passes them into `march_core`.

Parameters include: `cell_sz`, `half_cell`, `shape_size`, `shape_extra`, `bg_rgb`, `shape_rgb`, `beat_pulse`, `level`, `spectral`, `noise`. Most are FP27 values written from Python; `bg_rgb` and `shape_rgb` are RGB24.

**HDMI path:**

The video data path is separate from the render path. `vid_data`, `vid_hsync`, `vid_vsync`, `vid_active` come from the PS-side VDMA read master, which reads the completed framebuffer from DDR3 and streams it to `top.sv` in the pixel clock domain. `top.sv` drives `rgb2dvi` with these signals to produce TMDS differential output.

---

## `top_ps.sv`

The Zynq PS wrapper that connects `top` to the AXI-Lite register bank (`axi_camera_regs`) and the VDMA. This is what gets instantiated in the Vivado block design.

The `axi_camera_regs` IP (in `ip_repo/`) exposes all camera and scene parameters as memory-mapped 32-bit registers accessible from the PS at base address `0x43C00000`.

**Register map** (offsets in `ctrl.py`):

| Register | Offset | Content |
|----------|--------|---------|
| lookat[0..8] | 0×4 .. 8×4 | 3×3 camera matrix, FP27 |
| cam_origin[0..2] | 9×4 .. 11×4 | Camera position, FP27 |
| frame_base_0 | 12×4 | DDR3 address for frame buffer 0 |
| frame_base_1 | 13×4 | DDR3 address for frame buffer 1 |
| scene_cell_sz | 14×4 | Domain repeat cell size, FP27 |
| scene_half_cell | 15×4 | Half cell size, FP27 |
| scene_shape_size | 16×4 | Primary shape parameter, FP27 |
| scene_shape_extra | 17×4 | Secondary shape parameter, FP27 |
| scene_bg_rgb | 18×4 | Background colour, RGB24 |
| scene_shape_rgb | 19×4 | Shape colour, RGB24 |
| scene_beat_pulse | 20×4 | Audio: bass energy, FP27 |
| scene_level | 21×4 | Audio: overall level, FP27 |
| scene_spectral | 22×4 | Audio: spectral centroid, FP27 |
| scene_noise | 23×4 | Audio: noise floor, FP27 |
