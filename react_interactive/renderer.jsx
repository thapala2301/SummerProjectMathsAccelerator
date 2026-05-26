import React, { useEffect, useRef, useState } from "react";

import { clamp, createCameraState, createDebugState, resetCameraState } from "./camera.js";
import ControlSlider from "./control_slider.jsx";
import { DEFAULT_RENDER_PARAMS, RENDER_MODE_OPTIONS, getModeLabel } from "./params.js";
import { useRendererRuntime } from "./use_renderer.js";

/* ============================================================================
   Input and UI constants
   ============================================================================ */

// React helper functions like useEffect, useRef and useState are named imports,
// so they appear inside { }. ControlSlider is a default export, so it is imported
// without braces. The same rule applies to RaymarchViewer in main.jsx

// These keys control the viewer itself
// Preventing the browser defaults stops the page from scrolling while flying the camera
const PREVENT_DEFAULT_KEYS = [
    "KeyW", "KeyA", "KeyS", "KeyD", "KeyQ", "KeyE",
    "Space", "ShiftLeft", "ShiftRight", "ControlLeft",
    "ControlRight", "AltLeft", "AltRight",
];

// Convert mouse movement in pixels into camera rotation in radians
const LOOK_SENSITIVITY = 0.0019;

// Decide how often React copies debug data out of the fast mutable render state
const DEBUG_REFRESH_INTERVAL_MS = 120;

// Describe every slider in one data list
// The controls panel maps over this list to build the UI
// Each item is an object. key is the property name in params, while label is the text shown to the user
const PARAMETER_CONTROLS = [
    { key: "iterations", label: "Iterations", min: 4, max: 24, step: 1 },
    { key: "scale", label: "Scale", min: -2.5, max: 2.5, step: 0.01 },
    { key: "minRadius", label: "Min radius", min: 0.05, max: 1.4, step: 0.01 },
    { key: "fixedRadius", label: "Fixed radius", min: 0.1, max: 2.2, step: 0.01 },
    { key: "foldLimit", label: "Fold limit", min: 0.2, max: 2.0, step: 0.01 },
    { key: "epsilon", label: "Surface epsilon", min: 0.0004, max: 0.006, step: 0.0001 },
    { key: "maxSteps", label: "Max steps", min: 60, max: 240, step: 1 },
    { key: "maxDistance", label: "Max distance", min: 15, max: 160, step: 1 },
    { key: "fov", label: "FOV", min: 35, max: 95, step: 1 },
];

/* ============================================================================
   Overlay components
   ============================================================================ */

// Show the short control instructions in the top-left overlay
function InstructionsOverlay() {
    return (
        <div className="pointer-events-none absolute left-4 top-4 max-w-md rounded-2xl bg-slate-950/55 p-4 shadow-2xl ring-1 ring-white/10 backdrop-blur-md">
            <div className="text-xs leading-5 text-slate-300">
                Hold click and drag to look around. Fly with <b>WASD</b>, rise/fall with <b>Space/Shift</b>, sprint with <b>Ctrl</b>, slow with <b>Alt</b>, reset camera with <b>R</b>. Use the mouse wheel to change base flight speed.
            </div>
        </div>
    );
}

// Show FPS, frame time and camera position in the bottom-left overlay
// Props are plain values copied out of the mutable runtime state
function StatsOverlay({ debug, modeLabel }) {
    // { debug, modeLabel } is object destructuring for the incoming props object
    return (
        <div className="pointer-events-none absolute bottom-4 left-4 grid gap-2 rounded-2xl bg-slate-950/55 p-4 text-xs shadow-2xl ring-1 ring-white/10 backdrop-blur-md sm:grid-cols-2">
            {/* Show the currently selected render mode */}
            <div><span className="text-slate-400">Mode:</span> {modeLabel}</div>

            {/* Show the smoothed frames-per-second value */}
            <div><span className="text-slate-400">FPS:</span> {debug.fps.toFixed(1)}</div>

            {/* Show the smoothed frame time in milliseconds */}
            <div><span className="text-slate-400">Frame:</span> {debug.frameTimeMs.toFixed(2)} ms</div>
            <div className="sm:col-span-2">
                <div className="mb-1 text-slate-400">Position:</div>
                <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
                    {/* Show each camera axis on its own row so the numbers are easy to scan */}
                    <div className="text-slate-400">X</div>
                    <div>{debug.position[0].toFixed(2)}</div>
                    <div className="text-slate-400">Y</div>
                    <div>{debug.position[1].toFixed(2)}</div>
                    <div className="text-slate-400">Z</div>
                    <div>{debug.position[2].toFixed(2)}</div>
                </div>
            </div>
        </div>
    );
}

// Show a centred error panel if the WebGL runtime failed to start
function ErrorOverlay({ error }) {
    if (!error) return null;

    return (
        <div className="absolute inset-0 flex items-center justify-center bg-slate-950 p-8">
            <div className="max-w-xl rounded-2xl bg-red-950/40 p-5 text-sm text-red-100 ring-1 ring-red-400/30">
                <div className="mb-2 font-semibold">Renderer error</div>
                {/* Use <pre> so line breaks from the error text stay visible */}
                <pre className="whitespace-pre-wrap text-xs">{error}</pre>
            </div>
        </div>
    );
}

// Render the floating controls panel on the right side of the screen
// The parent component passes callbacks down so this child stays presentational
function ControlsPanel({
    params,
    onParameterChange,
    onResetCamera,
    onResetParams,
    onFocusCanvas,
}) {
    return (
        <div className="absolute right-4 top-4 hidden max-h-[calc(100vh-2rem)] w-80 overflow-y-auto rounded-2xl bg-slate-950/55 p-4 shadow-2xl ring-1 ring-white/10 backdrop-blur-md lg:block">
            {/* Build the scene mode buttons from the shared options list */}
            <div className="mb-4 grid grid-cols-3 gap-2">
                {RENDER_MODE_OPTIONS.map(({ label, value }) => (
                    // map(...) loops over the array and returns one button for each item
                    // { label, value } destructures each option object
                    <button
                        key={label}
                        onClick={() => {
                            // Update the selected render mode in React state
                            onParameterChange("renderMode", value);

                            // Give keyboard focus back to the canvas after clicking
                            onFocusCanvas();
                        }}
                        className={`rounded-xl px-3 py-2 text-xs font-medium transition focus:outline-none focus-visible:outline-none ${
                            params.renderMode === value
                                ? "bg-slate-100 text-slate-950"
                                : "bg-white/7 text-slate-300 ring-1 ring-white/10 hover:bg-white/12"
                        }`}
                    >
                        {label}
                    </button>
                ))}
            </div>

            {/* Build one slider row for each numeric parameter */}
            <div className="space-y-3">
                {PARAMETER_CONTROLS.map(({ key, label, min, max, step }) => (
                    <ControlSlider
                        key={key}
                        label={label}
                        // params[key] uses bracket lookup because key is a variable
                        // params.key would only look for a literal property named "key"
                        value={params[key]}
                        min={min}
                        max={max}
                        step={step}
                        onChange={(value) => onParameterChange(key, value)}
                    />
                ))}
            </div>

            {/* Render the two action buttons under the sliders */}
            <div className="mt-4 grid grid-cols-2 gap-2">
                <button
                    onClick={() => {
                        onResetCamera();
                        onFocusCanvas();
                    }}
                    className="rounded-xl bg-white/7 px-3 py-2 text-sm font-medium ring-1 ring-white/10 hover:bg-white/12 focus:outline-none focus-visible:outline-none"
                >
                    Reset camera
                </button>
                <button
                    onClick={() => {
                        onResetParams();
                        onFocusCanvas();
                    }}
                    className="rounded-xl bg-white/7 px-3 py-2 text-sm font-medium ring-1 ring-white/10 hover:bg-white/12 focus:outline-none focus-visible:outline-none"
                >
                    Reset params
                </button>
            </div>
        </div>
    );
}

/* ============================================================================
   Main viewer component
   ============================================================================ */

export default function RaymarchViewer() {
    // canvasRef points to the real <canvas> DOM element once React mounts it
    const canvasRef = useRef(null);

    // mouseLookRef remembers whether the left mouse button is currently held down
    const mouseLookRef = useRef(false);

    // keysRef stores which keyboard keys are currently pressed
    // A ref is used here because this data changes frequently and should not cause React re-renders
    const keysRef = useRef({});

    // stateRef stores the mutable camera and timing state used by the render loop
    const stateRef = useRef(createCameraState());

    // params is normal React state because changing it should update the controls UI
    const [params, setParams] = useState(DEFAULT_RENDER_PARAMS);

    // paramsRef mirrors params so the render loop can read the latest values without rerendering
    const paramsRef = useRef(params);

    // debug is small React state used only by the overlay text
    // [debug, setDebug] is array destructuring for the pair returned by useState
    const [debug, setDebug] = useState(createDebugState());

    // Keep paramsRef synchronised with the latest React state value
    useEffect(() => {
        paramsRef.current = params;
    }, [params]);

    // Start the WebGL runtime hook
    // It handles context creation, the frame loop and clean-up
    const { error } = useRendererRuntime({
        canvasRef,
        paramsRef,
        stateRef,
        keysRef,
    });

    /* ============================================================================
       Local UI actions
       ============================================================================ */

    // Update one parameter while leaving all the others unchanged
    const updateParam = (key, value) => {
        // ...prev copies all existing fields into a new object
        // [key]: value writes to whichever property name is stored in key
        setParams((prev) => ({ ...prev, [key]: value }));
    };

    // Reset the mutable camera state back to its defaults
    const resetCamera = () => {
        resetCameraState(stateRef.current);
    };

    // Reset all render parameters back to their default values
    const resetParams = () => {
        setParams(DEFAULT_RENDER_PARAMS);
    };

    // Put keyboard focus on the canvas so keyboard controls keep working
    const focusCanvas = () => {
        canvasRef.current?.focus();
    };

    /* ============================================================================
       Global input listeners
       ============================================================================ */

    // Register the keyboard and mouse listeners once
    // These handlers read from refs so they always see the latest mutable state
    useEffect(() => {
        // When a key goes down mark it as pressed
        const onKeyDown = (event) => {
            // event.code is a stable keyboard code such as "KeyW" or "ShiftLeft"
            keysRef.current[event.code] = true;

            // Stop the page from scrolling for viewer movement keys
            if (PREVENT_DEFAULT_KEYS.includes(event.code)) {
                event.preventDefault();
            }

            // Pressing R resets the camera immediately
            if (event.code === "KeyR") resetCamera();
        };

        // When a key comes back up mark it as no longer pressed
        const onKeyUp = (event) => {
            keysRef.current[event.code] = false;
        };

        // While mouse-look is active convert mouse movement into yaw and pitch changes
        const onMouseMove = (event) => {
            if (!mouseLookRef.current) return;

            const state = stateRef.current;

            // Horizontal mouse movement changes yaw
            state.yaw += event.movementX * LOOK_SENSITIVITY;

            // Vertical mouse movement changes pitch and is clamped to avoid flipping upside down
            state.pitch = clamp(state.pitch - event.movementY * LOOK_SENSITIVITY, -1.52, 1.52);
        };

        // Releasing the mouse button ends drag-to-look mode
        const onMouseUp = () => {
            mouseLookRef.current = false;
        };

        // Losing browser focus also ends drag-to-look mode
        const onWindowBlur = () => {
            mouseLookRef.current = false;
        };

        // Use the mouse wheel over the canvas to scale the base movement speed
        const onWheel = (event) => {
            const canvas = canvasRef.current;
            if (!canvas || !canvas.matches(":hover")) return;

            event.preventDefault();
            const state = stateRef.current;

            // Exponential scaling makes the speed changes feel smoother than a fixed increment
            const factor = Math.exp(-event.deltaY * 0.0015);
            state.speed = clamp(state.speed * factor, 0.15, 35);
        };

        // Periodically copy a small snapshot of debug values into React state
        // The render loop itself stays outside React for speed
        const debugInterval = window.setInterval(() => {
            const state = stateRef.current;
            setDebug({
                fps: state.fps,
                frameTimeMs: state.frameTimeMs,
                position: [...state.position],
                yaw: state.yaw,
                pitch: state.pitch,
            });
        }, DEBUG_REFRESH_INTERVAL_MS);

        // Attach the listeners to the window so they keep working even if the pointer moves
        // outside the canvas while the user is dragging
        window.addEventListener("keydown", onKeyDown, { passive: false });
        window.addEventListener("keyup", onKeyUp);
        window.addEventListener("mousemove", onMouseMove);
        window.addEventListener("mouseup", onMouseUp);
        window.addEventListener("blur", onWindowBlur);
        window.addEventListener("wheel", onWheel, { passive: false });

        // Remove everything during cleanup so no listeners survive after unmount
        return () => {
            window.clearInterval(debugInterval);
            window.removeEventListener("keydown", onKeyDown);
            window.removeEventListener("keyup", onKeyUp);
            window.removeEventListener("mousemove", onMouseMove);
            window.removeEventListener("mouseup", onMouseUp);
            window.removeEventListener("blur", onWindowBlur);
            window.removeEventListener("wheel", onWheel);
        };
    }, []);

    // Turn the numeric render mode into the text shown in the stats overlay
    const modeLabel = getModeLabel(params.renderMode);

    /* ============================================================================
       Render output
       ============================================================================ */

    return (
        // Outer wrapper fills the browser window and provides the base text colour
        <div className="h-screen w-full overflow-hidden bg-slate-950 text-slate-100">
            {/* main is the positioned container that all overlays sit inside */}
            <main className="relative h-full w-full">
                <canvas
                    ref={canvasRef}
                    className="h-full w-full cursor-crosshair outline-none"
                    tabIndex={0}
                    onMouseDown={(event) => {
                        // Only start look-dragging on left click
                        // event.button === 0 means the primary mouse button
                        if (event.button !== 0) return;

                        // Mark drag-to-look as active and focus the canvas for keyboard input
                        mouseLookRef.current = true;
                        focusCanvas();
                    }}
                />

                {/* Draw the floating overlays above the canvas */}
                <InstructionsOverlay />
                <StatsOverlay debug={debug} modeLabel={modeLabel} />
                <ControlsPanel
                    params={params}
                    onParameterChange={updateParam}
                    onResetCamera={resetCamera}
                    onResetParams={resetParams}
                    onFocusCanvas={focusCanvas}
                />

                {/* Show an error overlay only if the runtime reported an error */}
                <ErrorOverlay error={error} />
            </main>
        </div>
    );
}
