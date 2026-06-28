# RTL/core — Ray Generation and March Loop

The core of the renderer: turns pixel coordinates into rays, evaluates signed-distance steps, and manages the per-pixel state between iterations.

---

## `ray_gen.sv` — latency 48 cycles

Converts a pixel (x, y) and a camera lookat matrix into a normalised ray direction in world space.

**Steps:**

1. **Integer to float** (`int2fp`, combinational): converts pixel (x, y) from integer to FP27.
2. **Centred NDC**: shifts pixel to screen centre and divides by image dimensions to get normalised device coordinates in [−0.5, 0.5].
3. **Apply FOV**: multiplies by `FOV_Z_CONST` (default 1.0 — controls field of view).
4. **Lookat transform** (`fp_mul_vec3_mat33`): rotates the NDC direction from camera space to world space using the 3×3 lookat matrix (right, up, forward vectors). This is the most expensive step — 9 multiplies and 6 adds.
5. **Normalise** (`fp_normalize`, 36 cycles): ensures the ray direction has unit length.

The camera origin is passed straight through (no computation needed — it's the same for all pixels in a frame, just split into left/right eye by `march_core` using `HALF_IPD`).

Parameters:
- `IMG_W`, `IMG_H`: resolution (set to match `pixel_dispatch`)
- `FOV_Z_CONST`: field of view control

---

## `march_core.sv`

The main pipeline stage. Receives a ray (position + direction + iteration count) and advances it by one SDF step.

**Signal flow:**

```
in_pos ──────────────────────────────────────────────────► state_pipe ──► new_pos = pos + dir * sdf * step
                 │                                                              │
                 ▼                                                              ▼
         repeat_mod_cell                                               hit check / feedback
                 │
                 ▼
           scene_sdf
                 │
                 ▼ (SCENE_CORE_LAT cycles later)
             sdf_out
```

Side-channel signals (`pix_id`, `iter`, `ray_dir`, `in_pos`) are delayed by `state_pipe` instances to arrive at the output at the same cycle as `sdf_out`.

**Stereo rendering:**

`march_core` computes two eye origins:
- `cam_origin_left = cam_origin − HALF_IPD × lookat[0]` (right vector)
- `cam_origin_right = cam_origin + HALF_IPD × lookat[0]`

Both `ray_gen` instances (one per eye) receive the same direction but different origins. Their outputs are interleaved — even `pix_id` → left eye, odd → right eye (or based on `in_x` coordinate).

**Key localparams** (must be updated when changing scenes):

```verilog
localparam int REPEAT_LAT     = 18;   // repeat_mod_cell latency (0 if no repeat)
localparam int SCENE_CORE_LAT = 101;  // scene_sdf latency
localparam int SDF_LAT        = REPEAT_LAT + SCENE_CORE_LAT;
localparam int MAX_ITER        = 128;
localparam [26:0] HIT_THRESH  = {1'b0, 8'd117, 18'h01893}; // ≈ 0.001
localparam [26:0] HALF_IPD    = 27'h1E7AE14;                // ≈ 0.06
```

**Output ports:**

- `pix_done` + `out_pix_id` + `out_iter` → to `ddr_rgb_writer`
- `fb_*` → back to `feedback_ctrl` FIFO for another iteration

---

## `repeat_mod_cell.sv` — latency 18 cycles

Folds a coordinate `p` into a repeating cell centred at the origin:

```
q = ((p + half_cell) mod cell_sz) − half_cell
```

The `+half_cell / −half_cell` pair shifts the mod window so geometry sits centred in each cell rather than at the cell edge. An additional correction step handles the case where FP mod on a negative input returns a negative remainder (which breaks the centring).

This module is applied independently to the X and Z coordinates before passing position to `scene_sdf`. Y is left un-tiled (the scene extends infinitely vertically).

---

## `repeat_cell.sv`

Simpler variant using `fp_floor` instead of `fp_mod`. Kept for comparison.

---

## `state_pipe.v`

```verilog
module state_pipe #(
    parameter int WIDTH = 27,
    parameter int DEPTH = 1
) (
    input  logic             clk,
    input  logic [WIDTH-1:0] in,
    output logic [WIDTH-1:0] out
);
```

A shift register delay line. Vivado synthesises this as SRL32 LUTs (up to 32 deep per LUT), which is far more efficient than explicit flip-flop chains for deep delays. For `DEPTH > 32`, Vivado chains multiple SRL32s automatically.

Used everywhere operands need to be kept cycle-aligned with a pipelined result.

`state_pipe_unpacked_array.sv` is the same thing for `logic [W-1:0] arr[0:N-1]` arrays (e.g. a vec3 of FP27 values).
