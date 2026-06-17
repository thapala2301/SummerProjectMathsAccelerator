import { useEffect, useRef, useState } from "react";

import { advanceCameraState, clamp, createCameraState, resetCameraState } from "./camera.js";
import { createGpuRenderer } from "./gpu_renderer.js";

const LOOK_SENSITIVITY = 0.0019;
const HUD_REFRESH_MS = 120;
const SETTINGS = {
    fovDegrees: 60,
    renderScale: 1,
};
const PREVENT_DEFAULT_KEYS = ["KeyW", "KeyA", "KeyS", "KeyD", "Space", "ShiftLeft", "ShiftRight"];

export default function App() {
    // HUD values shown in the side panel
    const [hud, setHud] = useState({
        position: [0, 0.15, 4.5],
        speed: 4.5,
        frameMs: 0,
        fps: 0,
    });
    const [gpuError, setGpuError] = useState("");

    // Live renderer, camera and input state
    const canvasRef = useRef(null);
    const rendererRef = useRef(null);
    const cameraRef = useRef(createCameraState());
    const pressedKeysRef = useRef({});
    const mouseLookRef = useRef(false);

    // Create the renderer once and surface start-up errors in the UI
    useEffect(() => {
        if (!canvasRef.current || rendererRef.current) {
            return undefined;
        }

        try {
            rendererRef.current = createGpuRenderer(canvasRef.current);
        } catch (error) {
            // Show start-up failures in the overlay
            setGpuError(error instanceof Error ? error.message : "GPU renderer failed");
        }

        return () => {
            // Release renderer resources on unmount
            rendererRef.current?.dispose();
            rendererRef.current = null;
        };
    }, []);

    // Track global input without forcing React re-renders
    useEffect(() => {
        function onKeyDown(event) {
            // Record held keys for the frame loop
            pressedKeysRef.current[event.code] = true;

            // Stop the browser stealing movement keys
            if (PREVENT_DEFAULT_KEYS.includes(event.code)) {
                event.preventDefault();
            }

            // Reset the camera to its starting position and orientation
            if (event.code === "KeyR") {
                resetCameraState(cameraRef.current);
            }
        }

        function onKeyUp(event) {
            pressedKeysRef.current[event.code] = false;
        }

        function onMouseMove(event) {
            // Only rotate while drag-look is active
            if (!mouseLookRef.current) {
                return;
            }

            const camera = cameraRef.current;

            // Yaw turns left or right; pitch turns up or down
            camera.yaw += event.movementX * LOOK_SENSITIVITY;
            camera.pitch = clamp(camera.pitch - event.movementY * LOOK_SENSITIVITY, -1.52, 1.52);
        }

        function onMouseUp() {
            mouseLookRef.current = false;
        }

        function onWindowBlur() {
            mouseLookRef.current = false;
            pressedKeysRef.current = {};
        }

        function onWheel(event) {
            // Only change speed while the pointer is over the canvas
            if (!canvasRef.current || !canvasRef.current.matches(":hover")) {
                return;
            }

            event.preventDefault();

            const camera = cameraRef.current;

            // Scale speed smoothly rather than in fixed steps
            const factor = Math.exp(-event.deltaY * 0.0015);
            camera.speed = clamp(camera.speed * factor, 0.15, 35);
        }

        window.addEventListener("keydown", onKeyDown);
        window.addEventListener("keyup", onKeyUp);
        window.addEventListener("mousemove", onMouseMove);
        window.addEventListener("mouseup", onMouseUp);
        window.addEventListener("blur", onWindowBlur);
        window.addEventListener("wheel", onWheel, { passive: false });

        return () => {
            window.removeEventListener("keydown", onKeyDown);
            window.removeEventListener("keyup", onKeyUp);
            window.removeEventListener("mousemove", onMouseMove);
            window.removeEventListener("mouseup", onMouseUp);
            window.removeEventListener("blur", onWindowBlur);
            window.removeEventListener("wheel", onWheel);
        };
    }, []);

    // Run the frame loop and refresh the HUD on a slower timer
    useEffect(() => {
        let frameId = 0;
        let previousTime = performance.now();

        const hudInterval = window.setInterval(() => {
            // Copy the latest camera state into React for the HUD
            const camera = cameraRef.current;
            setHud({
                position: [...camera.position],
                speed: camera.speed,
                frameMs: camera.frameTimeMs,
                fps: camera.fps,
            });
        }, HUD_REFRESH_MS);

        function renderFrame(now) {
            const frameSeconds = (now - previousTime) / 1000;
            previousTime = now;

            // Cap movement only so long stalls don't cause huge jumps
            const movementDt = Math.min(frameSeconds, 0.05);

            advanceCameraState(cameraRef.current, pressedKeysRef.current, movementDt);

            rendererRef.current?.render(cameraRef.current, SETTINGS);

            const camera = cameraRef.current;
            const frameMs = frameSeconds * 1000;

            // Smooth the timing values so the HUD stays readable
            camera.frameTimeMs = camera.frameTimeMs * 0.92 + frameMs * 0.08;
            camera.fps = 1000 / Math.max(camera.frameTimeMs, 0.0001);

            frameId = requestAnimationFrame(renderFrame);
        }

        frameId = requestAnimationFrame(renderFrame);

        return () => {
            window.clearInterval(hudInterval);
            cancelAnimationFrame(frameId);
        };
    }, []);

    // Start drag-look on left click
    function handleMouseDown(event) {
        if (event.button !== 0) {
            return;
        }

        mouseLookRef.current = true;
        event.currentTarget.focus();
    }

    // Reset the camera and return focus to the canvas
    function handleReset() {
        resetCameraState(cameraRef.current);
        canvasRef.current?.focus();
    }

    return (
        <div className="app-shell">
            <div className="stage">
                <canvas
                    ref={canvasRef}
                    className="render-canvas is-active"
                    tabIndex={0}
                    onMouseDown={handleMouseDown}
                />

                <section className="panel panel--top-left">
                    <p>
                        Hold click and drag to look around. Fly with <b>WASD</b>,
                        rise with <b>Space</b>, fall with <b>Shift</b>, reset with
                        <b> R</b> and use the mouse wheel to change flight speed.
                    </p>
                    <div className="button-row">
                        <button className="action-button" type="button" onClick={handleReset}>
                            Reset camera
                        </button>
                    </div>
                </section>

                <section className="panel panel--bottom-left stats-panel">
                    <div className="stats-metrics">
                        <span className="stats-label">FPS</span>
                        <span>{hud.fps.toFixed(1)}</span>
                        <span className="stats-label">T</span>
                        <span>{hud.frameMs.toFixed(2)} ms</span>
                    </div>
                    <div className="stats-position">
                        <div className="stats-row">
                            <span className="stats-label">X</span>
                            <span>{hud.position[0].toFixed(2)}</span>
                        </div>
                        <div className="stats-row">
                            <span className="stats-label">Y</span>
                            <span>{hud.position[1].toFixed(2)}</span>
                        </div>
                        <div className="stats-row">
                            <span className="stats-label">Z</span>
                            <span>{hud.position[2].toFixed(2)}</span>
                        </div>
                        <div className="stats-row">
                            <span className="stats-label">SPD</span>
                            <span>{hud.speed.toFixed(2)}</span>
                        </div>
                    </div>
                </section>

                {gpuError ? (
                    <div className="error-overlay">
                        <div className="error-panel">
                            <div className="error-title">Error</div>
                            <pre>{gpuError}</pre>
                        </div>
                    </div>
                ) : null}
            </div>
        </div>
    );
}
