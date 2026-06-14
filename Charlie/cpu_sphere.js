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

function sphereDE(p) {
    return length(p) - 1.25;
}

function mapScene(p) {
    return sphereDE(p);
}

function estimateNormal(p) {
    const e = 0.003;

    const px = p[0];
    const py = p[1];
    const pz = p[2];

    return normalize([
        Math.hypot(px + e, py, pz) - Math.hypot(px - e, py, pz),
        Math.hypot(px, py + e, pz) - Math.hypot(px, py - e, pz),
        Math.hypot(px, py, pz + e) - Math.hypot(px, py, pz - e),
    ]);
}

function softShadow(rayOrigin, rayDir, minDist, maxDist) {
    let result = 1.0;
    let t = minDist;

    for (let i = 0; i < 80; i++) {
        if (t >= maxDist) {
            break;
        }

        const h = mapScene(add(rayOrigin, mul(rayDir, t)));

        if (h < 0.001) {
            return 0.05;
        }

        result = min(result, 12.0 * h / t);
        t += clamp(h, 0.015, 0.18);
    }

    return clamp(result, 0.05, 1.0);
}

function ambientOcclusion(p, n) {
    let occlusion = 0.0;
    let weight = 1.0;

    for (let i = 1; i <= 5; i++) {
        const h = 0.04 * float(i);
        const d = mapScene(add(p, mul(n, h)));

        occlusion += (h - d) * weight;
        weight *= 0.72;
    }

    return clamp(1.0 - 2.0 * occlusion, 0.0, 1.0);
}

function background(rayDir) {
    const t = clamp(rayDir[1] * 0.5 + 0.5, 0.0, 1.0);
    const high = vec3(0.62, 0.70, 0.82);
    const low = vec3(0.18, 0.20, 0.24);
    const col = mix(low, high, t);
    let grid = 0.0;

    if (abs(rayDir[1]) > 0.001) {
        const groundDist = (-2.5 - uCameraPosition[1]) / rayDir[1];

        if (groundDist > 0.0) {
            const groundPoint = add(uCameraPosition, mul(rayDir, groundDist));
            const groundXZ = mul([groundPoint[0], groundPoint[2]], 0.5);
            const gridDist = div(abs(sub(fract(groundXZ), 0.5)), fwidth(groundXZ));
            const line = 1.0 - min(min(gridDist[0], gridDist[1]), 1.0);
            const fade = exp(-0.045 * groundDist);

            grid = line * fade * 0.18;
        }
    }

    return add(col, grid);
}

function shade(rayDir, point) {
    const normal = estimateNormal(point);
    const lightDir = normalize(vec3(0.7, 1.0, 0.45));
    const halfDir = normalize(sub(lightDir, rayDir));
    const diffuse = max(dot(normal, lightDir), 0.0);
    const fresnel = pow(1.0 - max(dot(normal, neg(rayDir)), 0.0), 3.0);
    const specular = pow(max(dot(normal, halfDir), 0.0), 64.0);
    const shadow = softShadow(add(point, mul(normal, 0.01)), lightDir, 0.03, 6.0);
    const occlusion = ambientOcclusion(point, normal);
    const base = vec3(0.58, 0.58, 0.56);

    let colour = mul(base, (0.18 + 0.82 * diffuse * shadow) * occlusion);
    colour = add(colour, mul(vec3(1.0, 1.0, 1.0), specular * shadow * 0.55));
    colour = add(colour, mul(vec3(0.78, 0.86, 1.0), fresnel * 0.22));

    return colour;
}

function fragmentMain(vUv, rayDir) {
    const rayOrigin = uCameraPosition;

    let hitDist = -1.0;
    let travel = 0.0;

    for (let i = 0; i < 128; i++) {
        const p = add(rayOrigin, mul(rayDir, travel));
        const d = mapScene(p);

        if (d < 0.001) {
            hitDist = travel;
            break;
        }

        travel += d;

        if (travel > 100.0) {
            break;
        }
    }

    let colour;
    const bg = background(rayDir);

    if (hitDist > 0.0) {
        const hitPoint = add(rayOrigin, mul(rayDir, hitDist));
        colour = shade(rayDir, hitPoint);

        const fog = 1.0 - exp(-0.035 * hitDist * hitDist);
        colour = mix(colour, bg, fog);
    } else {
        colour = bg;
    }

    const q = sub(vUv, 0.5);

    colour = mul(colour, 1.0 - 0.38 * dot(q, q));
    colour = pow(max(colour, 0.0), vec3(0.4545, 0.4545, 0.4545));

    return vec4(colour[0], colour[1], colour[2], 1.0);
}

function makeFwidthContext(gl_FragCoord, rayDir) {
    // Approximate fwidth for the ground grid
    function groundXZScaledAt(coord, dir) {
        let rayDirAt = dir;

        if (!rayDirAt) {
            const uvAt = div(sub(mul(coord, 2.0), uResolution), uResolution[1]);
            rayDirAt = normalize(mul(uCameraMatrix, vec3(mul(uvAt, uFovScale), -1.0)));
        }

        if (abs(rayDirAt[1]) <= 0.001) {
            return null;
        }

        const groundDistAt = (-2.5 - uCameraPosition[1]) / rayDirAt[1];
        if (groundDistAt <= 0.0) {
            return null;
        }

        const groundPointAt = add(uCameraPosition, mul(rayDirAt, groundDistAt));
        return mul([groundPointAt[0], groundPointAt[2]], 0.5);
    }

    const at = groundXZScaledAt(gl_FragCoord, rayDir);
    const atX = groundXZScaledAt(vec2(gl_FragCoord[0] + 1.0, gl_FragCoord[1]));
    const atY = groundXZScaledAt(vec2(gl_FragCoord[0], gl_FragCoord[1] + 1.0));

    if (!at || !atX || !atY) {
        return vec2(1e-4, 1e-4);
    }

    return vec2(
        abs(atX[0] - at[0]) + abs(atY[0] - at[0]),
        abs(atX[1] - at[1]) + abs(atY[1] - at[1]),
    );
}

export function createCpuSphereRenderer(canvas) {
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
