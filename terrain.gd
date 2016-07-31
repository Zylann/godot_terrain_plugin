tool
extends Node

const CHUNK_SIZE = 16
const MAX_TERRAIN_SIZE = 1024

const PAINT_MODE_ADD = 0
const PAINT_MODE_SUBTRACT = 1
const PAINT_MODE_SMOOTH = 2


const Util = preload("terrain_utils.gd")

class Chunk:
	var mesh_instance = null
	var pos = Vector2(0,0)

var terrain_size = 0 setget set_terrain_size, get_terrain_size
var material = null setget set_material, get_material

var _data = []
var _normals = []

var _brush = null
var _brush_sum = 0
var _brush_radius = 6

var _chunks = []
var _chunks_x = 0
var _chunks_y = 0
var _dirty_chunks = {}


func _get_property_list():
	return [
		{
			"name": "terrain_size",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT
		},
		{
			"name": "material",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_DEFAULT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Material"
		},
		# We just want to hide the following properties
		{
			"name": "_data",
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
	
	_on_terrain_size_changed()
	_generate_brush(_brush_radius)
	set_process(true)


func get_terrain_size():
	return terrain_size

func set_terrain_size(new_size):
	if new_size != terrain_size and new_size > 0:
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
		for y in range(0, _chunks.size()):
			var row = _chunks[y]
			for x in range(0, row.size()):
				var chunk = row[x]
				chunk.mesh_instance.set_material_override(material)


func _on_terrain_size_changed():
	_chunks_x = Util.up_div(terrain_size, CHUNK_SIZE)
	_chunks_y = Util.up_div(terrain_size, CHUNK_SIZE)
	
	if is_inside_tree():
		
		Util.resize_grid(_data, terrain_size+1, terrain_size+1, 0)
		Util.resize_grid(_normals, terrain_size+1, terrain_size+1, Vector3(0,1,0))
		Util.resize_grid(_chunks, _chunks_x, _chunks_y, funcref(self, "_create_chunk_cb"), funcref(self, "_delete_chunk_cb"))
		
		for key in _dirty_chunks.keys():
			if key.mesh_instance == null:
				_dirty_chunks.erase(key)
		
		for y in range(0, _chunks.size()-1):
			var row = _chunks[y]
			_set_chunk_dirty(row[row.size()-1])
		if _chunks.size() != 0:
			var last_row = _chunks[_chunks.size()-1]
			for x in range(0, last_row.size()):
				_set_chunk_dirty(last_row[x])
		
		_update_dirty_chunks()


func _delete_chunk_cb(chunk):
	chunk.mesh_instance.queue_free()
	chunk.mesh_instance = null


func _create_chunk_cb(x, y):
	#print("Creating chunk (" + str(x) + ", " + str(y) + ")")
	var chunk = Chunk.new()
	chunk.mesh_instance = MeshInstance.new()
	chunk.mesh_instance.set_name("chunk_" + str(x) + "_" + str(y))
	chunk.mesh_instance.set_translation(Vector3(x,0,y) * CHUNK_SIZE)
	if material != null:
		chunk.mesh_instance.set_material_override(material)
	chunk.pos = Vector2(x,y)
	add_child(chunk.mesh_instance)
	_dirty_chunks[chunk] = true
	#update_chunk(chunk)
	return chunk


func _generate_brush(radius):
	var size = 2*radius
	_brush = Util.create_grid(size, size, 0)
	_brush_sum = 0
	for y in range(-radius, radius):
		for x in range(-radius, radius):
			var d = Vector2(x,y).distance_to(Vector2(0,0)) / float(radius)
			var v = clamp(1.0 - d*d*d, 0.0, 1.0)
			_brush[y+radius][x+radius] = v
			_brush_sum += v


func _paint(tx0, ty0, factor=1.0):
	var brush_radius = _brush.size()/2
	for by in range(0, _brush.size()):
		var brush_row = _brush[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - brush_radius
			var ty = ty0 + by - brush_radius
			if cell_pos_is_valid(tx, ty):
				_data[ty][tx] += factor * brush_value
	
	_set_area_dirty(tx0, ty0, brush_radius)


func _smooth(tx0, ty0, factor=1.0):
	var brush_radius = _brush.size()/2
	var value_sum = 0
	
	for by in range(0, _brush.size()):
		var brush_row = _brush[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - brush_radius
			var ty = ty0 + by - brush_radius
			if cell_pos_is_valid(tx, ty):
				var data_value = _data[ty][tx]
				value_sum += data_value * brush_value
	
	var value_mean = value_sum / _brush_sum

	for by in range(0, _brush.size()):
		var brush_row = _brush[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - brush_radius
			var ty = ty0 + by - brush_radius
			if cell_pos_is_valid(tx, ty):
				var data_value = _data[ty][tx]
				_data[ty][tx] = lerp(data_value, value_mean, factor * brush_value)
	
	_set_area_dirty(tx0, ty0, brush_radius)


func _set_area_dirty(tx, ty, radius):
	var cx_min = (tx - radius) / CHUNK_SIZE
	var cy_min = (ty - radius) / CHUNK_SIZE
	var cx_max = (tx + radius) / CHUNK_SIZE
	var cy_max = (ty + radius) / CHUNK_SIZE
	
	for y in range(cy_min, cy_max+1):
		for x in range(cx_min, cx_max+1):
			if x >= 0 and y >= 0 and x < _chunks_x and y < _chunks_y:
				_set_chunk_dirty_at(x, y)

func _set_chunk_dirty_at(cx, cy):
	_set_chunk_dirty(_chunks[cy][cx])

func _set_chunk_dirty(chunk):
	_dirty_chunks[chunk] = true


func paint_world_pos(wpos, mode=PAINT_MODE_ADD):
	var cell_pos = world_to_cell_pos(wpos)
	var delta = 1.0/60.0
	
	if mode == PAINT_MODE_ADD:
		_paint(cell_pos.x, cell_pos.y, 50.0*delta)
	
	elif mode == PAINT_MODE_SUBTRACT:
		_paint(cell_pos.x, cell_pos.y, -50*delta)
		
	elif mode == PAINT_MODE_SMOOTH:
		_smooth(cell_pos.x, cell_pos.y, 4.0*delta)
	
	else:
		error("Unknown paint mode " + str(mode))


func _process(delta):
	_update_dirty_chunks()


func _update_dirty_chunks():
	for chunk in _dirty_chunks:
		update_chunk_at(chunk.pos.x, chunk.pos.y)
	_dirty_chunks.clear()


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


func update_chunk_at(cx, cy):
	var chunk = _chunks[cy][cx]
	update_chunk(chunk)

func update_chunk(chunk):
	var mesh = generate_mesh_at(chunk.pos.x * CHUNK_SIZE, chunk.pos.y * CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
	chunk.mesh_instance.set_mesh(mesh)


func generate_mesh_at(x0, y0, w, h):
	var st = SurfaceTool.new()
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	
	#print("Updating normals data (" + str(x0) + ", " + str(y0) + ", " + str(w) + ", " + str(h) + ")")
	#_debug_print_actual_size(_normals, "normals")
	update_normals_data_at(x0, y0, w, h)
	
	var max_y = y0 + w
	var max_x = x0 + h
	
	if max_y >= terrain_size:
		max_y = terrain_size
	if max_x >= terrain_size:
		max_x = terrain_size
	
	for y in range(y0, max_y):
		var row = _data[y]
		var normal_row = _normals[y]
		for x in range(x0, max_x):
			
			var p00 = Vector3(x-x0, row[x], y-y0)
			var p10 = Vector3(x+1-x0, row[x+1], y-y0)
			var p01 = Vector3(x-x0, _data[y+1][x], y+1-y0)
			var p11 = Vector3(x+1-x0, _data[y+1][x+1], y+1-y0)
			
			var n00 = normal_row[x]
			var n10 = normal_row[x+1]
			var n01 = _normals[y+1][x]
			var n11 = _normals[y+1][x+1]
			
			var uv00 = Vector2(0,0)
			var uv10 = Vector2(1,0)
			var uv11 = Vector2(1,1)
			var uv01 = Vector2(0,1)
			
			st.add_normal(n00)
			st.add_uv(uv00)
			st.add_vertex(p00)
			
			st.add_normal(n10)
			st.add_uv(uv10)
			st.add_vertex(p10)
			
			st.add_normal(n11)
			st.add_uv(uv11)
			st.add_vertex(p11)

			st.add_normal(n00)
			st.add_uv(uv00)
			st.add_vertex(p00)
			
			st.add_normal(n11)
			st.add_uv(uv11)
			st.add_vertex(p11)
			
			st.add_normal(n01)
			st.add_uv(uv01)
			st.add_vertex(p01)
	
	# We can't rely on automatic normals because they would produce seams at the edges of chunks,
	# so instead we generate the normals from the actual terrain data
	#st.generate_normals()

	st.index()
	var mesh = st.commit()
	return mesh


func get_terrain_value(x, y):
	if x < 0 or y < 0 or x >= terrain_size or y >= terrain_size:
		return 0.0
	return _data[y][x]


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
	
	return Vector3(left - right, 2.0, fore - back).normalized()

func update_normals_data_at(x0, y0, w, h):
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



