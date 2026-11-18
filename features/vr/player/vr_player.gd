class_name VRPlayer
extends CharacterBody3D
signal activity_completed(activity: StringName)
@export var defaults: VRSettings
@onready var origin: XROrigin3D = %XROrigin
@onready var camera: XRCamera3D = %Head
@onready var left_hand: VRHand = %LeftHand
@onready var right_hand: VRHand = %RightHand
@onready var input_adapter: VRInput = %InputAdapter
@onready var locomotion: VRLocomotion = %Locomotion
@onready var teleport: VRTeleport = %Teleport
@onready var session: XRSession = %XRSession
@onready var comfort: MeshInstance3D = %ComfortMask
@onready var head_collision: VRHeadCollision = %HeadCollision
@onready var boundary: VRBoundary = %Boundary
const BODY_SWAY_MAX_OFFSET: float = 0.15
const BODY_SWAY_MIN_SPEED: float = 0.1
const BODY_SWAY_CYCLE_RATE: float = 0.9
const BODY_SWAY_SMOOTHING: float = 12.0
var settings: VRSettings
var _teleport_was_pressed: bool = false
var _blackout_time: float = 0.0
var _spawn: Vector3
var _origin_rest_x: float = 0.0
var _body_sway_phase: float = 0.0
var _body_sway_offset: float = 0.0

func _ready() -> void:
	settings = defaults.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as VRSettings if defaults != null else VRSettings.new()
	_spawn = global_position
	_origin_rest_x = origin.position.x
	input_adapter.configure(session.xr_active, self, camera, left_hand, right_hand)
	left_hand.configure(settings, session.xr_active)
	right_hand.configure(settings, session.xr_active)
	locomotion.configure(self, camera, origin, %BodyShape, settings)
	locomotion.set_seated(settings.seated)
	teleport.configure(self, camera, right_hand.aim, %BodyShape)
	head_collision.configure(camera)
	boundary.configure(session.interface, camera, origin, session.xr_active)
	session.focus_changed.connect(_on_focus_changed)
	session.recentered.connect(_on_recentered)
	locomotion.moved.connect(_on_moved)
	locomotion.turned.connect(_on_turned)
	locomotion.teleported.connect(_on_teleported)
	left_hand.grabbed.connect(_on_grabbed)
	right_hand.grabbed.connect(_on_grabbed)
	left_hand.used.connect(_on_used)
	right_hand.used.connect(_on_used)

func _physics_process(delta: float) -> void:
	input_adapter.update_desktop_hands()
	input_adapter.update_desktop_actions()
	if input_adapter.flight_toggle_pressed():
		locomotion.set_flight_mode(not locomotion.flight_mode)
	var aiming := input_adapter.teleport_pressed() and _blackout_time <= 0.0
	teleport.update_target(aiming)
	if _teleport_was_pressed and not aiming and _blackout_time <= 0.0 and input_adapter.can_teleport() and teleport.confirm_destination():
		_blackout_time = 0.12
		var previous_position := global_position
		locomotion.teleport_to(teleport.destination)
		left_hand.move_held_with_player(global_position - previous_position)
		right_hand.move_held_with_player(global_position - previous_position)
		right_hand.pulse(0.35)
		left_hand.clear_motion()
		right_hand.clear_motion()
	if not input_adapter.can_teleport():
		teleport.cancel()
	_teleport_was_pressed = aiming
	_blackout_time = maxf(0.0, _blackout_time - delta)
	locomotion.tick(delta, input_adapter.move_vector(), input_adapter.turn_value(), not aiming and _blackout_time <= 0.0, input_adapter.flight_vertical_value(), input_adapter.jump_pressed())
	_update_body_sway(delta)
	left_hand.tick(delta, input_adapter.grip_value(left_hand), input_adapter.use_value(left_hand), _blackout_time <= 0.0)
	right_hand.tick(delta, input_adapter.grip_value(right_hand), input_adapter.use_value(right_hand), not aiming and _blackout_time <= 0.0)
	var moving := settings.continuous_movement and Vector2(velocity.x, velocity.z).length() > 0.1
	var material := comfort.material_override as ShaderMaterial
	material.set_shader_parameter("vignette", settings.vignette_strength if moving else 0.0)
	head_collision.tick(not locomotion.flight_mode)
	material.set_shader_parameter("blackout", 1.0 if _blackout_time > 0.0 or head_collision.obstructed else 0.0)

func _update_body_sway(delta: float) -> void:
	var actual_velocity := get_real_velocity()
	var walking_speed := Vector2(actual_velocity.x, actual_velocity.z).length()
	var target_offset := 0.0
	if not locomotion.flight_mode and is_on_floor() and walking_speed > BODY_SWAY_MIN_SPEED:
		var speed_ratio := clampf(walking_speed / maxf(settings.move_speed, BODY_SWAY_MIN_SPEED), 0.0, 1.0)
		var cycle_frequency := clampf(walking_speed * BODY_SWAY_CYCLE_RATE, 1.0, 2.1)
		_body_sway_phase = fposmod(_body_sway_phase + TAU * cycle_frequency * delta, TAU)
		target_offset = sin(_body_sway_phase) * BODY_SWAY_MAX_OFFSET * speed_ratio
	var smoothing := 1.0 - exp(-BODY_SWAY_SMOOTHING * delta)
	_body_sway_offset = lerpf(_body_sway_offset, target_offset, smoothing)
	origin.position.x = _origin_rest_x + _body_sway_offset

func toggle_movement() -> void:
	settings.continuous_movement = not settings.continuous_movement

func toggle_seated() -> void:
	locomotion.set_seated(not settings.seated)

func reset_player() -> void:
	left_hand.cancel()
	right_hand.cancel()
	locomotion.set_flight_mode(false)
	locomotion.teleport_to(_spawn)

func _on_focus_changed(focused: bool) -> void:
	if not focused:
		left_hand.cancel()
		right_hand.cancel()
		teleport.cancel()
		_teleport_was_pressed = false

func _on_recentered() -> void:
	left_hand.cancel()
	right_hand.cancel()
	teleport.cancel()
	_teleport_was_pressed = false

func _on_moved(_distance: float) -> void:
	activity_completed.emit(&"movement")

func _on_turned(_degrees: float) -> void:
	left_hand.clear_motion()
	right_hand.clear_motion()
	activity_completed.emit(&"turn")

func _on_teleported(_destination: Vector3) -> void:
	activity_completed.emit(&"teleport")

func _on_grabbed(_target: Node3D) -> void:
	activity_completed.emit(&"grab")

func _on_used(_target: Node3D) -> void:
	activity_completed.emit(&"use")
