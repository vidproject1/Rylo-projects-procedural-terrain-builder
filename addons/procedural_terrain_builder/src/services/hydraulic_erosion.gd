@tool
extends RefCounted
class_name HydraulicErosion

## Service responsible for droplet-based hydraulic erosion (water-based terrain sculpting).
## Simulates rain drops landing, flowing downhill, dissolving soil, depositing sediment, and evaporating.

class Droplet:
	var pos: Vector2
	var dir: Vector2 = Vector2.ZERO
	var speed: float = 1.0
	var water: float = 1.0
	var sediment: float = 0.0

## Simulates particle-based hydraulic erosion.
## Returns an array of coordinates of affected chunks for localized rebuilding.
static func erode(
	terrain_data: TerrainData, 
	num_droplets: int = 50000, 
	max_lifetime: int = 30,
	inertia: float = 0.05,
	gravity: float = 4.0,
	capacity_factor: float = 4.0,
	deposition_rate: float = 0.1,
	erosion_rate: float = 0.1,
	evaporation_rate: float = 0.02,
	min_capacity: float = 0.01,
	brush_radius: int = 3
) -> Array[Vector2i]:
	
	if not terrain_data:
		return []
		
	terrain_data.ensure_initialized()
	var width = terrain_data.width
	var depth = terrain_data.depth
	var chunk_size = terrain_data.chunk_size
	var affected_chunks: Array[Vector2i] = []
	
	# Load heightmap into a flat array for high-performance reading/writing
	var map_data = PackedFloat32Array()
	map_data.resize(width * depth)
	for z in range(depth):
		for x in range(width):
			map_data[z * width + x] = terrain_data.get_height(x, z)
			
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Precalculate brush weights for spatial erosion distribution
	var brush_weights = []
	var brush_offsets = []
	var weight_sum = 0.0
	for dy in range(-brush_radius, brush_radius + 1):
		for dx in range(-brush_radius, brush_radius + 1):
			var dist = sqrt(dx * dx + dy * dy)
			if dist <= brush_radius:
				var w = 1.0 - (dist / brush_radius)
				brush_weights.append(w)
				brush_offsets.append(Vector2i(dx, dy))
				weight_sum += w
				
	# Normalize brush weights to sum to 1.0
	for i in range(brush_weights.size()):
		brush_weights[i] /= weight_sum

	# Main droplet simulation loop
	for d_idx in range(num_droplets):
		var d = Droplet.new()
		d.pos = Vector2(rng.randf_range(1.0, width - 2.0), rng.randf_range(1.0, depth - 2.0))
		
		for step in range(max_lifetime):
			var ix = int(d.pos.x)
			var iz = int(d.pos.y)
			var tx = d.pos.x - ix
			var tz = d.pos.y - iz
			
			# Calculate gradient using bilinear central differences
			var idx00 = iz * width + ix
			var idx10 = iz * width + (ix + 1)
			var idx01 = (iz + 1) * width + ix
			var idx11 = (iz + 1) * width + (ix + 1)
			
			var h00 = map_data[idx00]
			var h10 = map_data[idx10]
			var h01 = map_data[idx01]
			var h11 = map_data[idx11]
			
			# Gradient vector pointing downhill
			var grad_x = (h10 - h00) * (1.0 - tz) + (h11 - h01) * tz
			var grad_z = (h01 - h00) * (1.0 - tx) + (h11 - h10) * tx
			var grad = Vector2(grad_x, grad_z)
			
			# Calculate next direction and position
			d.dir = d.dir * inertia - grad * (1.0 - inertia)
			d.dir = d.dir.normalized()
			
			var next_pos = d.pos + d.dir
			
			# Stop if droplet goes off map boundary
			if next_pos.x < 1.0 or next_pos.x >= width - 2.0 or next_pos.y < 1.0 or next_pos.y >= depth - 2.0:
				break
				
			# Calculate height change
			var next_ix = int(next_pos.x)
			var next_iz = int(next_pos.y)
			var next_tx = next_pos.x - next_ix
			var next_tz = next_pos.y - next_iz
			
			var nh00 = map_data[next_iz * width + next_ix]
			var nh10 = map_data[next_iz * width + (next_ix + 1)]
			var nh01 = map_data[(next_iz + 1) * width + next_ix]
			var nh11 = map_data[(next_iz + 1) * width + (next_ix + 1)]
			
			var h_current = h00 * (1.0 - tx) * (1.0 - tz) + h10 * tx * (1.0 - tz) + h01 * (1.0 - tx) * tz + h11 * tx * tz
			var h_next = nh00 * (1.0 - next_tx) * (1.0 - next_tz) + nh10 * next_tx * (1.0 - next_tz) + nh01 * (1.0 - next_tx) * next_tz + nh11 * next_tx * next_tz
			
			var delta_h = h_next - h_current
			
			# Update droplet speed based on gravity and slope
			d.speed = sqrt(max(0.0, d.speed * d.speed + delta_h * gravity))
			
			# Stop if droplet has run completely dry or hit a dead end
			if d.speed < 0.0001:
				break
				
			# Calculate sediment capacity
			var slope = -delta_h
			var capacity = max(d.speed * d.water * slope * capacity_factor, min_capacity)
			
			if d.sediment > capacity or delta_h > 0.0:
				# Deposit sediment
				var deposit_amount = 0.0
				if delta_h > 0.0:
					deposit_amount = min(delta_h, d.sediment)
				else:
					deposit_amount = (d.sediment - capacity) * deposition_rate
					
				d.sediment -= deposit_amount
				
				# Bilinearly add sediment to landscape
				map_data[idx00] += deposit_amount * (1.0 - tx) * (1.0 - tz)
				map_data[idx10] += deposit_amount * tx * (1.0 - tz)
				map_data[idx01] += deposit_amount * (1.0 - tx) * tz
				map_data[idx11] += deposit_amount * tx * tz
			else:
				# Erode sediment
				var erode_amount = min((capacity - d.sediment) * erosion_rate, -delta_h)
				d.sediment += erode_amount
				
				# Disperse erosion weight across brush area
				for i in range(brush_offsets.size()):
					var offset = brush_offsets[i]
					var bx = ix + offset.x
					var bz = iz + offset.y
					if bx >= 0 and bx < width and bz >= 0 and bz < depth:
						var weight = brush_weights[i]
						var cell_idx = bz * width + bx
						var eroded_val = erode_amount * weight
						map_data[cell_idx] = max(0.0, map_data[cell_idx] - eroded_val)
						
			# Evaporation step
			d.water *= (1.0 - evaporation_rate)
			d.pos = next_pos
			
	# Save flattened data array back to heightmap texture
	for z in range(depth):
		for x in range(width):
			var h = map_data[z * width + x]
			terrain_data.set_height(x, z, h)
			
			var cx = x / chunk_size
			var cz = z / chunk_size
			var coord = Vector2i(cx, cz)
			if not affected_chunks.has(coord):
				affected_chunks.append(coord)
				
	return affected_chunks
