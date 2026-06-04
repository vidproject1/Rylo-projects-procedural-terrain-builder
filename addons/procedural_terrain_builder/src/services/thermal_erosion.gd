@tool
extends RefCounted
class_name ThermalErosion

## Service responsible for gravity-based thermal erosion (weathering and talus accumulation).
## Operates on the angle of repose. Excess heights are distributed down steep slopes.

## Simulates thermal erosion on a TerrainData heightmap.
## Returns an array of coordinates of affected chunks for localized rebuilding.
static func erode(
	terrain_data: TerrainData,
	iterations: int = 5,
	talus_threshold: float = 0.005,
	c_transfer: float = 0.1
) -> Array[Vector2i]:
	
	if not terrain_data:
		return []
		
	terrain_data.ensure_initialized()
	var width = terrain_data.width
	var depth = terrain_data.depth
	var affected_chunks: Array[Vector2i] = []
	var chunk_size = terrain_data.chunk_size

	# Use a double-buffer height grid to make calculations order-independent
	var height_buffer = PackedFloat32Array()
	height_buffer.resize(width * depth)
	
	# Copy heights from TerrainData heightmap
	for z in range(depth):
		for x in range(width):
			height_buffer[z * width + x] = terrain_data.get_height(x, z)
			
	var neighbors = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1)
	]

	# Iterative relaxation process
	for iter in range(iterations):
		var next_buffer = height_buffer.duplicate()
		for z in range(1, depth - 1):
			for x in range(1, width - 1):
				var idx = z * width + x
				var h = height_buffer[idx]
				
				# Find steepest slope and accumulate height differences
				var max_diff = 0.0
				var total_excess = 0.0
				var lower_neighbors: Array[int] = []
				
				for n in neighbors:
					var nx = x + n.x
					var nz = z + n.y
					var n_idx = nz * width + nx
					var nh = height_buffer[n_idx]
					var diff = h - nh
					
					if diff > talus_threshold:
						lower_neighbors.append(n_idx)
						total_excess += diff
						if diff > max_diff:
							max_diff = diff
							
				# If we exceed the angle of repose, distribute soil to lower neighbors
				if not lower_neighbors.is_empty():
					var total_to_transfer = max_diff * c_transfer
					next_buffer[idx] -= total_to_transfer
					
					# Distribute sediment among lower neighbors proportionally
					for n_idx in lower_neighbors:
						var diff = h - height_buffer[n_idx]
						var weight = diff / total_excess
						next_buffer[n_idx] += total_to_transfer * weight
						
		height_buffer = next_buffer

	# Write final heights back to the TerrainData heightmap
	for z in range(depth):
		for x in range(width):
			var final_h = height_buffer[z * width + x]
			terrain_data.set_height(x, z, final_h)
			
			# Register affected chunk coordinates
			var cx = x / chunk_size
			var cz = z / chunk_size
			var coord = Vector2i(cx, cz)
			if not affected_chunks.has(coord):
				affected_chunks.append(coord)
				
	return affected_chunks
