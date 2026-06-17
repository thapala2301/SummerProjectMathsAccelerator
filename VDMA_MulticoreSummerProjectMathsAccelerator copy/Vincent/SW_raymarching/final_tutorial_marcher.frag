uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;

vec3  rot3D(vec3 p, vec3 axis, float angle){
    return mix(dot(axis,p)* axis, p, cos(angle))+ cross(axis,p)*sin(angle);
}

mat2 rot2D (float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c,-s,s,c);
}

vec3 palette (float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1, 1, 1);
    vec3 d = vec3(0.263, 0.416, 0.557);
    return a + b*cos(6.28318*(c*t+d));
}

float sdSphere(vec3 p, float r){
    return length(p)-r;
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p)-b;
    return length(max(q,vec3(0.)))+min(max(q.x, max(q.y,q.z)),0.0);
}

float sdOctahedron(vec3 p, float s){
    p = abs(p);
    return (p.x+p.y+p.z-s)*0.57735027;
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(b-a)/k, 0., 1.);
    return mix(b, a, h) - k*h*(1.-h);
}

float map(vec3 p) {
    p.z += u_time * .4;
    //p= fract(p)-.5;
    //float box = sdBox(p, vec3(.1));
    p.xy = (fract(p.xy)-.5);
    p.z = mod(p.z, .25)-.125;
    float box = sdOctahedron(p, .15);
    return box;


    
}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = (fragCoord * 2. - u_resolution.xy) / u_resolution.y;
    vec2 m = (u_mouse.xy *2. - u_resolution.xy)/u_resolution.y;
    vec3 ro = vec3 (0,0,-3);
    vec3 rd = normalize(vec3(uv,1));
    float t = 0.;

    ro.yz *= rot2D(-m.y);
    rd.yz *= rot2D(-m.y);

    ro.xz *= rot2D(-m.x);
    rd.xz *= rot2D(-m.x);

    if (u_mouse.x == 0. && u_mouse.y == 0.) m = vec2(cos(u_time*.2), sin(u_time*.2));
    
    int i;
    for (i = 0; i < 120; i ++ ) {
        vec3 p = ro+rd*t;

        p.xy *= rot2D(t*.2 * m.x);
        p.y += sin(t*(m.y+1.)*.5)*.35;
        float d = map(p);
        t +=d;
        if(d<.001 || t>120.) break;
    }

    //vec3 col = vec3(float(i)/80.);
    vec3 col = palette (t*.04 + float(i)*.005);
    gl_FragColor = vec4(col, 1);
}