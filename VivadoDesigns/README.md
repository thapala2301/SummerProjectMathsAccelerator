# VivadoDesigns — Vivado Block Design and Bitstream

The integrated Vivado project that synthesises the full ray marcher and programs the PYNQ-Z1.

---

## `UI_Vivado/`

The main Vivado project. Open `UI_Vivado/` in Vivado 2020.x (or later) to get the full block design.

**IP used:**

| IP | Instance | Purpose |
|----|----------|---------|
| `rgb2dvi` | `rgb2dvi_0` | TMDS serialiser — converts RGB24 + sync signals to HDMI differential pairs |
| `clk_wiz_0` | `clk_wiz_0` | PLL: generates 125 MHz system clock and 371.25 MHz TMDS clock from 125 MHz PL input |
| `axi_camera_regs` | (custom) | AXI-Lite slave with 24 × 32-bit registers for camera and scene parameters |
| Xilinx VDMA | (PS-side) | Streams framebuffer from DDR3 to the PL video path |

The `rgb2dvi` and `clk_wiz` IP sources are in `ip_repo/rgb2dvi/` and `ip/clk_wiz_0/` respectively.

**Block design summary:**

```
Zynq PS ──AXI-HP──► DDR3
         ──AXI-Lite─► axi_camera_regs ──► top.sv (PL)
         ──VDMA MM2S─► vid_data/hsync/vsync ──► top.sv ──► rgb2dvi ──► HDMI
```

The PL-side top module (`top_ps.sv`, which wraps `top.sv`) is added as an RTL source in the block design.

---

## `Bitstream_Handoff/`

Pre-built bitstream and hardware handoff files (`.bit` and `.hwh`) for loading directly onto the PYNQ-Z1 without running synthesis yourself. Copy both files to the board and load with:

```python
from pynq import Overlay
ol = Overlay('path/to/bitstream.bit')
```

---

## Rebuilding from source

1. Open Vivado 2020.x+.
2. File → Open Project → navigate to `UI_Vivado/`.
3. In the Flow Navigator, click **Generate Bitstream**. This runs synthesis, implementation, and bitstream generation.
4. Estimated runtime: 20–40 minutes on a modern machine.
5. Export hardware (File → Export → Export Hardware, include bitstream) to get a fresh `.hwh` file.

Alternatively, to recreate the project from TCL:

```bash
cd SCRIPTS/Vivado_bd
vivado -mode batch -source create_project.tcl
```

---

## `vivado-library-master/`

Digilent's Vivado library — contains the `rgb2dvi` IP source. Required for synthesis. Already referenced by the project; do not move it.

---

## Timing

Target: 125 MHz. All paths met timing in the last known-good build. The longest combinational path is in the FP arithmetic: `fp_clamp1` (26-bit compare, ~2 ns) + `fp_times2` (8-bit increment, ~1 ns) = ~3 ns, well within the 8 ns budget.

If timing fails after adding a new SDF scene, check whether any purely combinational chains are too long — the Mandelbox has several combinational operations back-to-back that are close to the limit.
