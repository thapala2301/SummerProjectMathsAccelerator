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

float sdSphere(vec3 p, float r){
    return length(p)-r;
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p)-b;
    return length(max(q,vec3(0.)))+min(max(q.x, max(q.y,q.z)),0.0);
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(b-a)/k, 0., 1.);
    return mix(b, a, h) - k*h*(1.-h);
}

float map(vec3 p) {
    vec3 spherePos = vec3(sin(u_time)*2., 0, 0);
    float sphere = sdSphere(p - spherePos,1.);


    vec3 q =p;
    //q.xy *= rot2D(u_time);
    q.y -= u_time * .4;
    q = fract(q)-.5;

    float box = sdBox(q, vec3(.1));
    float ground = p.y+0.75;
    return smin(ground, smin(sphere, box, .2), .2);

    
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

    for (int i = 0; i < 120; i ++ ) {
        vec3 p = ro+rd*t;
        float d = map(p);
        t +=d;
        if(d<.001 || t>120.) break;
    }

    vec3 col = vec3(t* .05);

    gl_FragColor = vec4(col, 1);
}