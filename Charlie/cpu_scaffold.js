import { getCameraMatrix } from "./camera.js";

let fwidthContext = null;

function setFwidthContext(context) {
    fwidthContext = context;
}

function vec2(x, y) {
    return [x, y];
}

function vec3(x, y, z) {
    // vec3(vec2, float)
    // e.g. vec3(uv * fovScale, -1.0)
    if (Array.isArray(x) && typeof y === "number" && z === undefined) {
        return [x[0], x[1], y];
    }

    return [x, y, z];
}

function vec4(x, y, z, w) {
    return [x, y, z, w];
}

function add(a, b) {
    if (typeof b === "number") {
        if (a.length === 2) {
            return [a[0] + b, a[1] + b];
        }
        return [a[0] + b, a[1] + b, a[2] + b];
    }
    if (a.length === 2 && b.length === 2) {
        return [a[0] + b[0], a[1] + b[1]];
    }
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
}

function sub(a, b) {
    if (typeof b === "number") {
        if (a.length === 2) {
            return [a[0] - b, a[1] - b];
        }
        return [a[0] - b, a[1] - b, a[2] - b];
    }
    if (a.length === 2 && b.length === 2) {
        return [a[0] - b[0], a[1] - b[1]];
    }
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
}

function neg(v) {
    if (v.length === 2) {
        return [-v[0], -v[1]];
    }
    return [-v[0], -v[1], -v[2]];
}

function mul(a, b) {
    // mat3 * vec3
    if (a.length === 9) {
        return [
            a[0] * b[0] + a[3] * b[1] + a[6] * b[2],
            a[1] * b[0] + a[4] * b[1] + a[7] * b[2],
            a[2] * b[0] + a[5] * b[1] + a[8] * b[2],
        ];
    }
    if (typeof b === "number") {
        if (a.length === 2) {
            return [a[0] * b, a[1] * b];
        }
        return [a[0] * b, a[1] * b, a[2] * b];
    }
    if (typeof a === "number") {
        return mul(b, a);
    }
    if (a.length === 2 && b.length === 2) {
        return [a[0] * b[0], a[1] * b[1]];
    }
    return [a[0] * b[0], a[1] * b[1], a[2] * b[2]];
}

function div(a, b) {
    if (typeof b === "number") {
        if (a.length === 2) {
            return [a[0] / b, a[1] / b];
        }
        return [a[0] / b, a[1] / b, a[2] / b];
    }
    if (a.length === 2 && b.length === 2) {
        return [a[0] / b[0], a[1] / b[1]];
    }
    return [a[0] / b[0], a[1] / b[1], a[2] / b[2]];
}

function length(v) {
    return Math.hypot(v[0], v[1], v[2] ?? 0);
}

function normalize(v) {
    const len = Math.hypot(v[0], v[1], v[2] ?? 0);
    if (len < 1e-12) {
        return [0, 0, 0];
    }
    return [v[0] / len, v[1] / len, v[2] / len];
}

function dot(a, b) {
    let sum = a[0] * b[0] + a[1] * b[1];
    if (a.length > 2 && b.length > 2) {
        sum += a[2] * b[2];
    }
    return sum;
}

function mix(a, b, t) {
    return [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    ];
}

function clamp(value, minValue, maxValue) {
    return Math.max(minValue, Math.min(maxValue, value));
}

function fract(value) {
    if (Array.isArray(value)) {
        return [fract(value[0]), fract(value[1])];
    }
    return value - Math.floor(value);
}

function abs(value) {
    if (Array.isArray(value)) {
        return [Math.abs(value[0]), Math.abs(value[1])];
    }
    return Math.abs(value);
}

function min(a, b) {
    return Math.min(a, b);
}

function max(a, b) {
    if (Array.isArray(a) && typeof b === "number") {
        return [Math.max(a[0], b), Math.max(a[1], b), Math.max(a[2], b)];
    }
    return Math.max(a, b);
}

function pow(a, b) {
    if (Array.isArray(a) && Array.isArray(b)) {
        return [Math.pow(a[0], b[0]), Math.pow(a[1], b[1]), Math.pow(a[2], b[2])];
    }
    return Math.pow(a, b);
}

function exp(value) {
    return Math.exp(value);
}

function tan(value) {
    return Math.tan(value);
}

function radians(degrees) {
    return (degrees * Math.PI) / 180;
}

function float(value) {
    return value;
}

function fwidth(value) {
    return fwidthContext;
}

let uResolution;
let uCameraPosition;
let uCameraMatrix;
let uFovDegrees;
let uFovScale;

function abs3(v) {
    return [Math.abs(v[0]), Math.abs(v[1]), Math.abs(v[2])];
}

function repeat3(p, cellSize) {
    const halfCell = 0.5 * cellSize;

    function repeatAxis(axis) {
        return ((((axis + halfCell) % cellSize) + cellSize) % cellSize) - halfCell;
    }

    return [repeatAxis(p[0]), repeatAxis(p[1]), repeatAxis(p[2])];
}

function sdBoxFrame(p, b, e) {
    p = sub(abs3(p), b);
    const q = sub(abs3(add(p, e)), e);

    const xFace = length(max(vec3(p[0], q[1], q[2]), 0.0)) +
        min(max(p[0], max(q[1], q[2])), 0.0);

    const yFace = length(max(vec3(q[0], p[1], q[2]), 0.0)) +
        min(max(q[0], max(p[1], q[2])), 0.0);

    const zFace = length(max(vec3(q[0], q[1], p[2]), 0.0)) +
        min(max(q[0], max(q[1], p[2])), 0.0);

    return min(min(xFace, yFace), zFace);
}

function mapScene(p) {
    const c = 10.0;
    const q = repeat3(p, c);
    const wobbleFreq = 15.0;
    const wobble =
        Math.sin(wobbleFreq * p[0]) *
        Math.sin(wobbleFreq * p[1]) *
        Math.sin(wobbleFreq * p[2]) *
        0.1;

    return sdBoxFrame(q, vec3(4.5, 4.5, 4.5), 0.15) + wobble;
}

function fragmentMain(vUv, rayDir) {
    const rayOrigin = uCameraPosition;

    let t = 0.0;
    let i;

    for (i = 0; i < 128; i++) {
        const d = mapScene(add(rayOrigin, mul(rayDir, t)));
        t += d;

        if (d < 0.001 || t > 200.0) {
            break;
        }
    }

    let col = vec3(0.0, 0.0, 0.0);

    if (t < 200.0) {
        const step = float(i);
        col = vec3(
            fract(step * 0.020),
            fract(step * 0.013),
            fract(step * 0.007),
        );
    }

    return vec4(col[0], col[1], col[2], 1.0);
}

function makeFwidthContext(gl_FragCoord, rayDir) {
    return vec2(1e-4, 1e-4);
}

export function createCpuScaffoldRenderer(canvas) {
    // Rasterise the scene one pixel at a time
    const context = canvas.getContext("2d", { alpha: false });
    if (!context) {
        throw new Error("2D canvas context is not available");
    }

    let imageData = null;

    function render(camera, settings) {
        const [width, height] = settings.internalResolution;

        if (!imageData || canvas.width !== width || canvas.height !== height) {
            canvas.width = width;
            canvas.height = height;
            imageData = context.createImageData(width, height);
        }

        uResolution = vec2(width, height);
        uCameraPosition = camera.position;
        uCameraMatrix = getCameraMatrix(camera.yaw, camera.pitch);
        uFovDegrees = settings.fovDegrees;
        uFovScale = tan(radians(uFovDegrees) * 0.5);

        const pixels = imageData.data;
        let index = 0;

        for (let screenY = 0; screenY < height; screenY++) {
            for (let screenX = 0; screenX < width; screenX++) {
                // Flip Y so canvas rows match gl_FragCoord
                // Add 0.5 to sample at pixel centres
                const gl_FragCoord = vec2(screenX + 0.5, height - screenY - 0.5);

                // Calculate interpolated vUv coordinates
                // In the GPU, interpolation happens automatically across the triangle
                const vUv = vec2(gl_FragCoord[0] / width, gl_FragCoord[1] / height);

                // Construct the ray direction
                const uv = div(sub(mul(gl_FragCoord, 2.0), uResolution), uResolution[1]);
                const rayDir = normalize(mul(uCameraMatrix, vec3(mul(uv, uFovScale), -1.0)));

                setFwidthContext(makeFwidthContext(gl_FragCoord, rayDir));

                const outColour = fragmentMain(vUv, rayDir);

                pixels[index] = Math.round(clamp(outColour[0], 0.0, 1.0) * 255);
                pixels[index + 1] = Math.round(clamp(outColour[1], 0.0, 1.0) * 255);
                pixels[index + 2] = Math.round(clamp(outColour[2], 0.0, 1.0) * 255);
                pixels[index + 3] = 255;
                index += 4;
            }
        }

        context.putImageData(imageData, 0, 0);
    }

    function dispose() {
        imageData = null;
    }

    return { render, dispose };
}
