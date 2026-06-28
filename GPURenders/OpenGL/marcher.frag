uniform vec2 u_resolution;
uniform float u_time;
uniform vec2 u_mouse;


vec3 rot3D(vec3 p, vec3 axis, float angle){
    return mix(dot(axis,p) * axis, p, cos(angle))
    +cross(axis,p) * sin(angle);
}
float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

float sdBox (vec3 p, vec3 b) {
    vec3 q = abs(p)-b;
    return length(max(q,vec3(0.)))+min(max(q.x,max(q.y,q.z)),0.0);
    }

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5*(b-a)/k, 0., 1.);
    return mix(b, a, h) - k*h*(1.-h);
}

//dist to scene
float map(vec3 p) {
    vec3 spherePos;
    float sphere;
    vec3 boxP;
    float box;
    float ground;
    vec3 q;

    q = fract(p) - 0.5; // repeated space, each cell is -0.5 to 0.5

    spherePos = vec3(sin(u_time)*3., 0., 0.);
    sphere = sdSphere(p - spherePos, 1.);
    boxP = rot3D(q, vec3(0., 1., 0.), u_time);
    box = sdBox(boxP, vec3(.1));
    ground = p.y + .75;

    return min(ground, smin(sphere, box, 2.));
}


void main () {
    vec4 fragColor; //hold output color
    vec2 fragCoord = gl_FragCoord.xy; //gl_FragCoord: built in GLSL var, GPU automatically sets it to the pixel position this shader instance is computing
    //.xy: only takes x and y coords
    vec2 uv = (fragCoord* 2. - u_resolution.xy) / u_resolution.y;
    /*
    fragCoord            →  (0,0) to (800,600)       raw pixels
    fragCoord * 2.       →  (0,0) to (1600,1200)
    - u_resolution.xy    →  (-800,-600) to (800,600)  now centred at 0
    / u_resolution.y     →  (-1.33,-1) to (1.33,1)   scaled so height = 1
*/

    //initialization
    float yaw   = (u_mouse.x / u_resolution.x - 0.5) * 6.2832;
    float pitch = (u_mouse.y / u_resolution.y - 0.5) * 3.1416;
    vec3 ro = rot3D(rot3D(vec3(0,0,-3), vec3(0,1,0), yaw), vec3(1,0,0), pitch);
    vec3 rd = rot3D(rot3D(normalize(vec3(uv, 1)), vec3(0,1,0), yaw), vec3(1,0,0), pitch);
    vec3 col = vec3(0);
    float t = 0.; //total distance marched

    //raymarching
    for (int i= 0; i<80; i++) {
        vec3 p = ro+rd*t; //position along ray
        float d = map(p); //curr dist to scene
        t +=d; //march ray
        //col = vec3(i)/80.;
        if (d<.001 || t>100. ) break; //early stop if close enough

    }

    //coloring
    col = vec3(t*.2);
    

    gl_FragColor = vec4(col,1);
}