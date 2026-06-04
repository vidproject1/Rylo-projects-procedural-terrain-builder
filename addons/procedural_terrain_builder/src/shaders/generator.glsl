#[compute]
#version 450

// GLSL Compute Shader for instantaneous GPU-based realistic terrain generation
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer Heightmap {
    float heights[];
};

layout(push_constant) uniform Params {
    int width;
    int depth;
    int seed;
    float frequency;
    int octaves;
    float persistence;
    float lacunarity;
    float warp_amplitude;
    float mountain_influence;
    int terrace_count;
    float terrace_strength;
} params;

// Fast hash for procedural 2D noise
float hash2d(vec2 p, int seed_offset) {
    uint s = uint(params.seed + seed_offset);
    uint state = uint(p.x * 127.1 + p.y * 311.7) * 747796405u + s;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    uint res = (word >> 22u) ^ word;
    return float(res) / 4294967295.0;
}

// 2D Value Noise with Hermite interpolation
float noise2d(vec2 p, int seed_offset) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    float a = hash2d(i + vec2(0.0, 0.0), seed_offset);
    float b = hash2d(i + vec2(1.0, 0.0), seed_offset);
    float c = hash2d(i + vec2(0.0, 1.0), seed_offset);
    float d = hash2d(i + vec2(1.0, 1.0), seed_offset);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion (FBM) noise
float fbm(vec2 p, int seed_offset) {
    float value = 0.0;
    float amplitude = 0.5;
    float freq = params.frequency;
    for (int i = 0; i < params.octaves; i++) {
        value += amplitude * noise2d(p * freq, seed_offset);
        p *= params.lacunarity;
        amplitude *= params.persistence;
    }
    return value;
}

// Ridged Multi-fractal noise for sharp alpine peaks
float ridged(vec2 p, int seed_offset) {
    float value = 0.0;
    float amplitude = 0.5;
    float freq = params.frequency * 1.5;
    float weight = 1.0;
    
    for (int i = 0; i < params.octaves + 1; i++) {
        float n = noise2d(p * freq, seed_offset);
        // Invert noise to create sharp ridges
        n = 1.0 - abs(n * 2.0 - 1.0);
        n = n * n * weight;
        weight = clamp(n * 2.0, 0.0, 1.0);
        
        value += n * amplitude;
        p *= params.lacunarity;
        amplitude *= params.persistence * 0.9;
    }
    return value;
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint z = gl_GlobalInvocationID.y;
    
    if (x >= params.width || z >= params.depth) {
        return;
    }
    
    vec2 pos = vec2(float(x), float(z));
    
    // 1. Domain Warping coordinates
    vec2 warp_offset = vec2(
        fbm(pos * 2.0, 300) - 0.5,
        fbm(pos * 2.0 + vec2(100.0), 300) - 0.5
    ) * params.warp_amplitude;
    
    vec2 warped_pos = pos + warp_offset;
    
    // 2. Base rolling valleys (FBM)
    float valley_h = fbm(warped_pos, 0);
    
    // 3. Alpine mountain ridges (Ridged)
    float mountain_h = ridged(warped_pos, 100);
    
    // 4. Mountain placement mask
    float mask_val = clamp((noise2d(warped_pos * params.frequency * 0.4, 200) - 0.2) * 1.8, 0.0, 1.0);
    
    // 5. Blend plains and mountains
    float final_val = mix(valley_h * 0.25, mountain_h * params.mountain_influence + 0.15, mask_val);
    
    // 6. Apply sedimentary terracing on steeper slopes
    if (params.terrace_strength > 0.01 && final_val > 0.35) {
        float slope_weight = clamp((final_val - 0.35) / 0.3, 0.0, 1.0);
        float step_val = floor(final_val * float(params.terrace_count)) / float(params.terrace_count);
        final_val = mix(final_val, step_val, slope_weight * params.terrace_strength);
    }
    
    heights[z * params.width + x] = clamp(final_val, 0.0, 1.0);
}
