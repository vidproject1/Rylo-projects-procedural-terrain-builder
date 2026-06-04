@tool
extends Resource
class_name TerrainData

## Core configuration for the Procedural Terrain.
## Stores the heightmap as a FORMAT_RF (float32) image, which enables fast, high-precision reads/writes.
## Density maps are stored as FORMAT_L8 (grayscale) images.

@export var width: int = 512:
	set(val):
		width = val
@export var depth: int = 512:
	set(val):
		depth = val
@export var height_scale: float = 64.0
@export var chunk_size: int = 64

@export var heightmap_image: Image
@export var grass_density_image: Image
@export var tree_density_image: Image
@export var rock_density_image: Image
@export var splatmap_image: Image

## Initializes the underlying images to empty black textures with proper sizes.
func initialize() -> void:
	heightmap_image = Image.create(width, depth, false, Image.FORMAT_RF)
	heightmap_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	
	grass_density_image = Image.create(width, depth, false, Image.FORMAT_L8)
	grass_density_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	
	tree_density_image = Image.create(width, depth, false, Image.FORMAT_L8)
	tree_density_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	
	rock_density_image = Image.create(width, depth, false, Image.FORMAT_L8)
	rock_density_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	
	splatmap_image = Image.create(width, depth, false, Image.FORMAT_RGBA8)
	splatmap_image.fill(Color(1.0, 0.0, 0.0, 0.0)) # Default fully Grass (Red = 1.0)

## Checks if images are initialized, and if not, initializes them.
func ensure_initialized() -> void:
	var needs_init = false
	if not heightmap_image or heightmap_image.is_empty(): needs_init = true
	if not grass_density_image or grass_density_image.is_empty(): needs_init = true
	if not tree_density_image or tree_density_image.is_empty(): needs_init = true
	if not rock_density_image or rock_density_image.is_empty(): needs_init = true
	if not splatmap_image or splatmap_image.is_empty(): needs_init = true
	
	if needs_init:
		initialize()

## Returns raw height at (x, z) in local coordinate system [0.0, 1.0].
func get_height(x: int, z: int) -> float:
	ensure_initialized()
	if x < 0 or x >= width or z < 0 or z >= depth:
		return 0.0
	return heightmap_image.get_pixel(x, z).r

## Sets raw height at (x, z) in local coordinate system [0.0, 1.0].
func set_height(x: int, z: int, height: float) -> void:
	ensure_initialized()
	if x >= 0 and x < width and z >= 0 and z < depth:
		# FORMAT_RF puts float value in red channel.
		heightmap_image.set_pixel(x, z, Color(height, 0.0, 0.0, 1.0))

## Returns interpolated raw height using bilinear filtering.
func get_height_interpolated(x: float, z: float) -> float:
	ensure_initialized()
	var x_clamped = clampf(x, 0.0, float(width - 1))
	var z_clamped = clampf(z, 0.0, float(depth - 1))
	
	var x0 = int(floor(x_clamped))
	var x1 = min(x0 + 1, width - 1)
	var z0 = int(floor(z_clamped))
	var z1 = min(z0 + 1, depth - 1)
	
	var tx = x_clamped - x0
	var tz = z_clamped - z0
	
	var h00 = heightmap_image.get_pixel(x0, z0).r
	var h10 = heightmap_image.get_pixel(x1, z0).r
	var h01 = heightmap_image.get_pixel(x0, z1).r
	var h11 = heightmap_image.get_pixel(x1, z1).r
	
	var h0 = lerpf(h00, h10, tx)
	var h1 = lerpf(h01, h11, tx)
	
	return lerpf(h0, h1, tz)

## Returns raw height multiplied by height_scale (world coordinate).
func get_world_height(x: int, z: int) -> float:
	return get_height(x, z) * height_scale

## Returns raw interpolated height multiplied by height_scale (world coordinate).
func get_world_height_interpolated(x: float, z: float) -> float:
	return get_height_interpolated(x, z) * height_scale

## Sets raw height based on a world height (divides by height_scale).
func set_world_height(x: int, z: int, world_height: float) -> void:
	set_height(x, z, world_height / height_scale)

## Returns vegetation density value [0.0, 1.0] for the given map type ("grass", "tree", "rock").
func get_density(type: String, x: int, z: int) -> float:
	ensure_initialized()
	var img: Image
	match type.to_lower():
		"grass": img = grass_density_image
		"tree": img = tree_density_image
		"rock": img = rock_density_image
		_: return 0.0
	
	if x < 0 or x >= width or z < 0 or z >= depth:
		return 0.0
	return img.get_pixel(x, z).r

## Sets vegetation density value [0.0, 1.0] for the given map type ("grass", "tree", "rock").
func set_density(type: String, x: int, z: int, density: float) -> void:
	ensure_initialized()
	var img: Image
	match type.to_lower():
		"grass": img = grass_density_image
		"tree": img = tree_density_image
		"rock": img = rock_density_image
		_: return
	
	if x >= 0 and x < width and z >= 0 and z < depth:
		var clamped_val = clampf(density, 0.0, 1.0)
		img.set_pixel(x, z, Color(clamped_val, clamped_val, clamped_val, 1.0))

## Populates the heightmap image with normalized values generated from FastNoiseLite.
func import_noise(noise: FastNoiseLite, offset_x: float = 0.0, offset_z: float = 0.0) -> void:
	ensure_initialized()
	for z in range(depth):
		for x in range(width):
			var nx = float(x) + offset_x
			var nz = float(z) + offset_z
			var noise_val = noise.get_noise_2d(nx, nz)
			# Standard FastNoiseLite returns values in range [-1.0, 1.0].
			# Map to [0.0, 1.0] for our internal heightmap storage.
			var norm_val = clampf((noise_val + 1.0) * 0.5, 0.0, 1.0)
			heightmap_image.set_pixel(x, z, Color(norm_val, 0.0, 0.0, 1.0))

## Safely resizes the terrain heightmap and density images.
func resize(new_width: int, new_depth: int) -> void:
	ensure_initialized()
	# Keep copy of old images for sampling if needed, or simply scale them.
	# Standard resize using bilinear filtering preserves features well.
	heightmap_image.resize(new_width, new_depth, Image.INTERPOLATE_BILINEAR)
	grass_density_image.resize(new_width, new_depth, Image.INTERPOLATE_BILINEAR)
	tree_density_image.resize(new_width, new_depth, Image.INTERPOLATE_BILINEAR)
	rock_density_image.resize(new_width, new_depth, Image.INTERPOLATE_BILINEAR)
	splatmap_image.resize(new_width, new_depth, Image.INTERPOLATE_BILINEAR)
	
	width = new_width
	depth = new_depth

## Automatically generates a textured splatmap based on slope and height limits.
func auto_generate_splatmap(mat: ShaderMaterial = null) -> void:
	ensure_initialized()
	
	var rock_slope_threshold = 0.16
	var rock_slope_blend = 0.15
	var rock_height_limit = 45.0
	var rock_height_blend = 10.0
	var dirt_slope_threshold = 0.06
	var dirt_slope_blend = 0.10
	var sand_height_limit = 2.0
	var sand_blend_margin = 1.0
	
	if mat:
		rock_slope_threshold = mat.get_shader_parameter("rock_slope_threshold") if mat.get_shader_parameter("rock_slope_threshold") != null else rock_slope_threshold
		rock_slope_blend = mat.get_shader_parameter("rock_slope_blend") if mat.get_shader_parameter("rock_slope_blend") != null else rock_slope_blend
		rock_height_limit = mat.get_shader_parameter("rock_height_limit") if mat.get_shader_parameter("rock_height_limit") != null else rock_height_limit
		rock_height_blend = mat.get_shader_parameter("rock_height_blend") if mat.get_shader_parameter("rock_height_blend") != null else rock_height_blend
		dirt_slope_threshold = mat.get_shader_parameter("dirt_slope_threshold") if mat.get_shader_parameter("dirt_slope_threshold") != null else dirt_slope_threshold
		dirt_slope_blend = mat.get_shader_parameter("dirt_slope_blend") if mat.get_shader_parameter("dirt_slope_blend") != null else dirt_slope_blend
		sand_height_limit = mat.get_shader_parameter("sand_height_limit") if mat.get_shader_parameter("sand_height_limit") != null else sand_height_limit
		sand_blend_margin = mat.get_shader_parameter("sand_blend_margin") if mat.get_shader_parameter("sand_blend_margin") != null else sand_blend_margin

	for z in range(depth):
		for x in range(width):
			var pos_y = get_world_height(x, z)
			
			# Slope approximation via central difference
			var hl = get_world_height(x - 1, z)
			var hr = get_world_height(x + 1, z)
			var hu = get_world_height(x, z - 1)
			var hd = get_world_height(x, z + 1)
			var normal = Vector3(hl - hr, 2.0, hu - hd).normalized()
			var slope = 1.0 - normal.y
			
			# Custom thresholds matching shader parameters
			var rock_slope_w = clampf((slope - rock_slope_threshold) / rock_slope_blend, 0.0, 1.0)
			var rock_height_w = clampf((pos_y - rock_height_limit) / rock_height_blend, 0.0, 1.0)
			var rock_w = maxf(rock_slope_w, rock_height_w)
			
			var dirt_slope_w = clampf((slope - dirt_slope_threshold) / dirt_slope_blend, 0.0, 1.0)
			var dirt_w = dirt_slope_w * (1.0 - rock_w)
			
			var sand_w = clampf((sand_height_limit - pos_y) / sand_blend_margin, 0.0, 1.0) * (1.0 - rock_w) * (1.0 - dirt_w)
			var grass_w = clampf(1.0 - rock_w - dirt_w - sand_w, 0.0, 1.0)
			
			var total = grass_w + dirt_w + rock_w + sand_w
			if total > 0.0001:
				grass_w /= total
				dirt_w /= total
				rock_w /= total
				sand_w /= total
			else:
				grass_w = 1.0
				dirt_w = 0.0
				rock_w = 0.0
				sand_w = 0.0
				
			splatmap_image.set_pixel(x, z, Color(grass_w, dirt_w, rock_w, sand_w))
