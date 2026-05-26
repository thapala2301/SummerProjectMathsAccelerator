# React Interactive Learning Guide

This guide is deliberately focused on the core rendering path.

It does **not** spend much time on build tooling, package metadata or editor
settings. Those files matter operationally, but they do not explain how the
viewer actually produces pixels.

The files that matter most are:

1. `renderer.jsx`
2. `params.js`
3. `camera.js`
4. `use_renderer.js`
5. `webgl.js`
6. `shaders.js`
7. `sdf_shader.js`
8. `shading_shader.js`

## Very brief notes on the non-core files

- `index.html`
    Creates the page and the root element React mounts into.
- `main.jsx`
    Starts React and renders the main viewer component.
- `styles.css`
    Tailwind import and a few global page styles.
- `package.json`
    Lists dependencies and npm scripts.
- `vite.config.mjs`
    Vite configuration.
- `postcss.config.mjs`
    PostCSS and Tailwind configuration.
- `.editorconfig`
    Default indentation and newline rules.
- `README.md`
    Short project overview and run instructions.

Those files help the app exist.
The files below explain how the app works.

## The whole rendering story in one pass

This is the full chain from source code to image:

1. React renders the UI in `renderer.jsx`
2. The UI creates a `<canvas>` plus sliders, buttons and input handlers
3. React stores the current render parameters
4. The custom hook in `use_renderer.js` starts the WebGL runtime
5. `webgl.js` compiles the shaders and prepares one fullscreen triangle
6. Every animation frame:
    - the camera state is updated from held keys
    - the canvas drawing buffer is resized if needed
    - JavaScript uploads camera values and slider values as uniforms
    - WebGL draws the single fullscreen triangle
7. The vertex shader runs for the triangle's 3 vertices
8. The rasterizer turns that triangle into screen pixels
9. The fragment shader runs once for each covered pixel
10. The fragment shader creates a ray for that pixel, ray-marches the scene,
    shades the result and writes a final colour

The most important mental shift is this:

The scene is **not** a triangle mesh.
The only geometric primitive sent to the GPU is one fullscreen triangle.
The apparent 3D world is invented per pixel by shader maths.

## `renderer.jsx`

This file is the UI shell and input controller.

It is responsible for:

- creating the canvas
- storing the slider values in React state
- remembering which keys are pressed
- reading mouse movement and turning it into yaw/pitch changes
- showing overlays like FPS and position
- calling `useRendererRuntime(...)`

This file is **not** where the rendering maths happens.

Think of it as the control room:

- React state holds the current settings
- refs hold fast-changing mutable values
- the render hook consumes those refs and performs the GPU work

## `params.js`

This file defines:

- which scene modes exist
- what the default values are
- which labels the UI should display

Important parameter meanings:

- `iterations`
    how many Mandelbox fold-and-scale rounds happen
- `scale`
    the main Mandelbox scale factor
- `minRadius`
    inner sphere-fold safety radius
- `fixedRadius`
    outer sphere-fold inversion radius
- `foldLimit`
    half-size of the box used by the box fold
- `epsilon`
    how close a ray-march sample must be before we call it a hit
- `maxDistance`
    how far a ray may travel before we treat it as a miss
- `maxSteps`
    maximum number of ray-march iterations per pixel
- `fov`
    vertical field of view in degrees

The sphere and cube scenes do not use the Mandelbox fold parameters directly,
but they still use the general march controls like `epsilon`, `maxSteps`,
`maxDistance` and `fov`.

## `camera.js`

This file is about camera maths and camera motion.

### World axes

This project uses:

- X = left and right
- Y = up and down
- Z = forward and backward

But the important convention is:

**negative Z is forward**

So:

- `forward` means moving toward smaller Z
- positive Z is behind the scene

That is why the default camera starts at a positive Z value like `4.5`: it
starts back from the origin and looks toward the scene.

### Yaw and pitch

`yaw` means turning left and right around the world Y axis.

`pitch` means looking up and down.

They are stored in **radians**, not degrees.

Useful values:

- `0` radians = 0 degrees
- `Math.PI / 2` radians = 90 degrees
- `Math.PI` radians = 180 degrees

### Where the forward vector formula comes from

The hardest line in the file is the forward direction:

```js
const forward = [sy * cp, sp, -cy * cp];
```

where:

- `sy = sin(yaw)`
- `cy = cos(yaw)`
- `sp = sin(pitch)`
- `cp = cos(pitch)`

This comes from splitting a unit-length forward direction into:

- a vertical part
- a horizontal shadow on the XZ plane

The vertical part is easy:

```text
y = sin(pitch)
```

Why?

Because if the camera pitches upward, more of the unit vector points into Y.

The remaining horizontal shadow length is:

```text
cos(pitch)
```

because a unit vector tilted upward by `pitch` leaves `cos(pitch)` of its length
projected onto the horizontal plane.

Then yaw rotates that horizontal shadow around Y:

```text
x = sin(yaw) * cos(pitch)
z = -cos(yaw) * cos(pitch)
```

The Z part is negative because this renderer defines forward as negative Z.

### Worked examples

If `yaw = 0` and `pitch = 0`:

- `sin(0) = 0`
- `cos(0) = 1`
- `forward = [0, 0, -1]`

So the camera looks straight down world-space negative Z.

If `yaw = PI / 2` and `pitch = 0`:

- `sin(PI / 2) = 1`
- `cos(PI / 2) = 0`
- `forward = [1, 0, 0]`

So the camera now looks along positive X.

If `pitch = PI / 2`:

- `cos(PI / 2) = 0`
- the X and Z parts disappear
- `forward = [0, 1, 0]`

So the camera looks straight up.

### Why `right` ignores pitch

The code builds:

```js
const right = [cy, 0, sy];
```

That means "camera-right" stays level with the ground.
This is a deliberate fly-camera choice.

If right also followed pitch, the horizon would feel less stable and sideways
motion would become harder to predict.

### Why the cross product creates `up`

The camera needs 3 perpendicular basis directions:

- right
- up
- forward

If you already know `right` and `forward`, then a cross product gives a vector
perpendicular to both.
That is exactly what `up` should be.

The order matters:

- `right x forward` gives the upward direction for this coordinate convention
- reversing the order would flip it

### Why the matrix stores `[right, up, -forward]`

The shader first builds rays in **camera space**.
In that local space, forward is defined as `-Z`.

So the centre ray starts as:

```text
[0, 0, -1]
```

The camera matrix must therefore satisfy:

```text
camera-space -Z -> world-space forward
```

That is why the third basis column is stored as `-forward`.

Then:

```text
uCamRot * [0, 0, -1] = forward
```

### Identity example

If `yaw = 0` and `pitch = 0`, the basis becomes:

- `right = [1, 0, 0]`
- `up = [0, 1, 0]`
- `-forward = [0, 0, 1]`

So the matrix is:

```text
[1, 0, 0]
[0, 1, 0]
[0, 0, 1]
```

That is the identity basis.
In the default view, camera space already lines up with world space.

### Movement maths

The movement code does **not** move exactly where the camera looks.
It uses a level-flight model:

- W and S move along the ground plane
- A and D strafe along the ground plane
- Space and Shift move along the world Y axis

That is why movement recomputes a flat forward vector using yaw only:

```js
const forward = [sy, 0, -cy];
```

It is just the earlier forward vector with the vertical part removed.

### Why normalization matters

If you press only W, the movement vector length is `1`.

If you press W and D together, the vector is roughly:

```text
[1, 0, -1]
```

Its length is:

```text
sqrt(1^2 + 1^2) = sqrt(2) ≈ 1.414
```

So without normalization, diagonal movement would be about 41% faster.

Dividing by the vector length keeps the direction but makes the length exactly
`1`.

Then the final move is:

```text
normalized_direction * speed * dt
```

Units:

- `speed`
    scene units per second
- `dt`
    seconds

So the product is a movement amount in scene units.

## `use_renderer.js`

This file owns the live rendering runtime.

### What the hook does

It:

- creates the WebGL context
- creates the shader programme
- creates the fullscreen triangle
- starts the animation loop
- updates uniforms every frame
- draws every frame
- cleans everything up when the component unmounts

### Why `dtSeconds` is clamped

`requestAnimationFrame` supplies a timestamp called `now`.

The code compares that with `state.lastTime` to get frame delta.
That delta is converted from milliseconds to seconds.

Large gaps are clamped to `0.05` seconds.

Why?

If the tab sleeps for 5 seconds and a movement key is held, using the full
5-second delta would fling the camera across the scene.

The clamp deliberately prefers control stability over literal wall-clock motion.

### CSS pixels versus drawing-buffer pixels

This file deals with 2 different notions of size:

- CSS pixels
    how large the canvas looks on the page
- drawing-buffer pixels
    how many actual pixels the GPU renders

The fragment shader must think in drawing-buffer pixels because `gl_FragCoord`
is a real rendered-pixel coordinate.

That is why `uResolution` uses:

```js
canvas.width
canvas.height
```

not the `getBoundingClientRect()` size directly.

### Why DPR is capped

Higher device pixel ratios make the image sharper, but they also multiply the
number of pixels the shader must ray-march.

For a shader-heavy renderer, that cost climbs quickly.
The cap at `2` is a practical compromise.

### Why `uTime` gets raw elapsed seconds

Camera movement uses clamped delta.
Shader time uses raw elapsed seconds:

```js
gl.uniform1f(uniforms.uTime, now / 1000);
```

That means:

- motion stays stable after pauses
- time-based shader effects, if added later, would still advance according to
  real elapsed time

At the moment `uTime` is declared but unused by the shader.

### What `drawArrays(gl.TRIANGLES, 0, 3)` really causes

This one call triggers the whole GPU pipeline:

1. vertex shader runs 3 times, once for each triangle vertex
2. rasterizer finds all covered pixels
3. fragment shader runs once for each covered pixel
4. each fragment writes a colour into the canvas colour buffer

There is no `gl.clear()` because the fullscreen triangle covers the whole image
and overwrites every visible pixel every frame.

## `webgl.js`

This file contains the low-level GPU setup.

### Why one oversized triangle covers the whole screen

The triangle vertices are:

```text
(-1, -1)
( 3, -1)
(-1,  3)
```

In clip space, the visible square is the range `[-1, 1]` on X and Y.

This triangle extends past that square.
The GPU clips away the off-screen parts.
The remaining visible part still covers the whole square.

This trick avoids using 2 triangles for a quad and avoids a seam where they meet.

### How the buffer becomes vertices

The flat array:

```text
[-1, -1, 3, -1, -1, 3]
```

is interpreted as 3 pairs because the code says:

```js
gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
```

The `2` means:

"each vertex consumes 2 floats"

So WebGL reads:

1. `(-1, -1)`
2. `( 3, -1)`
3. `(-1,  3)`

The vertex shader then adds `z = 0` and `w = 1` when it writes `gl_Position`.

### What uniforms are

Uniforms are named values that JavaScript sends to the shader and that remain
constant for the whole draw call.

Examples:

- camera position
- camera rotation matrix
- field of view
- Mandelbox parameters

## `shaders.js`

This file contains the main vertex shader and fragment shader shell.

### Why there are 2 screen coordinate systems

The fragment shader uses:

- `gl_FragCoord`
    real pixel coordinates in the drawing buffer
- `vUv`
    a simple 0..1 screen-relative coordinate

The ray uses `gl_FragCoord` because ray construction must match the actual pixel
grid and the actual drawing-buffer resolution.

The vignette uses `vUv` because it only needs a percentage-like "how far from
screen centre?" coordinate.

### Why the ray formula divides by `uResolution.y`

The code is:

```glsl
vec2 uv = (gl_FragCoord.xy * 2.0 - uResolution.xy) / uResolution.y;
```

This makes the screen height the master unit.
That means:

- vertical range is roughly `[-1, 1]`
- horizontal range naturally becomes `[-aspect, aspect]`

So the field of view being applied is a **vertical** FOV.

### Why `tan(fov / 2)` appears

Imagine the camera at the tip of a triangle, looking at an image plane placed
1 unit forward.

Half the image-plane height is:

```text
tan(fov / 2)
```

because:

```text
tan(angle) = opposite / adjacent
```

and the adjacent side was chosen to be `1`.

That is why the code uses:

```glsl
float fovScale = tan(radians(uFov) * 0.5);
```

### Why the camera-space ray is `vec3(uv * fovScale, -1.0)`

This means:

- X and Y are offsets on the image plane
- Z is `-1`, meaning "one unit forward in camera space"

The exact value `1` is just a convenient convention.
Perspective depends on the ratios, not on that one distance by itself.

### Why normalize after rotation

The ray direction should have length `1` so that travelling by `t` world units
really means:

```text
point = origin + direction * t
```

If the direction length were not 1, `t` would no longer mean true travel
distance.

### Ray marching

Each loop:

1. computes the current point
2. asks `mapScene(p)` how far the nearest surface seems to be
3. marches forward by most of that amount

The step uses:

```glsl
max(d * 0.85, 0.0008)
```

Why:

- `0.85`
    conservative safety factor because the Mandelbox value is only an estimator
- `0.0008`
    minimum step so the march cannot stall forever on tiny values

The hit test is:

```glsl
d < uSurfaceEpsilon
```

That works for both:

- exact SDFs, which may go negative inside the surface
- the Mandelbox estimator, which is mainly used as a positive distance-like value

## `sdf_shader.js`

This file defines the scene distance functions.

### Exact SDFs versus distance estimators

The sphere and cube functions are exact signed distance fields.
Their returned value has a precise meaning:

- positive outside
- zero on the surface
- negative inside

The Mandelbox function is different.
It is a **distance estimator**.

That means:

"This number behaves enough like a distance to guide ray marching, but it is not
a perfect exact signed distance everywhere."

That is why the march later uses a safety factor instead of trusting the value
completely.

### Box fold intuition

The box fold reflects coordinates that leave the cube bounds.

For one axis with fold limit `1`:

- `0.3` stays `0.3`
- `1.3` becomes `0.7`
- `-1.4` becomes `-0.6`

Doing that repeatedly on all 3 axes keeps folding space back toward a box.
That repeated reflection is a major source of the Mandelbox's hard-edged,
self-similar structure.

### Sphere fold intuition

The sphere fold has 2 regions:

- inner sphere:
    constant scale to avoid a singularity at the origin
- middle band:
    true sphere inversion
- outer region:
    unchanged

Why inversion uses `fixedR2 / r2` on the whole vector:

If the current radius is `r`, then inversion wants:

```text
newRadius = R^2 / r
```

Scaling the whole vector by `R^2 / r^2` gives:

```text
newLength = r * (R^2 / r^2) = R^2 / r
```

which is exactly the desired inverted radius.

### What `dr` is tracking

`dr` is a scalar record of how strongly the iteration stretches space.

It is not a full derivative matrix.
It is a practical magnitude estimate.

The main update:

```glsl
dr = dr * abs(uScale) + 1.0;
```

has 2 ideas:

- existing stretch gets multiplied by the new scale
- the `+ p` translation in `z = z * uScale + p` contributes one more direct
  copy of the original-point change

That is why there is a `+ 1.0`.

### Why `length(z) / abs(dr)` is distance-like

By the end of the loop:

- `length(z)` tells us how far the transformed point ended up from the centre
  in the warped Mandelbox iteration space
- `dr` tells us how much the iteration stretched distances

So:

```text
length(z) / abs(dr)
```

means:

"Take the transformed-space distance and divide by the amount of stretching so
the answer makes sense again in the original space."

That is the central intuition behind the Mandelbox estimator.

It is still an approximation, which is why the rest of the renderer treats it
carefully.

## `shading_shader.js`

This file answers:

"Once I have hit a surface point, how do I light it?"

### Normals from nearby distance samples

The normal is estimated by central differences.

For each axis, the code compares:

```text
distance just ahead of the point
distance just behind the point
```

That gives an approximate gradient.
For a distance field, the gradient points in the direction of fastest increase,
which is perpendicular to the surface.

That is why the gradient direction is used as the surface normal.

### Why dot products appear everywhere

The dot product of 2 unit vectors equals the cosine of the angle between them.

That makes it perfect for lighting:

- `1`
    vectors align completely
- `0`
    vectors are perpendicular
- negative
    vectors point away from each other

So diffuse light uses:

```glsl
max(dot(normal, lightDir), 0.0)
```

because a surface should be brightest when it faces the light and darkest when
the light skims across it.

### Why `halfDir = normalize(lightDir - rd)`

`rd` points from the camera to the surface.
So the view direction from the surface back to the camera is:

```text
-rd
```

The half-vector lies halfway between:

- the light direction
- the view direction

So:

```text
halfDir = normalize(lightDir + viewDir)
        = normalize(lightDir + (-rd))
        = normalize(lightDir - rd)
```

### Soft shadow intuition

The shadow ray marches toward the light.

If the nearest geometry distance `h` becomes small quickly compared with the
travelled distance `t`, then something is probably crowding the light path.

That is why the code uses a ratio based on `h / t` to darken the result.

The constants there are tuning values, not strict physical laws.

### Ambient occlusion intuition

This implementation is a cheap approximation.

It only samples along the normal direction.
The idea is:

"If I expected empty space for distance `h`, but I hit geometry sooner than
that, then this point is tucked into nearby surfaces and should receive less
ambient light."

### Fog intuition

Fog fades distant geometry into the same colour the ray would have seen if it
had missed the object completely.

That is why the shader mixes toward `background(rd)`.
It keeps the distance fade visually consistent with the sky and ground that are
already behind the object.

## One complete frame, step by step

Here is one pixel's life from start to finish:

1. React has already stored the latest camera angles and slider values
2. `use_renderer.js` uploads those values as uniforms
3. WebGL draws one fullscreen triangle
4. The vertex shader runs for the 3 triangle vertices
5. The rasterizer creates a fragment for the current pixel
6. The fragment shader reads `gl_FragCoord` and `uResolution`
7. It converts that pixel into a camera-space ray
8. It rotates the ray into world space with `uCamRot`
9. It marches forward along that ray using `mapScene(...)`
10. If it gets close enough, it shades the hit point
11. If it never hits, it uses the background colour
12. It applies vignette and gamma correction
13. It writes the final colour into the canvas

That is the whole renderer in one chain.

## The 3 ideas that matter most

If you only remember three things, remember these:

1. The app does not render a mesh. It renders one fullscreen triangle and lets
   each pixel solve its own ray-march problem.
2. `camera.js` builds a camera basis so a local camera-space ray can be rotated
   into world space.
3. `sdf_shader.js` and `shading_shader.js` are the real scene: one defines how
   far surfaces are, the other defines how those surfaces look.
