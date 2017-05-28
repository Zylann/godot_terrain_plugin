extends Node2D

const Lodder = preload("res://addons/zylann.terrain/quad_tree_lod.gd")

export(NodePath) var terrain_path = null

var lodder = null
var _is_external_lodder = false

func _ready():
	var terrain = null
	if terrain_path != null:
		terrain = get_node(terrain_path)
	if terrain == null:
		lodder = Lodder.new()
	else:
		lodder = terrain._lodder
		_is_external_lodder = true
	set_process(true)


func _process(delta):
	if not _is_external_lodder:
		var pos = get_global_mouse_pos()
		pos = Vector3(pos.x, 0, pos.y)
		lodder.update_now(pos)
	update()


func _draw():
	lodder.debug_draw_tree(self)


