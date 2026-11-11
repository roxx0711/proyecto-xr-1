class_name VRHand
extends Node3D
signal grabbed(target: Node3D)
signal released(target: Node3D)
signal used(target: Node3D)
signal focus_changed(target: Node3D)
@export var tracker_name: StringName = &"left_hand"
@export var hand_color: Color = Color(0.2, 0.7, 0.85)
@onready var grip: XRController3D = %Grip
@onready var aim: XRController3D = %Aim
@onready var grab_area: Area3D = %GrabArea
@onready var hold_point: Marker3D = %HoldPoint
@onready var ray: RayCast3D = %InteractionRay
@onready var beam: MeshInstance3D = %Beam
@onready var hint: Label3D = %Hint
var held: Node3D
var focused: Node3D
var _settings: VRSettings
var _xr_active: bool = false
var _grip_down: bool = false
var _use_down: bool = false
var _velocity: Vector3 = Vector3.ZERO
var _previous_position: Vector3
var _samples_ready: bool = false

func _ready() -> void:
	grip.tracker = tracker_name
	aim.tracker = tracker_name
	grip.pose = &"grip"
	aim.pose = &"aim"
	beam.material_override = beam.material_override.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	(%HandVisual as MeshInstance3D).material_override = (%HandVisual as MeshInstance3D).material_override.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	((%HandVisual as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = hand_color

func configure(config: VRSettings, active: bool) -> void:
	_settings = config
	_xr_active = active
	ray.target_position.z = -config.ray_length

func tick(delta: float, grip_amount: float, use_amount: float, enabled: bool = true) -> void:
	if not enabled or (_xr_active and not grip.get_has_tracking_data()):
		cancel()
		return
	if _samples_ready:
		var sample := (hold_point.global_position - _previous_position) / maxf(delta, 0.001)
		_velocity = _velocity.lerp(sample.limit_length(10.0), 0.4)
	_previous_position = hold_point.global_position
	_samples_ready = true
	if not is_instance_valid(held):
		held = null
	_update_focus()
	var grip_now := grip_amount >= (_settings.release_threshold if _grip_down else _settings.grab_threshold)
	var use_now := use_amount >= (_settings.release_threshold if _use_down else _settings.grab_threshold)
	if grip_now and not _grip_down and focused != null and focused.has_method("begin_grab"):
		var grabbed_successfully: bool = false
		if focused.has_method("begin_surface_grab"):
			var hit_point := grip.global_position
			var hit_normal := Vector3.UP
			if ray.is_colliding() and ray.get_collider() == focused:
				hit_point = ray.get_collision_point()
				hit_normal = ray.get_collision_normal()
			grabbed_successfully = bool(focused.call("begin_surface_grab", hold_point, hit_point, hit_normal))
		else:
			grabbed_successfully = bool(focused.call("begin_grab", hold_point))
		if grabbed_successfully:
			held = focused
			grabbed.emit(held)
			pulse(0.35)
	if not grip_now and _grip_down:
		release_held()
	if use_now and not _use_down:
		var target := held if held != null else focused
		if target != null and target.has_method("use"):
			target.call("use", hold_point)
			used.emit(target)
			pulse(0.25)
	_grip_down = grip_now
	_use_down = use_now

func _update_focus() -> void:
	ray.force_raycast_update()
	var candidate: Node3D = null
	var best_distance: float = INF
	for body: Node3D in grab_area.get_overlapping_bodies():
		if not _can_interact(body):
			continue
		var distance := grip.global_position.distance_squared_to(body.global_position)
		var sight := PhysicsRayQueryParameters3D.create(grip.global_position, body.global_position, 11)
		var hit := get_world_3d().direct_space_state.intersect_ray(sight)
		if not hit.is_empty() and hit.collider != body:
			continue
		if distance < best_distance:
			candidate = body
			best_distance = distance
	var ray_target := ray.get_collider() as Node3D if ray.is_colliding() else null
	if candidate == null and _can_interact(ray_target):
		if not ray_target.has_method("begin_grab") or _settings.distance_grab:
			candidate = ray_target
	if focused != candidate:
		focused = candidate
		focus_changed.emit(focused)
		if focused != null:
			pulse(0.08)
	beam.visible = held == null
	var beam_length := aim.global_position.distance_to(ray.get_collision_point()) if ray.is_colliding() else _settings.ray_length
	beam.scale.z = beam_length
	beam.position.z = -beam_length * 0.5
	var material := beam.material_override as StandardMaterial3D
	material.albedo_color = Color(0.15, 1.0, 0.7) if focused != null else Color(0.4, 0.6, 0.8)
	hint.text = String(focused.call("get_prompt")) if focused != null and focused.has_method("get_prompt") else ""

func _can_interact(target: Node3D) -> bool:
	return is_instance_valid(target) and (target.has_method("begin_grab") or target.has_method("use"))

func release_held(throw_object: bool = true) -> void:
	if not is_instance_valid(held):
		held = null
		return
	var target := held
	held = null
	target.call("end_grab", _velocity if throw_object else Vector3.ZERO)
	released.emit(target)
	pulse(0.2)

func cancel() -> void:
	release_held(false)
	focused = null
	_grip_down = false
	_use_down = false
	beam.visible = false
	hint.text = ""
	clear_motion()

func move_held_with_player(offset: Vector3) -> void:
	if is_instance_valid(held):
		if held.has_method("offset_for_teleport"):
			held.call("offset_for_teleport", offset)
		else:
			release_held(false)
	clear_motion()

func clear_motion() -> void:
	_samples_ready = false
	_velocity = Vector3.ZERO

func pulse(amplitude: float) -> void:
	if _xr_active and grip.get_has_tracking_data():
		grip.trigger_haptic_pulse(&"haptic", 0.0, amplitude, 0.05, 0.0)

func _exit_tree() -> void:
	if is_instance_valid(held):
		held.call("end_grab", Vector3.ZERO)
