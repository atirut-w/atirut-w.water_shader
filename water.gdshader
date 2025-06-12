shader_type spatial;

// Water properties
uniform vec3 absorption_color : source_color = vec3(1.0, 0.533, 0);
uniform float concentration : hint_range(0.0, 10.0) = 1.0; // Concentration of the water
uniform float fog_density : hint_range(0.0, 1.0) = 0.5; // Density of the fog
uniform float scatter_power : hint_range(0.0, 1.0) = 0.25; // Power of the scattering effect
uniform float anisotropy : hint_range(-1.0, 1.0) = 0.5; // Anisotropy of the scattering

// Wave properties
uniform float wave_speed : hint_range(0.0, 10.0) = 2.5;
uniform float wave_amplitude : hint_range(0.0, 0.3) = 0.05;
uniform float wave_frequency : hint_range(0.1, 5.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, source_color, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable;

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
	float depth = VERTEX.z - get_pixel_coordinates(SCREEN_UV, INV_PROJECTION_MATRIX).z;
	vec3 transmittance = exp(-absorption_color * depth * concentration);
	float fog_mask = 1.0 - exp(-fog_density * depth);

	// TODO: Refraction effect
	vec3 underwater_color = texture(screen_texture, SCREEN_UV).rgb;
	underwater_color *= transmittance;
	underwater_color = mix(underwater_color, vec3(0.0), fog_mask);

	// Unconventional, but here's the idea: instead of using the albedo to
	// output what's underwater, we use the emission channel, which is unlit.
	// This way, the underwater is lit more realistically.
	ALBEDO = vec3(1) - absorption_color;
	EMISSION = vec3(underwater_color); // TODO: Absorption color
	ROUGHNESS = 0.1;
}

void light() {
	float cosTheta = dot(VIEW, -LIGHT);
	float phase = (1.0 - anisotropy * anisotropy) / pow(1.0 + anisotropy * anisotropy - 2.0 * anisotropy * cosTheta, 1.5);
	phase *= 0.25 / PI;

	DIFFUSE_LIGHT += phase * ATTENUATION * LIGHT_COLOR * scatter_power;

	// I literally just copied this from the Godot source code because they
	// did not document how to do the specular blob in a custom light function.
	vec3 H = normalize(VIEW + LIGHT);
	float cNdotH = max(dot(NORMAL, H), 0.0);
	float cNdotL = max(dot(NORMAL, LIGHT), 0.0);
	float shininess = exp2(15.0 * (1.0 - clamp(ROUGHNESS, 0.01, 1.0)) + 1.0) * 0.25;
	float blinn = pow(cNdotH, shininess) * cNdotL;
	blinn *= (shininess + 8.0) * (1.0 / (8.0 * PI));
	SPECULAR_LIGHT += LIGHT_COLOR * blinn * ATTENUATION;
}
