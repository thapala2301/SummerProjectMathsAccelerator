const DEFAULT_CAMERA_POSITION = [0, 0.15, 4.5];
const DEFAULT_CAMERA_SPEED = 4.5;

export function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function cloneDefaultPosition() {
    return [...DEFAULT_CAMERA_POSITION];
}

export function createCameraState() {
    return {
        position: cloneDefaultPosition(),
        yaw: 0,
        pitch: 0,
        speed: DEFAULT_CAMERA_SPEED,
        frameTimeMs: 0,
        fps: 0,
    };
}

export function resetCameraState(state) {
    state.position = cloneDefaultPosition();
    state.yaw = 0;
    state.pitch = 0;
}

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

export function advanceCameraState(state, keys, dt) {
    const cy = Math.cos(state.yaw);
    const sy = Math.sin(state.yaw);

    const forward = [sy, 0, -cy];
    const right = [cy, 0, sy];
    const up = [0, 1, 0];
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
    if (keys.Space) addScaled(up, 1);
    if (keys.ShiftLeft || keys.ShiftRight) addScaled(up, -1);

    const length = Math.hypot(move[0], move[1], move[2]);
    if (length < 0.0001) {
        return;
    }

    state.position[0] += (move[0] / length) * state.speed * dt;
    state.position[1] += (move[1] / length) * state.speed * dt;
    state.position[2] += (move[2] / length) * state.speed * dt;
}
