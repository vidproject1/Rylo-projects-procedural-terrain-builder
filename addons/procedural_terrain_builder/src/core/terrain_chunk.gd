@tool
extends StaticBody3D
class_name TerrainChunk3D

## Manages mesh generation, vertex normal calculations, and collision for a single terrain chunk.

# Child node references
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

# Chunk identification and references
var chunk_x: int = 0
var chunk_z: int = 0
var terrain_data: TerrainData

func _enter_tree() -> void:
	# Ensure child nodes exist
	_ensure_children_exist()

func _ensure_children_exist() -> void:
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "MeshInstance3D"
			add_child(mesh_instance)
				
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			add_child(collision_shape)

## Initializes the chunk with position and references.
func setup(cx: int, cz: int, data: TerrainData) -> void:
	chunk_x = cx
	chunk_z = cz
	terrain_data = data
	
	# Set position to top-left of the chunk in world coordinates.
	var world_x = float(chunk_x * terrain_data.chunk_size)
	var world_z = float(chunk_z * terrain_data.chunk_size)
	position = Vector3(world_x, 0.0, world_z)
	
	_ensure_children_exist()

## Regenerates the chunk's 3D mesh and collision shape from TerrainData.
func regenerate() -> void:
	if not terrain_data:
		return
		
	_ensure_children_exist()
	
	var size = terrain_data.chunk_size
	var width = terrain_data.width
	var depth = terrain_data.depth
	
	# Top-left vertex coordinates in global heightmap space
	var start_x = chunk_x * size
	var start_z = chunk_z * size
	
	# Standard vertex mesh generation
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate vertices
	for z in range(size + 1):
		var gz = start_z + z
		for x in range(size + 1):
			var gx = start_x + x
			
			# Sample height (clamp to borders for safety)
			var h = terrain_data.get_world_height(gx, gz)
			
			# Vertex position in local chunk space
			var vertex_pos = Vector3(float(x), h, float(z))
			
			# Calculate seamless normal based on surrounding pixels in global heightmap
			var normal = _calculate_normal(gx, gz)
			
			# Standard UV mapping [0.0, 1.0] across the entire terrain
			var uv = Vector2(float(gx) / float(width), float(gz) / float(depth))
			
			st.set_normal(normal)
			st.set_uv(uv)
			st.add_vertex(vertex_pos)
			
	# Generate indices
	# Grid is (size + 1) x (size + 1) vertices
	var stride = size + 1
	for z in range(size):
		for x in range(size):
			var i0 = z * stride + x
			var i1 = i0 + 1
			var i2 = (z + 1) * stride + x
			var i3 = i2 + 1
			
			# First Triangle (Top-Left, Top-Right, Bottom-Left)
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			
			# Second Triangle (Top-Right, Bottom-Right, Bottom-Left)
			st.add_index(i1)
			st.add_index(i3)
			st.add_index(i2)
			
	var mesh = st.commit()
	mesh_instance.mesh = mesh
	
	# Generate collision using HeightMapShape3D for extreme performance
	var shape = HeightMapShape3D.new()
	shape.map_width = size + 1
	shape.map_depth = size + 1
	
	var heights = PackedFloat32Array()
	heights.resize((size + 1) * (size + 1))
	
	var idx = 0
	# HeightMapShape3D reads row by row (z by x)
	for z in range(size + 1):
		var gz = start_z + z
		for x in range(size + 1):
			var gx = start_x + x
			heights[idx] = terrain_data.get_world_height(gx, gz)
			idx += 1
			
	shape.map_data = heights
	collision_shape.shape = shape
	
	# Position the collision shape offset
	# HeightMapShape3D is centered around its bounding box, so we offset it back
	var half_size = float(size) * 0.5
	collision_shape.position = Vector3(half_size, 0.0, half_size)

## Calculates normal vector at global coordinates (gx, gz) using a central difference scheme.
## This prevents seams between chunks because it samples the global heightmap.
func _calculate_normal(gx: int, gz: int) -> Vector3:
	var hl = terrain_data.get_world_height(gx - 1, gz)
	var hr = terrain_data.get_world_height(gx + 1, gz)
	var hu = terrain_data.get_world_height(gx, gz - 1)
	var hd = terrain_data.get_world_height(gx, gz + 1)
	
	# Normal vector derivation: Vector3(left - right, 2.0, up - down).normalized()
	var normal = Vector3(hl - hr, 2.0, hu - hd).normalized()
	return normal

## Helper to apply a material to this chunk.
func set_material(material: Material) -> void:
	_ensure_children_exist()
	mesh_instance.material_override = material
