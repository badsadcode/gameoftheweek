// sanity.gdshader : every full-screen effect in one pass.
//   strength : sanity loss (0 = fine, 1 = barely holding on): wobble, colour drain, purple bleed
//   grain    : gentle film noise
//   vhs      : wobbly old tape: line jitter, colour bleed, a rolling tracking band, soft blur
//   crt      : scanlines + rounded vignette
//   pixels   : chunky low-res picture
// Each switch is 0 or 1 (toggled in Settings); they stack.
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform float grain = 1.0;
uniform float vhs = 0.0;
uniform float crt = 0.0;
uniform float pixels = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 sample_screen(vec2 uv) { return texture(screen_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb; }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float s = strength;

	// retro pixels: snap to a ~1/3 resolution grid
	if (pixels > 0.5) {
		vec2 grid = floor(res / 3.0);
		uv = (floor(uv * grid) + 0.5) / grid;
	}
	// sanity wobble
	uv.x += sin(uv.y * 18.0 + time * 2.0) * 0.004 * s;
	uv.y += cos(uv.x * 14.0 + time * 1.3) * 0.003 * s;

	// VHS: per-line jitter and a tracking band that rolls up the screen
	float band = 0.0;
	if (vhs > 0.5) {
		float line = floor(uv.y * res.y / 2.0);
		uv.x += (hash(vec2(line, floor(time * 24.0))) - 0.5) * 0.0018;
		float band_y = fract(time * 0.07);
		band = smoothstep(0.035, 0.0, abs(uv.y - band_y));
		uv.x += band * 0.008 * sin(time * 40.0 + uv.y * 300.0);
	}

	vec3 c = sample_screen(uv);
	float shift = 0.006 * s + 0.0025 * vhs;
	if (shift > 0.0) {
		c.r = mix(c.r, sample_screen(uv + vec2(shift, 0.0)).r, min(1.0, s + vhs));
		c.b = mix(c.b, sample_screen(uv - vec2(shift, 0.0)).b, min(1.0, s + vhs));
	}
	if (vhs > 0.5) {
		// soft horizontal blur, faded colours, tape noise in the band
		vec3 blur = (sample_screen(uv + vec2(SCREEN_PIXEL_SIZE.x * 2.0, 0.0)) + sample_screen(uv - vec2(SCREEN_PIXEL_SIZE.x * 2.0, 0.0))) * 0.5;
		c = mix(c, blur, 0.45);
		float g = dot(c, vec3(0.3, 0.59, 0.11));
		c = mix(c, vec3(g), 0.18) * vec3(1.02, 0.98, 1.04);
		c += band * (hash(uv * res + time) - 0.3) * 0.2;
	}

	// sanity colour drain + purple bleed
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grey) * vec3(0.85, 0.8, 1.05), s * 0.6);
	vec2 d = SCREEN_UV - 0.5;
	float vig = smoothstep(0.85, 0.25 - s * 0.15, length(d) * (1.0 + s * 0.6));
	c *= mix(1.0, vig, 0.35 + s * 0.6);
	c += vec3(0.25, 0.05, 0.35) * s * 0.25 * (0.5 + 0.5 * sin(time * 0.7));

	// CRT scanlines + rounded corners
	if (crt > 0.5) {
		float scan = 0.82 + 0.18 * sin(SCREEN_UV.y * res.y * 3.14159);
		c *= scan;
		float corner = smoothstep(0.75, 0.55, length(d * vec2(1.0, 0.9)) * 1.25);
		c *= mix(0.55, 1.0, corner);
	}

	// gentle film grain (always last so it sits on top)
	if (grain > 0.5) {
		float n = hash(SCREEN_UV * res + fract(time * 7.13) * 100.0) - 0.5;
		c += n * (0.045 + 0.05 * s);
	}
	COLOR = vec4(c, 1.0);
}
