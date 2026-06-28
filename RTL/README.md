# RTL

All synthesisable SystemVerilog/Verilog for the ray marcher. Every module targets the Zynq XC7Z020 (PYNQ-Z1) at 125 MHz on the PL.

---

## Folder structure

```
RTL/
├─ FP_Lib/    27-bit floating-point arithmetic library
├─ core/      Ray generation and march loop
├─ sdf/       Signed-distance field scenes
├─ control/   Pixel scheduler and feedback FIFO
├─ video/     DDR3 writer and colour palette
└─ top/       Top-level integration and PS wrapper
```

Each folder has its own README with per-module detail.

---

## Dependency graph

```
top.sv
 ├─ pixel_dispatch     (control/)
 ├─ feedback_ctrl      (control/)
 │   └─ FIFO           (control/)
 ├─ march_core         (core/)
 │   ├─ ray_gen        (core/)
 │   ├─ repeat_mod_cell(core/)
 │   ├─ scene_sdf      (sdf/)   ← swapped per scene
 │   └─ state_pipe     (core/)
 ├─ ddr_rgb_writer     (video/)
 │   └─ palette        (video/)
 └─ rgb2dvi IP         (ip_repo/)
```

All floating-point computation inside `march_core`, `ray_gen`, and every `sdf/` module uses `FP_Lib/`.

---

## FP27 quick reference

Format: `[26] sign | [25:18] exp (bias-127) | [17:0] mantissa`

- ONE = `27'h1FC0000`
- TWO = `27'h2000000`
- ZERO = `27'h0`
- Negative: flip bit 26

See [FP_Lib/README.md](FP_Lib/README.md) for the full library.

---

## Design conventions

- All registered modules are synchronous active-low reset (`rst_n`) or active-high reset (`rst`) — check the port name.
- Latency is always expressed in clock cycles at 125 MHz. When connecting two pipelined modules, use `state_pipe` to delay side-channel signals (pix_id, iter, etc.) to match.
- `state_pipe #(.WIDTH(W), .DEPTH(D))` infers SRL32 shift registers in Vivado — do not replace with explicit flop chains.
- SDF modules present the same interface: `clk`, `px/py/pz [26:0]`, `sdf_out [26:0]`. Latency differs per scene and must be set via `SCENE_CORE_LAT` in `march_core`.
