tool
extends EditorPlugin

const TARGET_TYPE = "Terrain"
const Terrain = preload("res://terrain.gd")

var current_object = null

var _pressed = false
var _mode_selector = null
var _paint_mode = Terrain.PAINT_MODE_ADD


func _enter_tree():
	add_custom_type(TARGET_TYPE, "Node", Terrain, preload("icon.png"))
	
	_mode_selector = MenuButton.new()
	_mode_selector.set_text("Terrain")
	var popup = _mode_selector.get_popup()
	popup.add_check_item("Add", Terrain.PAINT_MODE_ADD)
	popup.add_check_item("Subtract", Terrain.PAINT_MODE_SUBTRACT)
	popup.add_check_item("Smooth", Terrain.PAINT_MODE_SMOOTH)
	popup.set_item_checked(_paint_mode, true)
	popup.connect("item_pressed", self, "_on_mode_selector_item_pressed")
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _mode_selector)
	_mode_selector.hide()
	
	var selection = get_selection()
	selection.connect("selection_changed", self, "_on_selection_changed")
	_on_selection_changed()


func _exit_tree():
	var selection = get_selection()
	selection.disconnect("selection_changed", self, "_on_selection_changed")
	
	_mode_selector.free()
	_mode_selector = null
	
	remove_custom_type(TARGET_TYPE)


func _on_mode_selector_item_pressed(item_id):
	var popup = _mode_selector.get_popup()
	popup.set_item_checked(_paint_mode, false)
	popup.set_item_checked(item_id, true)
	_paint_mode = item_id


func _on_selection_changed():
	if current_object != null:
		var selected_nodes = get_selection().get_selected_nodes()
		if selected_nodes.size() != 1 or not handles(selected_nodes[0]):
			stop_edit()


func paint(camera, mouse_pos, mode):
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	
	var hit_pos = current_object.raycast(origin, dir)
	if hit_pos != null:
		current_object.paint_world_pos(hit_pos, mode)


func handles(object):
	return object extends Terrain


func edit(object):
	current_object = object
	_mode_selector.show()

func stop_edit():
	current_object = null
	_mode_selector.hide()


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
		
		if _paint_mode == Terrain.PAINT_MODE_ADD and Input.is_mouse_button_pressed(BUTTON_RIGHT):
			paint(camera, event.pos, Terrain.PAINT_MODE_SUBTRACT)
			captured_event = true
		
		elif Input.is_mouse_button_pressed(BUTTON_LEFT):
			paint(camera, event.pos, _paint_mode)
			captured_event = true
	
	return captured_event



