
const Util = preload("terrain_utils.gd")

const MODE_ADD = 0
const MODE_SUBTRACT = 1
const MODE_SMOOTH = 2
const MODE_COUNT = 3

var _data = []
var _radius = 0
var _sum = 0.0
var _mode = MODE_ADD
var _mode_secondary = MODE_SUBTRACT


func generate(radius):
	_radius = radius
	var size = 2*radius
	_data = Util.create_grid(size, size, 0)
	_sum = 0
	for y in range(-radius, radius):
		for x in range(-radius, radius):
			var d = Vector2(x,y).distance_to(Vector2(0,0)) / float(radius)
			var v = clamp(1.0 - d*d*d, 0.0, 1.0)
			_data[y+radius][x+radius] = v
			_sum += v


func set_radius(r):
	if r > 0 and r != _radius:
		_radius = r
		_generate_brush(r)
		print("Change brush radius " + str(r))


func set_mode(mode):
	assert(mode >= 0 and mode < MODE_COUNT)
	_mode = mode


func get_mode():
	return _mode


func paint_world_pos(terrain, wpos, override_mode=-1):
	var cell_pos = terrain.world_to_cell_pos(wpos)
	var delta = 1.0/60.0
	
	var mode = _mode
	if override_mode != -1:
		mode = override_mode
	
	if mode == MODE_ADD:
		_paint(terrain, cell_pos.x, cell_pos.y, 50.0*delta)
	
	elif mode == MODE_SUBTRACT:
		_paint(terrain, cell_pos.x, cell_pos.y, -50*delta)
		
	elif mode == MODE_SMOOTH:
		_smooth(terrain, cell_pos.x, cell_pos.y, 4.0*delta)
	
	else:
		error("Unknown paint mode " + str(mode))


func _paint(terrain, tx0, ty0, factor=1.0):
	var data = terrain.get_data()
	var brush_radius = _data.size()/2
	
	for by in range(0, _data.size()):
		var brush_row = _data[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - brush_radius
			var ty = ty0 + by - brush_radius
			if terrain.cell_pos_is_valid(tx, ty):
				data[ty][tx] += factor * brush_value
	
	terrain.set_area_dirty(tx0, ty0, _radius)


func _smooth(terrain, tx0, ty0, factor=1.0):
	var data = terrain.get_data()
	var value_sum = 0
	
	for by in range(0, _data.size()):
		var brush_row = _data[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - _radius
			var ty = ty0 + by - _radius
			if terrain.cell_pos_is_valid(tx, ty):
				var data_value = data[ty][tx]
				value_sum += data_value * brush_value
	
	var value_mean = value_sum / _sum
	
	for by in range(0, _data.size()):
		var brush_row = _data[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - _radius
			var ty = ty0 + by - _radius
			if terrain.cell_pos_is_valid(tx, ty):
				var data_value = data[ty][tx]
				data[ty][tx] = lerp(data_value, value_mean, factor * brush_value)
	
	terrain.set_area_dirty(tx0, ty0, _radius)

