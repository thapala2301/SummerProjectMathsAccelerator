/* ============================================================================
   Default camera values
   ============================================================================ */

/*
These defaults are not mathematically special.

They are simply a comfortable starting pose for looking at the scene:

- X is the left/right axis
- Y is the up/down axis
- Z is the forward/back axis

This project treats negative Z as "forward".
That means:

- larger positive Z values are farther behind the scene
- smaller or negative Z values move you toward and then through the scene

The default position `[0, 0.15, 4.5]` therefore means:

- `0` on X
    start centred left-to-right
- `0.15` on Y
    start slightly above the exact middle so the horizon and floor feel nicer
- `4.5` on Z
    start a few world units back from the origin so the fractal is in front of you

The units here are just "scene units".
There is no built-in real-world scale like metres.
*/
const DEFAULT_CAMERA_POSITION = [0, 0.15, 4.5];

/*
`speed` is measured in scene units per second.

So a speed of `4.5` means:

"If one second passes and no sprint or slow modifier is active, move 4.5 scene
units in the chosen direction."
*/
const DEFAULT_CAMERA_SPEED = 4.5;

/* ============================================================================
   Shared scalar helpers
   ============================================================================ */

/*
Keep a number inside a chosen range.

The inner `Math.min(max, value)` says:

"If value is larger than max, replace it with max."

That gives us a number which is guaranteed not to be above the upper limit.

Then the outer `Math.max(min, ...)` says:

"If that result is smaller than min, replace it with min."

That gives us a final number which is guaranteed to be:

- no smaller than `min`
- no larger than `max`

Example with `clamp(12, 0, 10)`:

1. `Math.min(10, 12)` becomes `10`
2. `Math.max(0, 10)` stays `10`

Example with `clamp(-3, 0, 10)`:

1. `Math.min(10, -3)` becomes `-3`
2. `Math.max(0, -3)` becomes `0`
*/
export function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

/*
Return a fresh copy of the default position array.

Arrays are mutable in JavaScript.
If several parts of the app shared the exact same array object, changing one of
them would silently change all of them.

`[...DEFAULT_CAMERA_POSITION]` is spread syntax.
It means:

"Take each item from the source array and place it into a new array."
*/
function createDefaultPosition() {
    return [...DEFAULT_CAMERA_POSITION];
}

/* ============================================================================
   Camera basis maths
   ============================================================================ */

/*
Convert yaw and pitch into a 3x3 basis matrix that turns camera-space rays into
world-space rays.

Before the maths, the most important idea is this:

The fragment shader first invents a ray in camera space.
Camera space is a tiny local coordinate system attached to the camera itself.
In that local system:

- +X means "to the right on the image plane"
- +Y means "up on the image plane"
- -Z means "straight forward out of the camera"

That local ray is convenient to build, but it does not yet know where the
camera is pointing in the world.

This function builds three direction vectors that describe the camera's local
axes in world space:

- `right`
- `up`
- `forward`

Those three perpendicular directions form a basis.
A 3x3 rotation matrix is just those basis directions packed into a grid of
9 numbers so the shader can transform local camera directions into world-space
directions.

Angles in this file are stored in radians.

Useful reference values:

- `0` radians = `0` degrees
- `Math.PI / 2` radians = `90` degrees
- `Math.PI` radians = `180` degrees

`yaw` means turning left and right around the world Y axis.
`pitch` means looking up and down.
There is no roll in this viewer, so the horizon stays level.

Why the forward formula looks like spherical coordinates:

1. Start with a unit-length forward vector
2. The vertical part comes from pitch:
   `y = sin(pitch)`
3. Whatever length is left for the horizontal XZ shadow is:
   `cos(pitch)`
4. Yaw rotates that horizontal shadow around the Y axis:
   `x = sin(yaw) * cos(pitch)`
   `z = -cos(yaw) * cos(pitch)`

The negative Z matters because this renderer defines camera-forward as negative
Z, which is the same convention used when the shader later builds rays like
`vec3(x, y, -1)`.

Worked examples:

Example 1: `yaw = 0`, `pitch = 0`

- `sin(0) = 0`
- `cos(0) = 1`
- `forward = [0, 0, -1]`

So the camera looks straight down world-space negative Z.

Example 2: `yaw = PI / 2`, `pitch = 0`

- `sin(PI / 2) = 1`
- `cos(PI / 2) = 0`
- `forward = [1, 0, 0]`

So the camera now looks to positive X, which is "to the right".

Example 3: `pitch = PI / 2`

- `cos(PI / 2) = 0`
- horizontal XZ shadow disappears
- `forward = [0, 1, 0]`

So the camera looks straight up.

Why `right` ignores pitch:

`right` is the sideways direction of a level camera with no roll.
Keeping it tied only to yaw means the viewer keeps a stable horizon.
If `right` also tilted with pitch, "sideways" movement and the derived `up`
axis would feel less like a standard fly camera.

Why the cross product gives `up`:

If two unit vectors are perpendicular, their cross product gives a third vector
perpendicular to both.
That is exactly what we need for the camera basis.

The order matters:

- `right x forward` gives the upward direction for this right-handed convention
- `forward x right` would point the opposite way and flip the basis

Why the matrix stores `[right, up, -forward]`:

The shader multiplies this matrix by camera-space rays whose forward direction
is `-Z`.
That means the local vector `[0, 0, -1]` should come out as the camera's world
forward direction.

If we store the third basis column as `-forward`, then:

`uCamRot * vec3(0, 0, -1)` becomes `forward`

because the `-1` picks the third column and flips its sign back again.

Worked basis example for `yaw = 0`, `pitch = 0`:

- `forward = [0, 0, -1]`
- `right = [1, 0, 0]`
- `up = [0, 1, 0]`
- stored third column = `-forward = [0, 0, 1]`

So the packed matrix is:

    [1, 0, 0]
    [0, 1, 0]
    [0, 0, 1]

That is the identity basis.
In that default view, camera space and world space line up, so the centre ray
`[0, 0, -1]` already points the correct way without any extra rotation.

The returned `Float32Array` is just a flat list of 9 numbers with 32-bit float
storage, because that is the format WebGL expects for matrix uploads.
*/
export function getCameraMatrix(yaw, pitch) {
    const cy = Math.cos(yaw);
    const sy = Math.sin(yaw);
    const cp = Math.cos(pitch);
    const sp = Math.sin(pitch);

    const forward = [sy * cp, sp, -cy * cp];
    const right = [cy, 0, sy];

    const up = [
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0],
    ];

    return new Float32Array([
        right[0], right[1], right[2],
        up[0], up[1], up[2],
        -forward[0], -forward[1], -forward[2],
    ]);
}

/* ============================================================================
   State factory helpers
   ============================================================================ */

/*
Build the mutable camera/runtime state object.

This object is mutated every frame by the render loop, so it deliberately lives
outside normal React state.

Important units:

- `position`
    scene units
- `yaw`, `pitch`
    radians
- `speed`
    scene units per second
- `lastTime`
    milliseconds from `performance.now()`
- `frameTimeMs`
    milliseconds
- `fps`
    frames per second
*/
export function createCameraState() {
    return {
        position: createDefaultPosition(),
        yaw: 0,
        pitch: 0,
        speed: DEFAULT_CAMERA_SPEED,
        lastTime: performance.now(),
        frameTimeMs: 0,
        fps: 0,
    };
}

/*
Build the smaller debug snapshot copied into React state for the overlay.

The render loop mutates the full camera state every frame.
The overlay only needs a tiny readable subset of that information.
*/
export function createDebugState() {
    return {
        fps: 0,
        frameTimeMs: 0,
        position: createDefaultPosition(),
        yaw: 0,
        pitch: 0,
    };
}

/* Reset the pose without touching the timing data */
export function resetCameraState(state) {
    state.position = createDefaultPosition();
    state.yaw = 0;
    state.pitch = 0;
}

/* ============================================================================
   Per-frame movement update
   ============================================================================ */

/*
Update the camera position from the currently held keys.

The important design choice here is that movement is "level flight", not "move
exactly where the camera looks".

That means:

- W and S move along the ground plane
- A and D strafe along the ground plane
- Space and Shift move along the world up/down axis

Why pitch is ignored:

If pitch affected movement, looking upward and pressing W would make the camera
fly into the sky.
That can be useful in some editors, but this viewer chooses the more common
"walk/fly over the ground plane" behaviour.

So the movement forward vector is the camera's facing direction projected onto
the XZ ground plane:

- full view forward was `[sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)]`
- ground-plane forward simply removes the vertical part:
  `[sin(yaw), 0, -cos(yaw)]`

Worked examples:

If `yaw = 0`:

- movement forward = `[0, 0, -1]`
- pressing W decreases Z

If `yaw = PI / 2`:

- movement forward = `[1, 0, 0]`
- pressing W increases X

The world up direction is always `[0, 1, 0]`.
That means Y is permanently the vertical axis of the world.

Why movement is accumulated before being applied:

If W and D are held together, the intended direction is "forward-right" as one
combined vector.
Building one combined vector first makes it easy to normalize once and avoid
faster diagonal motion.

Why diagonal motion becomes too fast without normalization:

Pressing only W gives a movement vector length of `1`.
Pressing W and D together gives `[1, 0, -1]`, whose length is `sqrt(2)`.
That is about `1.414`, so diagonal movement would be about 41% faster if we
applied it directly.

Dividing by the vector length keeps the direction but makes the length exactly
`1`.

Why the final motion is:

    normalized_direction * speed * dt

- `normalized_direction`
    which way to move
- `speed`
    how many scene units per second to move
- `dt`
    how many seconds passed this frame

So the product has the correct unit:

    scene_units_per_second * seconds = scene_units

That final amount is then added onto position.
*/
export function advanceCameraState(state, keys, dt) {
    const cy = Math.cos(state.yaw);
    const sy = Math.sin(state.yaw);

    const forward = [sy, 0, -cy];
    const right = [cy, 0, sy];
    const up = [0, 1, 0];

    const sprint = keys.ControlLeft || keys.ControlRight;
    const slow = keys.AltLeft || keys.AltRight;
    const speed = state.speed * (sprint ? 2.6 : slow ? 0.25 : 1.0);

    const move = [0, 0, 0];

    const addScaled = (vector, scale) => {
        move[0] += vector[0] * scale;
        move[1] += vector[1] * scale;
        move[2] += vector[2] * scale;
    };

    if (keys.KeyW) addScaled(forward, 1);
    if (keys.KeyS) addScaled(forward, -1);
    if (keys.KeyD) addScaled(right, 1);
    if (keys.KeyA) addScaled(right, -1);
    if (keys.Space || keys.KeyE) addScaled(up, 1);
    if (keys.ShiftLeft || keys.ShiftRight || keys.KeyQ || keys.KeyC) addScaled(up, -1);

    /*
    `Math.hypot(x, y, z)` returns `sqrt(x*x + y*y + z*z)`.
    That is the ordinary Euclidean length of the vector.
    */
    const len = Math.hypot(move[0], move[1], move[2]);

    /*
    The tiny threshold avoids dividing by a value that is effectively zero
    because of floating-point noise or canceling key presses.
    */
    if (len <= 0.0001) return;

    state.position[0] += (move[0] / len) * speed * dt;
    state.position[1] += (move[1] / len) * speed * dt;
    state.position[2] += (move[2] / len) * speed * dt;
}
