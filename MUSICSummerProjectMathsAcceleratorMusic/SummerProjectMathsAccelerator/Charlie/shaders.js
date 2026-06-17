export const vertexShaderSource = `#version 300 es

precision highp float;

in vec2 aPosition;
out vec2 vUv;

void main() {
    vUv = aPosition * 0.5 + 0.5;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

export const fragmentShaderSource = `#version 300 es

precision highp float;

in vec2 vUv;
out vec4 outColour;

uniform vec2 uResolution;
uniform vec3 uCameraPosition;
uniform mat3 uCameraMatrix;
uniform float uFovDegrees;

float sphereDE(vec3 p) {
    return length(p) - 1.25;
}

float mapScene(vec3 p) {
    return sphereDE(p);
}

vec3 estimateNormal(vec3 p) {
    vec2 e = vec2(0.003, 0.0);

    return normalize(vec3(
        mapScene(p + e.xyy) - mapScene(p - e.xyy),
        mapScene(p + e.yxy) - mapScene(p - e.yxy),
        mapScene(p + e.yyx) - mapScene(p - e.yyx)
    ));
}

float softShadow(vec3 rayOrigin, vec3 rayDir, float minDist, float maxDist) {
    float result = 1.0;
    float t = minDist;

    // March towards the light until we hit the sphere or leave range
    for (int i = 0; i < 80; i++) {
        if (t >= maxDist) break;

        float h = mapScene(rayOrigin + rayDir * t);
        if (h < 0.001) return 0.05;

        result = min(result, 12.0 * h / t);
        t += clamp(h, 0.015, 0.18);
    }

    return clamp(result, 0.05, 1.0);
}

float ambientOcclusion(vec3 p, vec3 n) {
    float occlusion = 0.0;
    float weight = 1.0;

    // Sample along the normal, weighting nearby samples more
    for (int i = 1; i <= 5; i++) {
        float h = 0.04 * float(i);
        float d = mapScene(p + n * h);

        occlusion += (h - d) * weight;
        weight *= 0.72;
    }

    return clamp(1.0 - 2.0 * occlusion, 0.0, 1.0);
}

vec3 background(vec3 rayDir) {
    float t = clamp(rayDir.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 high = vec3(0.62, 0.70, 0.82);
    vec3 low = vec3(0.18, 0.20, 0.24);
    vec3 col = mix(low, high, t);
    float grid = 0.0;

    if (abs(rayDir.y) > 0.001) {
        float groundDist = (-2.5 - uCameraPosition.y) / rayDir.y;

        if (groundDist > 0.0) {
            vec3 groundPoint = uCameraPosition + rayDir * groundDist;
            // Anti-aliased distance to the nearest grid line
            vec2 gridDist = abs(fract(groundPoint.xz * 0.5) - 0.5) / fwidth(groundPoint.xz * 0.5);
            float line = 1.0 - min(min(gridDist.x, gridDist.y), 1.0);
            float fade = exp(-0.045 * groundDist);

            grid = line * fade * 0.18;
        }
    }

    return col + grid;
}

vec3 shade(vec3 rayDir, vec3 point) {
    vec3 normal = estimateNormal(point);
    // Fixed scene light direction and half-angle for specular
    vec3 lightDir = normalize(vec3(0.7, 1.0, 0.45));
    vec3 halfDir = normalize(lightDir - rayDir);

    float diffuse = max(dot(normal, lightDir), 0.0);
    float fresnel = pow(1.0 - max(dot(normal, -rayDir), 0.0), 3.0);
    float specular = pow(max(dot(normal, halfDir), 0.0), 64.0);

    // Start slightly above the surface to avoid self-shadowing
    float shadow = softShadow(point + normal * 0.01, lightDir, 0.03, 6.0);
    float occlusion = ambientOcclusion(point, normal);
    vec3 base = vec3(0.58, 0.58, 0.56);

    vec3 colour = base * (0.18 + 0.82 * diffuse * shadow) * occlusion;
    colour += vec3(1.0) * specular * shadow * 0.55;
    colour += vec3(0.78, 0.86, 1.0) * fresnel * 0.22;
    return colour;
}

void main() {
    // Turn this pixel into a camera ray
    vec2 uv = (gl_FragCoord.xy * 2.0 - uResolution.xy) / uResolution.y;
    float fovScale = tan(radians(uFovDegrees) * 0.5);
    vec3 rayDir = normalize(uCameraMatrix * vec3(uv * fovScale, -1.0));
    vec3 rayOrigin = uCameraPosition;

    float hitDist = -1.0;
    float travel = 0.0;

    // March the ray through the scene until it hits something or goes too far
    for (int i = 0; i < 128; i++) {
        vec3 p = rayOrigin + rayDir * travel;
        float d = mapScene(p);

        if (d < 0.001) {
            hitDist = travel;
            break;
        }

        travel += d;
        if (travel > 100.0) break;
    }

    vec3 colour;

    if (hitDist > 0.0) {
        vec3 hitPoint = rayOrigin + rayDir * hitDist;
        colour = shade(rayDir, hitPoint);

        float fog = 1.0 - exp(-0.035 * hitDist * hitDist);
        colour = mix(colour, background(rayDir), fog);
    } else {
        colour = background(rayDir);
    }

    vec2 q = vUv - 0.5;

    // Apply vignette and gamma correction
    colour *= 1.0 - 0.38 * dot(q, q);
    colour = pow(max(colour, 0.0), vec3(0.4545));
    outColour = vec4(colour, 1.0);
}
`;
