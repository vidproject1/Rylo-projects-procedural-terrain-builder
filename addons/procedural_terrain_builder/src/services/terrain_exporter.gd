@tool
extends RefCounted
class_name TerrainExporter

## Service responsible for exporting baked terrain meshes into GLB, OBJ, and Godot Mesh Resource formats.

const EXPORT_DIR = "res://BakedWorld/"

## Exports the terrain node hierarchy as a standalone GLB file using Godot's built-in GLTFDocument.
static func export_to_glb(terrain: ProceduralTerrain3D) -> String:
	if not terrain:
		return "Error: Terrain node is null."
		
	# Ensure export folder exists
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("BakedWorld"):
		dir.make_dir("BakedWorld")
		
	# 1. We build a temporary node tree representing the meshes
	var temp_root = Node3D.new()
	temp_root.name = "TerrainGLB"
	
	# We copy the mesh structures of all chunks
	for coord in terrain.chunks.keys():
		var chunk = terrain.chunks[coord]
		if not chunk or not chunk.mesh_instance or not chunk.mesh_instance.mesh:
			continue
			
		var mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [coord.x, coord.y]
		mi.mesh = chunk.mesh_instance.mesh.duplicate() as Mesh
		mi.position = chunk.position
		temp_root.add_child(mi)
		
	# 2. Use GLTFDocument to bake the node tree into GLB format
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	
	# Append the scene to the GLTFState
	document.append_from_scene(temp_root, state)
	
	# Write GLB
	var file_path = EXPORT_DIR + "exported_terrain.glb"
	var err = document.write_to_filesystem(state, file_path)
	
	# Clean up temporary node tree
	temp_root.free()
	
	if err != OK:
		return "Error: Failed to export to GLB (Error code %d)." % err
		
	# Trigger editor filesystem refresh
	if Engine.is_editor_hint():
		var interface = EditorInterface
		if interface:
			var res_fs = interface.get_resource_filesystem()
			if res_fs: res_fs.scan()
			
	return "Success: Exported terrain to " + file_path

## Compiles and merges all chunk meshes into a single global OBJ file.
static func export_to_obj(terrain: ProceduralTerrain3D) -> String:
	if not terrain:
		return "Error: Terrain node is null."
		
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("BakedWorld"):
		dir.make_dir("BakedWorld")
		
	var file_path = EXPORT_DIR + "exported_terrain.obj"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return "Error: Cannot write to file " + file_path
		
	# Write standard OBJ header
	file.store_line("# Wavefront OBJ file exported by Procedural Terrain Builder")
	file.store_line("# Godot 4 plugin")
	file.store_line("mtllib exported_terrain.mtl")
	file.store_line("o Terrain")
	
	var global_vertex_offset = 1
	
	for coord in terrain.chunks.keys():
		var chunk = terrain.chunks[coord]
		if not chunk or not chunk.mesh_instance or not chunk.mesh_instance.mesh:
			continue
			
		var mesh = chunk.mesh_instance.mesh
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, 0)
		
		# Write vertices
		for i in range(mdt.get_vertex_count()):
			# Position offset by chunk's position
			var v = mdt.get_vertex(i) + chunk.position
			file.store_line("v %f %f %f" % [v.x, v.y, v.z])
			
		# Write texture coordinates
		for i in range(mdt.get_vertex_count()):
			var uv = mdt.get_vertex_uv(i)
			file.store_line("vt %f %f" % [uv.x, 1.0 - uv.y]) # Invert V for standard OBJ UV layouts
			
		# Write normals
		for i in range(mdt.get_vertex_count()):
			var n = mdt.get_vertex_normal(i)
			file.store_line("vn %f %f %f" % [n.x, n.y, n.z])
			
		# Write faces (triangles)
		# OBJ indices are 1-based, so we offset by global_vertex_offset
		file.store_line("g Chunk_%d_%d" % [coord.x, coord.y])
		for i in range(mdt.get_face_count()):
			var v0 = mdt.get_face_vertex(i, 0) + global_vertex_offset
			var v1 = mdt.get_face_vertex(i, 1) + global_vertex_offset
			var v2 = mdt.get_face_vertex(i, 2) + global_vertex_offset
			
			# Format: f v/vt/vn
			file.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [v0, v0, v0, v1, v1, v1, v2, v2, v2])
			
		global_vertex_offset += mdt.get_vertex_count()
		
	file.close()
	
	# Trigger editor filesystem refresh
	if Engine.is_editor_hint():
		var interface = EditorInterface
		if interface:
			var res_fs = interface.get_resource_filesystem()
			if res_fs: res_fs.scan()
			
	return "Success: Exported terrain to " + file_path

## Merges all chunk meshes into a single global ArrayMesh resource and saves it to res://BakedWorld/.
static func export_to_mesh_resource(terrain: ProceduralTerrain3D) -> String:
	if not terrain:
		return "Error: Terrain node is null."
		
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("BakedWorld"):
		dir.make_dir("BakedWorld")
		
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for coord in terrain.chunks.keys():
		var chunk = terrain.chunks[coord]
		if not chunk or not chunk.mesh_instance or not chunk.mesh_instance.mesh:
			continue
			
		var mesh = chunk.mesh_instance.mesh
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, 0)
		
		# Add elements to the SurfaceTool, offsetting positions into global space
		for i in range(mdt.get_face_count()):
			for j in range(3):
				var vertex_idx = mdt.get_face_vertex(i, j)
				
				var pos = mdt.get_vertex(vertex_idx) + chunk.position
				var normal = mdt.get_vertex_normal(vertex_idx)
				var uv = mdt.get_vertex_uv(vertex_idx)
				
				st.set_normal(normal)
				st.set_uv(uv)
				st.add_vertex(pos)
				
	var merged_mesh = st.commit()
	var file_path = EXPORT_DIR + "exported_terrain_mesh.tres"
	var err = ResourceSaver.save(merged_mesh, file_path)
	
	if err != OK:
		return "Error: Failed to save Godot Mesh Resource (Error code %d)." % err
		
	# Trigger editor filesystem refresh
	if Engine.is_editor_hint():
		var interface = EditorInterface
		if interface:
			var res_fs = interface.get_resource_filesystem()
			if res_fs: res_fs.scan()
			
	return "Success: Exported terrain to " + file_path
