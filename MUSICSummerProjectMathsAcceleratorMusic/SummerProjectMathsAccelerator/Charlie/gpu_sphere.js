import { getCameraMatrix } from "./camera.js";
import { fragmentShaderSource, vertexShaderSource } from "./shaders.js";

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

export function createGpuSphereRenderer(canvas) {
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
        const width = Math.max(1, canvas.clientWidth);
        const height = Math.max(1, canvas.clientHeight);

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
