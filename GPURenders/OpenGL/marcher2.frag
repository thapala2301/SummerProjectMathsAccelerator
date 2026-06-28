uniform vec2 u_resolution;
uniform float u_time;


float sdSphere (vec3 p, float r) {
    //vector p from origin to current ray point, radius r
    return length(p)-r;
}


float map(vec3 p){
    return sdSphere(p,1.);
}

vec3 calcNormal(vec3 p){
    vec2 e = vec2(.001, 0);
    return normalize(vec3(
        map(p+e.xyy)- map(p-e.xyy), //how much dist change in x
        map(p+e.yxy) - map (p-e.yxy), //how much dist change in y
        map(p+e.yyx) - map(p-e.yyx) //how much dist change in z
    ));
}

void main() {
    //GLSL vars
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = (fragCoord*2. - u_resolution.xy) / u_resolution.y;
    //clipscale
    
    //position vectors for scene
    vec3 ro = vec3 (0,0,-3);
    vec3 rd = normalize(vec3(uv,1));
    float t = 0.;
    vec3 p = vec3(0);

    //marching the ray
    for (int i=0; i<80; i++){
        p = ro+rd*t;
        float d = map(p);
        t+=d;
        if(d<.001 || t> 100.) break;
    }

    vec3 col = vec3(0);
    if (t<100.) {
        vec3 p = ro+rd*t;
        vec3 normal = calcNormal(p);
        vec3 light = normalize(vec3(1,2,-1));
        float diff = dot(normal, light);
        col = vec3(diff);
    }

    gl_FragColor = vec4(col, 1);
}