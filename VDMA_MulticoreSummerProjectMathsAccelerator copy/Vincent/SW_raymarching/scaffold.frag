uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;

mat2 rot2D(float a) { float s=sin(a),c=cos(a); return mat2(c,-s,s,c); }

// Box frame SDF — just the edges of a box, not the solid
// b = half-extents, e = edge thickness
float sdBoxFrame(vec3 p, vec3 b, float e) {
    p = abs(p) - b;
    vec3 q = abs(p + e) - e;
    return min(min(
        length(max(vec3(p.x,q.y,q.z),0.))+min(max(p.x,max(q.y,q.z)),0.),
        length(max(vec3(q.x,p.y,q.z),0.))+min(max(q.x,max(p.y,q.z)),0.)),
        length(max(vec3(q.x,q.y,p.z),0.))+min(max(q.x,max(q.y,p.z)),0.));
}

float map(vec3 p) {
    float c = 10.0;
    // Domain repetition: tile every c units in all directions
    vec3 q = mod(p + 0.5*c, c) - 0.5*c;

    // Sinusoidal displacement — creates the jagged texture
    float defMag = 15.0;
    float def = sin(defMag*p.x) * sin(defMag*p.y) * sin(defMag*p.z) * 0.1;

    return sdBoxFrame(q, vec3(4.5), 0.15) + def;
}

// Camera ray — exactly the formula from the article
vec3 rayDirection(float fov, vec2 size, vec2 fragCoord) {
    vec2 xy = fragCoord - size / 2.0;
    float z = size.y / tan(radians(fov) / 2.0);
    return normalize(vec3(xy, -z));
}

void main() {
    vec2 m = (u_mouse * 2. - u_resolution.xy) / u_resolution.y;
    if (u_mouse.x == 0. && u_mouse.y == 0.)
        m = vec2(u_time * 0.15, sin(u_time * 0.08) * 0.3);

    // Camera — same as the article and Jai's ray_gen
    vec3 ro = vec3(0, 0, u_time * 3.0); // fly forward through the lattice
    vec3 rd = rayDirection(70.0, u_resolution.xy, gl_FragCoord.xy);
    ro.xz *= rot2D(-m.x); rd.xz *= rot2D(-m.x);
    ro.yz *= rot2D(-m.y); rd.yz *= rot2D(-m.y);

    // March
    float t = 0.;
    int i;
    for (i = 0; i < 128; i++) {
        float d = map(ro + rd * t);
        t += d;
        if (d < .001 || t > 200.) break;
    }

    // Bit-shift color mapping — exactly the paper's method
    // Each channel gets a different periodicity from the iteration count
    vec3 col = vec3(0);
    if (t < 200.) {
        float fi = float(i);
        col.r = fract(fi * 0.020);
        col.g = fract(fi * 0.013);
        col.b = fract(fi * 0.007);
    }

    gl_FragColor = vec4(col, 1);
}
