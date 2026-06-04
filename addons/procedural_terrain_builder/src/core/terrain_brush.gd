@tool
extends RefCounted
class_name TerrainBrush

## Mathematics and logic for terrain sculpting and density painting brushes.
## All operations are performed in heightmap grid coordinates.

## Brush Modes
const MODE_RAISE = "raise"
const MODE_LOWER = "lower"
const MODE_SMOOTH = "smooth"
const MODE_FLATTEN = "flatten"
const MODE_NOISE = "noise"

## Falloff types
enum FalloffType {
	FLAT,
	LINEAR,
	SMOOTHSTEP,
	GAUSSIAN
}

## Computes the falloff factor [0.0, 1.0] based on distance from the center and radius.
static func get_falloff(distance: float, radius: float, type: FalloffType = FalloffType.SMOOTHSTEP) -> float:
	if distance >= radius:
		return 0.0
	if radius <= 0.001:
		return 1.0
		
	var t = distance / radius
	match type:
		FalloffType.FLAT:
			return 1.0
		FalloffType.LINEAR:
			return 1.0 - t
		FalloffType.SMOOTHSTEP:
			# Smoothstep: 3t^2 - 2t^3 inverted
			return 1.0 - (t * t * (3.0 - 2.0 * t))
		FalloffType.GAUSSIAN:
			# Gaussian distribution approximation
			return exp(-4.0 * t * t)
		_:
			return 0.0

## Applies a height sculpting brush to the terrain.
## [param center] is in heightmap pixel coordinates.
## [param strength] is typically in range [0.0, 1.0].
## [param target_height] is in local normalized range [0.0, 1.0].
static func apply_height_brush(
	terrain_data: TerrainData,
	mode: String,
	center: Vector2,
	radius: float,
	strength: float,
	target_height: float = 0.0,
	noise: FastNoiseLite = null,
	falloff_type: FalloffType = FalloffType.SMOOTHSTEP
) -> Array[Vector2i]:
	
	var affected_chunks: Array[Vector2i] = []
	var cx = int(center.x)
	var cz = int(center.y)
	var r = int(ceil(radius))
	
	# Determine bounds to avoid scanning the entire heightmap
	var x_min = clampi(cx - r, 0, terrain_data.width - 1)
	var x_max = clampi(cx + r, 0, terrain_data.width - 1)
	var z_min = clampi(cz - r, 0, terrain_data.depth - 1)
	var z_max = clampi(cz + r, 0, terrain_data.depth - 1)
	
	# Keep track of chunk size to register which chunks need mesh regeneration
	var chunk_size = terrain_data.chunk_size
	
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var dist = center.distance_to(Vector2(x, z))
			if dist > radius:
				continue
				
			var falloff = get_falloff(dist, radius, falloff_type)
			var old_height = terrain_data.get_height(x, z)
			var new_height = old_height
			
			match mode.to_lower():
				MODE_RAISE:
					# Adjust height upwards
					new_height = clampf(old_height + (strength * falloff * 0.05), 0.0, 1.0)
				MODE_LOWER:
					# Adjust height downwards
					new_height = clampf(old_height - (strength * falloff * 0.05), 0.0, 1.0)
				MODE_FLATTEN:
					# Blend towards target height
					new_height = lerpf(old_height, target_height, strength * falloff)
				MODE_SMOOTH:
					# Blend towards the local average of the 3x3 grid
					var avg = get_local_average_height(terrain_data, x, z)
					new_height = lerpf(old_height, avg, strength * falloff)
				MODE_NOISE:
					# Blend with a noise factor
					if noise:
						var noise_val = noise.get_noise_2d(float(x), float(z))
						# Noise is [-1.0, 1.0]. Convert to delta.
						new_height = clampf(old_height + (noise_val * strength * falloff * 0.05), 0.0, 1.0)
			
			if not is_equal_approx(old_height, new_height):
				terrain_data.set_height(x, z, new_height)
				
				# Track affected chunks
				var chunk_coords = Vector2i(x / chunk_size, z / chunk_size)
				if not affected_chunks.has(chunk_coords):
					affected_chunks.append(chunk_coords)
					
				# Also check chunk borders to update neighboring chunks to prevent seams
				if x % chunk_size == 0 and x > 0:
					var neighbor = Vector2i((x - 1) / chunk_size, z / chunk_size)
					if not affected_chunks.has(neighbor): affected_chunks.append(neighbor)
				if z % chunk_size == 0 and z > 0:
					var neighbor = Vector2i(x / chunk_size, (z - 1) / chunk_size)
					if not affected_chunks.has(neighbor): affected_chunks.append(neighbor)
				if x % chunk_size == chunk_size - 1 and x < terrain_data.width - 1:
					var neighbor = Vector2i((x + 1) / chunk_size, z / chunk_size)
					if not affected_chunks.has(neighbor): affected_chunks.append(neighbor)
				if z % chunk_size == chunk_size - 1 and z < terrain_data.depth - 1:
					var neighbor = Vector2i(x / chunk_size, (z + 1) / chunk_size)
					if not affected_chunks.has(neighbor): affected_chunks.append(neighbor)
					
	return affected_chunks

## Applies a vegetation or layout painting brush.
## [param type] is "grass", "tree", or "rock".
## [param paint_mode] is: 1.0 to add (paint), 0.0 to subtract (erase).
static func apply_density_brush(
	terrain_data: TerrainData,
	type: String,
	paint_mode: float, # 1.0 = Paint, 0.0 = Erase
	center: Vector2,
	radius: float,
	strength: float,
	falloff_type: FalloffType = FalloffType.SMOOTHSTEP
) -> Array[Vector2i]:
	
	var affected_chunks: Array[Vector2i] = []
	var cx = int(center.x)
	var cz = int(center.y)
	var r = int(ceil(radius))
	
	var x_min = clampi(cx - r, 0, terrain_data.width - 1)
	var x_max = clampi(cx + r, 0, terrain_data.width - 1)
	var z_min = clampi(cz - r, 0, terrain_data.depth - 1)
	var z_max = clampi(cz + r, 0, terrain_data.depth - 1)
	
	var chunk_size = terrain_data.chunk_size
	
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var dist = center.distance_to(Vector2(x, z))
			if dist > radius:
				continue
				
			var falloff = get_falloff(dist, radius, falloff_type)
			var old_density = terrain_data.get_density(type, x, z)
			
			var new_density = old_density
			if paint_mode > 0.5:
				# Add density
				new_density = clampf(old_density + (strength * falloff * 0.1), 0.0, 1.0)
			else:
				# Erase density
				new_density = clampf(old_density - (strength * falloff * 0.1), 0.0, 1.0)
				
			if not is_equal_approx(old_density, new_density):
				terrain_data.set_density(type, x, z, new_density)
				
				var chunk_coords = Vector2i(x / chunk_size, z / chunk_size)
				if not affected_chunks.has(chunk_coords):
					affected_chunks.append(chunk_coords)
					
	return affected_chunks

## Calculates the average height of a 3x3 grid centered at (x, z).
static func get_local_average_height(terrain_data: TerrainData, x: int, z: int) -> float:
	var total = 0.0
	var count = 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx = x + dx
			var nz = z + dz
			if nx >= 0 and nx < terrain_data.width and nz >= 0 and nz < terrain_data.depth:
				total += terrain_data.get_height(nx, nz)
				count += 1
	return total / count if count > 0 else 0.0

## Applies a texture layer paint brush to the splatmap.
## [param layer_idx] is: 0 = Grass (R), 1 = Dirt (G), 2 = Rock (B), 3 = Sand (A).
static func apply_paint_brush(
	terrain_data: TerrainData,
	layer_idx: int,
	center: Vector2,
	radius: float,
	strength: float,
	falloff_type: FalloffType = FalloffType.SMOOTHSTEP
) -> Array[Vector2i]:
	
	var affected_chunks: Array[Vector2i] = []
	terrain_data.ensure_initialized()
	
	var cx = int(center.x)
	var cz = int(center.y)
	var r = int(ceil(radius))
	
	var x_min = clampi(cx - r, 0, terrain_data.width - 1)
	var x_max = clampi(cx + r, 0, terrain_data.width - 1)
	var z_min = clampi(cz - r, 0, terrain_data.depth - 1)
	var z_max = clampi(cz + r, 0, terrain_data.depth - 1)
	
	var chunk_size = terrain_data.chunk_size
	
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var dist = center.distance_to(Vector2(x, z))
			if dist > radius:
				continue
				
			var falloff = get_falloff(dist, radius, falloff_type)
			var old_col = terrain_data.splatmap_image.get_pixel(x, z)
			
			var channels = [old_col.r, old_col.g, old_col.b, old_col.a]
			var delta = strength * falloff * 0.1
			
			# Add weight to painted layer
			var old_val = channels[layer_idx]
			channels[layer_idx] = clampf(channels[layer_idx] + delta, 0.0, 1.0)
			
			# Adjust other channels so the sum stays exactly 1.0
			var other_sum = 0.0
			for i in range(4):
				if i != layer_idx:
					other_sum += channels[i]
					
			if other_sum > 0.0001:
				var factor = (1.0 - channels[layer_idx]) / other_sum
				for i in range(4):
					if i != layer_idx:
						channels[i] *= factor
			else:
				var distrib = (1.0 - channels[layer_idx]) / 3.0
				for i in range(4):
					if i != layer_idx:
						channels[i] = distrib
						
			var new_col = Color(channels[0], channels[1], channels[2], channels[3])
			if not new_col.is_equal_approx(old_col):
				terrain_data.splatmap_image.set_pixel(x, z, new_col)
				
				var chunk_coords = Vector2i(x / chunk_size, z / chunk_size)
				if not affected_chunks.has(chunk_coords):
					affected_chunks.append(chunk_coords)
					
	return affected_chunks
