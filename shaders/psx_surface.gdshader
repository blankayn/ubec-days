shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float vertex_snap = 360.0;
uniform float color_steps = 48.0;
uniform float creature_proximity = 0.0;
uniform float static_intensity = 0.0;
uniform float chromatic_offset = 0.0;

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip_position.xyz /= clip_position.w;
	float jitter = sin(TIME * 22.0 + VERTEX.x * 4.0) * creature_proximity * 0.003;
	clip_position.xy += vec2(jitter, -jitter);
	clip_position.xy = floor(clip_position.xy * vertex_snap) / vertex_snap;
	clip_position.xyz *= clip_position.w;
	POSITION = clip_position;
}

void fragment() {
	ALBEDO = floor(albedo_color.rgb * color_steps) / color_steps;
	ROUGHNESS = 1.0;
}
