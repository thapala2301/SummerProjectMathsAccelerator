import { useEffect, useRef, useState } from "react";

import { advanceCameraState, getCameraMatrix } from "./camera.js";
import { createFullscreenTriangle, createProgramme, getUniformLocations } from "./webgl.js";

/* ============================================================================
   Runtime limits
   ============================================================================ */

/*
Clamp very large frame gaps so the camera does not jump across the world after
the tab was paused or the machine stalled for a while.

`0.05` seconds means "pretend no more than 50 ms passed for movement purposes".

Why clamping is useful:

If the tab sleeps for 5 seconds and we used the full delta for movement, then a
key held during that sleep could move the camera by:

    speed * 5 seconds

which would feel like a teleport.

This clamp does mean motion becomes deliberately less than real time during huge
frame spikes. That is a tradeoff in favour of control stability.
*/
const MAX_FRAME_DELTA_SECONDS = 0.05;

/*
Cap device pixel ratio so extremely dense screens do not request a huge drawing
buffer for a real-time ray marcher.

This is a quality/performance tradeoff:

- higher DPR
    sharper image
- lower DPR
    fewer pixels to ray march
*/
const MAX_DEVICE_PIXEL_RATIO = 2;

/* ============================================================================
   Context creation
   ============================================================================ */

/*
Create the WebGL2 context that draws into the canvas.

Why this renderer disables depth and stencil:

The app does not draw a stack of separate triangles with hidden-surface testing.
It draws one fullscreen triangle, then the fragment shader decides the colour of
every pixel by ray marching.

So:

- depth buffer is not needed
- stencil buffer is not needed
- antialiasing is disabled because every extra sample would make the ray march
  more expensive
*/
function createRendererContext(canvas) {
    const gl = canvas.getContext("webgl2", {
        antialias: false,
        depth: false,
        stencil: false,
        powerPreference: "high-performance",
    });

    if (!gl) {
        throw new Error("WebGL2 is not available in this browser.");
    }

    return gl;
}

/* ============================================================================
   Canvas sizing
   ============================================================================ */

/*
Match the canvas drawing buffer to the size the canvas appears on screen.

There are two coordinate systems here:

- CSS pixels
    how large the canvas looks in layout terms
- device pixels
    how many real pixels the GPU actually renders

The fragment shader must think in drawing-buffer pixels, because `gl_FragCoord`
is expressed in actual rendered pixel coordinates.
That is why `uResolution` later uses `canvas.width` and `canvas.height`, not the
CSS rectangle size.

Why `Math.floor(...)` is used:

It prevents fractional pixel sizes.
A drawing buffer must use integer pixel counts.
Using `floor` here is a simple stable choice.

Why resizing is checked every frame:

The check is cheap, and it means the renderer automatically reacts to:

- window resizes
- CSS layout changes
- browser zoom changes
- device-pixel-ratio changes

Writing `canvas.width` or `canvas.height` recreates the drawing buffer, so the
function avoids doing that unless the size actually changed.
*/
function resizeCanvasToDisplaySize(canvas) {
    const rect = canvas.getBoundingClientRect();

    const dpr = Math.min(window.devicePixelRatio || 1, MAX_DEVICE_PIXEL_RATIO);
    const width = Math.max(1, Math.floor(rect.width * dpr));
    const height = Math.max(1, Math.floor(rect.height * dpr));

    if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
    }
}

/* ============================================================================
   Uniform updates
   ============================================================================ */

/*
Copy the current JavaScript-side state into GLSL uniforms.

This is the bridge between:

- React / JavaScript data
and
- GPU shader execution

Important units and conventions:

- `uResolution`
    drawing-buffer pixel counts
- `uTime`
    seconds since the page time origin
- `uCamPos`
    scene units
- `uCamRot`
    camera-to-world 3x3 basis matrix
- `uFov`
    degrees
- `uIterations`, `uMaxSteps`
    integer counts

Why use a separate `uCamPos` and `uCamRot` instead of one 4x4 matrix:

The fragment shader is not transforming existing mesh vertices.
It is creating a new ray direction per pixel.
So it only needs:

- one point to start from
- one 3x3 rotation basis for direction vectors

That is simpler than a full 4x4 camera matrix in this particular renderer.

Why some values are rounded right before upload:

The UI sliders produce JavaScript numbers, which are all just `number`.
The shader, however, expects actual integer uniforms for loop counts and mode
selection.
*/
function applyRendererUniforms(gl, uniforms, canvas, now, state, params) {
    gl.uniform2f(uniforms.uResolution, canvas.width, canvas.height);
    gl.uniform1f(uniforms.uTime, now / 1000);
    gl.uniform3f(uniforms.uCamPos, state.position[0], state.position[1], state.position[2]);
    gl.uniformMatrix3fv(uniforms.uCamRot, false, getCameraMatrix(state.yaw, state.pitch));

    gl.uniform1f(uniforms.uFov, params.fov);
    gl.uniform1i(uniforms.uIterations, Math.round(params.iterations));
    gl.uniform1f(uniforms.uScale, params.scale);
    gl.uniform1f(uniforms.uMinRadius, params.minRadius);
    gl.uniform1f(uniforms.uFixedRadius, params.fixedRadius);
    gl.uniform1f(uniforms.uFoldLimit, params.foldLimit);
    gl.uniform1f(uniforms.uSurfaceEpsilon, params.epsilon);
    gl.uniform1f(uniforms.uMaxDistance, params.maxDistance);
    gl.uniform1i(uniforms.uMaxSteps, Math.round(params.maxSteps));
    gl.uniform1i(uniforms.uRenderMode, params.renderMode);
}

/* ============================================================================
   Debug metric updates
   ============================================================================ */

/*
Update the numbers shown in the overlay.

These values are intentionally smoothed.
That means they are easier to read, but they are not a perfect raw profiling
measurement of each individual frame.
*/
function updateFrameMetrics(state, dtSeconds) {
    const instantFrameMs = dtSeconds * 1000;

    state.frameTimeMs = state.frameTimeMs * 0.92 + instantFrameMs * 0.08;
    state.fps = 1000 / Math.max(state.frameTimeMs, 0.0001);
}

/* ============================================================================
   React runtime hook
   ============================================================================ */

/*
Own the GPU runtime for the viewer.

Why this is a hook:

React components are for declaring UI.
This file is about lifecycle-heavy side effects:

- creating a WebGL context
- allocating GPU resources
- starting an animation loop
- cleaning up when the component unmounts

`useEffect(...)` is the correct React tool for that kind of setup/cleanup work.
*/
export function useRendererRuntime({
    canvasRef,
    paramsRef,
    stateRef,
    keysRef,
}) {
    const animationFrameRef = useRef(null);
    const [error, setError] = useState(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return undefined;

        let gl = null;
        let programme = null;
        let vao = null;
        let buffer = null;
        let uniforms = null;

        try {
            setError(null);

            gl = createRendererContext(canvas);
            programme = createProgramme(gl);

            const fullscreenTriangle = createFullscreenTriangle(gl, programme);
            vao = fullscreenTriangle.vao;
            buffer = fullscreenTriangle.buffer;

            uniforms = getUniformLocations(gl, programme);

            /*
            `renderFrame(now)` is called by the browser once per animation frame.

            `now` is a high-resolution timestamp in milliseconds.
            It uses the same time base as `performance.now()`.

            That is why `state.lastTime`, which was created from
            `performance.now()`, is directly compatible with it.
            */
            const renderFrame = (now) => {
                if (!gl || !programme || !vao || !uniforms) return;

                const state = stateRef.current;

                /*
                Convert the elapsed time from milliseconds into seconds for
                movement maths.

                The shader still receives raw elapsed time in seconds through
                `uTime`.
                That means:

                - camera motion is clamped for control stability
                - time-driven shader animation, if added later, would still see
                  true elapsed wall-clock time
                */
                const dtSeconds = Math.min(
                    (now - state.lastTime) / 1000,
                    MAX_FRAME_DELTA_SECONDS,
                );
                state.lastTime = now;

                advanceCameraState(state, keysRef.current, dtSeconds);
                resizeCanvasToDisplaySize(canvas);

                gl.viewport(0, 0, canvas.width, canvas.height);

                /*
                These state calls are repeated each frame even though the objects
                usually stay the same.
                That is a simple, explicit way to ensure the right programme and
                VAO are active before drawing.
                */
                gl.useProgram(programme);
                gl.bindVertexArray(vao);

                applyRendererUniforms(gl, uniforms, canvas, now, state, paramsRef.current);

                /*
                Draw one triangle using vertices 0, 1 and 2.

                What happens after this call:

                1. the vertex shader runs once for each of the 3 vertices
                2. the rasterizer finds every covered screen pixel
                3. the fragment shader runs once for each covered pixel
                4. each fragment writes a final colour into the canvas colour buffer

                There is no `gl.clear(...)` because this one fullscreen triangle
                covers the whole image every frame, so every visible pixel gets
                overwritten anyway.
                */
                gl.drawArrays(gl.TRIANGLES, 0, 3);

                updateFrameMetrics(state, dtSeconds);
                animationFrameRef.current = requestAnimationFrame(renderFrame);
            };

            animationFrameRef.current = requestAnimationFrame(renderFrame);
        } catch (err) {
            setError(err instanceof Error ? err.message : String(err));
        }

        return () => {
            if (animationFrameRef.current !== null) {
                cancelAnimationFrame(animationFrameRef.current);
            }

            if (!gl) return;

            /*
            Deleting the resources tells WebGL they are no longer needed.
            The browser/GPU driver handles the exact timing safely behind the scenes.
            */
            if (buffer) gl.deleteBuffer(buffer);
            if (vao) gl.deleteVertexArray(vao);
            if (programme) gl.deleteProgram(programme);
        };
    }, [canvasRef, keysRef, paramsRef, stateRef]);

    return { error };
}
