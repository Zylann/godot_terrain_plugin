extends Node


func _ready():
	set_process_input(true)


func _input(event):
	if event.type == InputEvent.KEY and event.pressed:
		if event.scancode == KEY_1:
			var box = preload("res://addons/zylann.terrain/demos/rb_cube.tscn").instance()
			box.set_translation(get_parent().get_translation() + Vector3(0, 3, 0))
			var f = -get_parent().get_node("Camera").get_transform().basis.z
			box.set_linear_velocity(f * 30.0)
			get_parent().get_parent().add_child(box)
