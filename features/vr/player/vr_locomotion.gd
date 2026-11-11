class_name VRLocomotion
extends Node
signal moved(distance: float)
signal turned(degrees: float)
signal teleported(destination: Vector3)
signal flight_mode_changed(enabled: bool)
const FLIGHT_SPEED: float = 8.0
var body: CharacterBody3D
var camera: XRCamera3D
var origin: XROrigin3D
var body_shape: CollisionShape3D
var settings: VRSettings
var _turn_armed: bool = true
var _gravity: float = 9.8
var _walking_collision_mask: int = 0
var flight_mode: bool = false

func configure(player_body: CharacterBody3D, head: XRCamera3D, xr_origin: XROrigin3D, shape: CollisionShape3D, config: VRSettings) -> void:
	body = player_body
	camera = head
	origin = xr_origin
	body_shape = shape
	settings = config
	_walking_collision_mask = player_body.collision_mask
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

func tick(delta: float, move_input: Vector2, turn_input: float, allow_move: bool = true, flight_vertical: float = 0.0) -> void:
	_update_capsule()
	if absf(turn_input) < settings.stick_deadzone:
		_turn_armed = true
	elif absf(turn_input) > 0.7 and _turn_armed and allow_move:
		_turn_armed = false
		snap_turn(-signf(turn_input) * settings.snap_degrees)
	if flight_mode:
		_tick_flight(move_input, flight_vertical, allow_move)
		return
	var direction := Vector3.ZERO
	if settings.continuous_movement and allow_move and move_input.length() > settings.stick_deadzone:
		var forward := -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		direction = (right * move_input.x - forward * move_input.y).limit_length(1.0)
	body.velocity.x = direction.x * settings.move_speed
	body.velocity.z = direction.z * settings.move_speed
	if body.is_on_floor():
		body.velocity.y = 0.0
	else:
		body.velocity.y -= _gravity * delta
	var before := body.global_position
	body.move_and_slide()
	var distance := Vector2(body.global_position.x - before.x, body.global_position.z - before.z).length()
	if distance > 0.0001:
		moved.emit(distance)

func _tick_flight(move_input: Vector2, vertical_input: float, allow_move: bool) -> void:
	var direction := Vector3.ZERO
	if allow_move and move_input.length() > settings.stick_deadzone:
		var forward := -camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		direction = (right * move_input.x - forward * move_input.y).limit_length(1.0)
	body.velocity = direction * FLIGHT_SPEED + Vector3.UP * clampf(vertical_input, -1.0, 1.0) * FLIGHT_SPEED if allow_move else Vector3.ZERO
	var before := body.global_position
	body.move_and_slide()
	var distance := body.global_position.distance_to(before)
	if distance > 0.0001:
		moved.emit(distance)

func set_flight_mode(enabled: bool) -> void:
	if flight_mode == enabled:
		return
	flight_mode = enabled
	body.collision_mask = 0 if enabled else _walking_collision_mask
	body.velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	flight_mode_changed.emit(enabled)

func _update_capsule() -> void:
	var head_local := body.to_local(camera.global_position)
	var capsule := body_shape.shape as CapsuleShape3D
	capsule.height = clampf(head_local.y, 0.65, 2.3)
	body_shape.position = Vector3(head_local.x, capsule.height * 0.5 + 0.02, head_local.z)

func snap_turn(degrees: float) -> void:
	var pivot := camera.global_position
	body.rotate_y(deg_to_rad(degrees))
	var correction := pivot - camera.global_position
	correction.y = 0.0
	body.global_position += correction
	turned.emit(degrees)

func teleport_to(destination: Vector3) -> void:
	var head_offset := camera.global_position - body.global_position
	head_offset.y = 0.0
	body.global_position = destination - head_offset + Vector3.UP * 0.03
	body.velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	teleported.emit(destination)

func set_seated(enabled: bool) -> void:
	settings.seated = enabled
	origin.position.y = settings.seated_height_offset if enabled else 0.0
