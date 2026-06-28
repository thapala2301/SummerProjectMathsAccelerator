# FP_Lib — 27-bit Floating-Point Library

Custom floating-point arithmetic library sized for the Xilinx DSP48E1 slice on the Artix-7 (PYNQ-Z1). Every module in the marcher uses this format exclusively.

---

## Number format

```
 bit 26    bits 25:18     bits 17:0
┌────────┬─────────────┬──────────────────────┐
│  sign  │  exponent   │      mantissa        │
│  (1b)  │  (8b, b127) │      (18b)           │
└────────┴─────────────┴──────────────────────┘
```

Same bias (127) and same field layout as IEEE 754 single-precision, just narrower. No denormals, no NaN, no infinity — the hardware assumes inputs are always normal finite numbers. This simplifies every arithmetic module significantly.

The 18-bit mantissa maps onto the B input of a DSP48E1 (which has an 18-bit port), so each `fp_mul` uses exactly one DSP48 slice.

---

## Module list

### `fp_mul.v` — 4 cycles

Multiplies two FP27 numbers.

- Sign: XOR of input signs.
- Exponent: add exponents, subtract bias (127).
- Mantissa: 18×18 unsigned multiply (one DSP48E1), take the upper 18 bits of the 36-bit product. Renormalise if the product overflows into the implicit leading bit.

Each instance costs one DSP48E1. With 220 available on the XC7Z020, and `fp_length` alone using 5, headroom is limited — avoid redundant instances.

### `fp_add.v` / `fp_sub.v` — 4 cycles

`fp_sub` is `fp_add` with the sign of `b` flipped before the adder. The adder:

1. Aligns the mantissas by right-shifting the smaller operand.
2. Adds (or subtracts) the aligned mantissas.
3. Renormalises: finds the leading 1 in the result and shifts.
4. Rounds (truncation).

Pipeline: four registered stages.

### `fp_isqrt.v` — 16 cycles

Inverse square root `1/√x` using the classic fast inverse square root algorithm:

1. Magic number initialisation (bit manipulation on the FP representation, combinational).
2. One iteration of Newton-Raphson: `y₁ = y₀ × (1.5 − 0.5×x×y₀²)`.

This requires 3 multiplies and 1 subtract, each 4 cycles deep. Total: 16 cycles.

The magic number used is the same as the Quake III Arena constant (Carmack's trick), adapted for our 27-bit format.

### `fp_length.v` — 32 cycles

`√(x² + y² + z²)` built from primitives:

```
x² = fp_mul(x, x)       — 4 cycles
y² = fp_mul(y, y)       — 4 cycles
z² = fp_mul(z, z)       — 4 cycles
x²+y² = fp_add          — 4 cycles
sum = fp_add(x²+y², z²) — 4 cycles
isqrt = fp_isqrt(sum)   — 16 cycles  (starts after first add finishes)
out = fp_mul(sum, isqrt)— 4 cycles
──────────────────────────────────────
Total: 32 cycles         (pipelined, not sequential)
```

Note: the comment in the source says 22 cycles — that's wrong. Actual is 32. This matters when setting `SCENE_CORE_LAT` for the Mandelbox (which contains two `fp_length` calls).

### `fp_normalize.sv` — 36 cycles

Divides a vec3 by its length: `fp_length` (32) + 3×`fp_mul` (4) in parallel = 36 cycles.

### `fp_abs.v` — combinational

Clears bit 26 (the sign bit). Zero cost in timing.

### `fp_max.v` / `fp_min.v` — combinational

26-bit unsigned comparison of the non-sign bits (since both positive and negative FP27 values sort correctly when the sign is handled first), then a mux. No pipeline delay.

### `fp_negate.v` — combinational

Flips bit 26. Used to implement subtraction without a dedicated subtracter.

### `fp_mod2.v` — pipelined

`a mod 2`: used by `repeat_mod_cell` to fold coordinates into a repeating cell.

### `fp_mul_vec3_mat33.sv` — pipelined

Multiplies a 3-vector by a 3×3 matrix. Instantiates 9 `fp_mul` and 6 `fp_add`. Used in `ray_gen` for the lookat transform.

### `int2fp.v` — combinational

Converts an integer pixel coordinate (up to 16 bits) to FP27. Finds the leading 1 to determine the exponent, shifts the remaining bits into the mantissa. Used in `ray_gen`.

### `fp_div.sv`, `fp_floor.sv`, `fp_mod.sv`, `fp_inverse.sv`, `fp_to_q4_12.sv`, `q4_12_to_fp.sv`

Additional utilities. `fp_to_q4_12` / `q4_12_to_fp` are used by the neural SDF path to convert between FP27 and Q4.12 fixed-point at the BRAM boundary.

---

## Using `state_pipe`

Every time a signal needs to be delayed by N cycles to stay aligned with a pipelined result, use:

```verilog
state_pipe #(.WIDTH(27), .DEPTH(N)) inst_name (
    .clk(clk), .in(signal), .out(delayed_signal)
);
```

Vivado infers SRL32 LUTs (shift-register LUTs) for depths ≤ 32, and chains them for larger depths. Do not replace with explicit flip-flop chains — the SRL inference is more efficient and packs better.

`state_pipe_unpacked_array.sv` handles arrays of signals (e.g. `logic [26:0] arr[0:2]`).

---

## Useful constant encodings

| Value | Binary | Hex |
|-------|--------|-----|
| 0.0 | `0 00000000 000000000000000000` | `27'h0` |
| 1.0 | `0 01111111 000000000000000000` | `27'h1FC0000` |
| 1.5 | `0 01111111 100000000000000000` | `27'h1FE0000` |
| 2.0 | `0 10000000 000000000000000000` | `27'h2000000` |
| 0.5 | `0 01111110 000000000000000000` | `27'h1F80000` |
| −1.0 | `1 01111111 000000000000000000` | `27'h3FC0000` |
