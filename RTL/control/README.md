# RTL/control — Pixel Scheduler and Feedback Loop

The control path manages which pixel gets processed next: either a fresh pixel from raster order, or a partially-marched ray that needs another step.

---

## `pixel_dispatch.sv`

Counts through pixels in raster order (left to right, top to bottom) and emits one pixel per clock when `pipeline_ready` is high.

```
x: 0 → WIDTH−1, then x=0 and y++
y: 0 → HEIGHT−1, then back to (0,0)
pix_id = y × WIDTH + x
```

When `pipeline_ready` goes low (FIFO almost full), the counter pauses — it doesn't skip any pixels. `valid` is simply `~rst & pipeline_ready`.

Parameters `WIDTH` and `HEIGHT` control resolution. Currently set to 512×300 (half-res) for faster simulation; the hardware target is 1024×600 (half of 1280×720, one pixel per two screen pixels).

---

## `feedback_ctrl.sv`

The arbiter between fresh pixels and returning rays. This is what makes the iterative ray-march work on a fixed pipeline.

**Problem:** ray marching is inherently iterative — a pixel needs many SDF evaluations before it hits or gives up. But the RTL pipeline is fixed-latency. The solution: after each march step, if the pixel hasn't finished, pack all its state into a FIFO entry and re-inject it at the start of the pipeline for another pass.

**Arbitration rule:** returning rays always win over fresh pixels. This prevents the FIFO from overflowing — if fresh pixels kept entering at the same rate, the FIFO would fill up with in-progress rays. By prioritising returning rays, the FIFO drains before new pixels are admitted.

**FIFO entry format (190 bits total):**

| Field | Width |
|-------|-------|
| `pix_id` | 20 bits |
| `pos_x, pos_y, pos_z` | 27 × 3 = 81 bits |
| `ray_dir_x, ray_dir_y, ray_dir_z` | 27 × 3 = 81 bits |
| `iteration_count` | 8 bits |

**Backpressure:** when `fifo_almost_full` goes high, `stall` is asserted back to `pixel_dispatch`. The "almost full" threshold is set 512 entries below the real full threshold, providing enough headroom for all in-flight pixels already deep in the `march_core` pipeline to drain into the FIFO before it actually overflows.

---

## `FIFO.sv`

Synchronous first-in first-out buffer. Parameterised on data width and depth. Provides `full`, `empty`, and `almost_full` flags. Used by `feedback_ctrl` to hold in-progress ray state between march iterations.
