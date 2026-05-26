import { sdfShaderSource } from "./sdf_shader.js";
import { shadingShaderSource } from "./shading_shader.js";

/* ============================================================================
   Vertex shader source
   ============================================================================ */

/*
The vertex shader is tiny because this renderer does not send a real 3D mesh to
the GPU.

It only sends one fullscreen triangle.

The vertex shader therefore has two jobs:

1. place that triangle in clip space
2. generate a simple 0..1 screen-relative coordinate called `vUv`

`vUv` is not used for the actual camera ray.
It is just a convenient screen-relative coordinate for image-wide effects such
as the vignette at the end of the fragment shader.
*/
export const vertexShaderSource = `#version 300 es
precision highp float;

in vec2 aPosition;
out vec2 vUv;

void main() {
    /*
    aPosition arrives in clip-space-like coordinates in the range used by the
    oversized fullscreen triangle.

    Multiplying by 0.5 and then adding 0.5 remaps:

    -1 -> 0
     0 -> 0.5
     1 -> 1

    That gives a screen-style coordinate where:

    - bottom-left is about (0, 0)
    - centre is about (0.5, 0.5)
    - top-right is about (1, 1)

    Even though the triangle is oversized, interpolation over the visible part
    still produces the correct smooth UV gradient after clipping.
    */
    vUv = aPosition * 0.5 + 0.5;

    /*
    Turn the incoming 2D position into a full clip-space vec4.

    - x and y come from the buffer
    - z is set to 0 because this triangle sits on the clip-space mid-plane
    - w is set to 1, which is the normal choice for ordinary positions
    */
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

/* ============================================================================
   Fragment shader source
   ============================================================================ */

/*
This shader does the real rendering work.

It is built by combining:

- the main frame/ray-march shell in this file
- the scene distance functions from `sdf_shader.js`
- the shading helpers from `shading_shader.js`

`${...}` is JavaScript template-literal interpolation.
It means the other GLSL source strings are pasted into this one before WebGL
ever compiles it.
*/
export const fragmentShaderSource = `#version 300 es
precision highp float;

in vec2 vUv;
out vec4 fragColor;

uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uCamPos;
uniform mat3 uCamRot;
uniform float uFov;
uniform int uIterations;
uniform float uScale;
uniform float uMinRadius;
uniform float uFixedRadius;
uniform float uFoldLimit;
uniform float uSurfaceEpsilon;
uniform float uMaxDistance;
uniform int uMaxSteps;
uniform int uRenderMode;

#define MAX_ITER 30
#define MAX_STEPS 240

${sdfShaderSource}
${shadingShaderSource}

void main() {
    /*
    Build a camera ray for this exact pixel.

    Why use gl_FragCoord here instead of vUv:

    - gl_FragCoord is the real pixel coordinate in the drawing buffer
    - vUv is a convenient 0..1 interpolated screen coordinate

    For ray construction we care about the real pixel position, because the ray
    must match the actual rendered resolution exactly.

    The formula:

        (gl_FragCoord.xy * 2.0 - uResolution.xy) / uResolution.y

    does three things:

    1. gl_FragCoord.xy * 2.0 - uResolution.xy
       recentres the screen so the middle becomes (0, 0)

    2. dividing by uResolution.y
       expresses both axes in "screen heights"

    3. because both axes use screen height as the unit, vertical FOV remains
       the master scale and horizontal width automatically expands by aspect ratio

    Example with a 1920 x 1080 buffer:

    - centre pixel gives roughly uv = (0, 0)
    - top edge gives roughly uv.y = +1
    - bottom edge gives roughly uv.y = -1
    - left and right become about -1.777... and +1.777...

    That 1.777... is just the aspect ratio 1920 / 1080.
    */
    vec2 uv = (gl_FragCoord.xy * 2.0 - uResolution.xy) / uResolution.y;

    /*
    Convert vertical field of view in degrees into image-plane scale.

    Imagine a right triangle from:

    - the camera eye
    - the centre of the image plane
    - the top edge of the image plane

    If the image plane is placed one unit in front of the camera, then:

        tan(fov / 2) = half_image_plane_height / 1

    so:

        half_image_plane_height = tan(fov / 2)

    That is exactly the scale we need for the camera-space X and Y coordinates.
    */
    float fovScale = tan(radians(uFov) * 0.5);

    /*
    Build the ray in camera space.

    vec3(uv * fovScale, -1.0) means:

    - x = horizontal offset on the image plane
    - y = vertical offset on the image plane
    - z = -1 means the image plane is one unit forward in camera space

    The exact distance 1 is a convenient convention, not a physical law.
    Perspective comes from the ratio between x/y and z, so any fixed forward
    distance would work after corresponding scaling.

    uCamRot then rotates that local camera-space ray into world space.

    Because uCamRot stores the camera basis columns, this multiplication is
    equivalent to:

        ray.x * right + ray.y * up + ray.z * backward

    The result is then normalized so the ray direction has length 1.
    That matters because the renderer wants t to measure distance in world
    units along the ray.
    */
    vec3 rd = normalize(uCamRot * vec3(uv * fovScale, -1.0));

    /*
    ro is the ray origin.
    It starts at the camera position.
    */
    vec3 ro = uCamPos;

    /*
    t is how far we have marched along the ray.
    Starting at 0 means "we are still at the camera".
    */
    float t = 0.0;

    /*
    hit is an integer flag used like a boolean:

    - 0 = miss so far
    - 1 = surface reached
    */
    int hit = 0;

    /*
    Record how many steps the march needed for this pixel.
    That number is later reused for subtle colouring.
    */
    int stepsTaken = 0;

    /*
    March along the ray.

    Each loop:

    1. evaluates the scene at the current point
    2. asks "about how far are we from the nearest surface?"
    3. moves forward by most of that amount

    Why there are both compile-time and runtime limits:

    GLSL needs a fixed loop upper bound that the compiler can see.
    The uniforms then let the app choose smaller limits at runtime.
    */
    for (int i = 0; i < MAX_STEPS; i++) {
        if (i >= uMaxSteps) break;

        vec3 p = ro + rd * t;
        float d = mapScene(p);
        stepsTaken = i;

        /*
        Why the hit test is d < uSurfaceEpsilon:

        - exact SDF scenes may go negative if the point is inside
        - the Mandelbox estimator is mainly used as a positive distance-like value

        In both cases, "small enough or inside enough" should count as a hit.
        So a one-sided threshold is enough here.
        */
        if (d < uSurfaceEpsilon) {
            hit = 1;
            break;
        }

        /*
        Why march by d * 0.85 instead of the full d:

        For perfect signed distance fields, stepping by exactly d is often
        safe.
        The Mandelbox value is only an estimate, not a guaranteed exact SDF.
        Using a safety factor of 0.85 makes the march more conservative and
        reduces the chance of stepping through thin or high-curvature detail.

        Why force a tiny minimum step:

        Near difficult surfaces the estimate can become extremely small.
        Without a minimum step, the march could stall and make almost no forward
        progress.
        */
        t += max(d * 0.85, 0.0008);

        if (t > uMaxDistance) break;
    }

    vec3 col;
    if (hit == 1) {
        /*
        ro + rd * t is the current best surface point.
        There is no extra refinement pass here because the goal is a responsive
        interactive renderer rather than a perfectly converged offline solve.
        */
        col = shade(ro, rd, ro + rd * t, t, stepsTaken);
    } else {
        col = background(rd);
    }

    /*
    Apply a vignette using the simple screen-relative vUv coordinate.

    This is one place where vUv is more convenient than gl_FragCoord,
    because we only want a visual "how far from screen centre?" effect.
    */
    vec2 q = vUv - 0.5;
    col *= 1.0 - 0.38 * dot(q, q);

    /*
    Apply simple gamma correction.

    0.4545 is approximately 1 / 2.2.
    This brightens mid-tones so the final image looks more correct on ordinary
    displays whose response is not linear.
    */
    col = pow(max(col, 0.0), vec3(0.4545));

    fragColor = vec4(col, 1.0);
}
`;
