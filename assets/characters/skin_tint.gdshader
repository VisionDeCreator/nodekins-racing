shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec4 skin_tone : source_color = vec4(0.894, 0.686, 0.510, 1.0);
void fragment() {
	ALBEDO = COLOR.rgb * skin_tone.rgb;
	ROUGHNESS = 0.9;
}
