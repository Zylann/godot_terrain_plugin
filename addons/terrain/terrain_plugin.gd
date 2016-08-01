tool
extends EditorPlugin

const Terrain = preload("terrain.gd")
const Brush = preload("terrain_brush.gd")

const TARGET_TYPE = "Terrain"

var current_object = null

var _pressed = false
var _mode_selector = null
var _brush = null


func _enter_tree():
	add_custom_type(TARGET_TYPE, "Node", Terrain, preload("icon.png"))
	
	_brush = Brush.new()
	_brush.generate(4)
	
	# TODO This is going to become a mess, move that to another script
	_mode_selector = MenuButton.new()
	_mode_selector.set_text("Terrain")
	var popup = _mode_selector.get_popup()
	popup.add_check_item("Add", Brush.MODE_ADD)
	popup.add_check_item("Subtract", Brush.MODE_SUBTRACT)
	popup.add_check_item("Smooth", Brush.MODE_SMOOTH)
	popup.set_item_checked(_brush.get_mode(), true)
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
	popup.set_item_checked(_brush.get_mode(), false)
	popup.set_item_checked(item_id, true)
	_brush.set_mode(item_id)


func _on_selection_changed():
	if current_object != null:
		var selected_nodes = get_selection().get_selected_nodes()
		if selected_nodes.size() != 1 or not handles(selected_nodes[0]):
			stop_edit()


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
		
		if _brush.get_mode() == Brush.MODE_ADD and Input.is_mouse_button_pressed(BUTTON_RIGHT):
			paint(camera, event.pos, Brush.MODE_SUBTRACT)
			captured_event = true
		
		elif Input.is_mouse_button_pressed(BUTTON_LEFT):
			paint(camera, event.pos)
			captured_event = true
	
	return captured_event



