uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;

mat2 rot2D(float a) { float s=sin(a),c=cos(a); return mat2(c,-s,s,c); }

// --- SDFs ---

float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, vec3(0.))) + min(max(q.x, max(q.y, q.z)), 0.);
}

// Sphere minus box = hollow box with rounded cutouts
float sdScene(vec3 p) {
    // Space repetition: tile every 3 units
    vec3 q = p;
    q = mod(q + 1.5, 3.0) - 1.5;

    float box    = sdBox(q, vec3(0.8));
    float sphere = sdSphere(q, 1.0);

    return max(sphere, -box); // sphere with box subtracted = hollow
}

// --- Normal estimation ---
vec3 calcNormal(vec3 p) {
    vec2 e = vec2(.001, 0);
    return normalize(vec3(
        sdScene(p + e.xyy) - sdScene(p - e.xyy),
        sdScene(p + e.yxy) - sdScene(p - e.yxy),
        sdScene(p + e.yyx) - sdScene(p - e.yyx)
    ));
}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = (fragCoord * 2. - u_resolution.xy) / u_resolution.y;
    vec2 m  = (u_mouse   * 2. - u_resolution.xy) / u_resolution.y;

    // Camera
    vec3 ro = vec3(0, 0, -4);
    vec3 rd = normalize(vec3(uv, 1.5));

    // Mouse orbit
    if (u_mouse.x == 0. && u_mouse.y == 0.) {
        m = vec2(u_time * 0.2, sin(u_time * 0.1) * 0.3);
    }
    ro.xz *= rot2D(-m.x); rd.xz *= rot2D(-m.x);
    ro.yz *= rot2D(-m.y); rd.yz *= rot2D(-m.y);

    // March
    float t = 0.;
    int i;
    for (i = 0; i < 128; i++) {
        vec3 p = ro + rd * t;
        float d = sdScene(p);
        t += d;
        if (d < .001 || t > 30.) break;
    }

    // Color by iteration count — matches what your Verilog will output
    float fi = float(i) / 128.;

    // Blue-purple-red gradient (matches the paper's color scheme)
    vec3 col = vec3(0);
    if (t < 30.) {
        vec3 p      = ro + rd * t;
        vec3 normal = calcNormal(p);
        vec3 light  = normalize(vec3(1, 2, -1));
        float diff  = max(dot(normal, light), 0.);
        vec3 base   = mix(vec3(0.1, 0.2, 0.8), vec3(0.8, 0.1, 0.3), fi);
        col = base * (0.2 + 0.8 * diff);
    }

    gl_FragColor = vec4(col, 1);
}
