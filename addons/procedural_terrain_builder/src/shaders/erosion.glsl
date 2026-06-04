#[compute]
#version 450

// GLSL Compute Shader for high-performance particle-based hydraulic erosion
layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer Heightmap {
    float heights[];
};

// PCG Hash for fast, high-quality GPU pseudo-random numbers
uint pcg_hash(uint seed) {
    uint state = seed * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float random_float(inout uint seed) {
    seed = pcg_hash(seed);
    return float(seed) / 4294967295.0;
}

// Push constants for uniforms passed from GDScript
layout(push_constant) uniform Params {
    int width;
    int depth;
    int max_lifetime;
    float inertia;
    float gravity;
    float capacity_factor;
    float deposition_rate;
    float erosion_rate;
    float evaporation_rate;
    float min_capacity;
    uint frame_seed;
} params;

void main() {
    uint gid = gl_GlobalInvocationID.x;
    uint seed = gid + params.frame_seed;
    
    // 1. Spawn a droplet at a random coordinate on the heightmap (excluding borders)
    float px = random_float(seed) * (float(params.width) - 3.0) + 1.0;
    float py = random_float(seed) * (float(params.depth) - 3.0) + 1.0;
    
    float vx = 0.0;
    float vy = 0.0;
    float speed = 1.0;
    float water = 1.0;
    float sediment = 0.0;
    
    for (int step = 0; step < params.max_lifetime; ++step) {
        int ix = int(px);
        int iy = int(py);
        float tx = px - float(ix);
        float ty = py - float(iy);
        
        int idx00 = iy * params.width + ix;
        int idx10 = iy * params.width + (ix + 1);
        int idx01 = (iy + 1) * params.width + ix;
        int idx11 = (iy + 1) * params.width + (ix + 1);
        
        // Safety bounds check
        if (idx11 >= params.width * params.depth) {
            break;
        }
        
        // Sample surrounding heights for gradient calculations
        float h00 = heights[idx00];
        float h10 = heights[idx10];
        float h01 = heights[idx01];
        float h11 = heights[idx11];
        
        // Calculate bilinear slope gradient pointing downhill
        float grad_x = (h10 - h00) * (1.0 - ty) + (h11 - h01) * ty;
        float grad_y = (h01 - h00) * (1.0 - tx) + (h11 - h10) * tx;
        
        // Update droplet direction and position
        vx = vx * params.inertia - grad_x * (1.0 - params.inertia);
        vy = vy * params.inertia - grad_y * (1.0 - params.inertia);
        
        // Normalize direction vector
        float len = sqrt(vx * vx + vy * vy);
        if (len > 0.0001) {
            vx /= len;
            vy /= len;
        } else {
            // Drop random direction if in completely flat region
            float angle = random_float(seed) * 6.28318;
            vx = cos(angle);
            vy = sin(angle);
        }
        
        float next_px = px + vx;
        float next_py = py + vy;
        
        // Terminate droplet if it exits the heightmap boundaries
        if (next_px < 1.0 || next_px >= float(params.width) - 2.0 || next_py < 1.0 || next_py >= float(params.depth) - 2.0) {
            break;
        }
        
        int next_ix = int(next_px);
        int next_iy = int(next_py);
        float next_tx = next_px - float(next_ix);
        float next_ty = next_py - float(next_iy);
        
        int n_idx00 = next_iy * params.width + next_ix;
        int n_idx10 = next_iy * params.width + (next_ix + 1);
        int n_idx01 = (next_iy + 1) * params.width + next_ix;
        int n_idx11 = (next_iy + 1) * params.width + (next_ix + 1);
        
        float nh00 = heights[n_idx00];
        float nh10 = heights[n_idx10];
        float nh01 = heights[n_idx01];
        float nh11 = heights[n_idx11];
        
        // Interpolate current and next heights
        float h_current = h00 * (1.0 - tx) * (1.0 - ty) + h10 * tx * (1.0 - ty) + h01 * (1.0 - tx) * ty + h11 * tx * ty;
        float h_next = nh00 * (1.0 - next_tx) * (1.0 - next_ty) + nh10 * next_tx * (1.0 - next_ty) + nh01 * (1.0 - next_tx) * next_ty + nh11 * next_tx * next_ty;
        
        float delta_h = h_next - h_current;
        
        // Accelerate speed based on gravity and steepness
        speed = sqrt(max(0.0, speed * speed + delta_h * params.gravity));
        
        if (speed < 0.0001) {
            break;
        }
        
        // Calculate carrying capacity
        float slope = -delta_h;
        float capacity = max(speed * water * slope * params.capacity_factor, params.min_capacity);
        
        if (sediment > capacity || delta_h > 0.0) {
            // Deposit excess sediment
            float deposit_amount = (delta_h > 0.0) ? min(delta_h, sediment) : (sediment - capacity) * params.deposition_rate;
            sediment -= deposit_amount;
            
            // Distribute sediment bilinearly back onto the heightmap
            heights[idx00] += deposit_amount * (1.0 - tx) * (1.0 - ty);
            heights[idx10] += deposit_amount * tx * (1.0 - ty);
            heights[idx01] += deposit_amount * (1.0 - tx) * ty;
            heights[idx11] += deposit_amount * tx * ty;
        } else {
            // Erode soil
            float erode_amount = min((capacity - sediment) * params.erosion_rate, -delta_h);
            sediment += erode_amount;
            
            // Distribute erosion bilinearly
            heights[idx00] = max(0.0, heights[idx00] - erode_amount * (1.0 - tx) * (1.0 - ty));
            heights[idx10] = max(0.0, heights[idx10] - erode_amount * tx * (1.0 - ty));
            heights[idx01] = max(0.0, heights[idx01] - erode_amount * (1.0 - tx) * ty);
            heights[idx11] = max(0.0, heights[idx11] - erode_amount * tx * ty);
        }
        
        // Evaporate water volume and update positions
        water *= (1.0 - params.evaporation_rate);
        px = next_px;
        py = next_py;
    }
}
