import { fragmentShaderSource, vertexShaderSource } from "./shaders.js";

/* ============================================================================
   Static shader and geometry metadata
   ============================================================================ */

/*
This array lists every uniform that JavaScript writes each frame.

A uniform is a read-only shader input whose value stays constant for the whole
draw call.

Examples in this project:

- camera position
- camera rotation
- field of view
- Mandelbox tuning values
- canvas resolution
*/
const UNIFORM_NAMES = [
    "uResolution",
    "uTime",
    "uCamPos",
    "uCamRot",
    "uFov",
    "uIterations",
    "uScale",
    "uMinRadius",
    "uFixedRadius",
    "uFoldLimit",
    "uSurfaceEpsilon",
    "uMaxDistance",
    "uMaxSteps",
    "uRenderMode",
];

/*
One oversized triangle is enough to cover the entire screen.

The three 2D vertices are:

- `(-1, -1)`
    bottom-left corner of clip space
- `( 3, -1)`
    far to the right
- `(-1,  3)`
    far above

Why this strange triangle works:

Clip space is the coordinate system used by the GPU right before rasterization.
Anything inside the square from `-1` to `1` in X and Y is potentially visible.
Anything outside is clipped away.

This one large triangle covers the whole visible square and then some.
The GPU clips off the excess.
The remaining visible part still fills the screen completely.

Why use one triangle instead of two:

- fewer vertices
- no diagonal seam where two triangles meet
- very common trick for fullscreen post-processing and ray marching
*/
const FULLSCREEN_TRIANGLE_VERTICES = new Float32Array([
    -1, -1,
    3, -1,
    -1, 3,
]);

/* ============================================================================
   Shader and programme creation
   ============================================================================ */

/*
Compile one shader from GLSL source code.

`type` tells WebGL whether this is a vertex shader or a fragment shader.
The result is a GPU object, not a JavaScript function.
*/
function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    if (!shader) throw new Error("Could not create shader");

    gl.shaderSource(shader, source);
    gl.compileShader(shader);

    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        const info = gl.getShaderInfoLog(shader) || "Unknown shader error";
        gl.deleteShader(shader);
        throw new Error(info);
    }

    return shader;
}

/*
Link the compiled vertex and fragment shaders into one executable GPU programme.

The British spelling `programme` is our own variable name.
The WebGL API methods still use their built-in American spelling such as
`createProgram`.

Why deleting the individual shader objects afterwards is safe:

Once linking succeeds, the linked programme keeps the executable GPU code it
needs internally.
The standalone shader objects are no longer needed as separate resources.
*/
export function createProgramme(gl) {
    const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertexShaderSource);
    const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource);

    const programme = gl.createProgram();
    if (!programme) throw new Error("Could not create WebGL programme");

    gl.attachShader(programme, vertexShader);
    gl.attachShader(programme, fragmentShader);
    gl.linkProgram(programme);

    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);

    if (!gl.getProgramParameter(programme, gl.LINK_STATUS)) {
        const info = gl.getProgramInfoLog(programme) || "Unknown programme link error";
        gl.deleteProgram(programme);
        throw new Error(info);
    }

    return programme;
}

/* ============================================================================
   Geometry and uniform lookup helpers
   ============================================================================ */

/*
Create the GPU objects needed to draw the fullscreen triangle.

Important WebGL objects here:

- buffer
    raw vertex number storage
- vertex attribute
    tells the GPU how to interpret those numbers
- VAO
    remembers that whole vertex-input setup

How `vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0)` should be
read:

- `2`
    each vertex supplies 2 numbers
- `gl.FLOAT`
    each number is a 32-bit float
- `false`
    do not normalise the numbers
- `0`
    tightly packed, no extra bytes between vertices
- `0`
    start at the beginning of the buffer

So the flat list:

    [-1, -1, 3, -1, -1, 3]

is interpreted as three `(x, y)` pairs:

    (-1, -1)
    ( 3, -1)
    (-1,  3)

The vertex shader then supplies `z` and `w` itself when it writes:

    gl_Position = vec4(aPosition, 0.0, 1.0);

That is why the buffer only needs `x` and `y`.
*/
export function createFullscreenTriangle(gl, programme) {
    const vao = gl.createVertexArray();
    const buffer = gl.createBuffer();

    if (!vao || !buffer) {
        throw new Error("Could not create fullscreen triangle resources");
    }

    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, FULLSCREEN_TRIANGLE_VERTICES, gl.STATIC_DRAW);

    const positionLocation = gl.getAttribLocation(programme, "aPosition");

    /*
    `-1` would mean the attribute could not be found, which would be a real
    setup error for this renderer.
    */
    if (positionLocation < 0) {
        throw new Error("Shader attribute aPosition was not found");
    }

    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    return { vao, buffer };
}

/*
Resolve every uniform location once up front.

`gl.getUniformLocation(...)` asks the linked programme:

"Where should JavaScript write the value for this named uniform?"

The returned value is later passed into calls like `gl.uniform1f(...)`.

`Object.fromEntries(...)` turns an array like:

    [["uTime", locationA], ["uResolution", locationB]]

into an object like:

    { uTime: locationA, uResolution: locationB }

That makes the later code much easier to read.
*/
export function getUniformLocations(gl, programme) {
    return Object.fromEntries(
        UNIFORM_NAMES.map((name) => [name, gl.getUniformLocation(programme, name)]),
    );
}
