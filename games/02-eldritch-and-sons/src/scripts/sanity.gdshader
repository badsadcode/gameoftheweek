// sanity.gdshader : the world gets less trustworthy as your sanity drops.
// strength 0 = clear, 1 = barely holding on (vignette, colour drain, wobble, purple bleed).
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	vec2 uv = SCREEN_UV;
	float s = strength;
	uv.x += sin(uv.y * 18.0 + time * 2.0) * 0.004 * s;
	uv.y += cos(uv.x * 14.0 + time * 1.3) * 0.003 * s;
	vec3 c = texture(screen_tex, uv).rgb;
	float shift = 0.006 * s;
	c.r = mix(c.r, texture(screen_tex, uv + vec2(shift, 0.0)).r, s);
	c.b = mix(c.b, texture(screen_tex, uv - vec2(shift, 0.0)).b, s);
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grey) * vec3(0.85, 0.8, 1.05), s * 0.6);
	vec2 d = SCREEN_UV - 0.5;
	float vig = smoothstep(0.85, 0.25 - s * 0.15, length(d) * (1.0 + s * 0.6));
	c *= mix(1.0, vig, 0.35 + s * 0.6);
	c += vec3(0.25, 0.05, 0.35) * s * 0.25 * (0.5 + 0.5 * sin(time * 0.7));
	COLOR = vec4(c, 1.0);
}
