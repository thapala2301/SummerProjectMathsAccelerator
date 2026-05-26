# Mandelbox CPU Benchmark Reference

This is a **compiled CPU benchmark/reference** version of the React/WebGL Mandelbox renderer.

It is intended for FPGA/RTL comparison, not interactive viewing.

It mirrors the shader pipeline:

```text
pixel → camera ray → mapScene/SDF → ray march loop
      → optional full shading → RGB/depth/steps stats
```

It supports:

- Mandelbox mode
- Sphere test mode
- Cube test mode
- Base benchmark mode: ray march only, simple RGB
- Full shader mode: finite-difference normals, soft shadows, AO, fog, specular, fresnel
- PPM output image
- text benchmark report via the legacy `--csv` flag
- deterministic camera/scene parameters

## Code layout

- `src/config.hpp`
    Shared runtime parameter types and mode enums.
- `src/vec3.hpp`
    Header-only vector math utilities.
- `src/sdf.hpp` / `src/sdf.cpp`
    Scene distance estimators and the scene dispatcher.
- `src/renderer.hpp` / `src/renderer.cpp`
    Camera basis construction, shading helpers, frame rendering and PPM output.
- `src/report.hpp` / `src/report.cpp`
    Whole-run summary generation and text report writing.
- `src/main.cpp`
    Command-line parsing and top-level benchmark flow.

## Build

```bash
make
```

## Run benchmark

Mandelbox, base comparison mode:

```bash
./cpu_raymarch --mode mandelbox --quality base --width 320 --height 180 --frames 3
```

Mandelbox, full shader visual mode:

```bash
./cpu_raymarch --mode mandelbox --quality full --width 320 --height 180 --frames 1 --out out.ppm
```

Sphere/cube tests:

```bash
./cpu_raymarch --mode sphere --quality base --width 320 --height 180 --frames 3
./cpu_raymarch --mode cube --quality base --width 320 --height 180 --frames 3
```

Save CSV:

```bash
./cpu_raymarch --mode mandelbox --quality base --csv benchmark.csv
```

Example report:

```text
run_1:
    mode: mandelbox
    quality: base
    avg_frame_ms: 70.435 ms

    frame_0:
        fps: 13.898 fps
```

The report includes run metadata, benchmark parameters, camera values,
multi-frame summary averages and per-frame timing and hit/step metrics.

## Why two quality modes?

For RTL comparison, use:

```text
--quality base
```

This measures the actual repeated ray-marching/SDF workload without the expensive visual extras.

The React shader also includes:
- normal estimation
- soft shadows
- ambient occlusion
- specular/fresnel
- fog/gamma/vignette

Those are implemented in:

```text
--quality full
```

but they are expensive and likely not the first RTL target.

## Important comparison rule

When comparing CPU vs RTL, match:

```text
width
height
max_steps
iterations
scale
min_radius
fixed_radius
fold_limit
epsilon
max_distance
camera position/yaw/pitch/FOV
mode
quality subset
```

For a fair early comparison, compare RTL against `--quality base`.

## Controls / Parameters

This is command-line only. Use `--help` for options.

Example:

```bash
./cpu_raymarch --help
```
