shader_type canvas_item;
render_mode unshaded;

// Preserve every source pixel's shape/alpha; only soften the UI palette.
uniform vec4 outline_color : source_color = vec4(0.827, 0.773, 0.627, 1.0);
uniform float flutter = 0.0;
uniform float flutter_phase = 0.0;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec2 uv = UV;
	// Optional one-source-pixel cloth motion on the map flag. Its pole stays fixed.
	float cloth = step(0.42, uv.x) * step(0.10, uv.y) * (1.0-step(0.62, uv.y));
	uv.x += sin(flutter_phase + uv.y*6.0) * (0.8/32.0) * cloth * flutter;
	vec4 pixel = texture(TEXTURE, uv);
	float darkest = min(pixel.r, min(pixel.g, pixel.b));
	float brightest = max(pixel.r, max(pixel.g, pixel.b));
	float white = smoothstep(0.86, 0.98, darkest) * (1.0-smoothstep(0.04, 0.13, brightest-darkest));
	pixel.rgb = mix(pixel.rgb * vec3(0.98, 0.97, 0.94), outline_color.rgb, white);
	COLOR = pixel * vertex_tint;
}
