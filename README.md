# Audio-Sync Ray Marcher — FPGA Accelerator

> Real-time, audio-reactive 3D **ray marcher** built from scratch on a **PYNQ-Z1** (Zynq-7000 SoC) — no GPU, no soft-core. Custom RTL renders a signed-distance scene on the FPGA fabric and streams it over **HDMI at 720p60**, while a hardware **FFT** makes the geometry react to live music.

**Imperial College London — summer term group project (EEE/EIE).**
📖 Deep-dive walkthrough and per-file explanations: [`LEARNING_GUIDE.md`](LEARNING_GUIDE.md)

<!--
HERO IMAGE — capture a clean render and save as docs/images/hero.png, then uncomment below.
  Option A (hardware): photograph the HDMI monitor running VivadoDesigns/ray_marcher_basev1.
  Option B (software): cd Charlie && npm install && npm run dev → http://127.0.0.1:4176, screenshot the canvas.
  Option C (RTL sim):  cd Vincent/Hardware && make → frame.ppm → sim_HDMI150MHz/convert_ppm_to_png.ps1.
-->
<!-- ![Rendered scene](docs/images/hero.png) -->

---

## Overview

The system renders a 3D fractal-style scene by **ray marching** a signed-distance field (SDF): for each of 921,600 pixels it shoots a ray and steps along it until it hits a surface, colouring the pixel by how many steps it took. Every stage — ray generation, the marching feedback loop, the distance-field maths, colour mapping, and HDMI scan-out — is custom hardware running in a fully pipelined datapath. In parallel, incoming audio is transformed by a hardware FFT and its bass/mid/treble energy is fed into the scene so the geometry pulses with the music.

**What it demonstrates:** end-to-end FPGA system design — custom floating-point arithmetic, deep pipelining, clock-domain crossing, AXI hardware/software co-design, real-time video, and a hardware/PyTorch ML path — integrated across a six-person team into a single bitstream.

---

## Technical highlights

- **Custom 27-bit floating-point ISA** (1·8·18) and a full FP library (`add/sub/mul/isqrt/length/min/max/abs`) hand-built to fit the FPGA's DSP/BRAM resources.
- **Deeply pipelined render core** — e.g. a ~48-cycle ray generator and a 32-cycle vector-length unit — with explicit `state_pipe` delay lines to keep operands cycle-aligned.
- **Feedback-loop scheduler** that runs an inherently iterative algorithm on a fixed pipeline: pixels recirculate one marching step per lap through a 190-bit × 128 FIFO, with a returning-rays-win arbiter to prevent overflow.
- **Hardware/software co-design** — 1024-point Xilinx FFT IP + AXI-DMA streaming into DDR, band extraction in PYNQ Python, piped back into the SDF as live parameters.
- **Real-time video** — RGB332 double-buffered framebuffer and a 720p60 HDMI scan-out across two clock domains (≈150 MHz compute · 74.25 MHz pixel).
- **Neural SDF (research path)** — a PyTorch MLP trained to approximate the distance field, quantised to Q4.12 and baked into BRAM for fixed-cost hardware inference.

**Skills:** SystemVerilog/Verilog · Vivado block design · AXI4-Lite/Stream/DMA · Verilator & Icarus simulation · WebGL2/GLSL · PyTorch · digital arithmetic & pipelining.

---

## Architecture

<img src="docs/images/architecture.svg" alt="System architecture" width="600">

Two clock domains: compute ~150 MHz (200 MHz variant in `Jai/hdmi_200mhz/`) · pixel 74.25 MHz. The framebuffer BRAM bridges them, double-buffered. The software renderer (`Charlie/`) and GLSL prototypes (`Vincent/SW_raymarching/`) are reference implementations that mirror the hardware scene.

---

## Render loop

<img src="docs/images/render_loop.svg" alt="Per-pixel render loop" width="760">

`pixel_dispatch` emits one pixel/clock → `feedback_ctrl` arbitrates fresh vs returning rays (returning win) → `ray_gen` builds the ray → `march_core` steps once via `scene_sdf`; miss ⇒ loop back through the FIFO, hit/limit ⇒ `iter_to_rgb` → `fb_write` → framebuffer → `scan_out`. Full per-pixel trace: `LEARNING_GUIDE.md` §3.

---

## Team & contributions

| Member | Ownership | Stack |
|--------|-----------|-------|
| Charlie | Software reference renderer (WebGL2 GPU + CPU) | React, Vite, WebGL2 |
| Geralt | Audio FFT pipeline (PL FFT/DMA + PS extraction) | Vivado, Xilinx FFT IP, AXI-Stream/DMA, PYNQ |
| Jai | Ray generation + 27-bit FP datapath | SystemVerilog |
| Sakthivel | HDMI output — framebuffer, scan-out, timing, palette. SDF testbenches, VR Headset CAD | SystemVerilog, Vivado |
| Thanus | Pixel-dispatch / feedback scheduler · FFT bridge + audio pipeline · SDF shape library · neural-SDF training | SystemVerilog, PyTorch |
| Vincent | Ray-marcher core (analytic + neural) + FP library | SystemVerilog, Verilog, Verilator |

Integration into a single PYNQ-Z1 bitstream lives in `VivadoDesigns/ray_marcher_basev1/`.

---

## Modules

| Module | Owner | What it does |
|--------|-------|--------------|
| **`Charlie/`** | Charlie | WebGL2 fragment-shader marcher (`gpu_renderer.js`) + JS mirror (`cpu_renderer.js`) + fly camera. Visual reference — `npm run dev` → :4176. |
| **`Geralt_fft/`** | Geralt | 1024-pt FFT IP (AXI-Stream) → AXI DMA → DDR. PS `server.py` unpacks complex, computes `√(R²+I²)`, splits bins 0–511 into bass / mid / high. |
| **`Jai/`** | Jai | `ray_gen.sv` — ~48-cycle pipeline turning pixel + camera into a ray in 27-bit FP; `axi_camera_regs.sv` AXI-Lite camera. `hdmi_200mhz/` = 200 MHz mirror. |
| **`Thanus/`** | Thanus | Render scheduler: `pixel_dispatch` (1280×720 scan, half-res `pix_id`), `feedback_ctrl` (fresh/return arbiter, 190-bit × 128 FIFO), `fb_write` (combinational BRAM write). Full TB suite (`run_tests.bat`). |
| **`Thanus/` FFT bridge** | Thanus | `fft_bridge.v` — per-frame bass/mid/treble/total-energy accumulators → sensitivity slices → `int2fp` → 11 frame-stable 27-bit FP outputs. Four new audio-reactive SDF parameters: `out_domain_fold` (bass → grid tiling), `out_twist` (mid → rotation), `out_epsilon` (treble → surface bloom), `out_sdf_scale` (total energy → scene scale). Xilinx CORDIC IP converts FFT real/imag to magnitude. All outputs propagated through `top.sv` → `march_core` → `scene_sdf`, replacing hardcoded constants. PS-side pipeline: `audio_sender.py` (laptop mic → Python FFT → 11 floats over TCP) and `board.py` (PYNQ TCP receiver → `fp32_to_fp27` → AXI MMIO register writes). Timing: WNS = +3.170 ns. |
| **`Thanus/` SDF library** | Thanus | 15+ standalone analytic SDF modules, each following the same clocked fp_-library interface as `scene_sdf`. Shapes: `sdf_sphere`, `sdf_torus`, `sdf_octahedron`, `sdf_gyroid` (Taylor-series sin/cos), `sdf_twisted_torus` (domain rotation), `sdf_chain_link` (clamped torus), `sdf_capsule`, `sdf_box`, `sdf_rounded_box`, `sdf_ellipsoid`, `sdf_pyramid`, `sdf_disk`, `sdf_pipe`, `sdf_vesica`, `sdf_hyperboloid`, `sdf_spiral`, `sdf_mandelbulb`. All pipeline-synchronised with explicit `state_pipe` delay lines. |
| **`Thanus_Neural/`** | Thanus | *Research path:* MLP `3→64→64→64→1` trained on analytical SDFs (sphere loss ~3e-5, torus ~5e-5, Mandelbox ~9e-3); `export_weights.py` → Q4.12 hex for `$readmemb`. |
| **`Vincent/`** | Vincent | Marcher core + the shared 27-bit FP library. Analytic `scene_sdf` (box-frame + domain repetition) and a neural BRAM-bake path; Verilator sim → `.ppm`; GLSL prototypes. |
| **`Sakthivel/HDMI_Intial/`** | Sakthivel | `framebuffer_bram` (RGB332), `scan_out` (double-buffer + CDC), `hdmi_timing` (720p60, 1650×750 @ 74.25 MHz), `iter_to_rgb` / `palette`. |
| **`VivadoDesigns/`** | All | Integrated block design + bitstream for the PYNQ-Z1. IP: rgb2dvi (HDMI), cordic (FFT magnitude). |

Per-file detail for every module is in [`LEARNING_GUIDE.md`](LEARNING_GUIDE.md) §5.

---

## Results

**Hardware FFT spectrum** — live audio transformed on the PL and read back over DMA:

![FFT spectrum](docs/images/fft_spectrum.png)

**Neural SDF** — learned zero-contour cross-sections after training (sphere test loss ~3e-5):

| Sphere | Torus |
|---|---|
| ![Sphere result](docs/images/neural_sphere.png) | ![Torus result](docs/images/neural_torus.png) |

<!-- Regenerate FFT: run server.py on the board with FPGA_FFT.html playing audio, screenshot the spectrum.
     Regenerate neural: cd Thanus_Neural && python sphere_test.py && python visualise.py -->

---

## Custom 27-bit float

Every hardware datapath shares one number format, sized to fit the FPGA's DSP/BRAM resources while keeping enough precision for stable marching:

<img src="docs/images/fp27_format.svg" alt="27-bit floating-point format" width="640">

Neural weights use Q4.12 (16-bit) via `fp_to_q4_12` / `q4_12_to_fp` at the boundary. Worked example and the full FP library: [`LEARNING_GUIDE.md`](LEARNING_GUIDE.md) §2.4.

---

## Build & run

```bash
# Software renderer
cd Charlie && npm install && npm run dev          # http://127.0.0.1:4176

# RTL simulation (Verilator) → frame.ppm
cd Vincent/Hardware && make

# Scheduler tests (Icarus)
cd Thanus && run_tests.bat

# Neural SDF
cd Thanus_Neural && pip install torch numpy matplotlib trimesh
python sphere_test.py && python visualise.py && python export_weights.py

# Audio pipeline (laptop side)
cd Vincent && pip install sounddevice numpy scipy
python audio_sender.py                           # streams mic audio to PYNQ over TCP

# Audio pipeline (PYNQ side)
# Copy board.py to PYNQ, update bitstream path, then:
python3 board.py                                 # receives audio params, writes to AXI registers

# Audio FFT: flash Geralt_fft/jupyter notebook/audio_fft.bit on PYNQ-Z1, run server.py
# Full HW: open VivadoDesigns/ray_marcher_basev1 in Vivado 2020.x+, gen bitstream, program board
```

**Requires:** PYNQ-Z1 · HDMI 720p60 display · 44.1 kHz audio · Vivado 2020.x+ · Node.js + WebGL2 browser · Python 3 (`torch numpy matplotlib trimesh sounddevice`) · Verilator + Icarus Verilog.

---

## Repository layout

```
SummerProjectMathsAccelerator/
├─ Charlie/                Software reference renderer (React + WebGL2)
├─ Geralt_fft/             Audio FFT pipeline (Vivado IP + PYNQ Python)
│  ├─ docs/                  FFT notes + waveform captures
│  └─ jupyter notebook/      PYNQ server + bitstream
├─ Jai/                    Ray generation + 27-bit FP datapath
│  └─ hdmi_200mhz/           Self-contained 200 MHz RTL + sim mirror
├─ Sakthivel/HDMI_Intial/  HDMI output — framebuffer, scan-out, timing
├─ Thanus/                 Pixel-dispatch / feedback scheduler + FIFO
├─ Thanus_Neural/          PyTorch neural-SDF training + Q4.12 export
├─ Vincent/                Ray-marcher core (analytic + neural) + FP library
│  ├─ Hardware/              Floating_Point_Lib, RTL, Verilator sim
│  └─ SW_raymarching/        GLSL shader prototypes
├─ VivadoDesigns/          Integrated block design + bitstream
├─ sim_HDMI150MHz/         Top-level Verilator sim harness
├─ docs/images/            Diagrams + result captures
├─ LEARNING_GUIDE.md       Full high→low onboarding guide
└─ progress_log.txt        Running project log
```

**Status (01/06/26):** core marcher functional; integration into `ray_marcher_basev1` underway; neural path experimental.
