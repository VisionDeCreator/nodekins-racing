shader_type spatial;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world_position.xz / 5.0;
    vec2 grid = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(0.001));
    float line = 1.0 - min(min(grid.x, grid.y), 1.0);
    vec2 major_p = world_position.xz / 25.0;
    vec2 major_grid = abs(fract(major_p - 0.5) - 0.5) / max(fwidth(major_p), vec2(0.001));
    float major_line = 1.0 - min(min(major_grid.x, major_grid.y), 1.0);
    ALBEDO = mix(vec3(0.16, 0.19, 0.22), vec3(0.30, 0.34, 0.38), line * 0.6 + major_line * 0.4);
    ROUGHNESS = 0.95;
}
