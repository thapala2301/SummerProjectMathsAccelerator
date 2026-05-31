import { getCameraMatrix } from "./camera.js";

export const vertexShaderSource = `#version 300 es
precision highp float;

in vec2 aPosition;

void main() {
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

export const fragmentShaderSource = `#version 300 es
precision highp float;

out vec4 outColour;

uniform vec2 uResolution;
uniform vec3 uCameraPosition;
uniform mat3 uCameraMatrix;
uniform float uFovDegrees;

mat2 rot2D(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, -s, s, c);
}

float sdBoxFrame(vec3 p, vec3 b, float e) {
    p = abs(p) - b;
    vec3 q = abs(p + e) - e;

    return min(min(
        length(max(vec3(p.x, q.y, q.z), 0.0)) + min(max(p.x, max(q.y, q.z)), 0.0),
        length(max(vec3(q.x, p.y, q.z), 0.0)) + min(max(q.x, max(p.y, q.z)), 0.0)),
        length(max(vec3(q.x, q.y, p.z), 0.0)) + min(max(q.x, max(q.y, p.z)), 0.0));
}

float map(vec3 p) {
    float c = 10.0;
    vec3 q = mod(p + 0.5 * c, c) - 0.5 * c;
    float wobbleFreq = 15.0;
    float wobble =
        sin(wobbleFreq * p.x) *
        sin(wobbleFreq * p.y) *
        sin(wobbleFreq * p.z) *
        0.1;

    return sdBoxFrame(q, vec3(4.5), 0.15) + wobble;
}

void main() {
    vec2 uv = (gl_FragCoord.xy * 2.0 - uResolution.xy) / uResolution.y;
    float fovScale = tan(radians(uFovDegrees) * 0.5);
    vec3 rayOrigin = uCameraPosition;
    vec3 rayDir = normalize(uCameraMatrix * vec3(uv * fovScale, -1.0));
    float t = 0.0;
    int i;

    for (i = 0; i < 128; i++) {
        float d = map(rayOrigin + rayDir * t);
        t += d;
        if (d < 0.001 || t > 200.0) break;
    }

    vec3 col = vec3(0.0);
    if (t < 200.0) {
        float step = float(i);
        col.r = fract(step * 0.020);
        col.g = fract(step * 0.013);
        col.b = fract(step * 0.007);
    }

    outColour = vec4(col, 1.0);
}
`;

const FULLSCREEN_TRIANGLE = new Float32Array([
    -1, -1,
    3, -1,
    -1, 3,
]);

function compileShader(gl, type, source) {
    const shader = gl.createShader(type);

    gl.shaderSource(shader, source);
    gl.compileShader(shader);

    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        return shader;
    }

    const message = gl.getShaderInfoLog(shader) || "Unknown shader compile error";
    gl.deleteShader(shader);
    throw new Error(message);
}

function createProgramme(gl) {
    const vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexShaderSource);
    const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource);
    const programme = gl.createProgram();

    gl.attachShader(programme, vertexShader);
    gl.attachShader(programme, fragmentShader);
    gl.linkProgram(programme);

    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);

    if (gl.getProgramParameter(programme, gl.LINK_STATUS)) {
        return programme;
    }

    const message = gl.getProgramInfoLog(programme) || "Unknown programme link error";
    gl.deleteProgram(programme);
    throw new Error(message);
}

export function createScaffoldRenderer(canvas) {
    const gl = canvas.getContext("webgl2", { antialias: false, alpha: false });
    if (!gl) {
        throw new Error("WebGL 2 is not available in this browser");
    }

    const programme = createProgramme(gl);
    const vertexArray = gl.createVertexArray();
    const vertexBuffer = gl.createBuffer();

    gl.bindVertexArray(vertexArray);
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, FULLSCREEN_TRIANGLE, gl.STATIC_DRAW);

    const positionLocation = gl.getAttribLocation(programme, "aPosition");
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);

    gl.bindVertexArray(null);
    gl.bindBuffer(gl.ARRAY_BUFFER, null);

    const uniforms = {
        resolution: gl.getUniformLocation(programme, "uResolution"),
        cameraPosition: gl.getUniformLocation(programme, "uCameraPosition"),
        cameraMatrix: gl.getUniformLocation(programme, "uCameraMatrix"),
        fovDegrees: gl.getUniformLocation(programme, "uFovDegrees"),
    };

    function render(camera, settings) {
        const width = Math.max(1, Math.floor(canvas.clientWidth * settings.renderScale));
        const height = Math.max(1, Math.floor(canvas.clientHeight * settings.renderScale));

        if (canvas.width !== width || canvas.height !== height) {
            canvas.width = width;
            canvas.height = height;
            gl.viewport(0, 0, width, height);
        }

        gl.useProgram(programme);
        gl.bindVertexArray(vertexArray);

        gl.uniform2f(uniforms.resolution, width, height);
        gl.uniform3fv(uniforms.cameraPosition, camera.position);
        gl.uniformMatrix3fv(uniforms.cameraMatrix, false, getCameraMatrix(camera.yaw, camera.pitch));
        gl.uniform1f(uniforms.fovDegrees, settings.fovDegrees);

        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    function dispose() {
        gl.deleteBuffer(vertexBuffer);
        gl.deleteVertexArray(vertexArray);
        gl.deleteProgram(programme);
    }

    return { render, dispose };
}
