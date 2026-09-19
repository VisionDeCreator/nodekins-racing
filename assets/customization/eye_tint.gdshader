shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec4 eye_color : source_color = vec4(0.05,0.5,0.7,1);
void fragment() {
	// Original face mesh has blue irises; whites, pupils and facial accents stay intact.
	float iris = float(COLOR.r < 0.06 && COLOR.g > 0.05 && COLOR.b > 0.08);
	ALBEDO = mix(COLOR.rgb,eye_color.rgb,iris);
	ROUGHNESS = 0.9;
}
