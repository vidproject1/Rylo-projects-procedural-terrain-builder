@tool
extends RefCounted
class_name GPUHydraulicErosion

## Service responsible for executing Vulkan GPU-based particle hydraulic erosion.
## Drives the erosion.glsl compute shader via Godot's RenderingDevice API.
## Includes a seamless CPU fallback to guarantee cross-hardware compatibility.

static func erode(
	terrain_data: TerrainData, 
	num_droplets: int = 100000, 
	max_lifetime: int = 30,
	inertia: float = 0.05,
	gravity: float = 4.0,
	capacity_factor: float = 4.0,
	deposition_rate: float = 0.1,
	erosion_rate: float = 0.1,
	evaporation_rate: float = 0.02,
	min_capacity: float = 0.01
) -> Array[Vector2i]:
	
	if not terrain_data:
		return []
		
	terrain_data.ensure_initialized()
	var width = terrain_data.width
	var depth = terrain_data.depth
	var chunk_size = terrain_data.chunk_size
	
	# 1. Try to get shared RenderingDevice context first, fall back to creating local context
	var rd = RenderingServer.get_rendering_device()
	var is_shared_device = true
	if not rd:
		rd = RenderingServer.create_local_rendering_device()
		is_shared_device = false
		
	if not rd:
		# Fall back to CPU if GPU compute is not supported (e.g. Compatibility renderer)
		print("GPU Compute not supported in this environment. Falling back to CPU Hydraulic Erosion.")
		var cpu_service = load("res://addons/procedural_terrain_builder/src/services/hydraulic_erosion.gd")
		return cpu_service.erode(
			terrain_data,
			num_droplets / 4, # Scale down count for CPU to keep UI fluid
			max_lifetime,
			inertia,
			gravity,
			capacity_factor,
			deposition_rate,
			erosion_rate,
			evaporation_rate,
			min_capacity
		)
		
	# 2. Load and verify the compiled GLSL shader SPIR-V representation
	var shader_path = "res://addons/procedural_terrain_builder/src/shaders/erosion.glsl"
	if not ResourceLoader.exists(shader_path):
		printerr("Error: GPU Erosion compute shader not found at ", shader_path)
		if not is_shared_device: rd.free()
		return []
		
	var shader_file = load(shader_path)
	var shader_spirv = shader_file.get_spirv()
	if not shader_spirv or not shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty():
		var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE) if shader_spirv else "SPIR-V is null"
		printerr("Error compiling GPU Erosion shader: ", err)
		if not is_shared_device: rd.free()
		return []
		
	var shader_rid = rd.shader_create_from_spirv(shader_spirv)
	if not shader_rid.is_valid():
		if not is_shared_device: rd.free()
		return []
		
	# 3. Load height data into a PackedFloat32Array and allocate storage buffer
	var heights = PackedFloat32Array()
	heights.resize(width * depth)
	for z in range(depth):
		for x in range(width):
			heights[z * width + x] = terrain_data.get_height(x, z)
			
	var heights_bytes = heights.to_byte_array()
	var buffer_rid = rd.storage_buffer_create(heights_bytes.size(), heights_bytes)
	
	# 4. Form the uniform binding set
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer_rid)
	var uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)
	
	# 5. Build push constants structure (44 bytes total: 2 ints, 8 floats, 1 uint)
	var push_constants = PackedByteArray()
	push_constants.resize(44)
	
	push_constants.encode_s32(0, width)
	push_constants.encode_s32(4, depth)
	push_constants.encode_s32(8, max_lifetime)
	push_constants.encode_float(12, inertia)
	push_constants.encode_float(16, gravity)
	push_constants.encode_float(20, capacity_factor)
	push_constants.encode_float(24, deposition_rate)
	push_constants.encode_float(28, erosion_rate)
	push_constants.encode_float(32, evaporation_rate)
	push_constants.encode_float(36, min_capacity)
	push_constants.encode_u32(40, randi())
	
	# 6. Instantiate Compute Pipeline and Dispatch
	var pipeline = rd.compute_pipeline_create(shader_rid)
	var list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_set_push_constant(list, push_constants, push_constants.size())
	
	# Dispatch in blocks of 1024 threads
	var thread_groups = int(ceil(float(num_droplets) / 1024.0))
	rd.compute_list_dispatch(list, thread_groups, 1, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# 7. Read processed heights back to CPU
	var output_bytes = rd.buffer_get_data(buffer_rid)
	var output_heights = output_bytes.to_float32_array()
	
	# 8. Explicitly free RIDs to prevent GPU memory leaks
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(buffer_rid)
	rd.free_rid(shader_rid)
	if not is_shared_device:
		rd.free() # Only free local RenderingDevice context
	
	# 9. Save heights and compute boundary coordinates of affected chunks
	var affected_chunks: Array[Vector2i] = []
	for z in range(depth):
		for x in range(width):
			var idx = z * width + x
			var h = output_heights[idx]
			terrain_data.set_height(x, z, h)
			
			var cx = x / chunk_size
			var cz = z / chunk_size
			var coord = Vector2i(cx, cz)
			if not affected_chunks.has(coord):
				affected_chunks.append(coord)
				
	return affected_chunks
