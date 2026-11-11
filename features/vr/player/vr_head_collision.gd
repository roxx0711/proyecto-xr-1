class_name VRHeadCollision
extends Node
signal obstruction_changed(obstructed: bool)
## Tracking is never clamped; fade if physical head movement enters virtual solids.
var _head: XRCamera3D
var _query: PhysicsShapeQueryParameters3D
var obstructed: bool = false

func configure(head: XRCamera3D) -> void:
	_head = head
	_query = PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.08
	_query.shape = sphere
	_query.collision_mask = 9

func tick(enabled: bool = true) -> void:
	if not enabled:
		if obstructed:
			obstructed = false
			obstruction_changed.emit(false)
		return
	_query.transform = Transform3D(Basis.IDENTITY, _head.global_position)
	var blocked := not _head.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()
	if blocked != obstructed:
		obstructed = blocked
		obstruction_changed.emit(obstructed)
