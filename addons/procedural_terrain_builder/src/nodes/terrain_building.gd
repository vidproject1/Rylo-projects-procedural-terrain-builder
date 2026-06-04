@tool
extends Node3D
class_name TerrainBuilding3D

## A node representing a building footprint area.
## Flattens the terrain beneath its footprint in real time when placed as a child of ProceduralTerrain3D.
## Supports rectangular (supporting rotation) and circular footprint shapes.

enum FootprintType {
	RECTANGLE,
	CIRCLE
}

@export var footprint_type: FootprintType = FootprintType.RECTANGLE:
	set(val):
		footprint_type = val
		_trigger_terrain_update()

@export var radius: float = 10.0:
	set(val):
		radius = maxf(val, 0.1)
		_trigger_terrain_update()

@export var size: Vector2 = Vector2(16.0, 16.0):
	set(val):
		size = Vector2(maxf(val.x, 0.1), maxf(val.y, 0.1))
		_trigger_terrain_update()

@export var falloff: float = 6.0:
	set(val):
		falloff = maxf(val, 0.1)
		_trigger_terrain_update()

func _ready() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_trigger_terrain_update()

func _trigger_terrain_update() -> void:
	var parent = get_parent()
	if parent and parent.has_method("recalculate_terrain"):
		parent.recalculate_terrain()

## Flattens the terrain around the footprint. Called by ProceduralTerrain3D.
func apply_to_heightmap(working_heightmap: TerrainData) -> void:
	var parent = get_parent() as Node3D
	if not parent:
		return
		
	var local_pos = position
	if is_inside_tree() and parent.is_inside_tree():
		local_pos = parent.to_local(global_position)
	var center = Vector2(local_pos.x, local_pos.z)
	
	# Determine bounds for scanning
	var max_influence = 0.0
	if footprint_type == FootprintType.CIRCLE:
		max_influence = radius + falloff
	else:
		max_influence = size.length() * 0.5 + falloff
		
	var cx = int(center.x)
	var cz = int(center.y)
	var r = int(ceil(max_influence))
	
	var x_min = clampi(cx - r, 0, working_heightmap.width - 1)
	var x_max = clampi(cx + r, 0, working_heightmap.width - 1)
	var z_min = clampi(cz - r, 0, working_heightmap.depth - 1)
	var z_max = clampi(cz + r, 0, working_heightmap.depth - 1)
	
	var target_h_norm = clampf(local_pos.y / working_heightmap.height_scale, 0.0, 1.0)
	
	# Cached scale values
	var half_x = size.x * 0.5
	var half_z = size.y * 0.5
	
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var factor = 0.0
			
			if footprint_type == FootprintType.CIRCLE:
				var dist = center.distance_to(Vector2(x, z))
				if dist <= radius:
					factor = 1.0
				elif dist <= radius + falloff:
					var t = (dist - radius) / falloff
					factor = 1.0 - (t * t * (3.0 - 2.0 * t))
			else:
				# Rectangle mode supporting rotation!
				var pixel_local: Vector3
				if is_inside_tree() and parent.is_inside_tree():
					var pixel_world = parent.to_global(Vector3(float(x), working_heightmap.get_world_height(x, z), float(z)))
					pixel_local = to_local(pixel_world)
				else:
					var pixel_pos_terrain = Vector3(float(x), working_heightmap.get_world_height(x, z), float(z))
					var rel_pos = pixel_pos_terrain - position
					pixel_local = rel_pos.rotated(Vector3.UP, -rotation.y)
				var local_xz = Vector2(pixel_local.x, pixel_local.z)
				
				# 2D Box Signed Distance Function (SDF) calculation
				var dx = absf(local_xz.x) - half_x
				var dz = absf(local_xz.y) - half_z
				
				var dist_outside = Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()
				var dist_inside = minf(maxf(dx, dz), 0.0)
				var sd = dist_outside + dist_inside
				
				if sd <= 0.0:
					factor = 1.0
				elif sd <= falloff:
					var t = sd / falloff
					factor = 1.0 - (t * t * (3.0 - 2.0 * t))
					
			if factor > 0.0:
				var old_h = working_heightmap.get_height(x, z)
				var new_h = lerpf(old_h, target_h_norm, factor)
				working_heightmap.set_height(x, z, new_h)
