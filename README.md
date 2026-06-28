# FPGA Ray Marcher — PYNQ-Z1

Real-time 3D ray marcher running entirely on the FPGA fabric of a PYNQ-Z1 (Zynq XC7Z020). No GPU, no CPU in the render loop. Custom 27-bit floating-point arithmetic, fully pipelined, outputs stereo over HDMI at 720p60 into a custom-built VR headset.

**Imperial College London — Year 2 group project (EEE/EIE), June 2026.**

*Note: if this main branch has missing code, look in `pre_final_scaffold` — that branch has all working code.*

---

## Renders

Hardware HDMI output — stereo side-by-side for VR:

| Scaffold corridor — space repetition cells | Scaffold tunnel — iteration colourmap recession | Scaffold overhead — oblique angle, infinite depth |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_corridor_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_tunnel_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_overhead_stereo.jpg) |

| Scaffold zenith — looking straight up through nested frames | Scaffold diagonal — FP27 resolves fine strut edges | Scaffold lattice — diamond grid, cell_size=2 |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_zenith_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_diagonal_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_lattice_stereo.jpg) |

| Torus SDF — green-purple colourmap, concave annular region | Early cone — wavy organic geometry, green-purple-orange palette | Space-repeated sphere array — infinite lattice, cell_size=10 |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_torus_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_gyroid_early_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_gyroid_spheres_stereo.jpg) |

| Spheres boundary — spiky self-similar structures, NR approximation artefacts | Spheres interior — NR accumulations | Spheres spiral — NR accumulations |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_mandelbox_closeup_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_mandelbox_interior_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_mandelbox_spiral_stereo.jpg) |

| Spheres lattice — infinite spheres, cell_size=2 | Capsule SDF — single-sheet teardrop geometry | Infinite spheres close range |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_mandelbox_lattice_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_hyperboloid_stereo.jpg) | ![](misc/Report_Sources/imgs/AppendixA/render_gyroid_spheres2_stereo.jpg) |

GLSL software reference renders (used to validate SDF maths before RTL):

| Scaffold pillar — twisted strut column, infinite depth | Scaffold ceiling — honeycomb-textured box-frame boundary | Scaffold edge — sphere-fold meets lattice surface |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_glsl_pillar.png) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_glsl_ceiling.png) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_glsl_edge.png) |

| Scaffold corner — deep lattice recession, validates camera matrix | Scaffold tunnel GLSL — visual reference for RTL comparison | Twisted torus GLSL spiral — twist rotates cross-section continuously |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_glsl_corner.png) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_glsl_tunnel.png) | ![](misc/Report_Sources/imgs/AppendixA/render_twisted_torus_glsl_spiral.png) |

| Twisted torus GLSL — blue-orange palette, twist convergence centre | GLSL box primitives reference — reflective floor, starburst diffraction | Early mandelbox debug — orange cross-hatch, VDMA buffer timing artefacts |
|---|---|---|
| ![](misc/Report_Sources/imgs/AppendixA/render_twisted_torus_glsl_centre.png) | ![](misc/Report_Sources/imgs/AppendixA/render_glsl_boxes_reference.png) | ![](misc/Report_Sources/imgs/AppendixA/render_scaffold_debug_early.jpg) |

Menger sponge (Verilator sim, pixel-accurate RTL output):

![Menger sponge — Verilator C++ testbench output](misc/menger.png)

---

## VR Headset

| Final SolidWorks assembly render | Physical build — HDMI cable clearance redesigns |
|---|---|
| ![](misc/Report_Sources/imgs/Headset_Images/final_rendered.png) | ![](misc/Report_Sources/imgs/Headset_Images/physical_construction.png) |

| Lens cup friction-fit — 37mm biconvex, +0.5mm tolerance | Screen panel — 45mm focal length for 5-inch LCD | FPGA housing cavity — +0.5–1mm friction-fit tolerance |
|---|---|---|
| ![](misc/Report_Sources/imgs/Headset_Images/lens_mount.png) | ![](misc/Report_Sources/imgs/Headset_Images/screen_panel.png) | ![](misc/Report_Sources/imgs/Headset_Images/fpga_housing_1.png) |

| Front panel — IMU bracket, 4mm standoffs for MPU-6050 | Quest 2 strap adapter — velcro slot removed, forward-mated | Assembled headset prototype — FPGA friction-fitted in chassis |
|---|---|---|
| ![](misc/Report_Sources/imgs/Headset_Images/most_front_panel.png) | ![](misc/Report_Sources/imgs/Headset_Images/quest2_strap_1.png) | ![](misc/Report_Sources/imgs/AppendixA/headset_photo_1.jpg) |

Designed in SolidWorks to hold a small HDMI screen and mount to a Meta Quest 3 head strap. The FPGA renders a stereo side-by-side image — one half per eye. Full CAD in [`CAD/`](CAD/README.md).

---

## Team

| Member | What they built | Stack |
|--------|----------------|-------|
| **Charlie** | Software reference renderer — WebGL2 GPU path + CPU mirror, fly camera | React, Vite, WebGL2, GLSL |
| **Geralt** | Audio FFT pipeline — 1024-pt FFT on PL, AXI DMA to DDR, band extraction on PS | Vivado, Xilinx FFT IP, AXI-Stream/DMA, PYNQ |
| **Jai** | Ray generation pipeline — pixel → ray in 27-bit FP, AXI-Lite camera registers | SystemVerilog |
| **Sakthivel** | HDMI output — framebuffer, scan-out, 720p60 timing, colour palette. VR headset CAD | SystemVerilog, Vivado, SolidWorks |
| **Thanus** | Pixel dispatch, feedback scheduler, FIFO. FFT bridge to scene params. 15+ analytic SDF shapes. Neural SDF training | SystemVerilog, PyTorch |
| **Vincent** | March core, FP27 library, Mandelbox/Menger SDFs, Verilator testbenches, GLSL prototypes | SystemVerilog, Verilog, Verilator |

---

## How it works

For each of the 921,600 pixels in a 1280×720 frame, the hardware shoots a ray and steps it along until it gets within `HIT_THRESH` of a surface (a hit) or exhausts `MAX_ITER` steps. The signed-distance function (SDF) tells the marcher exactly how far it can safely step without overshooting — so every step is as large as possible.

Because the RTL pipeline is fixed-latency, pixels can't loop inside the hardware. Instead, after each step, unfinished rays are packed into a 190-bit FIFO entry and re-injected at the pipeline input. Returning rays always beat fresh pixels at the arbiter — this prevents the FIFO from ever overflowing.

The system renders two eye positions (`cam_origin ± HALF_IPD × lookat_right`) simultaneously for the VR headset.

---

## System architecture

```
                         Audio In (44.1 kHz)
                               │
                               ▼
              ┌────────────────────────────────┐
Geralt — PL   │  Xilinx FFT IP (1024-point)    │
              │  AXI-Stream → AXI DMA → DDR    │
              └───────────────┬────────────────┘
                              ▼
Geralt — PS         Python: bass / mids / highs extraction
                              │  scene parameters over AXI-Lite
                              ▼
Jai — PL            axi_camera_regs  ──►  ray_gen (48 cycles)
                                              │  ray_origin + ray_dir (FP27)
                                              ▼
Thanus — PL         pixel_dispatch  →  feedback_ctrl  →  FIFO (190b × 128)
                                              │
                                              ▼
Vincent — PL        march_core  ──►  scene_sdf  ──►  repeat_mod_cell
                         │               (analytic or neural MLP→BRAM)
                         │  hit
                         ▼
Thanus/Sakthivel    ddr_rgb_writer (AXI4 master)  →  DDR3
                                              │
Sakthivel — PL      VDMA  →  rgb2dvi  →  HDMI 720p60
```

![Architecture](misc/images/architecture.svg)
![Render loop](misc/images/render_loop.svg)

---

## Custom 27-bit float (FP27)

Standard IEEE 754 single (32-bit) wastes resources — the DSP48E1 on Artix-7 multiplies 18-bit operands natively. So we defined our own format:

```
 bit 26    bits 25:18     bits 17:0
┌────────┬─────────────┬──────────────────────┐
│  sign  │  exponent   │      mantissa        │
│  (1b)  │  (8b, b127) │      (18b)           │
└────────┴─────────────┴──────────────────────┘
```

Same bias (127) as IEEE 754. No denormals, no NaN — the hardware assumes all inputs are valid finite numbers. Each `fp_mul` maps to exactly one DSP48E1 slice.

![FP27 format](misc/images/fp27_format.svg)

All modules share the same interface: `clk`, `a[26:0]`, `b[26:0]`, `out[26:0]`. Operands are cycle-aligned using `state_pipe.v`, which Vivado infers as SRL32 shift-register LUTs.

| Module | Op | Latency | Notes |
|--------|----|---------|-------|
| `fp_add.v` | a + b | 4 cycles | Align, add, renormalise |
| `fp_sub.v` | a − b | 4 cycles | Add with b sign flipped |
| `fp_mul.v` | a × b | 4 cycles | 1 DSP48E1 per instance |
| `fp_isqrt.v` | 1/√a | 16 cycles | Quake magic number + 1× Newton-Raphson |
| `fp_length.v` | √(x²+y²+z²) | 32 cycles | 3×mul + 2×add + isqrt + mul |
| `fp_normalize.sv` | v/‖v‖ | 36 cycles | fp_length + 3×mul |
| `fp_abs.v` | \|a\| | comb | Clear sign bit |
| `fp_max.v` / `fp_min.v` | max/min | comb | Comparator + mux |
| `fp_negate.v` | −a | comb | Flip sign bit |
| `fp_mod2.v` | a mod 2 | pipelined | Domain repetition |
| `fp_mul_vec3_mat33.sv` | v·M | pipelined | 9×mul + 6×add |
| `int2fp.v` | int → FP27 | comb | Pixel coords in ray_gen |
| `fp_div.sv`, `fp_floor.sv`, `fp_mod.sv`, `fp_inverse.sv` | — | pipelined | Utilities |

Key constants: `ONE = 27'h1FC0000`, `TWO = 27'h2000000`, `NEG_ONE = 27'h3FC0000`

---

## Modules in detail

### Charlie — Software renderer (`GPURenders/`)

Browser-based ray marcher used to prototype shaders and validate SDF maths before committing to RTL.

- **GPU path** (`gpu_renderer.js`): WebGL2 fragment shader — ray marching with soft shadows, ambient occlusion, ground-plane grid.
- **CPU path** (`cpu_renderer.js`): Pure JavaScript mirror of the GLSL — vec2/vec3/mat operations hand-translated for step-by-step debugging.
- **Camera** (`camera.js`): First-person fly camera, WASD + mouse-look.

```bash
cd GPURenders/OnlineShaderToy   # ShaderToy GLSL prototypes
# or
cd GPURenders/OpenGL
npm install && npm run dev       # http://127.0.0.1:4176
```

---

### Geralt — Audio FFT pipeline

Offloads frequency analysis from the ARM to the FPGA fabric.

**PL side:**
- Xilinx FFT IP — 1024-point, AXI4-Stream I/O, streaming from microphone input
- AXI DMA — moves FFT output directly to DDR without ARM involvement
- AXI GPIO — CPU-selectable Forward/Inverse mode

**PS side (`SCRIPTS/PYNQ/ctrl.py` audio path):**
- Unpacks 32-bit complex output: bits[15:0] = Real, bits[31:16] = Imaginary
- Computes magnitude: `√(R² + I²)`
- Splits bins into bands (bin width = 44100/1024 ≈ 43 Hz):

| Band | Range | Bins |
|------|-------|------|
| Bass | ~43–250 Hz | 1–5 |
| Mids | ~250–2000 Hz | 6–46 |
| Highs | ~2000–11000 Hz | 47–256 |

These three energy values become live `scene_beat_pulse`, `scene_level`, `scene_spectral` parameters written to the PL over AXI-Lite, making the geometry react to music in real time.

![FFT spectrum](misc/images/fft_spectrum.png)

---

### Jai — Ray generation (`RTL/core/ray_gen.sv`)

48-cycle pipeline turning a pixel coordinate into a normalised ray direction in world space.

1. `int2fp` (combinational): pixel (x, y) → FP27
2. Centre and scale to NDC: `(x − W/2, y − H/2)`
3. Set Z = `FOV_Z_CONST` (= 1.0, baking a fixed ~90° FOV)
4. `fp_normalize` (36 cycles): normalise the (x, y, z) direction vector
5. `fp_mul_vec3_mat33` (pipelined): rotate from camera space to world space using the 3×3 lookat matrix

The lookat matrix (right, up, forward vectors) and camera origin are written at runtime from Python over AXI-Lite via `axi_camera_regs` (custom IP in `ip_repo/`). No recompilation needed to move or rotate the camera.

For stereo, `march_core` computes:
```
cam_origin_left  = cam_origin − HALF_IPD × lookat_right
cam_origin_right = cam_origin + HALF_IPD × lookat_right
```
Both eyes share the same ray direction but diverge from different origins.

---

### Thanus — Pixel dispatch, feedback scheduler, SDF library

**`pixel_dispatch.sv`** — Sequences the full raster in scan order, one pixel per clock when `pipeline_ready` is high. Mapped to a halved address space (640×360) to fit the framebuffer in BRAM. `valid` is combinational (`~rst & pipeline_ready`) to avoid a one-cycle timing race at pipeline start.

**`feedback_ctrl.sv`** — The arbiter between fresh pixels and returning rays. Returning rays always win — this is the key invariant that prevents FIFO overflow. A fresh pixel is only admitted when the FIFO is empty. Between cores, each ray carries: 20-bit `pix_id` + 81-bit position + 81-bit direction + 8-bit iteration count = **190 bits**.

**`FIFO.sv`** — Parameterisable synchronous FIFO. Configured as WIDTH=190, DEPTH=128. Sized to cover the 48-cycle ray gen + 101-cycle SDF pipeline = 149 cycle maximum in-flight depth, with safety headroom.

![Pixel dispatch](misc/images/pixel_dispatch.png)
![Feedback ctrl](misc/images/feedback_ctrl.png)
![FIFO](misc/images/fifo.png)

**FFT bridge** — `fft_bridge.v` accumulates per-frame bass/mid/treble energy from Geralt's FFT output, applies sensitivity scaling, converts to FP27 via `int2fp`, and produces 11 frame-stable FP27 outputs. These feed `scene_beat_pulse`, `scene_level`, `scene_spectral`, `scene_noise` in `top.sv` → `march_core` → `scene_sdf`, replacing hardcoded constants with live audio parameters. Four audio-reactive SDF parameters: `out_domain_fold` (bass → grid tiling), `out_twist` (mid → rotation), `out_epsilon` (treble → surface bloom), `out_sdf_scale` (total energy → scene scale). Uses Xilinx CORDIC IP for FFT magnitude.

**Analytic SDF library** — 15+ standalone SDF modules following the same clocked FP27 interface as `scene_sdf`: `sdf_sphere`, `sdf_torus`, `sdf_octahedron`, `sdf_gyroid` (Taylor-series sin/cos), `sdf_twisted_torus`, `sdf_chain_link`, `sdf_capsule`, `sdf_box`, `sdf_rounded_box`, `sdf_ellipsoid`, `sdf_pyramid`, `sdf_disk`, `sdf_pipe`, `sdf_vesica`, `sdf_hyperboloid`, `sdf_spiral`, `sdf_mandelbulb`. All pipeline-synchronised with explicit `state_pipe` delay lines.

**Neural SDF training** (`Neural_SDF_Research/Software_Neural/`) — PyTorch MLP `3→32→32→32→1`, ReLU, trained on analytically-computed SDF values. Weights exported to Q4.12 hex for `$readmemb`. Test losses: sphere ~3×10⁻⁵, torus ~5×10⁻⁵.

| Neural sphere fit | Neural torus fit |
|---|---|
| ![](misc/images/neural_sphere.png) | ![](misc/images/neural_torus.png) |

---

### Sakthivel — HDMI output + VR headset CAD

**HDMI pipeline:**
- `framebuffer_bram` — RGB332 double-buffered framebuffer in BRAM. Double-buffering means the VDMA always reads a completed frame while the renderer writes the next one — no tearing.
- `scan_out` — Reads BRAM in raster order, crosses from compute clock (125 MHz) to pixel clock (74.25 MHz) using FIFO-based CDC.
- `hdmi_timing` — Generates 720p60 sync signals: 1650×750 total, 74.25 MHz pixel clock.
- `iter_to_rgb` / `palette` — Maps 8-bit iteration count to RGB24. The colour ramp is parameterisable; shape and background RGB are both writable at runtime from Python.

**VR headset CAD** (SolidWorks, in `CAD/`):
- Designed to hold a small HDMI screen at the correct focal distance for the lenses
- Adapts to Meta Quest 3 head strap — no modifications to the Quest needed
- Parts: `front_panel`, `screen_panel`, `eyes_panel`, `foam_support`, `body`, `Quest 3 Head band adapter v5`
- Assembly: `BodyAdapted.SLDASM`

| Headset CAD | Quest 2 strap adapter |
|---|---|
| ![](misc/Report_Sources/imgs/Headset_Images/final_rendered.png) | ![](misc/Report_Sources/imgs/Headset_Images/quest2_strap_1.png) |

---

### Vincent — March core, FP27 library, SDF scenes, testbenches

**`RTL/FP_Lib/`** — Full 27-bit FP library written from scratch. 16 modules. `fp_isqrt` uses the Quake III fast inverse square root (magic number bit trick + one Newton-Raphson step). `fp_length` pipelines 3×mul + 2×add + isqrt + mul = 32 cycles. `state_pipe` infers SRL32 LUTs in Vivado for cycle-alignment of side-channel signals.

**`RTL/core/march_core.sv`** — One pipeline pass = one SDF step. Passes position through optional `repeat_mod_cell` (domain tiling), evaluates `scene_sdf`, steps the ray, checks hit/miss. All side-channel signals (pix_id, iter, pos, dir) delayed by `state_pipe` to match `SDF_LAT = REPEAT_LAT + SCENE_CORE_LAT`. Stereo eye offset computed with 3×`fp_mul` + 3×`fp_sub`.

**`repeat_mod_cell.sv`** — Folds coordinates into a repeating cell: `q = ((p + half_cell) mod cell_sz) − half_cell`. Handles negative FP mod remainders. 18-cycle latency.

**SDF scenes:**

- **Scaffold / box-frame** (`scaffold_sdf.v`) — box-frame SDF with domain repetition. First scene rendered on hardware. `SCENE_CORE_LAT = 50`.

- **Twisted torus** (`twisted_torus_sdf.v`) — torus with Y-axis domain twist. Twist angle = `py × TWIST`, cos/sin via Taylor series (`1 − θ²/2`, `θ − θ³/6`). `SCENE_CORE_LAT = 101`.

- **Menger sponge** (`NOTWORKINGmenger_sdf.sv`) — 3-level box-frame IFS with `repeat_mod_cell` tiling. RTL sim verified. `SCENE_CORE_LAT = 83`, `SDF_LAT = 101`. Hardware dispatch bug under investigation.

- **Mandelbox** (`NOTWORKINGmandelbox.sv`) — 4-iteration orbit trap, scale = −1.5. Per-iteration: `fp_clamp1` (comb, 26-bit compare + mux), `fp_times2` (comb, 1-bit exponent increment), spherical fold (requires `fp_length` = 32 cycles), `scale×z + c`. `SCENE_CORE_LAT = 234`. Verilator testbench: all 9 inside/outside spot checks pass.

**Verilator testbenches** (`SIM_testbenches/`) — C++ PPM render tests producing pixel-accurate output matching what the hardware produces. SV unit tests for FP lib, march core, scene SDF, analytic SDF shapes (25+ test vector hex files).

**GLSL prototypes** (`GPURenders/OnlineShaderToy/`) — ShaderToy shaders used to validate SDF maths and scene design before RTL.

---

## PYNQ control

Everything is writable at runtime over AXI-Lite — no recompilation needed to move the camera, change scene geometry, or swap colours.

`SCRIPTS/PYNQ/ctrl.py`:
- Allocates two DDR3 frame buffers via `pynq.allocate`, writes base addresses to `FRAME_BASE0_REG`/`FRAME_BASE1_REG` (the PL won't dispatch pixels until both are non-zero)
- Configures VDMA (frame size, stride, start addresses, MM2S park mode)
- TCP server port 9999: receives 12-float camera packets (3×3 lookat + 3D origin) from the PC and writes to AXI registers
- TCP server port 9998 (optional): receives audio energy parameters from the PC
- Frame-ack GPIO loop: pulses every ~1 ms to tell the PL that VDMA consumed the last frame

`SCRIPTS/Computer/camera_mmio_controller.py` — keyboard/mouse camera controller running on a laptop, sends camera matrix over TCP to the board.

**AXI register map** (base `0x43C00000`):

| Register | Offset | Content |
|----------|--------|---------|
| lookat[0..8] | 0–8 × 4 | 3×3 camera matrix, FP27 |
| cam_origin[0..2] | 9–11 × 4 | Camera position, FP27 |
| frame_base_0/1 | 12–13 × 4 | DDR3 frame buffer addresses |
| scene_cell_sz | 14 × 4 | Domain repeat cell size, FP27 |
| scene_half_cell | 15 × 4 | Half cell, FP27 |
| scene_shape_size | 16 × 4 | Primary shape param, FP27 |
| scene_shape_extra | 17 × 4 | Secondary shape param, FP27 |
| scene_bg_rgb | 18 × 4 | Background colour, RGB24 |
| scene_shape_rgb | 19 × 4 | Shape colour, RGB24 |
| scene_beat_pulse | 20 × 4 | Audio bass energy, FP27 |
| scene_level | 21 × 4 | Audio overall level, FP27 |
| scene_spectral | 22 × 4 | Audio spectral centroid, FP27 |
| scene_noise | 23 × 4 | Audio noise floor, FP27 |

---

## Neural SDF (research path)

Instead of an analytic SDF, train a small MLP to approximate the distance field, bake it onto a 3D grid in BRAM, then use trilinear interpolation at query time. Constant per-query cost regardless of scene complexity.

**Training** (`Neural_SDF_Research/Software_Neural/`): PyTorch, `3→32→32→32→1`, ReLU, MSE loss vs analytically-computed values. Weights exported as Q4.12 (16-bit, 4 integer + 12 fractional bits) for `$readmemb`.

**RTL** (`Neural_SDF_Research/Neural_RTL/`): `baking_ctrl` sweeps all grid points on startup and writes SDF values to `sdf_bram`. At render time, `trilinear_interp` reads the 8 surrounding BRAM corners and interpolates. `fp_to_q4_12` / `q4_12_to_fp` handle format conversion at the BRAM boundary.

---

## Repository layout

```
├─ RTL/
│  ├─ FP_Lib/          27-bit FP library (16 modules)
│  ├─ core/            march_core, ray_gen, repeat_mod_cell, state_pipe
│  ├─ sdf/             SDF scenes (scaffold, twisted torus, menger, mandelbox, sphere)
│  ├─ control/         pixel_dispatch, feedback_ctrl, FIFO
│  ├─ video/           ddr_rgb_writer (AXI4 master), palette
│  └─ top/             top.sv, top_ps.sv (PS wrapper)
├─ SIM_testbenches/    Verilator C++ PPM tests + SV unit testbenches + test vectors
├─ VivadoDesigns/      Vivado block design, UI notebook, pre-built bitstream
├─ ip_repo/            axi_camera_regs AXI-Lite IP, rgb2dvi HDMI IP
├─ constraints/        XDC pin constraints for PYNQ-Z1
├─ CAD/                SolidWorks VR headset (parts + assembly)
├─ SCRIPTS/            PYNQ Python control, PC camera sender, Vivado TCL
├─ GPURenders/         OpenGL + ShaderToy reference shaders
├─ Neural_SDF_Research/ PyTorch training + Q4.12 BRAM inference RTL
└─ misc/               Progress log, notes, Mandelbox maths, report sources
```

---

## Build and run

```bash
# Verilator simulation → PPM image
cd SIM_testbenches && make menger_ppm
cd SIM_testbenches && make mandelbox_ppm

# SV unit tests (Icarus or Questa)
cd SIM_testbenches && bash run_all_tests.sh

# Software reference renderer
cd GPURenders/OpenGL && npm install && npm run dev

# Neural SDF training
cd Neural_SDF_Research/Software_Neural
pip install torch numpy matplotlib trimesh
python sphere_test.py && python export_weights.py && python visualise.py
```

**Hardware:**
1. Open `VivadoDesigns/UI_Vivado/` in Vivado 2020.x+
2. Generate bitstream → program PYNQ-Z1, or just use bitstreams from SCRIPTS folder
3. On board: `python3 SCRIPTS/PYNQ/ui_base_selector.py`. Must have ctrl.py as well
4. On PC: `python3 SCRIPTS/Computer/camera_mmio_controller.py --host <board-ip>`

**Requirements:** PYNQ-Z1 · HDMI 720p60 display · Vivado 2020.x+ · Verilator · Python 3 (`pynq numpy torch trimesh`)

---

**Status (June 2026):** scaffold and twisted torus rendering on hardware. Menger sponge RTL sim-verified — hardware dispatch bug under investigation. Mandelbox RTL sim-verified (all 9 spot checks pass) — needs adding to Vivado project. Neural SDF functional in simulation.
