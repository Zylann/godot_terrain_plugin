tool
extends EditorPlugin

const TARGET_TYPE = "Terrain"
const Terrain = preload("res://terrain.gd")

var current_object = null

var _pressed = false


func _enter_tree():
	add_custom_type(TARGET_TYPE, "Node", Terrain, preload("icon.png"))


func _exit_tree():
	remove_custom_type(TARGET_TYPE)


func paint(camera, mouse_pos, mode):
	var origin = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	
	var hit_pos = current_object.raycast(origin, dir)
	if hit_pos != null:
		current_object.paint_world_pos(hit_pos, mode)


func handles(object):
	print("Handles " + str(object.get_type()))
	#return object.is_type(TARGET_TYPE)
	return object extends Terrain

# TODO Use the selection in Godot 2.1
func edit(object):
	#print("edit(" + str(object) + ")")
	current_object = object


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
		
		if Input.is_mouse_button_pressed(BUTTON_LEFT):
			paint(camera, event.pos, Terrain.PAINT_MODE_ADD)
			captured_event = true
			
		elif Input.is_mouse_button_pressed(BUTTON_RIGHT):
			paint(camera, event.pos, Terrain.PAINT_MODE_SUBTRACT)
			captured_event = true
	
	return captured_event



