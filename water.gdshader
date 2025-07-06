shader_type spatial;
render_mode world_vertex_coords;

// Water properties
uniform sampler2D normal_texture : hint_normal; // Normal map for water surface
uniform float normal_scale = 0.25; // Scale of the normal map
uniform float normal_speed = 0.5; // Speed of the normal map animation
uniform vec3 absorption_color : source_color = vec3(1.0, 0.8, 0);
uniform float concentration : hint_range(0.01, 10.0) = 1.0; // Concentration of the water
uniform float scatter_power : hint_range(0.0, 1.0) = 0.25; // Power of the scattering effect
uniform float anisotropy : hint_range(-1.0, 1.0) = 0.5; // Anisotropy of the scattering

// Wave properties
uniform float wave_speed : hint_range(0.0, 10.0) = 2.5;
uniform float wave_amplitude : hint_range(0.0, 0.3) = 0.05;
uniform float wave_frequency : hint_range(0.1, 5.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, source_color, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable;

varying vec3 world_coords;

void vertex() {
	// More complex wave animation with multiple frequencies
	float time = TIME * wave_speed;

	// Primary wave
	float wave1 = sin(VERTEX.x * wave_frequency + time) * 
				cos(VERTEX.z * wave_frequency * 0.8 + time * 0.7) * wave_amplitude;

	// Secondary waves for more natural look
	float wave2 = sin(VERTEX.x * wave_frequency * 2.3 + time * 1.1) * 
				sin(VERTEX.z * wave_frequency * 1.8 + time * 0.9) * wave_amplitude * 0.3;

	VERTEX.y += wave1 + wave2;
	world_coords = VERTEX;

	// Adjust normals for lighting
	NORMAL = normalize(vec3(
		-cos(VERTEX.x * wave_frequency + time) * wave_amplitude * wave_frequency,
		1.0,
		-sin(VERTEX.z * wave_frequency * 0.8 + time * 0.7) * wave_amplitude * wave_frequency * 0.8
	));
}

vec3 get_pixel_coordinates(vec2 uv, mat4 inv_projection_matrix) {
	float depth = texture(depth_texture, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return view.xyz;
}

void fragment() {
	float depth = max(0.0, VERTEX.z - get_pixel_coordinates(SCREEN_UV, INV_PROJECTION_MATRIX).z);
	vec3 transmittance = exp(-absorption_color * concentration * depth);
	float fog_mask = 1.0 - exp(-concentration * depth);

	// TODO: Probably improve this
	vec2 normal_uv = world_coords.xz * normal_scale;
	vec3 normal1 = texture(normal_texture, normal_uv + vec2(TIME * normal_speed, 0.0) * normal_scale).rgb;
	vec3 normal2 = texture(normal_texture, normal_uv + vec2(0.0, TIME * normal_speed / 2.0) * normal_scale).rgb;
	vec3 normal = normal1 * 0.5 + normal2 * 0.5;
	NORMAL_MAP = normal;

	// TODO: Refraction effect
	vec3 underwater_color = texture(screen_texture, SCREEN_UV).rgb;
	underwater_color *= transmittance;
	underwater_color = mix(underwater_color, vec3(0.0), fog_mask);
	EMISSION = vec3(underwater_color);

	// Unconventional, but here's the idea: instead of using the albedo to
	// output what's underwater, we use the emission channel, which is unlit.
	// This way, the underwater is lit independently of the surface lighting.
	ALBEDO = vec3(1) - absorption_color;
	ROUGHNESS = 0.1;
}

float roughness_to_shininess(float roughness) {
	float r = 1.2 - roughness;
	float r2 = r * r;
	return r * r2 * r2 * 2000.0;
}

void light() {
	float cosTheta = dot(VIEW, -LIGHT);
	float phase = (1.0 - anisotropy * anisotropy) / pow(1.0 + anisotropy * anisotropy - 2.0 * anisotropy * cosTheta, 1.5);
	phase *= 0.25 / PI;

	DIFFUSE_LIGHT += phase * ATTENUATION * LIGHT_COLOR * scatter_power;

	// I literally just copied this from the Godot source code because they
	// did not document how to do the specular blob in a custom light function.
	// Source: https://github.com/godotengine/godot/blob/d50381065445e04b5c1af9992fa0a0b8fcfe49b0/drivers/gles3/shaders/scene.glsl#L353
	float NdotL = min(dot(NORMAL, LIGHT), 1.0);
	float cNdotL = max(NdotL, 0.0);
	float specular_brdf_NL = 0.0;
	// Normalized blinn always unless disabled.
	vec3 H = normalize(VIEW + LIGHT);
	float cNdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
	float shininess = roughness_to_shininess(ROUGHNESS);
	float blinn = pow(cNdotH, shininess);
	blinn *= (shininess + 2.0) * (1.0 / (8.0 * PI)) * cNdotL;
	specular_brdf_NL = blinn;
	// HACK: The divide isn't originally in the Godot source code, but the
	// resulting specular light is way too strong without it.
	SPECULAR_LIGHT += specular_brdf_NL * ATTENUATION * LIGHT_COLOR / 10.0;
}
