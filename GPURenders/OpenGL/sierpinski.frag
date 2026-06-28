uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;

mat2 rot2D(float a) { float s=sin(a),c=cos(a); return mat2(c,-s,s,c); }

// Sierpinski / tetrahedral fold SDF
// Each iteration folds space around the 4 corners of a tetrahedron
float sierpinski(vec3 p) {
    float scale = 1.0;

    for (int i = 0; i < 8; i++) {
        // Fold around each pair of axes
        if (p.x + p.y < 0.0) { float t = p.x; p.x = -p.y; p.y = -t; }
        if (p.x + p.z < 0.0) { float t = p.x; p.x = -p.z; p.z = -t; }
        if (p.y + p.z < 0.0) { float t = p.y; p.y = -p.z; p.z = -t; }

        // Scale and translate
        p = p * 2.0 - 1.0;
        scale *= 2.0;
    }

    // Distance to origin after folding, divided by accumulated scale
    return (length(p) - 1.5) / scale;
}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = (fragCoord * 2. - u_resolution.xy) / u_resolution.y;
    vec2 m  = (u_mouse   * 2. - u_resolution.xy) / u_resolution.y;

    // Auto-rotate if mouse hasn't moved
    if (u_mouse.x == 0. && u_mouse.y == 0.)
        m = vec2(u_time * 0.15, sin(u_time * 0.07) * 0.4);

    // Camera - same as the paper
    vec3 ro = vec3(0, 0, -3);
    vec3 rd = normalize(vec3(uv, 1.5));
    ro.xz *= rot2D(-m.x); rd.xz *= rot2D(-m.x);
    ro.yz *= rot2D(-m.y); rd.yz *= rot2D(-m.y);

    // March
    float t = 0.;
    int i;
    for (i = 0; i < 128; i++) {
        float d = sierpinski(ro + rd * t);
        t += d;
        if (d < .0005 || t > 20.) break;
    }

    // Color mapping — paper's bit-shift method per channel
    // Each channel = fract(t * 2^shift) — gives the banded rainbow look
    vec3 col = vec3(0);
    if (t < 20.) {
        float fi = float(i);
        col.r = fract(fi * 0.020);   // shift_r
        col.g = fract(fi * 0.013);   // shift_g
        col.b = fract(fi * 0.007);   // shift_b
    }

    gl_FragColor = vec4(col, 1);
}
