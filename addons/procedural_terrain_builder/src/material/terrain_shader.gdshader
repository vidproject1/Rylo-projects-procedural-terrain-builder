shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Procedural Terrain Shader with automatic Slope + Height based texturing, Triplanar mapping, and normal mapping.

// --- UNIFORMS ---
group_uniforms Texture_Scaling;
uniform float texture_scale : hint_range(0.001, 10.0) = 0.1;

group_uniforms Layer_Shoreline;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 sand_color : source_color = vec4(0.85, 0.75, 0.45, 1.0);
uniform float sand_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float sand_height_limit = 2.0;
uniform float sand_blend_margin = 1.0;
uniform bool tint_sand_texture = false;

group_uniforms Layer_Plains;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 grass_color : source_color = vec4(0.25, 0.55, 0.25, 1.0);
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.9;
uniform bool tint_grass_texture = false;

group_uniforms Layer_Slopes;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 dirt_color : source_color = vec4(0.45, 0.35, 0.25, 1.0);
uniform float dirt_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float dirt_slope_threshold : hint_range(0.0, 1.0) = 0.06;
uniform float dirt_slope_blend : hint_range(0.01, 1.0) = 0.1;
uniform bool tint_dirt_texture = false;

group_uniforms Layer_Cliffs;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 rock_color : source_color = vec4(0.45, 0.45, 0.45, 1.0);
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.7;
uniform float rock_slope_threshold : hint_range(0.0, 1.0) = 0.16;
uniform float rock_slope_blend : hint_range(0.01, 1.0) = 0.15;
uniform float rock_height_limit = 45.0;
uniform float rock_height_blend = 10.0;
uniform bool tint_rock_texture = false;

group_uniforms Layer_Painting;
uniform bool use_splatmap = false;
uniform sampler2D splat_map : source_color, filter_linear, hint_default_black;

group_uniforms Height_Blending;
uniform float height_blend_contrast : hint_range(0.01, 1.0) = 0.1;

group_uniforms Noise_Blending;
uniform float transition_noise_frequency : hint_range(0.01, 4.0) = 0.4;
uniform float transition_noise_amplitude : hint_range(0.0, 1.5) = 0.25;
uniform float splatmap_warp_strength : hint_range(0.0, 0.5) = 0.06;

group_uniforms Micro_Normal;
uniform bool use_micro_normal = false;
uniform sampler2D micro_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform float micro_normal_scale = 50.0;
uniform float micro_normal_strength : hint_range(0.0, 1.0) = 0.3;
uniform float micro_normal_distance : hint_range(5.0, 100.0) = 30.0;

group_uniforms Grass_Patchiness;
uniform bool enable_grass_patchiness = true;
uniform float grass_patch_frequency : hint_range(0.01, 2.0) = 0.15;
uniform float grass_patch_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float grass_patch_blend : hint_range(0.01, 1.0) = 0.25;
uniform float grass_macro_variation_frequency : hint_range(0.001, 0.5) = 0.015;
uniform vec4 grass_dry_color : source_color = vec4(0.45, 0.48, 0.22, 1.0);

group_uniforms Cliff_Enhancements;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 8.0;
uniform bool enable_strata = true;
uniform float strata_frequency : hint_range(0.05, 5.0) = 0.8;


// --- VARYINGS ---
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// Triplanar sampling function
vec4 sample_triplanar_albedo(sampler2D tex, vec3 pos, vec3 normal) {
	vec3 blend = abs(normal);
	blend = pow(blend, vec3(triplanar_sharpness));
	blend = normalize(max(blend, 0.00001));
	float b_sum = blend.x + blend.y + blend.z;
	blend /= b_sum;
	
	vec2 uv_x = pos.zy * texture_scale;
	vec2 uv_y = pos.xz * texture_scale;
	vec2 uv_z = pos.xy * texture_scale;
	
	vec4 s_x = texture(tex, uv_x);
	vec4 s_y = texture(tex, uv_y);
	vec4 s_z = texture(tex, uv_z);
	
	return s_x * blend.x + s_y * blend.y + s_z * blend.z;
}

vec3 sample_triplanar_normal(sampler2D tex, vec3 pos, vec3 normal) {
	vec3 blend = abs(normal);
	blend = pow(blend, vec3(triplanar_sharpness));
	blend = normalize(max(blend, 0.00001));
	float b_sum = blend.x + blend.y + blend.z;
	blend /= b_sum;
	
	vec2 uv_x = pos.zy * texture_scale;
	vec2 uv_y = pos.xz * texture_scale;
	vec2 uv_z = pos.xy * texture_scale;
	
	// Sample tangent space normals
	vec3 n_x = texture(tex, uv_x).xyz * 2.0 - 1.0;
	vec3 n_y = texture(tex, uv_y).xyz * 2.0 - 1.0;
	vec3 n_z = texture(tex, uv_z).xyz * 2.0 - 1.0;
	
	// Reorient normal vectors relative to their respective projection planes
	// X Plane (projection along X axis)
	// Tangent-space flat normal (0, 0, 1) maps to world normal (1, 0, 0)
	vec3 w_x = vec3(n_x.z, n_x.y, n_x.x) * vec3(sign(normal.x), 1.0, 1.0);
	
	// Y Plane (projection along Y axis)
	// Tangent-space flat normal (0, 0, 1) maps to world normal (0, 1, 0)
	vec3 w_y = vec3(n_y.x, n_y.z, n_y.y) * vec3(1.0, sign(normal.y), 1.0);
	
	// Z Plane (projection along Z axis)
	// Tangent-space flat normal (0, 0, 1) maps to world normal (0, 0, 1)
	vec3 w_z = vec3(n_z.x, n_z.y, n_z.z) * vec3(1.0, 1.0, sign(normal.z));
	
	// Blend and normalize
	return normalize(w_x * blend.x + w_y * blend.y + w_z * blend.z);
}

// Fast procedural 2D noise helpers for organic transitions
float procedural_noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float smooth_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	float a = procedural_noise(i + vec2(0.0, 0.0));
	float b = procedural_noise(i + vec2(1.0, 0.0));
	float c = procedural_noise(i + vec2(0.0, 1.0));
	float d = procedural_noise(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3-Octave Fractal Brownian Motion (FBM) for jagged, rugged boundaries
float fbm_noise(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 3; i++) {
		value += amplitude * smooth_noise(p * frequency);
		p *= 2.0;
		amplitude *= 0.5;
		frequency *= 1.8;
	}
	return value;
}

// Procedural height approximation if alpha channel is missing
float get_height_from_color(vec4 col) {
	if (col.a < 0.99) {
		return col.a;
	}
	// Fallback to luminance of albedo texture
	return dot(col.rgb, vec3(0.299, 0.587, 0.114));
}

// Height-based blending function
vec4 height_blend(vec4 weights, float h0, float h1, float h2, float h3, float contrast) {
	float a0 = weights.r + h0;
	float a1 = weights.g + h1;
	float a2 = weights.b + h2;
	float a3 = weights.a + h3;
	
	float max_h = max(max(a0, a1), max(a2, a3)) - contrast;
	
	vec4 b = vec4(
		max(a0 - max_h, 0.0),
		max(a1 - max_h, 0.0),
		max(a2 - max_h, 0.0),
		max(a3 - max_h, 0.0)
	);
	
	return b / (b.r + b.g + b.b + b.a + 0.0001);
}

// Reoriented Normal Mapping (RNM) for high-fidelity normal blending
vec3 blend_normals_rnm(vec3 base, vec3 detail) {
	base += vec3(0.0, 0.0, 1.0);
	detail *= vec3(-1.0, -1.0, 1.0);
	return base * dot(base, detail) / (base.z + 0.0001) - detail;
}

void fragment() {
	vec3 normal = normalize(v_world_normal);
	vec3 pos = v_world_pos;
	
	float grass_w = 0.0;
	float dirt_w  = 0.0;
	float rock_w  = 0.0;
	float sand_w  = 0.0;
	
	// Evaluate high-frequency fractal noise for organic transition boundaries
	float border_noise = (fbm_noise(pos.xz * transition_noise_frequency) - 0.45) * transition_noise_amplitude;
	
	if (use_splatmap) {
		// Warp the splatmap UV coordinates with multi-frequency noise to completely break rounded brush strokes
		vec2 warp = vec2(
			fbm_noise(pos.xz * 0.25),
			fbm_noise(pos.xz * 0.25 + vec2(5.2))
		) * 2.0 - 1.0;
		vec2 warped_uv = clamp(UV + warp * splatmap_warp_strength, 0.0, 1.0);
		
		vec4 splat = texture(splat_map, warped_uv);
		grass_w = splat.r;
		dirt_w  = splat.g;
		rock_w  = splat.b;
		sand_w  = splat.a;
	} else {
		// Domain-warp coordinates for the slope transition noise to break up straight/swirly lines
		vec2 warped_slope_uv = pos.xz + vec2(
			fbm_noise(pos.xz * 0.08),
			fbm_noise(pos.xz * 0.08 + vec2(10.0))
		) * 12.0;
		float slope_noise = (fbm_noise(warped_slope_uv * transition_noise_frequency) - 0.45) * transition_noise_amplitude;
		float slope = clamp(1.0 - normal.y + slope_noise, 0.0, 1.0);
		
		// 1. Calculate weights based on slope and height perturbed by FBM noise
		float rock_slope_w = clamp((slope - rock_slope_threshold) / rock_slope_blend, 0.0, 1.0);
		float rock_height_w = clamp((pos.y + border_noise * 25.0 - rock_height_limit) / rock_height_blend, 0.0, 1.0);
		rock_w = max(rock_slope_w, rock_height_w);
		
		// Dirt represents intermediate slope transit areas
		float dirt_slope_w = clamp((slope - dirt_slope_threshold) / dirt_slope_blend, 0.0, 1.0);
		dirt_w = dirt_slope_w * (1.0 - rock_w);
		
		// Sand represents coastal shoreline heights (make it highly jagged)
		float sand_h_perturbed = sand_height_limit + border_noise * 6.0;
		sand_w = clamp((sand_h_perturbed - pos.y) / sand_blend_margin, 0.0, 1.0) * (1.0 - rock_w) * (1.0 - dirt_w);
		
		// Grass represents the default flat terrain layer
		grass_w = clamp(1.0 - rock_w - dirt_w - sand_w, 0.0, 1.0);
	}
	
	// Apply high-frequency grass patchiness to break up flat grass fields (both procedural and splatmap)
	if (enable_grass_patchiness) {
		float patch_noise = fbm_noise(pos.xz * grass_patch_frequency);
		float patch_mask = clamp((patch_noise - grass_patch_threshold) / grass_patch_blend, 0.0, 1.0);
		
		float grass_to_dirt = grass_w * (1.0 - patch_mask);
		grass_w = grass_w * patch_mask;
		dirt_w += grass_to_dirt;
	}
	
	// Normalize layer weights to guarantee they sum to 1.0
	float total_w = grass_w + dirt_w + rock_w + sand_w;
	if (total_w > 0.0001) {
		grass_w /= total_w;
		dirt_w /= total_w;
		rock_w /= total_w;
		sand_w /= total_w;
	} else {
		grass_w = 1.0;
		dirt_w = 0.0;
		rock_w = 0.0;
		sand_w = 0.0;
	}
	
	// 2. Sample raw textures triplanarly
	vec4 grass_tex = sample_triplanar_albedo(grass_albedo, pos, normal);
	vec4 dirt_tex  = sample_triplanar_albedo(dirt_albedo, pos, normal);
	vec4 rock_tex  = sample_triplanar_albedo(rock_albedo, pos, normal);
	vec4 sand_tex  = sample_triplanar_albedo(sand_albedo, pos, normal);
	
	// Query texture dimensions to detect if a photo texture is assigned (empty/default textures are 1x1)
	bool has_grass = textureSize(grass_albedo, 0).x > 1;
	bool has_dirt  = textureSize(dirt_albedo, 0).x > 1;
	bool has_rock  = textureSize(rock_albedo, 0).x > 1;
	bool has_sand  = textureSize(sand_albedo, 0).x > 1;
	
	// Apply low-frequency color variation to the grass albedo for natural variation
	float macro_noise = smooth_noise(pos.xz * grass_macro_variation_frequency);
	vec4 target_grass_color = mix(grass_color, grass_dry_color, macro_noise);
	
	// Determine final colors: use raw texture if assigned, apply tint only if enabled, fallback to flat color if missing
	vec4 grass_col = has_grass ? (tint_grass_texture ? grass_tex * target_grass_color : grass_tex) : target_grass_color;
	vec4 dirt_col  = has_dirt  ? (tint_dirt_texture  ? dirt_tex  * dirt_color          : dirt_tex)  : dirt_color;
	vec4 rock_col  = has_rock  ? (tint_rock_texture  ? rock_tex  * rock_color          : rock_tex)  : rock_color;
	
	// Add vertical strata bands to rock cliffs
	if (enable_strata) {
		float strata_noise = fbm_noise(pos.xz * 0.15) * 1.5;
		float strata_val = sin(pos.y * strata_frequency + strata_noise);
		float strata_factor = mix(0.78, 1.05, smoothstep(-0.25, 0.25, strata_val));
		rock_col.rgb *= strata_factor;
	}
	
	vec4 sand_col  = has_sand  ? (tint_sand_texture  ? sand_tex  * sand_color          : sand_tex)  : sand_color;
	
	vec3 grass_norm = sample_triplanar_normal(grass_normal, pos, normal);
	vec3 dirt_norm  = sample_triplanar_normal(dirt_normal, pos, normal);
	vec3 rock_norm  = sample_triplanar_normal(rock_normal, pos, normal);
	vec3 sand_norm  = sample_triplanar_normal(sand_normal, pos, normal);
	
	// 3. Extract height displacement values
	float h_grass = get_height_from_color(grass_col);
	float h_dirt  = get_height_from_color(dirt_col);
	float h_rock  = get_height_from_color(rock_col);
	float h_sand  = get_height_from_color(sand_col);
	
	// 4. Calculate sharp height-blended weights
	vec4 base_weights = vec4(grass_w, dirt_w, rock_w, sand_w);
	vec4 blended_w = height_blend(base_weights, h_grass, h_dirt, h_rock, h_sand, height_blend_contrast);
	
	// 5. Blend Albedo, Normals, and Roughness using height-blended weights
	vec3 final_albedo = (grass_col.rgb * blended_w.r) + (dirt_col.rgb * blended_w.g) + (rock_col.rgb * blended_w.b) + (sand_col.rgb * blended_w.a);
	vec3 final_normal = normalize((grass_norm * blended_w.r) + (dirt_norm * blended_w.g) + (rock_norm * blended_w.b) + (sand_norm * blended_w.a));
	
	float final_roughness = (grass_roughness * blended_w.r) + (dirt_roughness * blended_w.g) + (rock_roughness * blended_w.b) + (sand_roughness * blended_w.a);
	
	// 6. Apply Micro-Normal Detail map with distance fade and RNM blending
	if (use_micro_normal) {
		vec2 detail_uv = pos.xz * micro_normal_scale;
		vec3 detail_norm = texture(micro_normal, detail_uv).rgb * 2.0 - 1.0;
		
		float camera_dist = distance(CAMERA_POSITION_WORLD, pos);
		float detail_fade = clamp(1.0 - (camera_dist - (micro_normal_distance * 0.2)) / (micro_normal_distance * 0.8), 0.0, 1.0);
		
		vec3 target_detail = mix(vec3(0.0, 0.0, 1.0), detail_norm, micro_normal_strength * detail_fade);
		final_normal = normalize(blend_normals_rnm(final_normal, target_detail));
	}
	
	// Write outputs to the spatial PBR fragment
	ALBEDO = final_albedo;
	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;
	ROUGHNESS = final_roughness;
	SPECULAR = 0.1; // Subdued specular for natural terrain look
}
