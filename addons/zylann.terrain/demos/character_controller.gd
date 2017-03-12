extends KinematicBody

export var speed = 5.0
export var gravity = 9.8
export(NodePath) var head = null

var _velocity = Vector3()
var _head = null


func _ready():
	set_fixed_process(true)
	_head = get_node(head)


func _fixed_process(delta):
	
	var forward = _head.get_transform().basis.z
	forward = Plane(Vector3(0, 1, 0), 0).project(forward)
	var right = _head.get_transform().basis.x
	var motor = Vector3()
	
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W):
		motor -= forward
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		motor += forward
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A):
		motor -= right
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		motor += right
	
	motor = motor.normalized() * speed
	
	_velocity.x = motor.x
	_velocity.z = motor.z
	_velocity.y -= gravity * delta
	
	var motion = _velocity * delta
	
	var rem = move(motion)
	
	if is_colliding():
		var n = get_collision_normal()
		rem = n.slide(rem)
		_velocity = n.slide(_velocity)
		move(rem)

