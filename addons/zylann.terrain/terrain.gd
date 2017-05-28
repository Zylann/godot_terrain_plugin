tool
extends Node

const Util = preload("terrain_utils.gd")
const Chunk = preload("terrain_chunk.gd")
const Mesher = preload("terrain_mesher.gd")
const Lodder = preload("quad_tree_lod.gd")

const CHUNK_SIZE = 16
const MAX_TERRAIN_SIZE = 1024

# Indexes for terrain data channels
const DATA_HEIGHT = 0
const DATA_NORMALS = 1
const DATA_COLOR = 2
const DATA_CHANNEL_COUNT = 3

# Note: the limit of 1024 is only because above this, GDScript and rendering become too slow
export(int, 0, 1024) var terrain_size = 128 setget set_terrain_size, get_terrain_size
export(Material) var material = null setget set_material, get_material
export var smooth_shading = true setget set_smooth_shading
export var generate_colliders = false setget set_generate_colliders

# TODO reduz worked on float Image format recently, keep that in mind for future optimization
var _data = []
var _colors = []
# Calculated
var _normals = []

# Size of the terrain in highest-LOD chunks
var _chunks_x = 0
var _chunks_y = 0

# When normals get dirty, we map them by highest-LOD chunks instead of updating everything
var _dirty_normals_chunks = {}
# Chunks pending update. Array of dictionaries, indexed by [lod_index][chunk_pos]
var _dirty_lod_chunks = []
# When terrain data get dirty, we map it by highest-LOD chunks instead of saving everything
var _undo_chunks = {}

var _lodder = null


func _get_property_list():
	return [
		# We just want to hide the following properties
		{
			"name": "_data",
			"type": TYPE_ARRAY,
			"usage": PROPERTY_USAGE_STORAGE
		},
		{
			"name": "_colors",
			"type": TYPE_ARRAY,
			"usage": PROPERTY_USAGE_STORAGE
		}
	]


func _ready():
	# !!!
	# TODO MEGA WARNINGS OF THE DEATH:
	# - exporting an array will load it in COW mode!!! this will break everything!!!
	# - reloading the script makes data LOST FOREVER
	# UGLY FIX, remove asap when Godot will be fixed, it severely impacts loading performance on huge terrains
	_data = Util.clone_grid(_data)
	_colors = Util.clone_grid(_colors)
	
	_lodder = Lodder.new()
	_reset_lods()
	_lodder.make_chunk_func = funcref(self, "_make_lod_chunk_cb")
	_lodder.recycle_chunk_func = funcref(self, "_recycle_lod_chunk_cb")
	
	_on_terrain_size_changed()
	_on_generate_colliders_changed()
	update_lods()
	set_process(true)

# Called when a chunk is needed at a given LOD
func _make_lod_chunk_cb(lod_index, origin):
	# TODO This is inefficient, should use chunk pooling
	var x = round(origin.x)
	var y = round(origin.y)
	var chunk = Chunk.new()
	chunk.create(x, y, CHUNK_SIZE, self, material)
	update_chunk(chunk, lod_index)
	if generate_colliders and lod_index == 0:
		chunk.update_collider()
	return chunk


# Called when a chunk is no longer needed
func _recycle_lod_chunk_cb(chunk):
	# TODO This is inefficient, should use chunk pooling
	chunk.clear()


func _reset_lods():
	_lodder.from_sizes(CHUNK_SIZE, terrain_size)


func get_terrain_size():
	return terrain_size

func set_terrain_size(new_size):
	if new_size != terrain_size:
		# Having a power of two is important for LOD
		new_size = nearest_po2(new_size)
		
		if new_size > MAX_TERRAIN_SIZE:
			new_size = MAX_TERRAIN_SIZE
			print("Max size reached, clamped at " + str(MAX_TERRAIN_SIZE) + " for your safety :p")
		terrain_size = new_size
		#print("Setting terrain_size to " + str(terrain_size))
		_on_terrain_size_changed()


func get_material():
	return material

func set_material(new_material):
	if new_material != material:
		material = new_material
		if is_inside_tree():
			_lodder.for_all_chunks(funcref(self, "_set_material_cb"))

func _set_material_cb(chunk):
	if chunk.mesh_instance != null:
		chunk.mesh_instance.set_material_override(material)


func set_smooth_shading(smooth):
	if smooth != smooth_shading:
		smooth_shading = smooth
		_force_update_all_chunks()


# TODO Should be renamed get_height_data (could also use get_data_channel)
# Direct data access for better performance.
# If you want to modify the data through this, don't forget to set the area as dirty
func get_data():
	return _data

func get_data_channel(channel):
	if channel == DATA_HEIGHT:
		return _data
	elif channel == DATA_COLOR:
		return _colors
	elif channel == DATA_NORMALS:
		return _normals
	else:
		print("Unknown channel " + str(channel))
		assert(channel < DATA_CHANNEL_COUNT)


func _on_terrain_size_changed():
	var prev_chunks_x = _chunks_x
	var prev_chunks_y = _chunks_y
	
	_chunks_x = Util.up_div(terrain_size, CHUNK_SIZE)
	_chunks_y = Util.up_div(terrain_size, CHUNK_SIZE)
	
	if is_inside_tree():
		
		# Resize data grids
		# Important: grid data is off by one,
		# because for an even number of quads you need an odd number of vertices
		Util.resize_grid(_data, terrain_size+1, terrain_size+1, 0)
		Util.resize_grid(_normals, terrain_size+1, terrain_size+1, Vector3(0,1,0))
		Util.resize_grid(_colors, terrain_size+1, terrain_size+1, Color(1,1,1,1))
		
		_update_all_normals()
		_reset_lods()
		
		# This is to prevent the user from seeing the entire terrain disappear,
		# because lods need the editor camera to update, for that reason they update
		# only if the viewport receives an event...
		if get_tree().is_editor_hint():
			update_lods()


# Call this just before modifying the terrain
func set_area_dirty(tx, ty, radius, mark_for_undo=false, data_channel=DATA_HEIGHT):
	assert(typeof(tx) == TYPE_INT)
	assert(typeof(ty) == TYPE_INT)
	assert(typeof(radius) == TYPE_INT)
	
	var cx_min = (tx - radius) / CHUNK_SIZE
	var cy_min = (ty - radius) / CHUNK_SIZE
	var cx_max = (tx + radius) / CHUNK_SIZE
	var cy_max = (ty + radius) / CHUNK_SIZE
	
	for cy in range(cy_min, cy_max+1):
		for cx in range(cx_min, cx_max+1):
			if cx >= 0 and cy >= 0 and cx < _chunks_x and cy < _chunks_y:
				_set_normals_chunk_dirty_at(cx, cy)
				if mark_for_undo:
					var k = Vector2(cx,cy)
					if not _undo_chunks.has(k):
						var data = extract_chunk_data(cx, cy, data_channel)
						_undo_chunks[k] = data
	
	_lodder.for_chunks_in_rect(funcref(self, "_set_lod_chunk_dirty_cb"), cx_min, cy_min, 2*radius, 2*radius)


func _set_lod_chunk_dirty_cb(chunk, origin, lod_index):
	if _dirty_lod_chunks.size() <= lod_index:
		_dirty_lod_chunks.resize(lod_index+1)
	var chunks = _dirty_lod_chunks[lod_index]
	if chunks == null:
		chunks = {}
		_dirty_lod_chunks[lod_index] = chunks
	if not chunks.has(origin):
		chunks[origin] = true


func extract_chunk_data(cx, cy, data_channel):
	var x0 = cx * CHUNK_SIZE
	var y0 = cy * CHUNK_SIZE
	var grid = get_data_channel(data_channel)
	var cell_data = Util.grid_extract_area_safe_crop(grid, x0, y0, CHUNK_SIZE, CHUNK_SIZE)
	var d = {
		"cx": cx,
		"cy": cy,
		"data": cell_data,
		"channel": data_channel
	}
	return d


func apply_chunks_data(chunks_data):
	for cdata in chunks_data:
		_set_normals_chunk_dirty_at(cdata.cx, cdata.cy)
		var x0 = cdata.cx * CHUNK_SIZE
		var y0 = cdata.cy * CHUNK_SIZE
		var grid = get_data_channel(cdata.channel)
		Util.grid_paste(cdata.data, grid, x0, y0)
		_lodder.for_chunks_in_rect(funcref(self, "_set_lod_chunk_dirty_cb"), cdata.cx, cdata.cy, 1, 1)


# Get this data just after finishing an edit action (if you use undo/redo)
func pop_undo_redo_data(data_channel):
	var undo_data = []
	var redo_data = []
	
	for k in _undo_chunks:
		
		var undo = _undo_chunks[k]
		undo_data.append(undo)
		
		var redo = extract_chunk_data(undo.cx, undo.cy, data_channel)
		redo_data.append(redo)
		
		# Debug check
		#assert(not Util.grid_equals(undo.data, redo.data))
		
	_undo_chunks = {}
	
	return {
		undo = undo_data,
		redo = redo_data
	}


func _set_normals_chunk_dirty_at(cx, cy):
	_dirty_normals_chunks[Vector2(cx,cy)] = true


func _process(delta):
	# Upate dirty normals (dynamic terrain edition)
	for k in _dirty_normals_chunks:
		_update_normals_chunk_at(k.x, k.y)
	_dirty_normals_chunks.clear()
	
	# Update lods (dynamic lod)
	if get_tree().is_editor_hint() == false:
		update_lods()
	
	# Update dirty lods (dynamic terrain edition)
	for lod_index in range(0, _dirty_lod_chunks.size()):
		var chunks = _dirty_lod_chunks[lod_index]
		# Note: that can be null if that LOD level was never reached yet
		if chunks != null:
			for cpos in chunks:
				var chunk = _lodder.get_chunk_at(cpos.x, cpos.y, lod_index)
				if chunk != null:
					update_chunk(chunk, lod_index)
	_dirty_lod_chunks.clear()


func update_lods(fallback_viewer=null):
	var viewer_pos = Vector3(0,0,0)
	var viewport = get_viewport()
	if viewport != null:
		var viewer = get_viewport().get_camera()
		if viewer == null:
			viewer = fallback_viewer
		if viewer != null:
			viewer_pos = viewer.get_global_transform().origin
	#print("Updating lods from ", viewer_pos)
	_lodder.update_now(viewer_pos)


func _force_update_all_chunks():
	_lodder.for_all_chunks(funcref("_force_update_chunk_cb"))

func _force_update_chunk_cb(chunk, lod_index):
	update_chunk(chunk, lod_index)


func world_to_cell_pos(wpos):
	#wpos -= _mesh_instance.get_translation()
	return Vector2(int(wpos.x), int(wpos.z))


func cell_pos_is_valid(x, y):
	return x >= 0 and y >= 0 and x <= terrain_size and y <= terrain_size

#func generate_terrain():
#	for y in range(_data.size()):
#		var row = _data[y]
#		for x in range(row.size()):
#			row[x] = 2.0 * (cos(x*0.2) + sin(y*0.2))

func _update_normals_chunk_at(cx, cy):
	var x0 = cx * CHUNK_SIZE
	var y0 = cy * CHUNK_SIZE
	var w = CHUNK_SIZE
	var h = CHUNK_SIZE
	
	if smooth_shading:
		_update_normals_data_at(x0, y0, w+1, h+1)


# This function is the most time-consuming one in this tool.
func update_chunk(chunk, lod_index=0):
	var x0 = chunk.pos.x * CHUNK_SIZE
	var y0 = chunk.pos.y * CHUNK_SIZE
	var w = CHUNK_SIZE
	var h = CHUNK_SIZE
	
	var opt = {
		"heights": _data,
		"normals": _normals,
		"colors": _colors,
		"x0": x0,
		"y0": y0,
		"w": w,
		"h": h,
		"smooth_shading": smooth_shading,
		"lod_index": lod_index
	}
	
	var mesh = Mesher.make_heightmap(opt)
	chunk.mesh_instance.set_mesh(mesh)
	
	if get_tree().is_editor_hint() == false:
		if generate_colliders:
			chunk.update_collider()
		else:
			chunk.clear_collider()


# TODO Should be renamed get_terrain_height
func get_terrain_value(x, y):
	if x < 0 or y < 0 or x >= terrain_size or y >= terrain_size:
		return 0.0
	return _data[y][x]

# TODO Should be renamed get_terrain_height_worldv
func get_terrain_value_worldv(pos):
	#pos -= _mesh_instance.get_translation()
	return get_terrain_value(int(pos.x), int(pos.z))

func position_is_above(pos):
	return pos.y > get_terrain_value_worldv(pos)


func _calculate_normal_at(x, y):
	#var center = get_terrain_value(x,y)
	var left = get_terrain_value(x-1,y)
	var right = get_terrain_value(x+1,y)
	var fore = get_terrain_value(x,y+1)
	var back = get_terrain_value(x,y-1)
	
	return Vector3(left - right, 2.0, back - fore).normalized()

func _update_normals_data_at(x0, y0, w, h):
	if x0 + w > terrain_size:
		w = terrain_size - x0
	if y0 + h > terrain_size:
		h = terrain_size - y0
	var max_x = x0+w
	var max_y = y0+h
	for y in range(y0, max_y):
		var row = _normals[y]
		for x in range(x0, max_x):
			row[x] = _calculate_normal_at(x,y)

func _update_all_normals():
	# TODO Shouldn't the size be off by one?
	_update_normals_data_at(0, 0, terrain_size, terrain_size)


# TODO Should be renamed `slow_raycast`
# This is a quick and dirty raycast, but it's enough for edition
func raycast(origin, dir):
	if not position_is_above(origin):
		return null
	var pos = origin
	var unit = 1.0
	var d = 0.0
	var max_distance = 800.0
	while d < max_distance:
		pos += dir * unit
		if not position_is_above(pos):
			return pos - dir * unit
		d += unit
	return null


func set_generate_colliders(gen_colliders):
	if generate_colliders != gen_colliders:
		generate_colliders = gen_colliders
		_on_generate_colliders_changed()

func _on_generate_colliders_changed():
	# Don't generate colliders if not in tree yet, will produce errors otherwise
	if not is_inside_tree():
		return
	# Don't generate colliders in the editor, it's useless and time consuming
	if get_tree().is_editor_hint():
		return
	_lodder.for_all_chunks(funcref(self, "_update_generate_collider_for_chunk"))

func _update_generate_collider_for_chunk(chunk, lod_index):
	if generate_colliders:
		chunk.update_collider()
	else:
		chunk.clear_collider()
