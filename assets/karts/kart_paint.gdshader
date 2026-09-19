shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Blender COLOR_0: neutral grayscale RGB, paint mask in alpha (never transparency).
uniform vec4 paint_color : source_color = vec4(0.12, 0.58, 0.74, 1.0);
uniform vec4 feedback_color : source_color = vec4(1.0);
uniform float feedback_mix : hint_range(0.0, 1.0) = 0.0;
uniform float feedback_energy : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 tint = mix(paint_color.rgb, feedback_color.rgb, feedback_mix);
	ALBEDO = COLOR.rgb * mix(vec3(1.0), tint, COLOR.a);
	ROUGHNESS = 0.8;
	EMISSION = feedback_color.rgb * feedback_energy * COLOR.a;
}
