class_name CampusBuilding
extends StaticBody3D

const DEFORM_RADIUS: float = 1.8
const TEAR_RADIUS: float = 2.2

var display_name: String = "Edificio"
var _visual: MeshInstance3D
var _collision_shape: CollisionShape3D
var _grab_marker: MeshInstance3D
var _original_mesh: ArrayMesh
var _surface_materials: Array[Material] = []
var _grab_vertices: Array[PackedVector3Array] = []
var _bounds_size: Vector3 = Vector3.ONE
var _anchor: Node3D
var _anchor_start: Vector3
var _grab_point: Vector3
var _grab_normal: Vector3 = Vector3.UP
var _pull_offset: Vector3 = Vector3.ZERO
var _panel_detached: bool = false

func configure(label: String, mesh: ArrayMesh, bounds_size: Vector3, object_position: Vector3) -> void:
	display_name = label
	position = object_position
	_bounds_size = bounds_size
	_visual = get_node("Visual") as MeshInstance3D
	_collision_shape = get_node("CollisionShape") as CollisionShape3D
	_original_mesh = mesh.duplicate(true) as ArrayMesh
	_visual.mesh = _original_mesh.duplicate(true) as ArrayMesh
	for surface_index: int in range(_visual.mesh.get_surface_count()):
		_surface_materials.append(_visual.mesh.surface_get_material(surface_index))
	_refresh_collision_shape()
	_create_grab_marker()

func _ready() -> void:
	collision_layer = 3
	collision_mask = 0
	add_to_group(&"vr_grabbable")
	add_to_group(&"campus_building")

func begin_grab(anchor: Node3D) -> bool:
	return begin_surface_grab(anchor, anchor.global_position, Vector3.UP)

func begin_surface_grab(anchor: Node3D, world_point: Vector3, world_normal: Vector3) -> bool:
	if not is_instance_valid(anchor) or is_instance_valid(_anchor):
		return false
	_anchor = anchor
	_anchor_start = anchor.global_position
	_grab_point = to_local(world_point)
	_grab_normal = (global_basis.inverse() * world_normal).normalized()
	if _grab_normal.is_zero_approx():
		_grab_normal = Vector3.UP
	_grab_vertices.clear()
	var mesh := _visual.mesh as ArrayMesh
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		_grab_vertices.append(vertices.duplicate())
	_pull_offset = Vector3.ZERO
	_panel_detached = false
	_grab_marker.position = _grab_point
	_grab_marker.visible = true
	return true

func end_grab(_throw_velocity: Vector3) -> void:
	if is_instance_valid(_anchor):
		_refresh_collision_shape()
	_anchor = null
	_grab_vertices.clear()
	_panel_detached = false
	_grab_marker.visible = false

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_anchor) or _panel_detached:
		if not is_instance_valid(_anchor):
			_anchor = null
		return
	_pull_offset = global_basis.inverse() * (_anchor.global_position - _anchor_start)
	var mesh := _visual.mesh as ArrayMesh
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for surface_index: int in range(_grab_vertices.size()):
		var base_vertices := _grab_vertices[surface_index]
		var vertices := _deform_vertices(base_vertices, _pull_offset)
		mesh.surface_update_vertex_region(surface_index, 0, vertices.to_byte_array())
		for vertex: Vector3 in vertices:
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
	_grab_marker.position = _grab_point + _pull_offset
	_bounds_size = maximum - minimum

func _deform_vertices(base_vertices: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	var deformed := base_vertices.duplicate()
	for vertex_index: int in range(deformed.size()):
		var base_vertex := base_vertices[vertex_index]
		var distance := base_vertex.distance_to(_grab_point)
		if distance < DEFORM_RADIUS:
			var influence := 1.0 - distance / DEFORM_RADIUS
			deformed[vertex_index] = base_vertex + offset * influence * influence
	return deformed

func use(_anchor_node: Node3D) -> void:
	if is_instance_valid(_anchor):
		if not _panel_detached:
			_detach_surface_patch()
		return
	reset_building()

func _detach_surface_patch() -> void:
	var mesh := _visual.mesh as ArrayMesh
	var kept_surfaces: Array[PackedVector3Array] = []
	var detached_surfaces: Array[PackedVector3Array] = []
	var kept_materials: Array[Material] = []
	var detached_materials: Array[Material] = []
	var selected_point := _grab_point + _pull_offset
	for surface_index: int in range(_grab_vertices.size()):
		var material: Material = _surface_materials[surface_index]
		var current_vertices := _deform_vertices(_grab_vertices[surface_index], _pull_offset)
		var kept := PackedVector3Array()
		var detached := PackedVector3Array()
		for vertex_index: int in range(0, current_vertices.size(), 3):
			var a := current_vertices[vertex_index]
			var b := current_vertices[vertex_index + 1]
			var c := current_vertices[vertex_index + 2]
			var face_center := (a + b + c) / 3.0
			var face_normal := (b - a).cross(c - a).normalized()
			var near_grip := face_center.distance_to(selected_point) <= TEAR_RADIUS
			var facing_grip := absf(face_normal.dot(_grab_normal)) >= 0.45
			if near_grip and facing_grip:
				detached.append(a)
				detached.append(b)
				detached.append(c)
			else:
				kept.append(a)
				kept.append(b)
				kept.append(c)
		if not detached.is_empty():
			detached_surfaces.append(detached)
			detached_materials.append(material)
		if not kept.is_empty():
			kept_surfaces.append(kept)
			kept_materials.append(material)
	if detached_surfaces.is_empty():
		return
	_spawn_wall_fragment(detached_surfaces, detached_materials)
	_visual.mesh = _build_mesh(kept_surfaces, kept_materials)
	_surface_materials = kept_materials
	_grab_vertices = kept_surfaces
	_panel_detached = true

func _spawn_wall_fragment(surfaces: Array[PackedVector3Array], materials: Array[Material]) -> void:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for vertices: PackedVector3Array in surfaces:
		for vertex: Vector3 in vertices:
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
	var center := (minimum + maximum) * 0.5
	var fragment_surfaces: Array[PackedVector3Array] = []
	for vertices: PackedVector3Array in surfaces:
		var centered := PackedVector3Array()
		for vertex: Vector3 in vertices:
			centered.append(vertex - center)
		fragment_surfaces.append(centered)
	var fragment := RigidBody3D.new()
	fragment.name = "DetachedWallPanel"
	fragment.position = center
	fragment.collision_layer = 2
	fragment.collision_mask = 1
	fragment.add_collision_exception_with(self)
	var visual := MeshInstance3D.new()
	visual.mesh = _build_mesh(fragment_surfaces, materials)
	fragment.add_child(visual)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (maximum - minimum).max(Vector3(0.12, 0.12, 0.12))
	collision.shape = box
	fragment.add_child(collision)
	add_child(fragment)
	fragment.linear_velocity = _pull_offset.limit_length(3.0) + Vector3.UP * 0.5

func _build_mesh(surfaces: Array[PackedVector3Array], materials: Array[Material]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface_index: int in range(surfaces.size()):
		if surfaces[surface_index].is_empty():
			continue
		var surface_tool := SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex: Vector3 in surfaces[surface_index]:
			surface_tool.add_vertex(vertex)
		surface_tool.generate_normals()
		surface_tool.set_material(materials[surface_index])
		surface_tool.commit(mesh, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	return mesh

func _refresh_collision_shape() -> void:
	var mesh := _visual.mesh as ArrayMesh
	if mesh == null:
		return
	var trimesh := mesh.create_trimesh_shape()
	if trimesh == null:
		push_error("No se pudo crear colisión para " + display_name)
		var fallback := BoxShape3D.new()
		fallback.size = _bounds_size
		_collision_shape.shape = fallback
		return
	_collision_shape.shape = trimesh
	_collision_shape.position = Vector3.ZERO

func _create_grab_marker() -> void:
	_grab_marker = MeshInstance3D.new()
	_grab_marker.name = "GrabMarker"
	var sphere := SphereMesh.new()
	sphere.radius = 0.075
	sphere.height = 0.15
	_grab_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.38, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.22, 0.02)
	_grab_marker.material_override = material
	_grab_marker.visible = false
	add_child(_grab_marker)

func reset_building() -> void:
	_anchor = null
	_panel_detached = false
	_pull_offset = Vector3.ZERO
	_visual.mesh = _original_mesh.duplicate(true) as ArrayMesh
	_surface_materials.clear()
	for surface_index: int in range(_visual.mesh.get_surface_count()):
		_surface_materials.append(_visual.mesh.surface_get_material(surface_index))
	_refresh_collision_shape()
	for child: Node in get_children():
		if child is RigidBody3D and child.name == "DetachedWallPanel":
			child.queue_free()
	_grab_marker.visible = false

func get_prompt() -> String:
	return display_name + " · Grip: deformar zona · gatillo: retirar panel/restablecer"
