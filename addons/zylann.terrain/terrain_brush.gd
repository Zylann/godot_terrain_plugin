
const Util = preload("terrain_utils.gd")

const MODE_ADD = 0
const MODE_SUBTRACT = 1
const MODE_SMOOTH = 2
const MODE_FLATTEN = 3
const MODE_COUNT = 4


var _data = []
var _radius = 4
var _opacity = 1.0 # TODO Should be renamed "hardness"
var _sum = 0.0
var _mode = MODE_ADD
var _mode_secondary = MODE_SUBTRACT
var _source_image = null
var _use_undo_redo = false
var _flatten_height = 0.0


func _init():
	generate(_radius)


func generate(radius):
	if _source_image == null:
		generate_procedural(radius)
	else:
		generate_from_image(_source_image, radius)


func generate_procedural(radius):
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


func generate_from_image(image, radius=-1):
	if image.get_width() != image.get_height():
		print("Brush shape image must be square!")
		return
	
	_source_image = image
	
	if radius < 0:
		radius = _radius
	else:
		_radius = radius
	
	var size = radius*2
	if size != image.get_width():
		image = image.resized(size, size, Image.INTERPOLATE_BILINEAR)
	
	_data = Util.create_grid(image.get_width(), image.get_height(), 0)
	_sum = 0
	
	for y in range(0, image.get_height()):
		for x in range(0, image.get_width()):
			var color = image.get_pixel(x,y)
			var h = color.a
			_data[y][x] = h
			_sum += h


func set_radius(r):
	if r > 0 and r != _radius:
		_radius = r
		generate(r)

func get_radius():
	return _radius


func set_opacity(opacity):
	_opacity = clamp(opacity, 0.0, 2.0)


func set_mode(mode):
	assert(mode >= 0 and mode < MODE_COUNT)
	_mode = mode

func get_mode():
	return _mode


func set_flatten_height(h):
	_flatten_height = h

func get_flatten_height():
	return _flatten_height


func set_undo_redo(use_undo_redo):
	_use_undo_redo = use_undo_redo


func paint_world_pos(terrain, wpos, override_mode=-1):
	var cell_pos = terrain.world_to_cell_pos(wpos)
	var delta = _opacity * 1.0/60.0
	
	var mode = _mode
	if override_mode != -1:
		mode = override_mode
	
	if mode == MODE_ADD:
		_paint(terrain, cell_pos.x, cell_pos.y, 50.0*delta)
	
	elif mode == MODE_SUBTRACT:
		_paint(terrain, cell_pos.x, cell_pos.y, -50*delta)
		
	elif mode == MODE_SMOOTH:
		_smooth(terrain, cell_pos.x, cell_pos.y, 4.0*delta)
	
	elif mode == MODE_FLATTEN:
		_flatten(terrain, cell_pos.x, cell_pos.y, _flatten_height)
	
	else:
		error("Unknown paint mode " + str(mode))


func _foreach_xy(terrain, tx0, ty0, operator, modifier=true):
	if modifier:
		terrain.set_area_dirty(tx0, ty0, _radius, _use_undo_redo)
	
	var data = terrain.get_data()
	var brush_radius = _data.size()/2
	
	operator.dst = data
	
	for by in range(0, _data.size()):
		var brush_row = _data[by]
		for bx in range(0, brush_row.size()):
			var brush_value = brush_row[bx]
			var tx = tx0 + bx - brush_radius
			var ty = ty0 + by - brush_radius
			# TODO We could get rid if this `if` by calculating proper bounds beforehands
			if terrain.cell_pos_is_valid(tx, ty):
				operator.exec(tx, ty, brush_value)

# TODO Update this part when Godot will support lambdas

class Operator:
	var dst = null
	var opacity = 1.0

class AddOperator extends Operator:
	var factor = 1.0
	func exec(x, y, value):
		dst[y][x] = dst[y][x] + factor * value

class LerpOperator extends Operator:
	var height = 0.0
	func exec(x, y, value):
		dst[y][x] = lerp(dst[y][x], height, value * opacity)

class SumOperator extends Operator:
	var sum = 0.0
	func exec(x, y, value):
		sum += dst[y][x] * value


func _paint(terrain, tx0, ty0, factor=1.0):
	var op = AddOperator.new()
	op.factor = factor
	_foreach_xy(terrain, tx0, ty0, op)


func _flatten(terrain, tx0, ty0, height):
	var op = LerpOperator.new()
	op.height = height
	op.opacity = clamp(_opacity, 0.0, 1.0)
	_foreach_xy(terrain, tx0, ty0, op)


func _smooth(terrain, tx0, ty0, factor=1.0):
	var sum_op = SumOperator.new()
	_foreach_xy(terrain, tx0, ty0, sum_op, false)
	
	var lerp_op = LerpOperator.new()
	lerp_op.height = sum_op.sum / _sum
	lerp_op.opacity = clamp(_opacity, 0.0, 1.0)
	_foreach_xy(terrain, tx0, ty0, lerp_op)


