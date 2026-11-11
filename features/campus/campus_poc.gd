extends Node3D

@onready var player: VRPlayer = %VRPlayer
@onready var controls: Label = %Controls
var _controls_instructions: String

func _ready() -> void:
	player.settings.distance_grab = true
	player.settings.continuous_movement = true
	player.locomotion.flight_mode_changed.connect(_on_flight_mode_changed)
	controls.visible = not player.session.xr_active
	_controls_instructions = controls.text
	_update_controls(false)

func _on_flight_mode_changed(flying: bool) -> void:
	_update_controls(flying)

func _update_controls(flying: bool) -> void:
	var mode := "VUELO · sin colisión" if flying else "CAMINAR · colisión activa"
	controls.text = "MODO: " + mode + "\n" + _controls_instructions
