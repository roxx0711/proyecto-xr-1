class_name CampusModel
extends Node3D

const CAMPUS_BUILDING_SCRIPT: Script = preload("res://features/campus/campus_building.gd")
const GLB_UNIT_CORRECTION: float = 0.1
const CAMPUS_SCALE: float = 3.0
const INTERACTIVE_BUILDINGS: Array[StringName] = [
	&"A", &"Achoclonados", &"B", &"C", &"D", &"E", &"F", &"G", &"H", &"J",
	&"L", &"L_Anexo", &"La_Minga", &"Tienda"
]
const BUILDING_LABELS: Dictionary[StringName, String] = {
	&"A": "Bloque A", &"Achoclonados": "Achoclonados", &"B": "Bloque B",
	&"C": "Bloque C", &"D": "Bloque D", &"E": "Bloque E", &"F": "Bloque F",
	&"G": "Bloque G", &"H": "Bloque H", &"J": "Bloque J", &"L": "Bloque L",
	&"L_Anexo": "Anexo L", &"La_Minga": "La Minga", &"Tienda": "Tienda"
}

@export_file("*.glb") var source_model: String = "res://assets/models/scene.glb"

var _two_sided_materials: Dictionary = {}

func _ready() -> void:
	if not FileAccess.file_exists(source_model):
		push_error("No se encuentra el modelo GLB del campus: " + source_model)
		return
	var packed_scene := ResourceLoader.load(source_model) as PackedScene
	if packed_scene == null:
		push_error("No se pudo importar el modelo GLB del campus: " + source_model)
		return
	var imported_root := packed_scene.instantiate()
	if not imported_root is Node3D:
		push_error("La escena GLB del campus debe tener una raíz Node3D.")
		imported_root.free()
		return
	var mesh_records: Array[Dictionary] = []
	_collect_mesh_data(imported_root, Transform3D.IDENTITY, mesh_records)
	imported_root.free()
	if mesh_records.is_empty():
		push_error("El modelo GLB del campus no contiene mallas utilizables: " + source_model)
		return
	_build_campus(mesh_records)
	var preview := get_node_or_null("ModelPreview") as Node3D
	if preview != null:
		preview.visible = false

func _collect_mesh_data(node: Node, parent_transform: Transform3D, records: Array[Dictionary]) -> void:
	var node_transform := Transform3D.IDENTITY
	if node is Node3D:
		node_transform = (node as Node3D).transform
	var model_transform := parent_transform * node_transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var source_mesh := mesh_instance.mesh as ArrayMesh
		if source_mesh == null:
			push_error("La malla GLB no es ArrayMesh: " + str(mesh_instance.name))
			return
		var normal_transform := model_transform.basis.inverse().transposed()
		for surface_index: int in range(source_mesh.get_surface_count()):
			if source_mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				push_error("La superficie del campus debe usar triángulos: " + str(mesh_instance.name))
				continue
			var arrays := source_mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var transformed_vertices := PackedVector3Array()
			transformed_vertices.resize(vertices.size())
			for vertex_index: int in range(vertices.size()):
				transformed_vertices[vertex_index] = model_transform * vertices[vertex_index] * GLB_UNIT_CORRECTION * CAMPUS_SCALE
			arrays[Mesh.ARRAY_VERTEX] = transformed_vertices
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if not normals.is_empty():
				var transformed_normals := PackedVector3Array()
				transformed_normals.resize(normals.size())
				for normal_index: int in range(normals.size()):
					transformed_normals[normal_index] = (normal_transform * normals[normal_index]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = transformed_normals
			var material := mesh_instance.get_surface_override_material(surface_index)
			if material == null:
				material = source_mesh.surface_get_material(surface_index)
			records.append({
				"name": _base_object_name(mesh_instance.name),
				"arrays": arrays,
				"material": _get_two_sided_material(material)
			})
	for child: Node in node.get_children():
		_collect_mesh_data(child, model_transform, records)

func _base_object_name(node_name: StringName) -> StringName:
	var name := String(node_name)
	var part_marker := name.rfind("_mm")
	if part_marker >= 0 and name.substr(part_marker + 3).is_valid_int():
		name = name.substr(0, part_marker)
	return StringName(name)

func _get_two_sided_material(material: Material) -> Material:
	if material == null or not material is BaseMaterial3D:
		return material
	if _two_sided_materials.has(material):
		return _two_sided_materials[material] as Material
	var duplicate := material.duplicate(true) as BaseMaterial3D
	duplicate.cull_mode = BaseMaterial3D.CULL_DISABLED
	_two_sided_materials[material] = duplicate
	return duplicate

func _build_campus(mesh_records: Array[Dictionary]) -> void:
	var objects: Dictionary = {}
	for surface_record: Dictionary in mesh_records:
		var object_name: StringName = surface_record["name"]
		if not objects.has(object_name):
			objects[object_name] = {
				"surfaces": [],
				"minimum": Vector3(INF, INF, INF),
				"maximum": Vector3(-INF, -INF, -INF)
			}
		var object_data: Dictionary = objects[object_name]
		var surfaces: Array = object_data["surfaces"]
		surfaces.append(surface_record)
		object_data["surfaces"] = surfaces
		var arrays: Array = surface_record["arrays"]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var object_minimum: Vector3 = object_data["minimum"]
		var object_maximum: Vector3 = object_data["maximum"]
		for vertex: Vector3 in vertices:
			object_minimum = object_minimum.min(vertex)
			object_maximum = object_maximum.max(vertex)
		object_data["minimum"] = object_minimum
		object_data["maximum"] = object_maximum
		objects[object_name] = object_data

	var model_min := Vector3(INF, INF, INF)
	var model_max := Vector3(-INF, -INF, -INF)
	for object_name: StringName in objects:
		var object_data: Dictionary = objects[object_name]
		model_min = model_min.min(object_data["minimum"])
		model_max = model_max.max(object_data["maximum"])
	var campus_origin := Vector3((model_min.x + model_max.x) * 0.5, model_min.y, (model_min.z + model_max.z) * 0.5)
	for object_name: StringName in objects:
		var object_data: Dictionary = objects[object_name]
		var object_min: Vector3 = object_data["minimum"]
		var object_max: Vector3 = object_data["maximum"]
		var object_center := (object_min + object_max) * 0.5
		var mesh := _create_mesh(object_data["surfaces"], object_center)
		var object_size := object_max - object_min
		var object_position := object_center - campus_origin
		if INTERACTIVE_BUILDINGS.has(object_name):
			_add_building(object_name, mesh, object_size, object_position)
		else:
			_add_static_mesh(object_name, mesh, object_position)

func _create_mesh(surfaces: Array, object_center: Vector3) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface_record: Dictionary in surfaces:
		var arrays: Array = surface_record["arrays"]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var local_vertices := vertices.duplicate()
		for vertex_index: int in range(local_vertices.size()):
			local_vertices[vertex_index] -= object_center
		arrays[Mesh.ARRAY_VERTEX] = local_vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		mesh.surface_set_material(mesh.get_surface_count() - 1, surface_record["material"])
	return mesh

func _add_building(object_name: StringName, mesh: ArrayMesh, size: Vector3, object_position: Vector3) -> void:
	var building := StaticBody3D.new()
	building.set_script(CAMPUS_BUILDING_SCRIPT)
	building.name = String(object_name)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	building.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	building.add_child(collision)
	var label: String = BUILDING_LABELS.get(object_name, String(object_name))
	(building as CampusBuilding).configure(label, mesh, size, object_position)
	add_child(building)

func _add_static_mesh(object_name: StringName, mesh: ArrayMesh, object_position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "CampusCollision_" + String(object_name)
	body.collision_layer = 1
	body.collision_mask = 0
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	body.position = object_position
	body.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)
