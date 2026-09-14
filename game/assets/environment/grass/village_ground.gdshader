// HWR-GRASS-001 R3: static village ground. One opaque terrain mesh, textures sampled in continuous
// world XZ (no per-cell UV restart, no per-cell random colour), grass/dirt blended by a data mask
// (R = dirt / path, G = keep the flat vertex colour of functional cells, B = forest shade).
// No displacement, no normal map, no time-dependent motion.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D variation_tex : hint_default_white, filter_linear_mipmap, repeat_enable;   // linear grey, mean 0.5
uniform sampler2D mask_tex : hint_default_black, filter_linear, repeat_disable;             // data, not colour
uniform vec2 map_origin = vec2(0.0, 0.0);          // world XZ of mask texel (0,0)
uniform vec2 map_size = vec2(32.0, 10.8);          // world XZ covered by the mask
uniform float grass_scale = 3.0;                   // world units per grass texture repeat
uniform float dirt_scale = 2.0;                    // world units per dirt texture repeat
uniform float variation_scale = 9.0;               // world units per variation repeat (large, soft blotches)
uniform float variation_amount : hint_range(0.0, 0.2) = 0.05;
uniform vec3 grass_tint : source_color = vec3(1.0);
uniform vec3 dirt_tint : source_color = vec3(1.0);
uniform float forest_shade : hint_range(0.0, 0.5) = 0.10;   // darkening of the forest-floor cells
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_world;
varying vec3 v_color;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_color = COLOR.rgb;
}

void fragment() {
	vec2 muv = (v_world.xz - map_origin) / map_size;
	vec4 m = texture(mask_tex, muv);
	if (any(lessThan(muv, vec2(0.0))) || any(greaterThan(muv, vec2(1.0)))) {
		m = vec4(0.0);   // beyond the village grid (backdrop plane): plain grass
	}
	vec3 g = texture(grass_tex, v_world.xz / grass_scale).rgb * grass_tint;
	vec3 d = texture(dirt_tex, v_world.xz / dirt_scale).rgb * dirt_tint;
	float var = texture(variation_tex, v_world.xz / variation_scale).r;
	g *= 1.0 + variation_amount * (var - 0.5) * 2.0;
	g *= 1.0 - forest_shade * m.b;
	vec3 base = mix(g, d, clamp(m.r, 0.0, 1.0));
	ALBEDO = mix(base, v_color, clamp(m.g, 0.0, 1.0));
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
