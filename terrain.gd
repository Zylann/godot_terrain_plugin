tool
extends Node

const CHUNK_SIZE = 16

class Chunk:
	var mesh_instance = null
	var pos = Vector2(0,0)


export(int) var terrain_size = 64

var _data = null
var _normals = null

var _brush = null
var _brush_sum = 0

var _chunks = null
var _chunks_x = 0
var _chunks_y = 0
var _dirty_chunks = {}


func _ready():
	set_process_input(true)
	
	_data = create_grid(terrain_size, terrain_size, 0.0)
	_normals = create_grid(terrain_size, terrain_size, Vector3(0,1,0))
	
	_chunks_x = up_div(terrain_size, CHUNK_SIZE)
	_chunks_y = up_div(terrain_size, CHUNK_SIZE)
	_chunks = create_grid(_chunks_x, _chunks_y)
	for y in range(_chunks.size()):
		var row = _chunks[y]
		for x in range(row.size()):
			var chunk = Chunk.new()
			chunk.mesh_instance = MeshInstance.new()
			chunk.mesh_instance.set_name("chunk_" + str(x) + "_" + str(y))
			chunk.mesh_instance.set_translation(Vector3(x,0,y) * CHUNK_SIZE)
			chunk.pos = Vector2(x,y)
			add_child(chunk.mesh_instance)
			row[x] = chunk
			update_chunk_at(x,y)
	
	_generate_brush(6)
	#generate_terrain()
	if not get_tree().is_editor_hint():
		set_process(true)


static func up_div(a, b):
	if a % b != 0:
		return a / b + 1
	return a / b


func _generate_brush(radius):
	var size = 2*radius
	_brush = create_grid(size, size, 0)
	_brush_sum = 0
	for y in range(-radius, radius):
		for x in range(-radius, radius):
			var d = Vector2(x,y).distance_to(Vector2(0,0)) / float(radius)
			var v = clamp(1.0 - d*d, 0.0, 1.0)
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
	var chunk = _chunks[cy][cx]
	_dirty_chunks[chunk] = true


func _process(delta):
	var camera = get_parent().get_node("Camera")
	var origin = camera.get_translation()
	var dir = camera.get_transform().basis * Vector3(0,0,-1)
	var hit_pos = raycast(origin, dir)
	if hit_pos != null:
		get_parent().get_node("TestCube").set_translation(hit_pos)
		
		var up = Input.is_mouse_button_pressed(BUTTON_LEFT)
		var down = Input.is_mouse_button_pressed(BUTTON_RIGHT)
		
		if up or down:
			var cell_pos = world_to_cell_pos(hit_pos)
			if Input.is_key_pressed(KEY_X):
				var factor = 4.0*delta
				_smooth(cell_pos.x, cell_pos.y, factor)
			else:
				var factor = 20.0 * delta
				if down:
					factor = -factor
				_paint(cell_pos.x, cell_pos.y, factor)
	
	_update_dirty_chunks()


func _update_dirty_chunks():
	for chunk in _dirty_chunks:
		update_chunk_at(chunk.pos.x, chunk.pos.y)
	_dirty_chunks.clear()


func world_to_cell_pos(wpos):
	#wpos -= _mesh_instance.get_translation()
	return Vector2(int(wpos.x), int(wpos.z))


func cell_pos_is_valid(x, y):
	return x >= 0 and y >= 0 and x < terrain_size and y < terrain_size


func generate_terrain():
	for y in range(_data.size()):
		var row = _data[y]
		for x in range(row.size()):
			row[x] = 2.0 * (cos(x*0.2) + sin(y*0.2))


func update_chunk_at(cx, cy):
	var chunk = _chunks[cy][cx]
	var mesh = generate_mesh_at(cx * CHUNK_SIZE, cy * CHUNK_SIZE, CHUNK_SIZE, CHUNK_SIZE)
	chunk.mesh_instance.set_mesh(mesh)


func generate_mesh_at(x0, y0, w, h):
	var st = SurfaceTool.new()
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	
	update_normals_data_at(x0, y0, w, h)
	
	var max_y = y0 + w
	var max_x = x0 + h
	
	if max_y+1 >= terrain_size:
		max_y = terrain_size - 2
	if max_x+1 >= terrain_size:
		max_x = terrain_size - 2
	
	for y in range(y0, max_y):
		var row = _data[y]
		var normal_row = _normals[y]
		for x in range(x0, max_x):
			
			var h00 = row[x]
			var h10 = row[x+1]
			var h01 = _data[y+1][x]
			var h11 = _data[y+1][x+1]
			
			st.add_color(Color(0,1,0))
			
			var n00 = normal_row[x]
			var n10 = normal_row[x+1]
			var n01 = _normals[y+1][x]
			var n11 = _normals[y+1][x+1]
			
			st.add_normal(n00)
			st.add_vertex(Vector3(x-x0, h00, y-y0))
			
			st.add_normal(n10)
			st.add_vertex(Vector3(x+1-x0, h10, y-y0))
			
			st.add_normal(n11)
			st.add_vertex(Vector3(x+1-x0, h11, y+1-y0))

			st.add_normal(n00)
			st.add_vertex(Vector3(x-x0, h00, y-y0))
			
			st.add_normal(n11)
			st.add_vertex(Vector3(x+1-x0, h11, y+1-y0))
			
			st.add_normal(n01)
			st.add_vertex(Vector3(x-x0, h01, y+1-y0))
	
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
	var max_distance = 100.0
	while d < max_distance:
		pos += dir * unit
		if not position_is_above(pos):
			return pos - dir * unit
		d += unit
	return null


func _input(event):
	pass


static func create_grid(w, h, v=null):
	var grid = []
	grid.resize(h)
	for y in range(grid.size()):
		var row = []
		row.resize(w)
		for x in range(row.size()):
			row[x] = v
		grid[y] = row
	return grid


