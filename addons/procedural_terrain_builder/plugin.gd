@tool
extends EditorPlugin

## Main script for the Procedural Terrain Builder editor plugin.
## Registers custom node types, adds the custom dock panel, and handles 3D viewport raycast sculpting.

const DOCK_SCENE_PATH = "res://addons/procedural_terrain_builder/src/ui/terrain_dock.tscn"

# Instanced dock panel control (typed as Control to prevent load-order dependency warnings)
var dock: Control

# Selected terrain node reference (typed as Node3D to prevent load-order warnings)
var current_terrain: Node3D

# Viewport sculpting state
var is_painting: bool = false

# Transient viewport brush ring gizmo
var ring_gizmo: MeshInstance3D

func _enter_tree() -> void:
	# 1. Register custom node types to make them visible in the Godot "Create Node" panel
	add_custom_type(
		"ProceduralTerrain3D",
		"Node3D",
		preload("res://addons/procedural_terrain_builder/src/core/terrain_node.gd"),
		preload("res://icon.svg")
	)
	add_custom_type(
		"TerrainModifier3D",
		"Node3D",
		preload("res://addons/procedural_terrain_builder/src/nodes/terrain_modifier.gd"),
		preload("res://icon.svg")
	)
	add_custom_type(
		"TerrainRoad3D",
		"Path3D",
		preload("res://addons/procedural_terrain_builder/src/nodes/terrain_road.gd"),
		preload("res://icon.svg")
	)
	add_custom_type(
		"TerrainBuilding3D",
		"Node3D",
		preload("res://addons/procedural_terrain_builder/src/nodes/terrain_building.gd"),
		preload("res://icon.svg")
	)
	
	# 2. Instantiate and add the custom dock panel
	var scene = load(DOCK_SCENE_PATH)
	if scene:
		dock = scene.instantiate() as Control
		add_control_to_dock(DOCK_SLOT_RIGHT_UR, dock)
		
	# 3. Create the transient 3D brush ring gizmo
	_create_ring_gizmo()

func _exit_tree() -> void:
	# 1. Clean up custom types
	remove_custom_type("ProceduralTerrain3D")
	remove_custom_type("TerrainModifier3D")
	remove_custom_type("TerrainRoad3D")
	remove_custom_type("TerrainBuilding3D")
	
	# 2. Clean up dock panel
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		
	# 3. Clean up ring gizmo
	if is_instance_valid(ring_gizmo):
		ring_gizmo.queue_free()

## Create the 3D line strip ring gizmo using ImmediateMesh for high-performance viewport rendering.
func _create_ring_gizmo() -> void:
	ring_gizmo = MeshInstance3D.new()
	ring_gizmo.name = "TerrainBrushGizmo"
	ring_gizmo.visible = false
	
	var imm_mesh = ImmediateMesh.new()
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	# Draw a high-definition circle made of 64 vertices
	var segments = 64
	for i in range(segments + 1):
		var angle = float(i) * TAU / float(segments)
		imm_mesh.surface_add_vertex(Vector3(cos(angle), 0.05, sin(angle))) # Slight offset to prevent Z-fighting
		
	imm_mesh.surface_end()
	ring_gizmo.mesh = imm_mesh
	
	# Glowing unshaded orange material
	var material = StandardMaterial3D.new()
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.45, 0.0) # Vibrant Orange
	imm_mesh.surface_set_material(0, material)

## Tells the editor that this plugin handles ProceduralTerrain3D selection.
func _handles(object: Object) -> bool:
	return object.has_method("generate_base_terrain")

## Responds to editor selection changes.
func _make_visible(visible: bool) -> void:
	if not visible:
		# Unselect terrain
		if current_terrain:
			_detach_ring_gizmo()
		current_terrain = null
		if dock and dock.has_method("set_current_terrain"):
			dock.set_current_terrain(null)
		is_painting = false

func _edit(object: Object) -> void:
	if object.has_method("generate_base_terrain"):
		current_terrain = object as Node3D
		if dock and dock.has_method("set_current_terrain"):
			dock.set_current_terrain(current_terrain)
		_attach_ring_gizmo()
	else:
		if current_terrain:
			_detach_ring_gizmo()
		current_terrain = null
		if dock and dock.has_method("set_current_terrain"):
			dock.set_current_terrain(null)

func _attach_ring_gizmo() -> void:
	if is_instance_valid(current_terrain) and is_instance_valid(ring_gizmo):
		_detach_ring_gizmo()
		current_terrain.add_child(ring_gizmo)

func _detach_ring_gizmo() -> void:
	if is_instance_valid(ring_gizmo) and ring_gizmo.get_parent():
		ring_gizmo.get_parent().remove_child(ring_gizmo)
		ring_gizmo.visible = false

## Viewport input event processing. Handles sculpting click/drags and draws the brush circle gizmo.
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not current_terrain or not dock or not current_terrain.get("terrain_data"):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
		
	# Viewport raycast calculations
	var mouse_pos: Vector2
	if event is InputEventMouse:
		mouse_pos = event.position
	else:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
		
	# Cast ray into the editor viewport physics world to hit our chunk collision shapes
	var space_state = viewport_camera.get_world_3d().direct_space_state
	var ray_origin = viewport_camera.project_ray_origin(mouse_pos)
	var ray_normal = viewport_camera.project_ray_normal(mouse_pos)
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 5000.0)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	
	var hit = space_state.intersect_ray(query)
	var has_hit = not hit.is_empty() and hit.collider.has_method("regenerate")
	
	# Update brush ring gizmo position and size
	if has_hit and is_instance_valid(ring_gizmo):
		ring_gizmo.visible = true
		ring_gizmo.global_position = hit.position
		var r = dock.get("brush_radius") if "brush_radius" in dock else 10.0
		ring_gizmo.scale = Vector3(r, 1.0, r)
	else:
		if is_instance_valid(ring_gizmo):
			ring_gizmo.visible = false
			
	# Process sculpt click/drag interactions
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and has_hit:
				is_painting = true
				_apply_sculpt_stroke(hit.position)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			else:
				is_painting = false
				
	elif event is InputEventMouseMotion and is_painting:
		if has_hit:
			_apply_sculpt_stroke(hit.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		else:
			is_painting = false
			
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _apply_sculpt_stroke(world_pos: Vector3) -> void:
	if not current_terrain or not dock:
		return
		
	var is_density = dock.get("is_density_mode") if "is_density_mode" in dock else false
	var is_texture = dock.get("is_texture_mode") if "is_texture_mode" in dock else false
	
	if is_density:
		current_terrain.paint_density(
			dock.get("density_type") if "density_type" in dock else "grass",
			dock.get("density_paint_mode") if "density_paint_mode" in dock else 1.0,
			world_pos,
			dock.get("brush_radius") if "brush_radius" in dock else 10.0,
			dock.get("brush_strength") if "brush_strength" in dock else 0.5
		)
	elif is_texture:
		current_terrain.paint_texture(
			dock.get("texture_layer") if "texture_layer" in dock else 0,
			world_pos,
			dock.get("brush_radius") if "brush_radius" in dock else 10.0,
			dock.get("brush_strength") if "brush_strength" in dock else 0.5
		)
	else:
		current_terrain.paint_sculpt(
			dock.get("brush_mode") if "brush_mode" in dock else "raise",
			world_pos,
			dock.get("brush_radius") if "brush_radius" in dock else 10.0,
			dock.get("brush_strength") if "brush_strength" in dock else 0.5,
			dock.get("brush_target_height") if "brush_target_height" in dock else 0.0
		)
