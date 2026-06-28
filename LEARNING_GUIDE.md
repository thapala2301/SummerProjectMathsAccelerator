# Learning Guide — Audio-Sync Ray Marcher (FPGA)

A guided, **high-level → low-level** path for understanding this whole project, written for someone who is comfortable programming but newer to FPGAs. Read it top to bottom the first time. After that, use it as a map: every module and (nearly) every source file is explained, with the *why* as well as the *what*.

> If a term is unfamiliar, check the **Glossary** at the end — it is written for this exact project.

---

## 0. How to use this guide

The project is large because it spans four very different worlds: GPU-style graphics maths, digital hardware design (RTL), embedded Linux/Python, and a bit of machine learning. You do **not** need to understand all of it before any of it makes sense. The trick is to anchor on **one idea** — *"march a ray through a distance field, colour the pixel by how hard that was"* — and then see how each module is just one stage of doing that, fast, in silicon.

The reading order in **Section 4** is the fastest way to ramp. Sections 5+ are reference.

---

## 1. The 60-second mental model

The board (a **PYNQ-Z1**, which is an ARM CPU + FPGA fabric on one chip) renders a 3D fractal-ish scene **in real time** and shows it on an **HDMI monitor at 720p, 60 frames per second**. Music coming in is analysed by an **FFT** (frequency analysis) and the loudness of bass / mids / treble is fed into the scene so the geometry **reacts to the audio**.

There is no GPU. The image is computed by custom digital circuits the team designed, using a **home-made 27-bit number format** instead of normal floats, because that packs better into the FPGA's hardware multipliers.

Three things are happening at once:

1. **Audio path** — sound → FFT → three numbers (bass, mid, treble).
2. **Render path** — for every one of the ~921,600 pixels, shoot a ray into the scene, step along it until it hits a surface, count the steps.
3. **Display path** — turn each pixel's step-count into a colour and stream it out over HDMI with exactly the right timing.

Everything else is plumbing that makes those three things keep up with a 60 Hz monitor.

---

## 2. Concept primers

Short, project-specific explanations of the ideas you need. Skim now, return when a module leans on one.

### 2.1 Ray marching (the core algorithm)
Normal 3D graphics draws triangles. **Ray marching** instead asks, for each pixel: *"if I shoot a ray out from the camera through this pixel, where does it hit something?"* You answer it by stepping along the ray. At each step you ask a **distance function** "how far is the nearest surface from where I am right now?" and you jump forward by exactly that much (it's safe — nothing is closer). Repeat. Either you get very close (a **hit**) or you give up after N steps (background). The **number of steps** is a natural, cheap thing to colour by, which is why the whole pipeline carries an `iter` (iteration) count around.

### 2.2 Signed Distance Fields (SDF)
A **Signed Distance Field** is just that distance function: feed it a 3D point `(x,y,z)`, it returns the distance to the nearest surface. **Signed** = negative inside the object, positive outside, zero exactly on the surface. The beauty is that complex shapes are pure maths — no mesh, no memory. This project's hardware scene is a **repeated box-frame** (a 3D grid of hollow cube edges), based on Inigo Quilez's classic `sdBoxFrame`. The software prototypes (`Vincent/SW_raymarching/`) also include the famous **Mandelbox** fractal, which is where the project's "Mandelbox Math" slides come from.

### 2.3 Domain repetition (infinite scenes for free)
You can tile one shape infinitely by **folding** the input coordinate into a single repeating cell before evaluating the SDF (`p mod cellSize`, roughly). That's what `repeat_cell.sv` does — it maps any world coordinate back into one 10-unit cell so a single box-frame appears as an endless lattice.

### 2.4 Fixed point vs floating point, and the custom 27-bit format
A **float** stores a number as sign × mantissa × 2^exponent — great range, but standard IEEE-754 floats are 32 bits and their hardware is bulky. The team designed a **27-bit float**: **1 sign bit, 8 exponent bits, 18 mantissa bits**, with the same bias-127 trick as IEEE. It keeps enough precision for stable marching while fitting the FPGA's DSP multiplier blocks efficiently. The **neural** path additionally uses **Q4.12 fixed-point** (16-bit: 4 integer bits, 12 fractional bits) for network weights, with explicit converter modules at the boundary. *This format is the single most important thing to internalise — every hardware module speaks it.*

![27-bit float format](docs/images/fp27_format.svg)

### 2.5 PL vs PS (the two halves of the chip)
A Zynq/PYNQ chip has two parts:
- **PS (Processing System)** — a normal ARM CPU running Linux/Python. Good at flexible, sequential work.
- **PL (Programmable Logic)** — the FPGA fabric, where you build custom parallel circuits.
The art of the project is **co-design**: put the massively parallel per-pixel maths in the PL, and the flexible control (camera, audio band extraction) in the PS.

### 2.6 AXI (how PS and PL talk)
**AXI** is ARM's standard on-chip bus. Three flavours appear here:
- **AXI4-Lite** — simple memory-mapped registers. Used so the CPU can write the camera position (`axi_camera_regs.sv`).
- **AXI4-Stream** — a firehose of data with `valid`/`ready`/`last` handshake. Used to push audio into the FFT and pull spectrum out.
- **AXI DMA** — a block that copies streams to/from CPU memory (DDR) without the CPU babysitting each word.

### 2.7 Pipelining and latency (why everything is delayed)
In hardware you can't do a big calculation in one clock tick at high speed; you **pipeline** it — break it into stages, one register per stage, a result popping out every clock but **delayed** by the number of stages (the **latency**). That's why the code is obsessed with counts like "fp_mul = 4 cycles, fp_isqrt = 16, fp_length = 32." When two signals must meet at the same stage, the shorter one is delayed by a **`state_pipe`** (a shift-register delay line) so they line up. If you remember one thing about reading this RTL: **most "weird" code is just keeping data aligned in time.** The figure below traces this through `fp_length`:

![fp_length pipeline timing](docs/images/fp_length_pipeline.svg)

### 2.8 HDMI timing (why 1650×750 for a 1280×720 image)
A monitor expects pixels streamed in a strict rhythm with invisible **blanking** gaps (front porch, sync pulse, back porch) between lines and frames — a holdover from CRT days. For 720p60 the *visible* area is 1280×720 but the *total* swept area is **1650×750**, clocked at **74.25 MHz**, which works out to ~60 frames/sec. `hdmi_timing.sv` is literally those magic numbers turned into counters.

### 2.9 Double buffering (no torn frames)
The renderer writes pixels into a framebuffer while the display reads pixels out of one. If they share one buffer you'd see half-finished frames. **Double buffering** uses two banks: render into bank A while displaying bank B, then swap. `scan_out.sv` carries the `write_bank`/`read_bank` logic for exactly this.

---

## 3. The journey of one pixel (end-to-end data flow)

This is the spine of the whole system. Trace it once and the module boundaries will make sense.

![System architecture](docs/images/architecture.svg)

```
1. pixel_dispatch (Thanus)      → "render pixel (x,y)"  emits one per clock
2. feedback_ctrl (Thanus)       → picks a source: NEW pixel, or a half-marched
                                   pixel coming back for another step (FIFO).
                                   Returning rays win, so they finish first.
3. ray_gen (Jai)                → turns (x,y) + camera into a ray:
                                   origin[3] + direction[3], in 27-bit FP.
4. march_core (Vincent)         → take one (or more) marching step(s):
       └─ scene_sdf (Vincent)        ask "distance to nearest surface?"
            └─ repeat_cell, sdf_term, fp_* library do the maths
                                   - if close enough → HIT, done.
                                   - else → send pixel BACK to feedback_ctrl
                                     with new position + iteration count.
5. iter_to_rgb (Sakthivel)      → map final iteration count → 24-bit colour
6. fb_write (Thanus)            → write that colour to the framebuffer BRAM
                                   at this pixel's address (double-buffered).
7. framebuffer_bram (Sakthivel) → stores the frame (compressed to RGB332/8-bit)
8. scan_out + hdmi_timing (S.)  → read framebuffer in raster order, generate
                                   sync signals, stream to the HDMI encoder.
9. HDMI monitor                 → picture!

Meanwhile, in parallel:
   Audio → Xilinx FFT IP (Geralt) → DMA → Python band extraction (Geralt, PS)
        → fft_bridge (Thanus) turns spectrum into scene parameters
        → fed into scene_sdf so the geometry reacts to the music.
```

The **feedback loop** (steps 2↔4) is the cleverest part: a pixel may loop around many times, one marching step per lap, until it hits or maxes out. That's how a deeply iterative algorithm runs on a fixed pipeline.

![Per-pixel render loop](docs/images/render_loop.svg)

---

## 4. Recommended reading order (your ramp-up path)

Do these in order. Each builds on the last. Don't try to understand a whole file — read the header comment and the port list (the `module (...)` block) first; that tells you 80% of the story.

1. **This guide, Sections 1–3.** The mental model.
2. **`README.md`** (repo root) — the team's own overview and the architecture diagram.
3. **`Vincent/SW_raymarching/scaffold.frag` and `mandelbox.frag`** — the *software* version of the scene maths in GLSL. Far easier to read than RTL, and the hardware mirrors it. Run Charlie's renderer (Section 8) to *see* it.
4. **`Charlie/gpu_renderer.js` + `camera.js`** — how a ray marcher works in plain JavaScript/WebGL. This is your "reference implementation."
5. **The 27-bit FP library** — start with `fp_mul.v` (cleanest), then `fp_add.v`, then `fp_length.v`. Read the stage comments. This teaches you how to *read* the team's pipelined RTL style.
6. **`ray_gen.sv`** (Jai) — your first "real" pipeline: pixel in, ray out.
7. **`scene_sdf.v` → `sdf_term.v` → `repeat_cell.sv`** (Vincent) — the distance field, built from the FP library.
8. **`march_core.sv`** (Vincent) — ties ray_gen + scene_sdf into the stepping loop.
9. **`pixel_dispatch.sv` → `feedback_ctrl.sv` → `FIFO.sv` → `fb_write.sv`** (Thanus) — the scheduler that drives the whole loop.
10. **`hdmi_timing.sv` → `scan_out.sv` → `framebuffer_bram.sv` → `iter_to_rgb.sv`** (Sakthivel) — getting pixels onto a screen.
11. **`Geralt_fft/docs/README.md` → `server.py` → `fft_bridge.v`** — the audio path.
12. **`Thanus_Neural/sphere_test.py` → `export_weights.py`**, then **`Vincent/.../Neural_RTL/`** — the optional neural SDF. (Save this for last; the README marks it "only if we get there.")
13. **`Vincent/Hardware/RTL/Analytic_SSF/top.sv`** and **`VivadoDesigns/`** — how it's all wired into one bitstream.

---

## 5. Module-by-module deep dive

Each module is one team member's area. For each, you get: what it does, the key idea, and a per-file table.

### 5.1 `Charlie/` — Software renderer (the reference)
A browser ray marcher in **React + Vite + WebGL2**. It exists so the team can *see* the intended image and debug the maths in an easy language before committing it to hardware.

| File | What it does |
|---|---|
| `gpu_renderer.js` | The real renderer: compiles a WebGL2 fragment shader that ray-marches the scene on your GPU. Soft shadows, ambient occlusion, ground grid. |
| `cpu_renderer.js` | Pure-JS fallback that re-implements the same GLSL maths (vec/mat ops by hand) so logic can be checked step-by-step. |
| `camera.js` | First-person fly camera: mouse-look + WASD + Space/Shift. Produces the camera matrix the shader uses. |
| `shaders.js` | The GLSL source strings (vertex + fragment) loaded by `gpu_renderer.js`. |
| `scaffold_renderer.js` | Minimal renderer used to bring up a new scene quickly. |
| `app.jsx`, `main.jsx` | React app shell / entry point that mounts the canvas and renderer. |
| `index.html`, `styles.css` | Page host and styling. |
| `package.json`, `vite.config.mjs` | Dependencies and the Vite dev-server config (serves on `http://127.0.0.1:4176`). |

### 5.2 `Geralt_fft/` — Audio FFT pipeline
Offloads frequency analysis to the FPGA, then extracts three audio bands on the CPU. **Co-design** in miniature.

| File | What it does |
|---|---|
| `fft.tcl` | Vivado script that rebuilds the FFT block design (FFT IP + AXI DMA + GPIO). |
| `jupyter notebook/server.py` | Runs on the PS. Opens a WebSocket, receives raw audio from a browser, packs it 16-bit, fires the DMA through the hardware FFT, reads back the spectrum, computes magnitude `√(R²+I²)`, keeps the first 512 bins, streams it back. |
| `jupyter notebook/audio_fft.bit` / `.hwh` | The compiled FPGA bitstream + hardware description PYNQ loads. |
| `fft_bridge.v` | (Owned/extended by Thanus — see 5.6.) Turns the live spectrum into scene parameters in hardware. |
| `config_sender.v` | Helper to push configuration words onto the FFT's AXI control stream. |
| `app.jsx`, `FPGA_FFT.html` | A small web front-end to visualise the spectrum. |
| `docs/*.md`, `docs/PYNQ FFT/*.png` | Excellent written notes on the FFT IP, bin maths, and waveform captures. **Read `docs/README.md` first.** |

**Key numbers:** 1024-point FFT, sample rate 44.1 kHz → **43.07 Hz per bin**; only bins 0–511 are usable (Nyquist), bin 0 (DC) discarded. Bands: **Bass** ≈ bins 1–5, **Mids** ≈ 6–46, **Highs** ≈ 47–256.

![Live FFT spectrum](docs/images/fft_spectrum.png)

### 5.3 `Jai/` — Ray generation + FP datapath origins
SystemVerilog that converts a pixel coordinate + camera into a ray, plus the AXI register block that lets the CPU move the camera. `Jai/hdmi_200mhz/` is a **full standalone project tree** containing a complete copy of the RTL (fp lib, core, control, video) wired for a 200 MHz experiment — handy as a self-contained reference build.

| File | What it does |
|---|---|
| `ray_gen.sv` | The headline module: a deep pipeline (≈48 clock latency) that takes `(pix_x, pix_y)`, the 3×3 `lookat` matrix and camera origin, and outputs `ray_orig[3]` + `ray_dir[3]` in 27-bit FP. Includes an inline int→FP helper. |
| `axi_camera_regs.sv` | AXI4-Lite slave exposing the lookat matrix + camera origin as registers, so the PS can reposition the camera at runtime. |
| `tb_ray_gen.sv`, `tb_axi_camera_regs.sv`, `tb_fp_ops.sv` | Testbenches for the above and the FP ops. |
| `hdmi_200mhz/rtl/...` | A complete mirror of the whole RTL design (fp, core, control, video, top) for a 200 MHz variant — see Section 5.7 file groups; same modules, different top-level. |
| `hdmi_200mhz/sim/...` | Verilator/Icarus sims and `Makefile` for that variant. |
| `hdmi_200mhz/constraints/pynq_z1.xdc` | Pin assignments for the PYNQ-Z1. |
| `hdmi_200mhz/ip*/rgb2dvi*` | Vendored Digilent RGB→DVI/HDMI encoder IP (VHDL). |

### 5.4 `Sakthivel/` — HDMI output pipeline
Turns finished pixels into a correctly-timed HDMI signal. All under `HDMI_Intial/`.

| File | What it does |
|---|---|
| `hdmi_timing.sv` | Generates HSYNC/VSYNC/active-video and the `(x,y)` counters for 720p60 (totals 1650×750 @ 74.25 MHz). |
| `scan_out.sv` | Reads the framebuffer in raster order in step with `hdmi_timing`, handles **double-buffering** (`write_bank`/`read_bank` with clock-domain-crossing sync), and outputs 24-bit RGB. |
| `framebuffer_bram.sv` | Dual-port BRAM holding the frame. Stores **RGB332 (8-bit)** to fit PYNQ's limited Block RAM, decompresses to 24-bit on read. |
| `iter_to_rgb.sv` | The colour map: turns an 8-bit iteration count into 24-bit RGB using thresholds + bit-shifts (a cheap palette). This feeds Thanus's `fb_write`. |
| `palette.sv` | Palette lookup variant/support for the colour mapping. |
| `test_pattern_gen.sv` | Standalone colour-bar generator to bring up the display path before the renderer is ready. |
| `pynq_hdmi.xdc` | HDMI pin constraints for the PYNQ-Z1. |
| `bd_wrappers.v` | Auto-generated wrappers letting these modules drop into a Vivado block design. |
| `fullres/*` | Full-resolution (1280×720, no 2× downscale) variants of the framebuffer/scan-out/test-pattern. |
| `hdmi_test_proj/...` | A standalone Vivado bring-up project for the HDMI path. |

### 5.5 `Thanus/` — Pixel dispatch & feedback scheduling
The **traffic controller** for the render loop. Every pixel passes through here, both on the way in (fresh) and on the way back (re-iterating). This is what makes a fixed pipeline run an iterative algorithm.

| File | What it does |
|---|---|
| `pixel_dispatch.sv` | Sweeps the 1280×720 raster in scan order, one pixel per clock when the pipeline is ready. Maps to a **640×360** framebuffer (`pix_id = (y>>1)*640 + (x>>1)`) to halve BRAM. `valid` is combinational to kill a one-cycle start-up race. |
| `feedback_ctrl.sv` | The arbiter: chooses between a **fresh** pixel from dispatch and a **returning** half-marched pixel from `march_core` (carried via the FIFO). **Returning pixels always win**, so in-flight rays finish before new ones start — this prevents FIFO overflow. |
| `FIFO.sv` | Parameterisable synchronous FIFO with combinational read. Used at **WIDTH=190, DEPTH=128** to buffer in-flight ray state (covers ~103-cycle worst-case round-trip with headroom). |
| `fb_write.sv` | When a pixel is done, takes its `pix_id` + `hit` + 24-bit `rgb` (from `iter_to_rgb`) and drives the BRAM write port (`bram_we/addr/data_in`). Deliberately trivial/combinational. |
| `pixel_dispatch_tb.sv`, `feedback_ctrl_tb.sv`, `fb_write_tb.sv` | Unit testbenches. |
| `integration_tb.sv` | Wires all three together with a mock framebuffer + a "seen every pixel" checker. |
| `run_tests.bat` | Runs the whole suite under Icarus Verilog. |

Thanus's own hand-drawn explanations of each scheduler module (centralized in `docs/images/`):

| | |
|---|---|
| ![Pixel dispatch](docs/images/pixel_dispatch.png) | ![Feedback control](docs/images/feedback_ctrl.png) |
| ![FIFO](docs/images/fifo.png) | ![Feedback write](docs/images/fb_write.png) |

### 5.6 `Thanus/` — FFT Bridge integration + `Thanus_Neural/`
Two extra responsibilities beyond scheduling.

**FFT bridge** (`Geralt_fft/fft_bridge.v`, extended here): five pipelined stages — a 512-bin counter; 40-bit energy accumulators for bass (bins 0–10), mid (11–150), treble (151–511) and total; bit-slice "sensitivity" windows; `int2fp` conversion; and **frame-stable output registers latched once per frame at pixel (0,0)** so every ray in a frame sees the same audio snapshot. New outputs `out_domain_fold` (bass→tiling), `out_twist` (mid→spiral), `out_epsilon` (treble→surface tightness), `out_sdf_scale` (total→scene scale) feed straight into `scene_sdf`/`march_core`.

**`Thanus_Neural/`** — train a tiny MLP to *be* the SDF, then bake it into hardware.

| File | What it does |
|---|---|
| `sphere_test.py` | Trains the net on an analytic sphere SDF (500k points). End-to-end sanity check; final test loss ~3e-5. |
| `torus_test.py` | Same idea for a torus (R=1.0, r=0.3). |
| `stanford_bunny_test.py` | Harder target using a real mesh (needs `trimesh`). |
| `export_weights.py` | Loads a trained `.pth`, quantises weights to **Q4.12** (`round(w×4096)`), writes one hex file per neuron (`w_*.hex`, `b_*.hex`) — directly loadable by the Verilog `$readmemb`. |
| `visualise.py` | Plots the learned SDF's zero-contour (the surface cross-section at z=0) to eyeball training quality. |
| `explanation.txt` | Thanus's own notes-to-the-team on the workflow and file roles. **Read this.** |
| `*.pth`, `*.npy`, `*_result.png` | Saved weights, train/test datasets, and result images. |

Network: `3 → 32 → 32 → 32 → 1`, ReLU hidden layers, linear output, ~3,201 params, inputs in `[-2,2]³`. Learned-SDF results (zero-contour cross-sections):

| Sphere | Torus |
|---|---|
| ![Sphere result](docs/images/neural_sphere.png) | ![Torus result](docs/images/neural_torus.png) |

### 5.7 `Vincent/` — Ray-marcher core + FP library
The compute heart, plus the shared 27-bit FP library every hardware module imports.

**`Hardware/Floating_Point_Lib/`** — the 27-bit FP arithmetic. Each is a small pipeline; latencies matter (they're commented in the files):

| File | Operation (latency) |
|---|---|
| `fp_mul.v` | Multiply — DSP-based, 4 stages. The cleanest file to learn the style from. |
| `fp_add.v` / `fp_sub.v` | Add / subtract — align exponents, add mantissas, renormalise (~4 stages). |
| `fp_isqrt.v` | Inverse square root `1/√x` (~16 stages) — used instead of a true sqrt to avoid division. |
| `fp_length.v` | Vector length `√(x²+y²+z²)` (~22–32 cycles) built from `fp_mul` + `fp_add` + `fp_isqrt`, with `state_pipe` delays to align terms. |
| `fp_abs.v`, `fp_negate.v` | Sign-bit tricks (combinational). |
| `fp_min.v`, `fp_max.v` | Compare-and-select. |
| `int2fp.v` | Integer → 27-bit FP (priority-encoder normalise). |

**`Hardware/RTL/Analytic_SSF/`** — the analytic (hand-derived) scene:

| File | What it does |
|---|---|
| `scene_sdf.v` | The distance field: a **repeated box-frame** (`sdBoxFrame` + domain repetition). Built entirely from the FP library; carefully pipelined with `state_pipe` delays. Multiplies its output by `sdf_scale_in` (audio-reactive). |
| `sdf_term.v` | One term of the box-frame formula: `length(max(v,0)) + min(max(...),0)`. |
| `repeat_cell.sv` | Folds a world coordinate into a single 10-unit cell (the infinite-lattice trick) via a big priority-encoder of thresholds. |
| `march_core.sv` | The per-pixel marcher: instantiates `ray_gen`, queries `scene_sdf`, decides hit vs continue, and emits either a finished pixel (to `fb_write`) or feedback (back to `feedback_ctrl`). |
| `state_pipe.v` | The generic delay line (`WIDTH`/`DEPTH` shift register) used everywhere to time-align signals. **Tiny but load-bearing.** |
| `top.sv` | Top-level wiring for this analytic design: clock wizard (compute clock + 74.25 MHz pixel clock), camera constants, and the HDMI output instances. |

**`Hardware/RTL/Neural_RTL/`** — the alternative neural SDF (optional/experimental):

| File | What it does |
|---|---|
| `neural_sdf_top.sv` | Top of the neural path: bakes the net into a BRAM grid at startup, then answers distance queries by interpolation. |
| `sdf_nn.sv`, `neuron.sv`, `neuron_layer.sv`, `neuron_ReLu.sv` | The MLP inference fabric (uses the exported Q4.12 weight hex files). |
| `baking_ctrl.sv` | Sweeps the input grid once at startup, runs each point through the net, writes results to `sdf_bram`. |
| `sdf_bram.sv` | Stores the baked distance grid. |
| `trilinear_interp.sv`, `blend_lerp.sv` | Read the grid and interpolate between the 8 nearest baked samples — cheap, fixed-cost distance lookups. |
| `fp_to_q4_12.sv`, `q4_12_to_fp.sv` | Convert between the 27-bit FP datapath and the Q4.12 weight format. |

**`Hardware/Testbenches_Sim/`** — `sim_top.sv`, `state_pipe_tb.v`, driven by `Hardware/Makefile` (Verilator). Renders to a `.ppm` image you can open.

**`SW_raymarching/`** — the GLSL playground where the scene maths was prototyped: `mandelbox.frag`, `sierpinski.frag`, `marcher*.frag`, `scaffold.frag`, etc. **Start here to understand the maths** before the RTL. `Hardware/References/` has linked notes; `Hardware/OLD_NN/` is an earlier neural experiment kept for reference.

**`PC_to_Mac_Transfers.txt`** — the `ip_repo` paths and pin-constraint snippets used to set the Vivado project up across machines.

### 5.8 `VivadoDesigns/` — the integrated build
`ray_marcher_basev1/` is the Vivado project that stitches **everyone's** RTL into one block design + bitstream for the PYNQ-Z1. `ip_repo/` vendors the Digilent rgb2dvi HDMI encoder; the `cordic_0` IP converts FFT real/imag pairs into magnitude in hardware. The `.srcs/sources_1/imports/` folder is the canonical snapshot of which files actually went into the integrated build — a good place to confirm "what's really wired up." Most other files under here (`.runs/`, `.cache/`, `.gen/`) are **Vivado-generated build artifacts** — you can ignore them when learning.

### 5.9 Root-level files
| File | What it does |
|---|---|
| `README.md` | The team overview + architecture diagram. |
| `LEARNING_GUIDE.md` | This document. |
| `progress_log.txt` | Running project log. |
| `Mandelbox Math.pptx` | The fractal maths background slides. |
| `Presentation_Details` | Notes/requirements for the project presentation. |
| `sim_HDMI150MHz/` | A top-level Verilator sim harness for the 150 MHz HDMI variant (mirrors the per-module sims). |
| `.gitignore`, `.DS_Store` | Git config / macOS cruft (ignore). |

---

## 6. Clock domains (don't let this trip you up)
There are **two main clocks**, created by the Xilinx clocking IP in `top.sv`:
- **Compute clock** (~150 MHz in the main design, a 200 MHz variant exists under `Jai/hdmi_200mhz/`) — runs the render pipeline: dispatch, ray_gen, march_core, FP library, FIFO.
- **Pixel clock 74.25 MHz** — runs `hdmi_timing` + `scan_out` for 720p60.
The framebuffer BRAM sits **between** the two domains (written by compute side, read by pixel side), which is why `scan_out.sv` has those `ASYNC_REG` clock-domain-crossing synchronisers on the bank-select signal. Audio runs off the AXI/FFT clock on the PS side.

---

## 7. Glossary (project-specific)
- **SDF** — Signed Distance Field/Function: returns distance to nearest surface; negative inside.
- **Ray marching** — stepping along a ray by the SDF distance until hit or give-up.
- **iter / iteration count** — how many steps a pixel's ray took; used as the colour index.
- **27-bit FP** — this project's float: 1 sign + 8 exponent + 18 mantissa, bias 127.
- **Q4.12** — 16-bit fixed-point (4 integer, 12 fractional bits) used for neural weights.
- **PL / PS** — Programmable Logic (FPGA fabric) / Processing System (ARM CPU).
- **RTL** — Register-Transfer Level: the hardware description (the `.v`/`.sv` source).
- **BRAM** — Block RAM: on-chip memory blocks inside the FPGA.
- **DSP** — hardware multiply-accumulate blocks in the FPGA; the FP multiplier uses these.
- **AXI / AXI-Lite / AXI-Stream / DMA** — on-chip bus standards; see 2.6.
- **state_pipe** — a shift-register delay line used to time-align pipelined signals.
- **domain repetition / repeat_cell** — folding coordinates to tile one shape infinitely.
- **RGB332** — 8-bit colour (3 red, 3 green, 2 blue) used to shrink the framebuffer.
- **Porch / sync / blanking** — invisible timing gaps in the video signal (see 2.8).
- **Double buffering** — render to one bank, display the other, then swap.
- **Bitstream (.bit)** — the compiled FPGA configuration; `.hwh` describes it to PYNQ.
- **Verilator / Icarus** — simulators used to test RTL on a PC before hardware.

---

## 8. Running things (hands-on)
**Software renderer (easiest — do this first):**
```bash
cd Charlie
npm install
npm run dev      # open http://127.0.0.1:4176  — fly with WASD + mouse
```

**RTL simulation (see the hardware render a frame to an image):**
```bash
cd Vincent/Hardware
make             # Verilator build; produces a frame.ppm you can open
```
(Thanus's scheduler tests: `cd Thanus && run_tests.bat`, needs Icarus Verilog.)

**Neural SDF training (optional):**
```bash
cd Thanus_Neural
pip install torch numpy matplotlib trimesh
python sphere_test.py     # trains, saves sphere_sdf.pth
python visualise.py       # check the learned surface
python export_weights.py  # emit Q4.12 hex weights for the RTL
```

**Audio FFT (needs the board):** flash `Geralt_fft/jupyter notebook/audio_fft.bit` on a PYNQ-Z1, run `server.py`, open the web front-end.

**Full hardware build:** open `VivadoDesigns/ray_marcher_basev1` in Vivado 2020.x+, generate bitstream, program the PYNQ-Z1, connect HDMI.

---

*Tip for your own understanding: pick one pixel and narrate its journey (Section 3) out loud, naming the file responsible at each step. If you can do that without looking, you understand the system.*
