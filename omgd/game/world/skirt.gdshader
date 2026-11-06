// Land past the map edge: the map painting mirrored outward, a little darker, so no void shows.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D ground : source_color, filter_linear_mipmap, repeat_enable;
// x, z of the map's corner at uv 0 and its width, depth in Godot units.
uniform vec4 map_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float shade = 0.72;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world.xz - map_rect.xy) / map_rect.zw;
	vec2 cell = mod(uv, 2.0);
	uv = mix(cell, 2.0 - cell, step(1.0, cell));
	ALBEDO = texture(ground, uv).rgb * shade;
	ROUGHNESS = 1.0;
}
