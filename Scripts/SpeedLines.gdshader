shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed_ratio : hint_range(0.0, 1.0) = 0.0;
uniform vec3 camera_velocity = vec3(0.0);
uniform vec4 line_color : source_color = vec4(1.0);
uniform float line_density : hint_range(8.0, 256.0) = 70.0;
uniform float line_width : hint_range(0.0, 0.5) = 0.15;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.2;
uniform float edge_softness : hint_range(0.01, 0.5) = 0.15;
uniform float dash_frequency : hint_range(0.1, 10.0) = 1.6;
uniform float min_length : hint_range(0.01, 1.0) = 0.15;
uniform float max_length : hint_range(0.01, 1.0) = 0.85;
uniform float min_flow_speed : hint_range(0.0, 10.0) = 0.5;
uniform float max_flow_speed : hint_range(0.0, 10.0) = 3.0;
uniform float softness : hint_range(0.001, 0.5) = 0.08;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float dist = length(p);
	vec2 radial = dist > 0.0001 ? p / dist : vec2(0.0);

	vec2 lateral = vec2(camera_velocity.x, -camera_velocity.y);
	vec2 flow = radial * -camera_velocity.z + lateral;
	float flow_length = length(flow);
	vec2 flow_dir = flow_length > 0.0001 ? flow / flow_length : radial;
	vec2 flow_perp = vec2(-flow_dir.y, flow_dir.x);

	float along = dot(p, flow_dir);
	float across = dot(p, flow_perp);
	float lanes = across * line_density;
	float lane_fraction = fract(lanes);
	float lane_distance = min(lane_fraction, 1.0 - lane_fraction);
	float line_mask = 1.0 - smoothstep(0.0, line_width, lane_distance);
	float seed = hash11(floor(lanes));

	float flow_speed = mix(min_flow_speed, max_flow_speed, speed_ratio);
	float scroll = along * dash_frequency - TIME * flow_speed * (0.4 + seed * 0.6);
	float phase = fract(scroll + seed);
	float length_scale = mix(min_length, max_length, speed_ratio) * (0.6 + seed * 0.4);
	float dash = smoothstep(0.0, softness, phase);
	dash *= 1.0 - smoothstep(length_scale - softness, length_scale, phase);

	float edge_mask = smoothstep(inner_radius, inner_radius + edge_softness, dist);
	float alpha = intensity * line_mask * dash * edge_mask * (0.35 + 0.65 * seed);

	COLOR = vec4(line_color.rgb, line_color.a * alpha);
}
