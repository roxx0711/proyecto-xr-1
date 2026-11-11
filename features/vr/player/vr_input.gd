class_name VRInput
extends Node
## Desktop adapter and OpenXR share exactly the same gameplay commands.
@export var move_action: StringName = &"primary"
@export var turn_action: StringName = &"primary"
@export var grip_action: StringName = &"grip"
@export var use_action: StringName = &"trigger"
@export var teleport_action: StringName = &"ax_button"
@export var flight_action: StringName = &"by_button"
var xr_active: bool = false
var _pitch: float = 0.0
var _camera: XRCamera3D
var _body: CharacterBody3D
var _left: VRHand
var _right: VRHand
var _left_desktop_offset: Vector3 = Vector3.ZERO
var _right_desktop_offset: Vector3 = Vector3.ZERO
var _flight_button_down: bool = false

func configure(active: bool, body: CharacterBody3D, camera: XRCamera3D, left: VRHand, right: VRHand) -> void:
	xr_active = active
	_body = body
	_camera = camera
	_left = left
	_right = right
	if not active:
		_camera.position = Vector3(0.0, 1.7, 0.0)
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if xr_active or _camera == null:
		return
	if event.is_action_pressed(&"desktop_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if _drag_desktop_hands(motion.relative):
			return
		_body.rotate_y(-motion.relative.x * 0.002)
		_pitch = clampf(_pitch - motion.relative.y * 0.002, -1.2, 1.2)
		_camera.rotation.x = _pitch
	if event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var button := event as InputEventMouseButton
		if button.pressed and (Input.is_action_pressed(&"desktop_grab_left") or Input.is_action_pressed(&"desktop_grab_right")):
			var depth_delta := -0.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.15
			if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if Input.is_action_pressed(&"desktop_grab_left"):
					_left_desktop_offset.z = clampf(_left_desktop_offset.z + depth_delta, -3.0, 2.0)
				if Input.is_action_pressed(&"desktop_grab_right"):
					_right_desktop_offset.z = clampf(_right_desktop_offset.z + depth_delta, -3.0, 2.0)

func _drag_desktop_hands(relative: Vector2) -> bool:
	var is_grabbing := false
	if Input.is_action_pressed(&"desktop_grab_left"):
		_left_desktop_offset += Vector3(relative.x, -relative.y, 0.0) * 0.004
		is_grabbing = true
	if Input.is_action_pressed(&"desktop_grab_right"):
		_right_desktop_offset += Vector3(relative.x, -relative.y, 0.0) * 0.004
		is_grabbing = true
	return is_grabbing

func update_desktop_hands() -> void:
	if xr_active:
		return
	for hand: VRHand in [_left, _right]:
		var side: float = -1.0 if hand == _left else 1.0
		var offset := _left_desktop_offset if hand == _left else _right_desktop_offset
		var action := &"desktop_grab_left" if hand == _left else &"desktop_grab_right"
		if not Input.is_action_pressed(action):
			offset = Vector3.ZERO
			if hand == _left:
				_left_desktop_offset = offset
			else:
				_right_desktop_offset = offset
		hand.grip.global_transform = _camera.global_transform.translated_local(Vector3(side * 0.22 + offset.x, -0.22 + offset.y, -0.4 + offset.z))
		hand.aim.global_transform = hand.grip.global_transform

func move_vector() -> Vector2:
	if xr_active:
		var axis := _left.grip.get_vector2(move_action) if _left.grip.get_has_tracking_data() else Vector2.ZERO
		return Vector2(axis.x, -axis.y)
	return Input.get_vector(&"desktop_left", &"desktop_right", &"desktop_forward", &"desktop_back")

func turn_value() -> float:
	if xr_active:
		return _right.grip.get_vector2(turn_action).x if _right.grip.get_has_tracking_data() else 0.0
	return Input.get_axis(&"desktop_turn_left", &"desktop_turn_right")

func flight_vertical_value() -> float:
	if xr_active:
		return -_right.grip.get_vector2(move_action).y if _right.grip.get_has_tracking_data() else 0.0
	return Input.get_axis(&"desktop_fly_down", &"desktop_fly_up")

func flight_toggle_pressed() -> bool:
	if not xr_active:
		var pressed := Input.is_action_pressed(&"desktop_fly_toggle")
		var just_pressed := pressed and not _flight_button_down
		_flight_button_down = pressed
		return just_pressed
	var pressed := _right.aim.get_has_tracking_data() and _right.aim.is_button_pressed(flight_action)
	var just_pressed := pressed and not _flight_button_down
	_flight_button_down = pressed
	return just_pressed

func can_teleport() -> bool:
	return not xr_active or _right.aim.get_has_tracking_data()

func teleport_pressed() -> bool:
	if xr_active:
		return _right.aim.get_has_tracking_data() and _right.aim.is_button_pressed(teleport_action)
	return Input.is_action_pressed(&"desktop_teleport")

func grip_value(hand: VRHand) -> float:
	if xr_active:
		return hand.grip.get_float(grip_action) if hand.grip.get_has_tracking_data() else 0.0
	return float(Input.is_action_pressed(&"desktop_grab_left" if hand == _left else &"desktop_grab_right"))

func use_value(hand: VRHand) -> float:
	if xr_active:
		return hand.grip.get_float(use_action) if hand.grip.get_has_tracking_data() else 0.0
	return float(Input.is_action_pressed(&"desktop_use_left" if hand == _left else &"desktop_use_right"))
