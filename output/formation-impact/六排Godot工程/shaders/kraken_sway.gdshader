shader_type canvas_item;
render_mode unshaded;

// Driven by the atlas clock, so hidden maps and dialogs hold the current pose.
uniform float sway_time = 0.0;
uniform float sway_period = 6.4;
uniform float sway_pixels = 1.0;

float tip_weight(vec2 pixel, vec2 tip, vec2 radius) {
	return 1.0 - smoothstep(0.25, 1.0, length((pixel - tip) / radius));
}

float sway(float phase, float delay) {
	// Every tip returns to the original pixels at time zero / reduced motion.
	return (sin(phase + delay) - sin(delay)) * 0.65;
}

void fragment() {
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	float phase = mod(sway_time, sway_period) / sway_period * TAU;
	vec2 offset = vec2(0.0);
	// Local tip fields follow this original 64px sprite; the body is never scaled.
	offset.x += tip_weight(pixel, vec2(31.0, 18.0), vec2(8.0, 8.0)) * sway(phase, 0.0);
	offset += tip_weight(pixel, vec2(47.0, 25.0), vec2(8.0, 7.0)) * vec2(sway(phase, 0.8), sway(phase, 1.5) * 0.5);
	offset.x += tip_weight(pixel, vec2(18.0, 34.0), vec2(8.0, 7.0)) * sway(phase, 2.1);
	offset.y += tip_weight(pixel, vec2(19.0, 42.0), vec2(9.0, 5.0)) * sway(phase, 3.0);
	offset.y += tip_weight(pixel, vec2(39.0, 44.0), vec2(10.0, 5.0)) * sway(phase, 4.2);
	offset.x += tip_weight(pixel, vec2(46.0, 37.0), vec2(6.0, 6.0)) * sway(phase, 5.0);
	// Freeze the eye/head rectangle and soften influence over the next 3 pixels.
	vec2 head_distance = max(max(vec2(21.0, 23.0) - pixel, pixel - vec2(32.0, 33.0)), vec2(0.0));
	offset *= smoothstep(0.0, 3.0, length(head_distance));
	// Sample whole source pixels only: no interpolated colours or blurry edges.
	vec2 sample_pixel = pixel + round(offset * sway_pixels);
	COLOR = texture(TEXTURE, (sample_pixel + vec2(0.5)) * TEXTURE_PIXEL_SIZE);
}
