// HWR-GRASS-001 grass tile material: baked albedo/normal + vertex-colour wind mask.
// UV2.x = bend mask (0 dirt wall / grass root, 1 grass tip), UV2.y = part id. The dirt never moves.
// Wind phase is computed from WORLD position and TIME, so neighbouring tiles (and rotated
// instances) share one continuous wave. Works for MultiMesh (MODEL_MATRIX is per instance).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

group_uniforms wind;
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;   // 0 = exact rest pose
uniform vec2 wind_dir = vec2(1.0, 0.35);                    // world XZ
uniform float wind_speed = 1.6;                             // world units / s
uniform float wind_wavelength = 5.0;                        // world units per wave
uniform float wind_amplitude = 0.012;                       // world units at strength 1, mask 1 (~7% of 0.18 grass height)
uniform float wind_gust : hint_range(0.0, 1.0) = 0.45;      // slow strength modulation
uniform float wind_sheen : hint_range(0.0, 0.3) = 0.07;     // brightness ripple following the wave

varying float v_wind;
varying vec3 v_tint;

void vertex() {
	v_tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, INSTANCE_CUSTOM.a);   // per-instance tint (MultiMesh custom data)
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 d = normalize(wind_dir);
	float k = 6.2831853 / max(wind_wavelength, 0.01);
	float along = dot(wp.xz, d);
	float phase = k * (along - wind_speed * TIME);
	float sway = sin(phase) * 0.7 + sin(phase * 2.31 + 1.7) * 0.3;
	float gust = 1.0 + wind_gust * sin(0.37 * TIME + 0.22 * along + 0.9 * wp.z);
	float mask = UV2.x;
	float amount = wind_strength * mask * gust;
	// lean with the wind plus travelling sway; the mask keeps the wall/root fixed
	vec2 disp = d * wind_amplitude * amount * (0.35 + sway);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * vec3(disp.x, 0.0, disp.y);
	v_wind = sway * amount;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * v_tint * (1.0 + wind_sheen * v_wind);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	if (UV2.y > 0.75) {
		// fin cards: shade like the turf under them whichever side faces the camera (Godot flips back-face normals)
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	} else {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
