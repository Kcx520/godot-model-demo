extends Node3D
## Procedural modeling demo: a lathe (surface-of-revolution) vase, built from a
## 2D profile curve, plus a shader-free checker floor, sky and 3-point-ish light.
## Renders one frame to res://shot.png and quits, so the result can be inspected.

const SEGMENTS := 96
const SHOT_PATH := "res://shot.png"


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_vase()
	_build_csg_part()
	_build_camera()

	if DisplayServer.get_name() == "headless":
		print("headless run: geometry built, skipping render")
		get_tree().quit()
		return

	await _render_shot()


func _render_shot() -> void:
	# Let the sky, shadows and mesh instances settle before grabbing the frame.
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT_PATH)
	print("saved %s -> %s" % [SHOT_PATH, error_string(err)])
	get_tree().quit()


# --- modeling -----------------------------------------------------------

func _vase_profile() -> PackedVector2Array:
	# Traversed as a closed loop: up the outside wall, over the rim, back down
	# the inside wall. Both ends sit on the axis (x = 0), so the surface closes.
	var outer := [
		Vector2(0.00, 0.000),
		Vector2(0.34, 0.000),
		Vector2(0.38, 0.030),
		Vector2(0.46, 0.110),
		Vector2(0.53, 0.280),
		Vector2(0.56, 0.470),
		Vector2(0.54, 0.640),
		Vector2(0.47, 0.800),
		Vector2(0.37, 0.930),
		Vector2(0.30, 1.010),
		Vector2(0.29, 1.070),
		Vector2(0.33, 1.110),
	]
	var rim := [
		Vector2(0.345, 1.125),
		Vector2(0.325, 1.128),
	]
	var inner := []
	for i in range(outer.size() - 1, -1, -1):
		var p: Vector2 = outer[i]
		inner.append(Vector2(p.x * 0.86, p.y * 0.985 + 0.006))

	var profile := PackedVector2Array()
	profile.append_array(PackedVector2Array(outer))
	profile.append_array(PackedVector2Array(rim))
	profile.append_array(PackedVector2Array(inner))
	return profile


func _build_vase_surface(profile: PackedVector2Array, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings := profile.size()
	for r in rings:
		var p: Vector2 = profile[r]
		for s in segments:
			var a := TAU * float(s) / float(segments)
			st.set_uv(Vector2(float(s) / float(segments) * 3.0, float(r) / float(rings - 1)))
			st.add_vertex(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))

	for r in rings - 1:
		for s in segments:
			var s2 := (s + 1) % segments
			var a0 := r * segments + s
			var a1 := r * segments + s2
			var b0 := (r + 1) * segments + s
			var b1 := (r + 1) * segments + s2
			st.add_index(a0)
			st.add_index(a1)
			st.add_index(b0)
			st.add_index(b0)
			st.add_index(a1)
			st.add_index(b1)

	# Shared indices -> smooth normals averaged across the rings.
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _build_vase() -> void:
	var mesh := _build_vase_surface(_vase_profile(), SEGMENTS)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.83, 0.62, 0.28)
	mat.metallic = 1.0
	mat.roughness = 0.22
	mat.metallic_specular = 0.6

	var vase := MeshInstance3D.new()
	vase.name = "Vase"
	vase.mesh = mesh
	vase.material_override = mat
	vase.position = Vector3(0.0, 0.01, 0.0)
	add_child(vase)


func _checker_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var a := Color(0.16, 0.17, 0.19)
	var b := Color(0.22, 0.23, 0.26)
	for y in size:
		for x in size:
			var c := a if ((x / 32) + (y / 32)) % 2 == 0 else b
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _build_csg_part() -> void:
	# Second technique: constructive solid geometry (boolean subtraction).
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.42, 0.45)
	mat.roughness = 0.35
	mat.metallic = 0.1

	var block := CSGBox3D.new()
	block.size = Vector3(0.56, 0.56, 0.56)
	block.position = Vector3(1.10, 0.31, -0.55)
	block.material = mat
	block.use_collision = false
	add_child(block)

	var drill := CSGCylinder3D.new()
	drill.radius = 0.20
	drill.height = 1.20
	drill.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	drill.operation = CSGShape3D.OPERATION_SUBTRACTION
	drill.material = mat
	drill.use_collision = false
	block.add_child(drill)


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _checker_texture()
	mat.uv1_scale = Vector3(6.0, 6.0, 1.0)
	mat.roughness = 0.75

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = plane
	floor_mesh.material_override = mat
	add_child(floor_mesh)


# --- scene setup --------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.10, 0.13, 0.22)
	sky_mat.sky_horizon_color = Color(0.42, 0.46, 0.52)
	sky_mat.ground_horizon_color = Color(0.20, 0.20, 0.22)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.06)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-48.0, -42.0, 0.0)
	key.light_energy = 2.4
	key.light_color = Color(1.0, 0.94, 0.86)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 20.0
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-15.0, 120.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.65, 0.75, 1.0)
	add_child(fill)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 40.0
	cam.position = Vector3(2.15, 1.80, 2.60)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.62, 0.0))
	cam.current = true

