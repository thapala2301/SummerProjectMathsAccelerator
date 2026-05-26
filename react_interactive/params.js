/* ============================================================================
   Render mode constants
   ============================================================================ */

/*
These numbers are the scene IDs sent to the shader.

They are not special by themselves.
They simply let JavaScript and GLSL agree on which scene should be rendered:

- `0`
    Mandelbox
- `1`
    Sphere test scene
- `2`
    Cube test scene

Using named constants is clearer than scattering raw `0`, `1`, and `2`
throughout the codebase.
*/
export const RENDER_MODES = {
    MANDELBOX: 0,
    SPHERE: 1,
    CUBE: 2,
};

/* ============================================================================
   Default parameter values
   ============================================================================ */

/*
These are tuning defaults, not mathematically sacred values.

They were chosen to make the Mandelbox open in a useful, detailed state rather
than a blank or uninteresting one.

Parameter meanings:

- `iterations`
    how many fold-and-scale rounds the Mandelbox runs
- `scale`
    the main Mandelbox scale factor
- `minRadius`
    inner sphere-fold safety radius
- `fixedRadius`
    outer sphere-fold inversion radius
- `foldLimit`
    half-size of the box used by the box fold
- `epsilon`
    how close a marched point must be to count as "hit the surface"
- `maxDistance`
    how far a ray is allowed to travel before we treat it as a miss
- `maxSteps`
    maximum number of ray-march steps per pixel
- `fov`
    vertical field of view in degrees
- `renderMode`
    which scene function `mapScene(...)` should use

Which values matter in each mode:

- Mandelbox uses all of them
- Sphere and cube mainly care about `epsilon`, `maxDistance`, `maxSteps`, `fov`
  and `renderMode`
- The Mandelbox-specific fold parameters are still uploaded in all modes, but
  the sphere and cube distance functions ignore them

Why the default `scale` is negative:

A negative Mandelbox scale flips orientation each iteration as well as
rescaling. That often produces more visually interesting internal structure than
the nearby positive values used here.
*/
export const DEFAULT_RENDER_PARAMS = {
    iterations: 13,
    scale: -1.78,
    minRadius: 0.5,
    fixedRadius: 1.0,
    foldLimit: 1.0,
    epsilon: 0.0015,
    maxDistance: 80,
    maxSteps: 160,
    fov: 60,
    renderMode: RENDER_MODES.MANDELBOX,
};

/* ============================================================================
   UI metadata
   ============================================================================ */

/*
The controls UI builds its mode buttons from this array.
Each object keeps the human label and the numeric mode value together.
*/
export const RENDER_MODE_OPTIONS = [
    { label: "Mandelbox", value: RENDER_MODES.MANDELBOX },
    { label: "Sphere", value: RENDER_MODES.SPHERE },
    { label: "Cube", value: RENDER_MODES.CUBE },
];

/* ============================================================================
   Display helpers
   ============================================================================ */

/* Convert the numeric mode into the text shown in the overlay */
export function getModeLabel(renderMode) {
    if (renderMode === RENDER_MODES.SPHERE) return "Sphere test";
    if (renderMode === RENDER_MODES.CUBE) return "Cube test";
    return "Mandelbox";
}
