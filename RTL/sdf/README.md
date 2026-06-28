# RTL/sdf — Signed-Distance Field Scenes

Each module in this folder implements a different 3D scene as a signed-distance function. They all share the same interface so they can be swapped in and out of `march_core` by changing a parameter.

---

## Module interface

Every SDF module takes a 3D point and returns the signed distance to the nearest surface:

```verilog
module scene_sdf (
    input  logic clk,
    input  logic [26:0] px, py, pz,   // query point in FP27
    output logic [26:0] sdf_out        // signed distance in FP27
);
```

Positive distance = outside the surface. Negative = inside. The marcher steps toward the surface when `sdf_out > HIT_THRESH`.

When swapping scenes, update `SCENE_CORE_LAT` in `march_core.sv` to match the new module's pipeline depth. Getting this wrong causes misaligned pixel IDs and garbage renders.

---

## `twisted_torus_sdf.v` — SCENE_CORE_LAT = 101

A standard torus with a Y-axis domain twist. The twist rotates the XZ plane by `angle = py × TWIST` before evaluating the torus SDF, which creates a helical twist along the vertical axis.

**Pipeline breakdown:**

1. `angle = fp_mul(py, TWIST)` — 4 cycles
2. `angle² = fp_mul(angle, angle)` — 4 cycles
3. `cos ≈ 1 − angle²/2` (Taylor) — 4+4 cycles
4. `sin ≈ angle − angle³/6` (Taylor) — 4+4+4 cycles
5. Rotated `px' = cos·px − sin·pz` — 4+4 cycles
6. Rotated `pz' = sin·px + cos·pz` — 4+4 cycles
7. Torus SDF on (px', py, pz'): `length(px'-R, pz') − small_r` — ~32 cycles

Total: ~101 cycles. The Taylor approximations for sin/cos are accurate for small twist angles; large twists will introduce visible error (though it still looks interesting).

Parameters (localparams in the module):
- `BIG_R = 1.2` — major radius
- `SMALL_R = 0.35` — tube radius
- `TWIST = 0.5` — twist rate per unit height

---

## `NOTWORKINGmenger_sdf.sv` — SCENE_CORE_LAT = 83

Three-level Menger sponge using a box-frame IFS. The "NOTWORKING" prefix means the SDF is correct and sim-verified, but the hardware render is broken (frame dispatch issue in top.sv — see main README). The RTL itself is fine.

**Algorithm per iteration:**

```
fold:  p = abs(p)
       if p.x < p.y: swap(p.x, p.y)  — fold to x ≥ y ≥ z
       if p.x < p.z: swap(p.x, p.z)
       if p.y < p.z: swap(p.y, p.z)
scale: p = p × 3 − 2
```

After 3 iterations, evaluate box-frame SDF on the resulting point. The box-frame SDF is `max(max(|px|,|py|,|pz|) − outer, min(max(|px|,|py|), ...) − inner)` (roughly — it punches holes along all three axes).

Domain repetition via `repeat_mod_cell` tiles the sponge infinitely in XZ.

`REPEAT_LAT = 18` (from `repeat_mod_cell`), `SCENE_CORE_LAT = 83`, `SDF_LAT = 101`.

---

## `NOTWORKINGmandelbox.sv` — SCENE_CORE_LAT = 234

4-iteration Mandelbox orbit trap with scale = −1.5. Also RTL-verified in sim, not yet added to Vivado project.

**Per-iteration operations:**

1. `fp_clamp1`: clamp each component to [−1, 1]. Combinational: `a[25:0] > {8'h7F, 18'h0} ? {a[26], 8'h7F, 18'h0} : a`. No pipeline delay.
2. `z = 2·clamp(z) − z`: "box fold". `fp_times2` is combinational (add 1 to exponent). Then `fp_sub` (4 cycles).
3. Spherical fold: compare `|z|` to `minRadius` and `fixedRadius`, scale accordingly. Requires `fp_length` (32 cycles).
4. `z = scale·z + c`: `fp_mul` (4 cycles) + `fp_add` (4 cycles).

After 4 iterations: `sdf_out = length(z) × |scale|^(−iters)`.

`SCENE_CORE_LAT = 234` (not 224 as the inline comment says — the comment is wrong).

`REPEAT_LAT = 0` (Mandelbox has no spatial tiling).

---

## `sphere_sdf.v`

Basic sphere SDF: `length(p) − radius`. Used as a reference/test scene. `SCENE_CORE_LAT = 37` (fp_length = 32, fp_sub = 4, register = 1).

---

## `scaffold_sdf.v`

Box-frame SDF used as an early scaffold before other scenes were implemented. Still in the folder for reference.

---

## Adding a new scene

1. Write your SDF module with the interface above.
2. Measure or compute its pipeline latency (`SCENE_CORE_LAT`).
3. In `march_core.sv`: instantiate your module, update `SCENE_CORE_LAT`, and update `REPEAT_LAT` (0 if no tiling).
4. Add your `.sv` file to the Vivado project source list.
5. Update `ctrl.py` on the PYNQ if the scene needs different cell size or shape parameters.
