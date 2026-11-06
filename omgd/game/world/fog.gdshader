// Full-screen fog of war. Darkens whatever is drawn, walls and ground alike, from the team grid.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D fog_texture : repeat_disable, filter_linear;
// origin x, origin y, width, height of the grid in Godot x and backend-signed z.
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float unseen_alpha = 0.92;
uniform float explored_alpha = 0.55;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view /= view.w;
	vec3 world = (INV_VIEW_MATRIX * view).xyz;
	vec2 uv = (vec2(world.x, -world.z) - fog_rect.xy) / fog_rect.zw;
	// Outside the grid nothing can be seen; the land there reads as explored, never as a black void.
	bool outside = uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0;
	float sight = outside ? 0.5 : texture(fog_texture, uv).r;
	float explored = smoothstep(0.0, 0.5, sight);
	float visible = smoothstep(0.5, 1.0, sight);
	ALBEDO = vec3(0.002, 0.003, 0.006);
	ALPHA = mix(mix(unseen_alpha, explored_alpha, explored), 0.0, visible);
}
