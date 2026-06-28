# RTL/video — DDR3 Writer and Colour Palette

Handles the output side: takes completed pixels from `march_core` and writes them to DDR3, then maps iteration counts to colours.

---

## `ddr_rgb_writer.sv`

AXI4 write master. Buffers completed pixels in an internal FIFO and writes them to DDR3 in bursts.

**Why the internal FIFO?** `march_core` produces pixels at irregular intervals (some pixels hit after a few steps, others after many). DDR3 write transactions have variable latency due to bank conflicts, refresh, etc. The FIFO decouples the two.

**AXI4 write path:**

- AW channel: `top.sv` provides `frame_base_0` or `frame_base_1` (the DDR3 base address of the current render bank). `ddr_rgb_writer` computes the pixel address as `base + pix_id × 4` and issues write address transactions.
- W channel: sends the RGB24 pixel data (padded to 32 bits).
- B channel: receives write responses (not used for flow control, just consumed).

**Backpressure:**

`fifo_almost_full` is asserted when the internal FIFO is nearly full. This feeds back to `top.sv` as `writer_fifo_almost_full`, which gates `dispatch_enable`, pausing `pixel_dispatch`. The almost-full threshold is set 512 entries below the actual full point to account for pixels already in flight in the march pipeline.

`MAX_OUTSTANDING = 8` limits the number of in-flight AXI write transactions. The Zynq DDR controller supports more, but keeping it bounded prevents the response queue from filling up and causing deadlock.

Parameters:
- `FIFO_DEPTH = 4096`
- `FIFO_ALMOST_FULL = FIFO_DEPTH − 512`
- `MAX_OUTSTANDING = 8`
- `SCREEN_WIDTH = 512`, `SCREEN_HEIGHT = 300` (must match `pixel_dispatch`)

---

## `palette.sv`

Maps an 8-bit iteration count to a 24-bit RGB colour. A simple lookup: the colour ramps through a palette based on how many steps the ray took before hitting. Pixels that hit quickly (few iterations) get one colour; pixels that almost exhausted `MAX_ITER` get another. Background (max iteration, no hit) gets `bg_rgb` from the scene parameters.

The palette is hardcoded in the module as a case statement. To change the colouring, edit `palette.sv` and re-synthesise.
