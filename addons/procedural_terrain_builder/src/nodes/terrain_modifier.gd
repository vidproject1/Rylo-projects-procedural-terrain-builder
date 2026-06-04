@tool
extends Node3D
class_name TerrainModifier3D

## A spatial node that procedurally modifies the terrain heightmap in real time when placed as a child of ProceduralTerrain3D.

enum Mode {
	FLATTEN,
	RAISE,
	LOWER,
	SMOOTH
}

@export var mode: Mode = Mode.FLATTEN:
	set(val):
		mode = val
		_trigger_terrain_update()

@export var radius: float = 10.0:
	set(val):
		radius = maxf(val, 0.1)
		_trigger_terrain_update()

@export var strength: float = 1.0:
	set(val):
		strength = clampf(val, 0.0, 1.0)
		_trigger_terrain_update()

func _ready() -> void:
	# Forces editor configuration update
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_trigger_terrain_update()

func _trigger_terrain_update() -> void:
	var parent = get_parent()
	if parent and parent.has_method("recalculate_terrain"):
		parent.recalculate_terrain()

## Modifies the heightmap in its influence zone. Called by ProceduralTerrain3D.
func apply_to_heightmap(working_heightmap: TerrainData) -> void:
	var parent = get_parent() as Node3D
	if not parent:
		return
		
	# Transform global position to local terrain coordinates
	var local_pos = position
	if is_inside_tree() and parent.is_inside_tree():
		local_pos = parent.to_local(global_position)
	var center = Vector2(local_pos.x, local_pos.z)
	var radius_px = radius
	
	var cx = int(center.x)
	var cz = int(center.y)
	var r = int(ceil(radius_px))
	
	# Restrict bounds to the overlapping area
	var x_min = clampi(cx - r, 0, working_heightmap.width - 1)
	var x_max = clampi(cx + r, 0, working_heightmap.width - 1)
	var z_min = clampi(cz - r, 0, working_heightmap.depth - 1)
	var z_max = clampi(cz + r, 0, working_heightmap.depth - 1)
	
	# Target height is normalized to [0, 1] relative to terrain's height_scale
	var target_h_norm = clampf(local_pos.y / working_heightmap.height_scale, 0.0, 1.0)
	
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var dist = center.distance_to(Vector2(x, z))
			if dist > radius_px:
				continue
				
			# Compute a smoothstep falloff factor
			var t = dist / radius_px
			var factor = 1.0 - (t * t * (3.0 - 2.0 * t))
			
			var old_h = working_heightmap.get_height(x, z)
			var new_h = old_h
			
			match mode:
				Mode.FLATTEN:
					new_h = lerpf(old_h, target_h_norm, strength * factor)
				Mode.RAISE:
					new_h = clampf(old_h + (strength * factor * 0.1), 0.0, 1.0)
				Mode.LOWER:
					new_h = clampf(old_h - (strength * factor * 0.1), 0.0, 1.0)
				Mode.SMOOTH:
					var avg = TerrainBrush.get_local_average_height(working_heightmap, x, z)
					new_h = lerpf(old_h, avg, strength * factor)
					
			working_heightmap.set_height(x, z, new_h)
