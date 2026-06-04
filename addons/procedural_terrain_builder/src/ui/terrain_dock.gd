@tool
extends PanelContainer
class_name TerrainDock

## Control script for the "Terrain Builder" Editor Dock panel.
## Coordinates editor inputs, triggers noise generations, and runs baking/exporting routines.

# --- NODE REFERENCES ---
# We will bind these dynamically in _ready to ensure compatibility with the scene file.
var size_select: OptionButton
var chunk_size_select: OptionButton
var height_scale_spin: SpinBox

var seed_spin: SpinBox
var freq_spin: SpinBox
var octaves_spin: SpinBox
var persist_spin: SpinBox
var lacunarity_spin: SpinBox

var btn_generate: Button

var brush_mode_select: OptionButton
var radius_slider: HSlider
var radius_value: Label
var strength_slider: HSlider
var strength_value: Label
var target_height_spin: SpinBox

var density_type_select: OptionButton
var paint_mode_check: CheckButton

var btn_bake: Button
var btn_glb: Button
var btn_obj: Button
var btn_tres: Button
var btn_auto_paint: Button
var btn_thermal_erode: Button
var btn_hydraulic_erode: Button

var status_label: Label

# Current active selected terrain node
var current_terrain: ProceduralTerrain3D

# Brush configurations (accessible by the main plugin script)
var brush_mode: String = "raise"
var brush_radius: float = 10.0
var brush_strength: float = 0.5
var brush_target_height: float = 0.0

var density_type: String = "grass"
var density_paint_mode: float = 1.0 # 1.0 = Paint, 0.0 = Erase

var is_density_mode: bool = false
var is_texture_mode: bool = false
var texture_layer: int = 0 # 0=Grass, 1=Dirt, 2=Rock, 3=Sand

func _ready() -> void:
	_bind_ui_nodes()
	_connect_signals()
	_update_ui_state()

func _bind_ui_nodes() -> void:
	size_select = find_child("SizeSelect") as OptionButton
	chunk_size_select = find_child("ChunkSizeSelect") as OptionButton
	height_scale_spin = find_child("HeightScaleSpin") as SpinBox
	
	seed_spin = find_child("SeedSpin") as SpinBox
	freq_spin = find_child("FreqSpin") as SpinBox
	octaves_spin = find_child("OctavesSpin") as SpinBox
	persist_spin = find_child("PersistSpin") as SpinBox
	lacunarity_spin = find_child("LacunaritySpin") as SpinBox
	
	btn_generate = find_child("BtnGenerate") as Button
	
	brush_mode_select = find_child("BrushModeSelect") as OptionButton
	radius_slider = find_child("RadiusSlider") as HSlider
	radius_value = find_child("RadiusValue") as Label
	strength_slider = find_child("StrengthSlider") as HSlider
	strength_value = find_child("StrengthValue") as Label
	target_height_spin = find_child("TargetHeightSpin") as SpinBox
	
	density_type_select = find_child("DensityTypeSelect") as OptionButton
	paint_mode_check = find_child("PaintModeCheck") as CheckButton
	
	btn_bake = find_child("BtnBake") as Button
	btn_glb = find_child("BtnGLB") as Button
	btn_obj = find_child("BtnOBJ") as Button
	btn_tres = find_child("BtnTRES") as Button
	btn_auto_paint = find_child("BtnAutoPaint") as Button
	btn_thermal_erode = find_child("BtnThermalErode") as Button
	btn_hydraulic_erode = find_child("BtnHydraulicErode") as Button
	
	status_label = find_child("StatusLabel") as Label

func _connect_signals() -> void:
	if btn_generate: btn_generate.pressed.connect(_on_generate_pressed)
	if btn_bake: btn_bake.pressed.connect(_on_bake_pressed)
	if btn_glb: btn_glb.pressed.connect(_on_glb_pressed)
	if btn_obj: btn_obj.pressed.connect(_on_obj_pressed)
	if btn_tres: btn_tres.pressed.connect(_on_tres_pressed)
	if btn_auto_paint: btn_auto_paint.pressed.connect(_on_auto_paint_pressed)
	if btn_thermal_erode: btn_thermal_erode.pressed.connect(_on_thermal_erode_pressed)
	if btn_hydraulic_erode: btn_hydraulic_erode.pressed.connect(_on_hydraulic_erode_pressed)
	
	if radius_slider:
		radius_slider.value_changed.connect(func(val):
			brush_radius = val
			if radius_value: radius_value.text = "%.1f" % val
		)
	if strength_slider:
		strength_slider.value_changed.connect(func(val):
			brush_strength = val
			if strength_value: strength_value.text = "%.2f" % val
		)
	if target_height_spin:
		target_height_spin.value_changed.connect(func(val):
			brush_target_height = val / (current_terrain.terrain_data.height_scale if current_terrain and current_terrain.terrain_data else 64.0)
		)
	if brush_mode_select:
		brush_mode_select.item_selected.connect(func(idx):
			var text = brush_mode_select.get_item_text(idx).to_lower()
			if text == "paint density":
				is_density_mode = true
				is_texture_mode = false
			elif text == "paint texture":
				is_density_mode = false
				is_texture_mode = true
			else:
				is_density_mode = false
				is_texture_mode = false
				brush_mode = text
		)
	if density_type_select:
		density_type_select.item_selected.connect(func(idx):
			density_type = density_type_select.get_item_text(idx).to_lower()
			texture_layer = idx
		)
	if paint_mode_check:
		paint_mode_check.toggled.connect(func(toggled_on):
			density_paint_mode = 1.0 if toggled_on else 0.0
		)

## Sets the currently selected ProceduralTerrain3D node and loads its settings.
func set_current_terrain(terrain: ProceduralTerrain3D) -> void:
	current_terrain = terrain
	_update_ui_state()
	
	if current_terrain and current_terrain.terrain_data:
		var td = current_terrain.terrain_data
		# Populate inputs based on active terrain data
		if height_scale_spin: height_scale_spin.value = td.height_scale
		
		# Set size options
		if size_select:
			for i in range(size_select.item_count):
				if size_select.get_item_text(i).to_int() == td.width:
					size_select.selected = i
					break
					
		# Set chunk size options
		if chunk_size_select:
			for i in range(chunk_size_select.item_count):
				if chunk_size_select.get_item_text(i).to_int() == td.chunk_size:
					chunk_size_select.selected = i
					break
					
		# Load noise parameters
		if seed_spin: seed_spin.value = current_terrain.noise_seed
		if freq_spin: freq_spin.value = current_terrain.noise_frequency
		if octaves_spin: octaves_spin.value = current_terrain.noise_octaves
		if persist_spin: persist_spin.value = current_terrain.noise_persistence
		if lacunarity_spin: lacunarity_spin.value = current_terrain.noise_lacunarity
		
		_show_status("Selected terrain: " + current_terrain.name)
	else:
		_show_status("Please select a ProceduralTerrain3D node in the hierarchy.")

func _update_ui_state() -> void:
	var active = current_terrain != null
	
	# Enable/Disable all container contents based on whether a terrain is selected
	for child in get_children():
		_set_enabled_recursive(child, active)
		
	# The status label and panel themselves must always remain visible/enabled
	if status_label:
		status_label.set_process(true)
		
	# If disabled, override status text
	if not active:
		_show_status("No active ProceduralTerrain3D selected.")

func _set_enabled_recursive(node: Node, enabled: bool) -> void:
	if node is Control:
		if node != status_label:
			node.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
			node.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
			
			# Dynamic property assignment to prevent compile-time type mismatch errors in different Godot versions
			if "disabled" in node:
				node.set("disabled", not enabled)
			elif "editable" in node:
				node.set("editable", enabled)
	for child in node.get_children():
		_set_enabled_recursive(child, enabled)

func _show_status(text: String) -> void:
	if status_label:
		status_label.text = "Status: " + text

# --- SIGNAL HANDLERS ---

func _on_generate_pressed() -> void:
	if not current_terrain or not current_terrain.terrain_data:
		return
		
	_show_status("Generating procedural noise base...")
	
	# Apply configuration inputs to terrain node
	var td = current_terrain.terrain_data
	td.width = size_select.get_item_text(size_select.selected).to_int()
	td.depth = td.width
	td.chunk_size = chunk_size_select.get_item_text(chunk_size_select.selected).to_int()
	td.height_scale = height_scale_spin.value
	
	current_terrain.noise_seed = int(seed_spin.value)
	current_terrain.noise_frequency = freq_spin.value
	current_terrain.noise_octaves = int(octaves_spin.value)
	current_terrain.noise_persistence = persist_spin.value
	current_terrain.noise_lacunarity = lacunarity_spin.value
	
	# Generate base and update
	current_terrain.generate_base_terrain()
	current_terrain._rebuild_chunks()
	
	_show_status("Terrain base generated successfully.")

func _on_bake_pressed() -> void:
	if not current_terrain: return
	_show_status("Baking world...")
	var msg = TerrainBaker.bake_world(current_terrain)
	_show_status(msg)

func _on_glb_pressed() -> void:
	if not current_terrain: return
	_show_status("Exporting to GLB...")
	var msg = TerrainExporter.export_to_glb(current_terrain)
	_show_status(msg)

func _on_obj_pressed() -> void:
	if not current_terrain: return
	_show_status("Exporting to OBJ...")
	var msg = TerrainExporter.export_to_obj(current_terrain)
	_show_status(msg)

func _on_tres_pressed() -> void:
	if not current_terrain: return
	_show_status("Exporting to Mesh Resource...")
	var msg = TerrainExporter.export_to_mesh_resource(current_terrain)
	_show_status(msg)

func _on_auto_paint_pressed() -> void:
	if not current_terrain: return
	_show_status("Auto-painting slopes and cliffs...")
	current_terrain.auto_paint_textures()
	_show_status("Auto-paint completed successfully.")

func _on_thermal_erode_pressed() -> void:
	if not current_terrain or not current_terrain.terrain_data:
		return
	_show_status("Running thermal erosion...")
	var thermal_service = load("res://addons/procedural_terrain_builder/src/services/thermal_erosion.gd")
	var affected = thermal_service.erode(current_terrain.terrain_data, 10, 0.002, 0.1)
	current_terrain.recalculate_terrain(affected)
	_show_status("Thermal erosion completed successfully.")

func _on_hydraulic_erode_pressed() -> void:
	if not current_terrain or not current_terrain.terrain_data:
		return
	_show_status("Running hydraulic erosion (GPU Accelerated)...")
	var gpu_service = load("res://addons/procedural_terrain_builder/src/services/gpu_hydraulic_erosion.gd")
	var affected = gpu_service.erode(current_terrain.terrain_data, 100000, 30, 0.05, 4.0, 4.0, 0.1, 0.1, 0.02, 0.01)
	current_terrain.recalculate_terrain(affected)
	_show_status("Hydraulic erosion completed successfully.")
