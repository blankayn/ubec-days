shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float virtual_height = 480.0;
uniform float color_steps = 32.0;
uniform float dither_strength = 0.4;
uniform float scanline_strength = 0.02;
uniform float vignette_strength = 0.42;
// Controlled by scare_manager via HUD material parameter:
uniform float fear_intensity = 0.0;   // 0..1 — ramps up chromatic ab, grain, distortion
uniform float time_offset = 0.0;      // set each frame for animated grain
uniform float creature_proximity = 0.0;
uniform float static_intensity = 0.0;
uniform float chromatic_offset = 0.0;

float noise_dither(vec2 pixel) {
	return fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
}

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(127.1, 311.7))) * 43758.5453);
}

// Barrel / CRT lens distortion
vec2 barrel_distort(vec2 uv, float strength) {
	vec2 cc = uv - 0.5;
	float dist = dot(cc, cc);
	return uv + cc * dist * strength;
}

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;

	// ── CRT barrel distortion (increases with fear) ───────────────────────────
	float threat = max(fear_intensity, creature_proximity);
	float barrel_strength = 0.05 + threat * 0.18;
	vec2 distorted_uv = barrel_distort(SCREEN_UV, barrel_strength);

	// Clamp so edges don't sample out-of-bounds (show black border)
	vec2 edge_mask_uv = clamp(distorted_uv, 0.0, 1.0);
	float in_bounds = step(0.001, distorted_uv.x) * step(distorted_uv.x, 0.999)
	                * step(0.001, distorted_uv.y) * step(distorted_uv.y, 0.999);

	vec2 virtual_size = vec2(virtual_height * screen_size.x / screen_size.y, virtual_height);
	vec2 snapped_uv = (floor(edge_mask_uv * virtual_size) + 0.5) / virtual_size;

	// ── Chromatic aberration (RGB split, grows with fear) ─────────────────────
	float ca_amount = 0.0015 + threat * 0.009 + chromatic_offset * 0.001;
	vec2 ca_offset = vec2(ca_amount, 0.0);
	float r = texture(screen_texture, clamp(snapped_uv + ca_offset, 0.0, 1.0)).r;
	float g = texture(screen_texture, snapped_uv).g;
	float b = texture(screen_texture, clamp(snapped_uv - ca_offset, 0.0, 1.0)).b;
	vec3 color = vec3(r, g, b) * in_bounds;

	// ── Dithering & color quantization ───────────────────────────────────────
	vec2 pixel = floor(edge_mask_uv * virtual_size);
	color += noise_dither(pixel) * dither_strength / color_steps;
	color = floor(clamp(color, 0.0, 1.0) * color_steps) / color_steps;

	// ── Scanlines ─────────────────────────────────────────────────────────────
	float scanline = mod(pixel.y, 2.0);
	color *= 1.0 - scanline * scanline_strength;

	// ── Animated film grain (more at high fear) ───────────────────────────────
	float grain_strength = 0.04 + threat * 0.14 + static_intensity * 0.24;
	float grain = rand(pixel + vec2(time_offset, time_offset * 1.3)) - 0.5;
	color += grain * grain_strength;

	// ── Vignette ─────────────────────────────────────────────────────────────
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float vignette = smoothstep(1.35, 0.25, length(centered * vec2(0.78, 1.0)));
	float v_strength = vignette_strength + threat * 0.3;
	color *= mix(1.0 - v_strength, 1.0, vignette);

	// ── Red tint at peak fear ─────────────────────────────────────────────────
	float static_line = step(0.82, rand(vec2(floor(pixel.y * 0.35), floor(time_offset * 22.0))));
	color = mix(color, vec3(rand(pixel + time_offset)), static_line * static_intensity * 0.62);
	float red_tint = threat * 0.12;
	color.r = clamp(color.r + red_tint, 0.0, 1.0);
	color.g = clamp(color.g - red_tint * 0.4, 0.0, 1.0);
	color.b = clamp(color.b - red_tint * 0.4, 0.0, 1.0);

	COLOR = vec4(color, 1.0);
}
