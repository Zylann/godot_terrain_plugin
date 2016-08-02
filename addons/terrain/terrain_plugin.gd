tool
extends EditorPlugin

const Terrain = preload("terrain.gd")
const Brush = preload("terrain_brush.gd")

const TARGET_TYPE = "Terrain"

var current_object = null

var _pressed = false
var _brush = null

var _panel = null


func _enter_tree():
	add_custom_type(TARGET_TYPE, "Node", Terrain, preload("icon.png"))
	
	_brush = Brush.new()
	
	# TODO Initial brush state doesn't match the GUI
	_panel = preload("brush_panel.tscn").instance()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _panel)
	_panel.connect("brush_size_changed", self, "_on_brush_size_changed")
	_panel.connect("brush_mode_changed", self, "_on_brush_mode_changed")
	_panel.connect("brush_shape_changed", self, "_on_brush_shape_changed")
	_panel.hide()
	
	var selection = get_selection()
	selection.connect("selection_changed", self, "_on_selection_changed")
	_on_selection_changed()


func _exit_tree():
	var selection = get_selection()
	selection.disconnect("selection_changed", self, "_on_selection_changed")
	
	_panel.free()
	_panel = null
	
	remove_custom_type(TARGET_TYPE)


func _on_selection_changed():
	if current_object != null:
		var selected_nodes = get_selection().get_selected_nodes()
		if selected_nodes.size() != 1 or not handles(selected_nodes[0]):
			stop_edit()


func _on_brush_size_changed(size):
	_brush.generate(size)


func _on_brush_mode_changed(mode):
	_brush.set_mode(mode)


func _on_brush_shape_changed(tex):
	assert(tex extends ImageTexture)
	_brush.generate_from_image(tex.get_data())


func paint(camera, mouse_pos, mode=-1):
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	
	var hit_pos = current_object.raycast(origin, dir)
	if hit_pos != null:
		_brush.paint_world_pos(current_object, hit_pos, mode)


func handles(object):
	return object extends Terrain


func edit(object):
	current_object = object
	_panel.show()

func stop_edit():
	current_object = null
	_panel.hide()


func forward_spatial_input_event(camera, event):
	var captured_event = false
	
	if event.type == InputEvent.MOUSE_BUTTON:
		if event.button_index == BUTTON_LEFT or event.button_index == BUTTON_RIGHT:
			captured_event = true
			if event.is_pressed():
				_pressed = true
			else:
				_pressed = false
	
	elif _pressed and event.type == InputEvent.MOUSE_MOTION:
		
		if _brush.get_mode() == Brush.MODE_ADD and Input.is_mouse_button_pressed(BUTTON_RIGHT):
			paint(camera, event.pos, Brush.MODE_SUBTRACT)
			captured_event = true
		
		elif Input.is_mouse_button_pressed(BUTTON_LEFT):
			paint(camera, event.pos)
			captured_event = true
	
	return captured_event



