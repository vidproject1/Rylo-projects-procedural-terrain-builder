@tool
extends RefCounted
class_name TerrainBaker

## Service responsible for baking the compiled procedural terrain into a standalone static scene
## with independent meshes, materials, collision shapes, and textures saved in res://BakedWorld/.

const BAKE_DIR = "res://BakedWorld/"

## Main bake function. Computes the final heightmap, saves static assets,
## and packs a standalone Node3D scene with meshes and collision.
static func bake_world(terrain: ProceduralTerrain3D) -> String:
	if not terrain or not terrain.terrain_data:
		return "Error: Terrain node or terrain data is null."
		
	# 1. Create the target folder
	var dir = DirAccess.open("res://")
	if not dir:
		return "Error: Cannot open res:// directory."
	if not dir.dir_exists("BakedWorld"):
		var err = dir.make_dir("BakedWorld")
		if err != OK:
			return "Error: Cannot create BakedWorld folder (Error code %d)." % err
			
	# 2. Force a full terrain recalculation to make sure everything is completely up to date
	terrain.recalculate_terrain()
	var working_data = terrain.working_heightmap
	if not working_data:
		working_data = terrain.terrain_data
		
	# 3. Save heightmap and density map textures as external files
	# Heightmap uses 32-bit floating point EXR to preserve exact heights without stepping artifacts.
	if working_data.heightmap_image:
		var err = working_data.heightmap_image.save_exr(BAKE_DIR + "baked_heightmap.exr", false)
		if err != OK:
			print("Warning: Failed to save baked_heightmap.exr (Error code %d)." % err)
			
	# Density maps are saved as lightweight standard PNGs
	if working_data.grass_density_image:
		working_data.grass_density_image.save_png(BAKE_DIR + "baked_grass_density.png")
	if working_data.tree_density_image:
		working_data.tree_density_image.save_png(BAKE_DIR + "baked_tree_density.png")
	if working_data.rock_density_image:
		working_data.rock_density_image.save_png(BAKE_DIR + "baked_rock_density.png")
		
	# 4. Save and copy the material resource
	var baked_material: Material
	if terrain.terrain_material:
		# Save a copy or reference the existing one
		baked_material = terrain.terrain_material.duplicate() as Material
		var mat_err = ResourceSaver.save(baked_material, BAKE_DIR + "baked_terrain_material.tres")
		if mat_err != OK:
			# Fall back to using the same resource
			baked_material = terrain.terrain_material
	else:
		# Create a default fallback material
		baked_material = StandardMaterial3D.new()
		baked_material.albedo_color = Color(0.2, 0.5, 0.2)
		ResourceSaver.save(baked_material, BAKE_DIR + "baked_terrain_material.tres")

	# 5. Build the static scene tree
	var baked_root = Node3D.new()
	baked_root.name = "BakedTerrain"
	
	var size = working_data.chunk_size
	var chunks_x = working_data.width / size
	var chunks_z = working_data.depth / size
	var half_size = float(size) * 0.5
	
	for cz in range(chunks_z):
		for cx in range(chunks_x):
			var active_chunk = terrain.chunks.get(Vector2i(cx, cz))
			if not active_chunk or not active_chunk.mesh_instance:
				continue
				
			var chunk_mesh = active_chunk.mesh_instance.mesh
			if not chunk_mesh:
				continue
				
			# Duplicate the mesh to make it a standalone independent asset
			var saved_mesh = chunk_mesh.duplicate() as Mesh
			var mesh_path = BAKE_DIR + "mesh_chunk_%d_%d.tres" % [cx, cz]
			ResourceSaver.save(saved_mesh, mesh_path)
			
			# Duplicate collision shape as well
			var chunk_col_shape = active_chunk.collision_shape.shape
			var saved_shape: Shape3D
			if chunk_col_shape:
				saved_shape = chunk_col_shape.duplicate() as Shape3D
				var shape_path = BAKE_DIR + "shape_chunk_%d_%d.tres" % [cx, cz]
				ResourceSaver.save(saved_shape, shape_path)
				
			# Create static baked nodes
			var chunk_node = Node3D.new()
			chunk_node.name = "Chunk_%d_%d" % [cx, cz]
			baked_root.add_child(chunk_node)
			chunk_node.owner = baked_root
			chunk_node.position = active_chunk.position
			
			# Create MeshInstance3D
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "MeshInstance3D"
			mesh_inst.mesh = saved_mesh
			mesh_inst.material_override = baked_material
			chunk_node.add_child(mesh_inst)
			mesh_inst.owner = baked_root
			
			# Create StaticBody3D
			var static_body = StaticBody3D.new()
			static_body.name = "StaticBody3D"
			chunk_node.add_child(static_body)
			static_body.owner = baked_root
			
			# Create CollisionShape3D
			var col_shape = CollisionShape3D.new()
			col_shape.name = "CollisionShape3D"
			col_shape.shape = saved_shape
			col_shape.position = Vector3(half_size, 0.0, half_size)
			static_body.add_child(col_shape)
			col_shape.owner = baked_root
			
	# 6. Pack the built node tree into a PackedScene
	var packed_scene = PackedScene.new()
	var pack_err = packed_scene.pack(baked_root)
	if pack_err != OK:
		baked_root.free()
		return "Error: Failed to pack static terrain scene (Error code %d)." % pack_err
		
	# 7. Save packed scene to res://BakedWorld/BakedTerrain.tscn
	var save_err = ResourceSaver.save(packed_scene, BAKE_DIR + "BakedTerrain.tscn")
	baked_root.free()
	
	if save_err != OK:
		return "Error: Failed to save PackedScene to res://BakedWorld/BakedTerrain.tscn (Error code %d)." % save_err
		
	# Re-scan the resource filesystem in editor so the user sees the files instantly
	if Engine.is_editor_hint():
		var interface = EditorInterface
		if interface:
			var res_fs = interface.get_resource_filesystem()
			if res_fs:
				res_fs.scan()
				
	return "Success: Baked terrain scene successfully saved to res://BakedWorld/BakedTerrain.tscn"
