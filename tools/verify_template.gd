extends SceneTree
## Integration verification using the actual Godot/Jolt runtime, no headset required.
var failures: Array[String] = []
var lab: Node3D
var player: VRPlayer

func _init() -> void:
	run_checks.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame

func run_checks() -> void:
	lab = load("res://examples/interaction_lab/interaction_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	player = lab.get_node("VRPlayer") as VRPlayer
	await frames(30)
	check(not player.session.xr_active, "Verification must run in desktop mode")
	check(player.is_on_floor(), "Player must settle on the floor")
	check(player.right_hand.grip.tracker == &"right_hand", "Right controller tracker must survive scene serialization")
	check(player.left_hand.grip.tracker == &"left_hand", "Left tracker")
	check(player.left_hand.grip.pose == &"grip" and player.right_hand.aim.pose == &"aim", "Separate grip and aim poses")
	var key := lab.get_node("Stations/Key") as VRGrabbable
	check(key.color.g > key.color.r, "Key color must survive scene serialization")
	# Inject actual XRServer trackers using the names produced by the OpenXR runtime.
	var left_tracker := XRControllerTracker.new()
	left_tracker.name = &"left_hand"
	left_tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	var right_tracker := XRControllerTracker.new()
	right_tracker.name = &"right_hand"
	right_tracker.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	XRServer.add_tracker(left_tracker)
	XRServer.add_tracker(right_tracker)
	var pose_transform := Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.5))
	left_tracker.set_pose(&"grip", pose_transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	left_tracker.set_pose(&"aim", pose_transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	right_tracker.set_pose(&"grip", pose_transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	right_tracker.set_pose(&"aim", pose_transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	left_tracker.set_input(&"primary", Vector2(0.0, 1.0))
	right_tracker.set_input(&"primary", Vector2(1.0, 0.0))
	right_tracker.set_input(&"grip", 0.9)
	right_tracker.set_input(&"trigger", 0.8)
	right_tracker.set_input(&"ax_button", true)
	player.set_physics_process(false)
	await frames(3)
	check(player.right_hand.grip.get_has_tracking_data(), "Real XRNode tracking from synthetic runtime tracker")
	check(player.origin.to_local(player.right_hand.grip.global_position).distance_to(pose_transform.origin) < 0.001, "Nested XR hand transforms must be relative to origin")
	player.input_adapter.xr_active = true
	check(player.input_adapter.move_vector().y < 0.0, "OpenXR forward thumbstick must map to forward movement")
	check(player.input_adapter.turn_value() > 0.5, "OpenXR turn thumbstick")
	check(player.input_adapter.grip_value(player.right_hand) > 0.8, "OpenXR analog grip")
	check(player.input_adapter.use_value(player.right_hand) > 0.7, "OpenXR trigger")
	check(player.input_adapter.teleport_pressed(), "OpenXR A button teleport")
	right_tracker.invalidate_pose(&"grip")
	await frames(2)
	check(player.input_adapter.grip_value(player.right_hand) == 0.0, "Lost controller tracking must suppress input")
	player.input_adapter.xr_active = false
	XRServer.remove_tracker(left_tracker)
	XRServer.remove_tracker(right_tracker)
	player.set_physics_process(true)
	await frames(2)
	# Actual input adapter maps desktop actions to the same grip state as OpenXR.
	Input.action_press(&"desktop_grab_left")
	check(player.input_adapter.grip_value(player.left_hand) == 1.0, "Desktop grip adapter")
	var previous_mouse_mode := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.input_adapter.update_desktop_hands()
	var hand_before_drag := player.left_hand.grip.global_position
	player.input_adapter._drag_desktop_hands(Vector2(0.0, -50.0))
	player.input_adapter.update_desktop_hands()
	check(player.left_hand.grip.global_position.y > hand_before_drag.y + 0.1, "Desktop mouse drag moves the virtual hand while gripping")
	Input.action_release(&"desktop_grab_left")
	player.input_adapter.update_desktop_hands()
	Input.mouse_mode = previous_mouse_mode
	# Snapshot camera position during rotation and off-center teleport.
	var head_before := player.camera.global_position
	player.locomotion.snap_turn(30.0)
	check(player.camera.global_position.distance_to(head_before) < 0.002, "Snap turning must pivot around head")
	player.camera.position.x = 0.4
	player.locomotion.teleport_to(Vector3(0.0, 0.0, 3.0))
	check(Vector2(player.camera.global_position.x, player.camera.global_position.z).distance_to(Vector2(0.0, 3.0)) < 0.002, "Teleport must account for room-scale head offset")
	player.camera.position.x = 0.0
	# Collision-sensitive movement against a real wall.
	player.settings.continuous_movement = true
	player.locomotion.teleport_to(Vector3(7.5, 0.0, 3.0))
	player.rotation = Vector3.ZERO
	for index: int in range(80):
		player.locomotion.tick(1.0 / 90.0, Vector2.RIGHT, 0.0)
		await physics_frame
	check(player.camera.global_position.x < 7.9, "Locomotion must not pass through wall")
	player.settings.continuous_movement = false
	var stopped := player.global_position
	player.locomotion.tick(0.1, Vector2.RIGHT, 0.0)
	check(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(stopped.x, stopped.z)) < 0.01, "Teleport-only mode must disable continuous movement")
	player.reset_player()
	await frames(5)
	var floor_node := lab.get_node("World/Floor")
	check(player.teleport.validate_destination(Vector3(1.5, 0.0, 3.0), Vector3.UP, floor_node), "Open floor teleport")
	check(not player.teleport.validate_destination(Vector3(7.95, 0.0, 3.0), Vector3.UP, floor_node), "Wall clearance teleport rejection")
	check(not player.teleport.validate_destination(Vector3(8.0, 0.0, 6.0), Vector3.UP, floor_node), "Unsupported footprint teleport rejection")
	check(not player.teleport.validate_destination(Vector3(1.0, 0.0, 3.0), Vector3.RIGHT, floor_node), "Steep normal rejection")
	check(not player.teleport.validate_destination(Vector3(0.0, 1.0, 0.0), Vector3.UP, lab.get_node("Stations/ControlPanel")), "Non-teleportable table rejection")
	# End-to-end release-to-teleport using the real adapter, arc and player loop.
	player.locomotion.teleport_to(Vector3(5.4, 0.0, 4.0))
	player.rotation = Vector3.ZERO
	player.camera.rotation.x = -0.4
	await frames(5)
	Input.action_press(&"desktop_teleport")
	await frames(5)
	check(player.teleport.target_valid, "Arc must locate a valid destination")
	var expected_destination := player.teleport.destination
	Input.action_release(&"desktop_teleport")
	await frames(5)
	check(Vector2(player.camera.global_position.x, player.camera.global_position.z).distance_to(Vector2(expected_destination.x, expected_destination.z)) < 0.03, "Releasing teleport input moves the player to the arc marker")
	player.camera.rotation.x = 0.0
	player.reset_player()
	await frames(5)
	player.camera.global_position = Vector3(7.99, 1.5, 3.0)
	player.head_collision.tick()
	check(player.head_collision.obstructed, "Physical head movement into a wall must trigger fade")
	player.camera.position = Vector3(0.0, 1.7, 0.0)
	player.head_collision.tick()
	check(not player.head_collision.obstructed, "Head fade clears after exiting a solid")
	# Held state persists while input remains pressed and is exclusive to one hand.
	player.set_physics_process(false)
	player.right_hand.grip.global_position = key.global_position + Vector3(0.0, 0.0, 0.04)
	player.right_hand.aim.global_transform = player.right_hand.grip.global_transform
	await frames(3)
	# Disable automatic player polling while driving the component through its public API.
	player.set_physics_process(false)
	player.right_hand.tick(1.0 / 90.0, 1.0, 0.0)
	check(player.right_hand.held == key, "Near grab through hand detection")
	check(not key.begin_grab(player.left_hand.hold_point), "A held object cannot be stolen by another hand")
	await frames(3)
	player.right_hand.tick(1.0 / 90.0, 1.0, 0.0)
	check(player.right_hand.held == key and key.held_by != null, "Grip hold must not auto-release next frame")
	player.right_hand.tick(1.0 / 90.0, 0.0, 0.0)
	check(key.held_by == null and player.right_hand.held == null, "Grip release")
	# Movable props accompany teleport without gaining artificial throw speed.
	key.begin_grab(player.right_hand.hold_point)
	player.right_hand.held = key
	var key_before := key.global_position
	player.right_hand.move_held_with_player(Vector3(1.0, 0.0, 0.0))
	await frames(2)
	check(key.global_position.x > key_before.x + 0.4, "Held prop relocation during teleport")
	player.right_hand.release_held(false)
	key.end_grab(Vector3(100.0, 0.0, 0.0))
	check(key.linear_velocity.length() <= key.maximum_throw_speed + 0.01, "Throw velocity clamp")
	var socket := lab.get_node("Stations/KeySocket") as VRSocket
	var cube := lab.get_node("Stations/Cube1") as VRGrabbable
	check(not socket.insert_item(cube), "Socket rejects wrong item")
	check(socket.insert_item(key), "Socket accepts key")
	check(key.freeze and socket.occupant == key, "Socket locks key")
	check((lab.get_node("Stations/SlidingDoor") as VRDoor).opened, "Key opens door through signals")
	check(key.begin_grab(player.left_hand.hold_point), "Key removable from socket")
	check(socket.occupant == null and not key.freeze, "Removing key releases socket")
	key.end_grab(Vector3.ZERO)
	var flashlight := lab.get_node("Stations/Flashlight") as VRFlashlight
	flashlight.use(player.right_hand.hold_point)
	check(flashlight.light.visible, "Held tool trigger activates flashlight")
	flashlight.use(player.right_hand.hold_point)
	check(not flashlight.light.visible, "Flashlight toggle")
	var lever := lab.get_node("Stations/Lever") as VRLever
	lever.set_value(5.0)
	check(is_equal_approx(lever.value, 1.0), "Lever clamps value")
	var button := lab.get_node("Stations/MovementButton") as VRButton
	button.use(player.right_hand.hold_point)
	check(player.settings.continuous_movement, "World-space button toggles movement")
	# Focus cancellation prevents retained grips, and restores pre-existing pause/mute.
	key.begin_grab(player.right_hand.hold_point)
	player.right_hand.held = key
	player.session._lose_focus()
	check(paused and key.held_by == null, "Focus loss pauses simulation and releases objects")
	player.session._gain_focus()
	check(not paused, "Focus gain resumes")
	paused = true
	player.session._lose_focus()
	player.session._gain_focus()
	check(paused, "Session must preserve an unrelated pause")
	paused = false
	lab.reset_lab()
	player.set_physics_process(true)
	await frames(20)
	check(not player.settings.continuous_movement and socket.occupant == null, "Demo reset restores comfort mode and socket")
	check(key.global_position.distance_to(Vector3(-2.5, 1.0, 0.3)) < 0.25, "Demo reset restores props")
	var campus := (load("res://examples/campus_poc/campus_poc.tscn") as PackedScene).instantiate()
	var campus_preview := campus.get_node_or_null("CampusModel/ModelPreview") as Node3D
	check(campus_preview != null and campus_preview.visible, "Campus GLB is visible in the editor scene")
	root.add_child(campus)
	current_scene = campus
	await frames(5)
	check(campus_preview != null and not campus_preview.visible, "Runtime uses the interactive campus meshes instead of duplicating the preview")
	var campus_buildings := get_nodes_in_group(&"campus_building")
	check(campus_buildings.size() == 14, "Campus model exposes each movable building as an individual object")
	var building := campus.get_node("CampusModel/B") as CampusBuilding
	var building_mesh := building.get_node("Visual") as MeshInstance3D
	check(building_mesh.mesh != null and building_mesh.mesh.get_surface_count() > 0, "Campus building mesh imports with geometry")
	check(building_mesh.get_aabb().size.y > 16.0, "Campus is enlarged for human-scale VR")
	check(building_mesh.mesh.get_surface_count() >= 6, "GLB sub-meshes are grouped into their building")
	var building_material := building_mesh.mesh.surface_get_material(0) as BaseMaterial3D
	check(building_material != null and building_material.cull_mode == BaseMaterial3D.CULL_DISABLED, "Imported building materials render interior faces")
	check(building.get_node("CollisionShape").shape is ConcavePolygonShape3D, "Campus buildings use mesh-accurate walk collision")
	var stretch_anchor := Node3D.new()
	campus.add_child(stretch_anchor)
	var original_mesh := building_mesh.mesh as ArrayMesh
	var original_vertices: PackedVector3Array = original_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var original_vertex_count := 0
	for surface_index: int in range(original_mesh.get_surface_count()):
		var surface_arrays: Array = original_mesh.surface_get_arrays(surface_index)
		var surface_vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		original_vertex_count += surface_vertices.size()
	var grab_point := original_vertices[0]
	var face_normal := (original_vertices[1] - original_vertices[0]).cross(original_vertices[2] - original_vertices[0]).normalized()
	stretch_anchor.global_position = building.to_global(grab_point)
	var building_position := building.global_position
	check(building.begin_surface_grab(stretch_anchor, building.to_global(grab_point), building.global_basis * face_normal), "Campus building accepts a precise surface grab point")
	stretch_anchor.global_position += Vector3.UP * 1.0
	await frames(3)
	var deformed_vertices := building._deform_vertices(original_vertices, building._pull_offset)
	check(building.global_position.distance_to(building_position) < 0.001, "Local deformation does not move the complete building")
	check(not deformed_vertices[0].is_equal_approx(original_vertices[0]), "Moving the hand deforms the grabbed mesh region")
	check(((building_mesh.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE) != 0, "Campus mesh supports vertex buffer updates")
	building.end_grab(Vector3.ZERO)
	building.reset_building()
	grab_point = (original_vertices[0] + original_vertices[1] + original_vertices[2]) / 3.0
	stretch_anchor.global_position = building.to_global(grab_point)
	check(building.begin_surface_grab(stretch_anchor, building.to_global(grab_point), building.global_basis * face_normal), "Campus building can grab a wall panel for removal")
	building.use(stretch_anchor)
	var detached_vertex_count := 0
	var detached_mesh := building_mesh.mesh as ArrayMesh
	for surface_index: int in range(detached_mesh.get_surface_count()):
		var surface_arrays: Array = detached_mesh.surface_get_arrays(surface_index)
		var surface_vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
		detached_vertex_count += surface_vertices.size()
	check(detached_vertex_count < original_vertex_count, "Using while gripping removes a local wall panel")
	building.end_grab(Vector3.ZERO)
	building.use(stretch_anchor)
	check((building_mesh.mesh as ArrayMesh).get_surface_count() > 0, "Using an unheld building restores its mesh")
	var campus_player := campus.get_node("VRPlayer") as VRPlayer
	check(campus_player.scale.distance_to(Vector3.ONE) < 0.001, "Player remains at human scale")
	check(campus_player.global_position.z > 96.0 and campus_player.global_position.z < 110.0, "Player starts outside the enlarged campus")
	var walking_collision_mask := campus_player.collision_mask
	campus_player.locomotion.set_flight_mode(true)
	check(campus_player.collision_mask == 0, "Flight mode disables player collisions")
	campus_player.locomotion.set_flight_mode(false)
	check(campus_player.collision_mask == walking_collision_mask, "Walking mode restores player collisions")
	Input.action_press(&"desktop_fly_toggle")
	check(campus_player.input_adapter.flight_toggle_pressed(), "Desktop flight toggle input")
	Input.action_release(&"desktop_fly_toggle")
	campus_player.input_adapter.flight_toggle_pressed()
	campus.queue_free()
	await process_frame
	# F6: each reusable scene can run without a lab singleton.
	for path: String in ["player/vr_player.tscn", "hands/vr_hand.tscn", "interaction/vr_grabbable.tscn", "interaction/vr_button.tscn", "interaction/vr_lever.tscn", "interaction/vr_socket.tscn", "interaction/vr_door.tscn", "interaction/vr_flashlight.tscn", "locomotion/vr_teleport.tscn"]:
		var instance := (load("res://features/vr/" + path) as PackedScene).instantiate()
		root.add_child(instance)
		await frames(2)
		instance.queue_free()
		await process_frame
	lab.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: VR template integration checks")
	else:
		print("FAIL: ", failures)
	quit(0 if failures.is_empty() else 1)
