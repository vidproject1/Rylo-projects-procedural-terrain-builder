@tool
extends Path3D
class_name TerrainRoad3D

## A spline-based road node extending Path3D.
## Flatten and carves the terrain along its Curve3D path in real time when a child of ProceduralTerrain3D.

@export var road_width: float = 6.0:
	set(val):
		road_width = maxf(val, 0.1)
		_trigger_terrain_update()

@export var falloff_distance: float = 6.0:
	set(val):
		falloff_distance = maxf(val, 0.1)
		_trigger_terrain_update()

@export var road_depth: float = 0.0:
	set(val):
		road_depth = val
		_trigger_terrain_update()

func _ready() -> void:
	# Monitor curve changes and node movements in the editor
	if curve:
		curve.changed.connect(_trigger_terrain_update)
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_trigger_terrain_update()

func _trigger_terrain_update() -> void:
	var parent = get_parent()
	if parent and parent.has_method("recalculate_terrain"):
		parent.recalculate_terrain()

## Carves and flattens the terrain beneath the road path. Called by ProceduralTerrain3D.
func apply_to_heightmap(working_heightmap: TerrainData) -> void:
	var parent = get_parent() as Node3D
	if not parent or not curve:
		return
		
	var baked_len = curve.get_baked_length()
	if baked_len < 1.0:
		return
		
	# Sample step size. 1.0 units ensures solid coverage of heightmap pixels.
	var step_size = 1.0
	var total_steps = int(ceil(baked_len / step_size))
	
	# Dictionary to store the best road point match for each heightmap pixel.
	# Key: Vector2i(x, z), Value: { "dist": float, "target_h": float, "factor": float }
	var pixel_mods = {}
	
	var r_total = road_width + falloff_distance
	
	# Step through the spline curve
	for i in range(total_steps + 1):
		var offset = minf(float(i) * step_size, baked_len)
		var road_pos_local = curve.sample_baked(offset)
		var t_pos = road_pos_local + position
		if is_inside_tree() and parent.is_inside_tree():
			t_pos = parent.to_local(to_global(road_pos_local))
		var center = Vector2(t_pos.x, t_pos.z)
		
		var cx = int(center.x)
		var cz = int(center.y)
		var r = int(ceil(r_total))
		
		# Small bounding box around current sample point
		var x_min = clampi(cx - r, 0, working_heightmap.width - 1)
		var x_max = clampi(cx + r, 0, working_heightmap.width - 1)
		var z_min = clampi(cz - r, 0, working_heightmap.depth - 1)
		var z_max = clampi(cz + r, 0, working_heightmap.depth - 1)
		
		# Height includes depth offset
		var target_h_norm = clampf((t_pos.y + road_depth) / working_heightmap.height_scale, 0.0, 1.0)
		
		for z in range(z_min, z_max + 1):
			for x in range(x_min, x_max + 1):
				var dist = center.distance_to(Vector2(x, z))
				if dist > r_total:
					continue
					
				# Determine blending factor based on road width and falloff
				var factor = 0.0
				if dist <= road_width:
					factor = 1.0
				else:
					var t = (dist - road_width) / falloff_distance
					factor = 1.0 - (t * t * (3.0 - 2.0 * t)) # Smoothstep
					
				var coord = Vector2i(x, z)
				
				# Keep the sample point that is closest to this pixel
				if not pixel_mods.has(coord) or dist < pixel_mods[coord].dist:
					pixel_mods[coord] = {
						"dist": dist,
						"target_h": target_h_norm,
						"factor": factor
					}
					
	# Apply final gathered modifications to the heightmap
	for coord in pixel_mods.keys():
		var mod = pixel_mods[coord]
		var old_h = working_heightmap.get_height(coord.x, coord.y)
		var new_h = lerpf(old_h, mod.target_h, mod.factor)
		working_heightmap.set_height(coord.x, coord.y, new_h)
