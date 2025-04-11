shader_type spatial;

// Water properties
uniform vec3 absorption_color : source_color = vec3(1.0, 0.533, 0);
uniform float absorption_scale : hint_range(0.0, 1.0) = 0.2;
uniform vec3 scattering_color : source_color = vec3(0.0, 0.767, 1.0);
uniform float scattering_scale : hint_range(0.0, 1.0) = 0.1;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.02;

// Wave properties
uniform float wave_speed : hint_range(0.0, 10.0) = 2.5;
uniform float wave_amplitude : hint_range(0.0, 0.3) = 0.05;
uniform float wave_frequency : hint_range(0.1, 5.0) = 1.0;

// Visibility properties
uniform float visibility_distance : hint_range(1.0, 100.0) = 20.0;
uniform float visibility_fade_power : hint_range(0.1, 10.0) = 2.0;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable;
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

void fragment() {
	vec2 refraction_offset = NORMAL.xy * refraction_strength;
	vec2 refracted_uv = clamp(SCREEN_UV + refraction_offset, 0.0, 1.0);
	
	float depth = texture(depth_texture, refracted_uv).r;
	
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(refracted_uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(refracted_uv * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = view.z;
	float water_depth = VERTEX.z - linear_depth;
	water_depth = max(water_depth, 0.0);
	
	// Apply Beer's Law for absorption
	vec3 absorption = exp(-absorption_color * water_depth * absorption_scale);
	vec3 scattering = scattering_color * clamp(water_depth, 0.0, 1.0) * scattering_scale;
	
	vec3 color = texture(screen_texture, refracted_uv).rgb;
	vec3 deep_water_color = vec3(0.0) * absorption + scattering;
	
	color = color * absorption;
	color = clamp(color + scattering, 0.0, 1.0);

	float visibility_factor = 1.0 - clamp(pow(water_depth / visibility_distance, visibility_fade_power), 0.0, 1.0);
	color = mix(deep_water_color, color, visibility_factor);
	
	ALBEDO = color;
	ROUGHNESS = 0.1;
}
