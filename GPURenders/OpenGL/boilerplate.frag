#ifdef GL_ES
precision mediump float;
#endif

//uniform: value same for every px, set by CPU (glslViewer) and read by GPU
uniform vec2 u_resolution;
uniform float u_time;

// glslViewer uses u_resolution / u_time instead of iResolution / iTime
void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = (fragCoord * 2.0 - u_resolution.xy) / u_resolution.y;

    vec3 ro = vec3(0, 0, -3);
    vec3 rd = normalize(vec3(uv, 1));
    vec3 col = vec3(0);
    float t = 0.;

    for (int i = 0; i < 80; i++) {
        vec3 p = ro + rd * t;
        // float d = map(p);  // define your SDF here
        // t += d;
    }

    gl_FragColor = vec4(uv, 0, 1);
}
