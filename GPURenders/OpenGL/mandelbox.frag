uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;

mat2 rot2D(float a) {float s = sin(a), c = cos(a); return mat2(c,-s,s,c);}

float mandelbox(vec3 p) {
    vec3 z = p;
    float dr = 1.0;
    float scale = 2.0;

    for (int i=0; i<8; i++) {
        //box fold
        z = clamp(z, -1.0, 1.0)*2.0-z;

        //sphere fold
        float r2 = dot(z,z);
        if (r2 <0.25) { z *= 4.0; dr *= 4.0;}
        else if(r2 <1.0) { z /= r2; dr /=r2;}

        //scale + translate
        z= z* scale +p;
        dr = dr *abs(scale) +1.0;

    }
    return length(z) /abs(dr);

}

float map(vec3 p ) {return mandelbox(p);}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = (fragCoord*2. - u_resolution.xy)/u_resolution.y;
    vec2 m = (u_mouse*2. -u_resolution.xy)/u_resolution.y;

    vec3 ro = vec3(0,0,-11);
    vec3 rd = normalize(vec3(uv,1.5));
    ro.xz *= rot2D(-m.x); rd.xz *= rot2D(-m.x);
    ro.yz *= rot2D(-m.y); rd.yz *= rot2D(-m.y);

    float t = 0.;
    int i;
    for (i = 0; i < 120; i++) {
        vec3 p = ro + rd * t;
        float d = map(p);
        t += d;
        if (d < .001 || t > 20.) break;
    }

    vec3 col = vec3(float(i) / 120.);
    gl_FragColor = vec4(col, 1);
}