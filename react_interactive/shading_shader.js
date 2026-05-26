/* ============================================================================
   Surface shading source
   ============================================================================ */

/*
Everything inside the template literal below is GLSL.

This file answers the question:

"Once the ray marcher says we hit something, what colour should that point look
like?"

The helpers below are mostly approximations chosen for speed and readability,
not fully physically exact light transport.
*/
export const shadingShaderSource = `
/*
Estimate a surface normal from the distance field.

Why finite differences give a normal:

If a scalar field stores distance-like values, then the direction of fastest
increase is perpendicular to the equal-value surface passing through the point.
That "fastest increase" direction is the gradient.
For a signed distance field, the gradient points outward and is perpendicular to
the surface, which is exactly what a normal should do.

We do not have an analytic gradient here, so we estimate it by sampling the
field slightly on both sides of each axis and subtracting:

    f(x + h) - f(x - h)

That is a central-difference approximation of the derivative.

The swizzles:

- e.xyy = (h, 0, 0)
- e.yxy = (0, h, 0)
- e.yyx = (0, 0, h)

So the code is sampling plus/minus X, plus/minus Y and plus/minus Z.
*/
vec3 estimateNormal(vec3 p) {
    /*
    Tie the normal-sampling distance to the surface hit epsilon, but keep a
    minimum floor so the subtraction does not collapse into numerical noise.

    Too small:
    the two samples become almost identical and precision suffers

    Too large:
    the normal becomes overly blurred and misses fine detail
    */
    vec2 e = vec2(max(uSurfaceEpsilon * 2.0, 0.00035), 0.0);

    return normalize(vec3(
        mapScene(p + e.xyy) - mapScene(p - e.xyy),
        mapScene(p + e.yxy) - mapScene(p - e.yxy),
        mapScene(p + e.yyx) - mapScene(p - e.yyx)
    ));
}

/*
Estimate how much shadow lies between a surface point and the light.

This is another ray march, but now the ray points toward the light source
instead of away from the camera.

Intuition for h / t:

- h
    current clearance from geometry
- t
    how far we have travelled toward the light so far

If clearance becomes small very quickly relative to travelled distance, an
occluder is probably close to the light ray, so the point should become darker.

The constant 12.0 is a tuning value that controls how quickly the shadow
darkens. It is a look/performance choice, not a mathematical law.
*/
float softShadow(vec3 ro, vec3 rd, float mint, float maxt) {
    float result = 1.0;
    float t = mint;

    for (int i = 0; i < 80; i++) {
        if (t >= maxt) break;

        float h = mapScene(ro + rd * t);

        /*
        Return a small non-zero floor instead of pure black.
        That keeps fully shadowed areas from becoming unnaturally crushed.
        */
        if (h < 0.001) return 0.05;

        result = min(result, 12.0 * h / t);

        /*
        Clamp the shadow step size so the ray:

        - does not get stuck taking microscopic steps
        - does not jump too far and miss thin blockers
        */
        t += clamp(h, 0.015, 0.18);
    }

    return clamp(result, 0.05, 1.0);
}

/*
Cheap ambient occlusion approximation.

Real ambient occlusion would consider many directions in a hemisphere.
That is too expensive for this small interactive shader.

This approximation only samples along the surface normal.
The intuition is:

If the normal direction should be empty for distance h, but the scene says a
surface appears sooner than that, then nearby geometry is crowding the point and
should darken the ambient term.

(h - d) therefore acts like "missing empty space".
The closer d is to zero compared with h, the more occluded that sample is.
*/
float ambientOcclusion(vec3 p, vec3 n) {
    float occ = 0.0;
    float sca = 1.0;

    for (int i = 1; i <= 5; i++) {
        float h = 0.04 * float(i);
        float d = mapScene(p + n * h);
        occ += (h - d) * sca;

        /*
        Fade the contribution of farther samples.
        Nearby geometry should matter more than faraway geometry.
        */
        sca *= 0.72;
    }

    return clamp(1.0 - 2.0 * occ, 0.0, 1.0);
}

/*
Colour used when a ray misses all geometry.

This has two pieces:

- a sky gradient
- a faint ground grid for orientation
*/
vec3 background(vec3 rd) {
    /*
    Remap the ray's vertical direction from roughly [-1, 1] into [0, 1].

    - rays pointing downward bias toward the bottom colour
    - rays pointing upward bias toward the top colour
    */
    float t = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);

    vec3 top = vec3(0.62, 0.70, 0.82);
    vec3 bottom = vec3(0.18, 0.20, 0.24);
    vec3 col = mix(bottom, top, t);

    float grid = 0.0;
    vec3 planeRo = uCamPos;

    if (abs(rd.y) > 0.001) {
        /*
        Solve the ray-plane intersection for a horizontal plane at y = -2.5.

        Ray equation:

            position = planeRo + rd * gt

        We want the Y component of that position to equal -2.5.
        */
        float gt = (-2.5 - planeRo.y) / rd.y;

        if (gt > 0.0) {
            vec3 gp = planeRo + rd * gt;

            /*
            Build a repeating grid pattern on the XZ plane.

            fract(value) keeps only the fractional part, so values repeat every
            whole-number interval.

            Example:

            - fract(0.1) = 0.1
            - fract(1.1) = 0.1
            - fract(2.1) = 0.1

            Subtracting 0.5 recentres each repeating cell around zero, which
            makes it easy to detect thin lines near the middle of each cell.

            fwidth(...) measures how quickly the value changes across nearby
            pixels. Dividing by it produces anti-aliased lines whose thickness
            adapts to screen resolution and viewing angle.
            */
            vec2 g = abs(fract(gp.xz * 0.5) - 0.5) / fwidth(gp.xz * 0.5);
            float line = 1.0 - min(min(g.x, g.y), 1.0);

            /*
            Fade the grid with distance so it does not dominate the sky.
            */
            float fade = exp(-0.045 * gt);
            grid = line * fade * 0.18;
        }
    }

    return col + grid;
}

/*
Shade a hit point.

Lighting terms used here:

- diffuse
    how much the surface faces the light
- specular
    shiny highlight
- fresnel-like rim
    stronger glancing-edge brightness
- soft shadow
    light blockage estimate
- ambient occlusion
    nearby-space crowding estimate
- fog
    distance fade
*/
vec3 shade(vec3 ro, vec3 rd, vec3 p, float travel, int steps) {
    vec3 n = estimateNormal(p);
    vec3 lightDir = normalize(vec3(0.7, 1.0, 0.45));

    /*
    rd points from the camera toward the surface.
    The view direction from the surface back toward the camera is therefore -rd.

    The half-vector is the direction halfway between:

    - light direction
    - view direction

    So:

        halfDir = normalize(lightDir + viewDir)
                = normalize(lightDir + (-rd))
                = normalize(lightDir - rd)
    */
    vec3 halfDir = normalize(lightDir - rd);

    /*
    Diffuse lighting uses the dot product because:

    - dot = 1 when the vectors point the same way
    - dot = 0 when they are perpendicular

    That matches Lambertian intuition:

    - full brightness when the surface faces the light directly
    - zero brightness when the light skims along the surface
    */
    float diff = max(dot(n, lightDir), 0.0);

    /*
    A simple rim/fresnel-style term that brightens glancing angles.
    The exponent is a look-tuning choice rather than a strict physical formula.
    */
    float fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

    /*
    Specular highlight.
    Raising the cosine term to a high power makes the lobe narrow and sharp.
    */
    float spec = pow(max(dot(n, halfDir), 0.0), 64.0);

    /*
    Offset the shadow ray a little along the normal so it does not immediately
    self-intersect the same surface because of floating-point precision.
    */
    float shadow = softShadow(p + n * 0.01, lightDir, 0.03, 6.0);
    float ao = ambientOcclusion(p, n);

    /*
    Start from a neutral rock-like base.
    For the Mandelbox only, add subtle bands so the folds are easier to read.
    This is an artistic reveal of detail, not a physically necessary material.
    */
    vec3 base = vec3(0.58, 0.58, 0.56);
    if (uRenderMode == 0) {
        float bands = 0.5 + 0.5 * sin(8.0 * length(p) + 0.35 * float(steps));
        base = mix(vec3(0.46, 0.46, 0.44), vec3(0.74, 0.73, 0.68), bands * 0.45);
    }

    /*
    Combine the lighting terms.

    The numeric weights here are tuning choices for the final look.
    */
    vec3 col = base * (0.18 + 0.82 * diff * shadow) * ao;
    col += vec3(1.0) * spec * shadow * 0.55;
    col += vec3(0.78, 0.86, 1.0) * fresnel * 0.22;

    /*
    Fog fades distant surfaces into the same background the ray would have seen
    if it had missed the geometry entirely.

    Using travel * travel makes the fade accelerate with distance, which gives
    a stronger depth cue than a purely linear-looking fade.
    */
    float fog = 1.0 - exp(-0.035 * travel * travel);
    col = mix(col, background(rd), fog);

    return col;
}
`;
