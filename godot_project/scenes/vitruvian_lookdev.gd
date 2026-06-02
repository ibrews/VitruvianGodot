extends Node3D

# ─────────────────────────────────────────────────────────────────────────────
# VITRUVIAN SPIKE look-dev — does a CC0 CharMorph "Vitruvian" head render well
# through our MatMADNESS skin_shader_local stack?  (Motivation: MetaHuman's Epic
# EULA blocked the Capafy cloud-sub product; a CC0 base would remove that.)
#
# Self-contained: mirrors scenes/look_dev.gd's lighting/camera/environment so the
# comparison to the MetaHuman is fair, but loads res://vitruvian_head.glb and
# wires skin_shader_local to the FACE surface (index 0) BY INDEX (surf 0 =
# VitruvianSkin, surf 1 = eyes/mouth — confirmed via probe_vitruvian.gd).
# Environment uses AgX + SSIL + High SSS per reference-godot-metahuman-realism.
#
# Headless-ish verification capture (windowed, needs a GPU framebuffer):
#   set NO_LOAD_SETTINGS=1
#   set LOOKDEV_CAPTURE=H:/Work01/MetaHumanGodot/out/vitruvian_spike/g
#   Godot_v4.6_console --path godot_project scenes/vitruvian_lookdev.tscn --resolution 1280x1280
# → writes g_a.png (clean default) and g_b.png (SSS pushed + orbit), then quits.
# ─────────────────────────────────────────────────────────────────────────────

const HEAD_GLB: String = "res://vitruvian_head.glb"

var skin_mat: ShaderMaterial
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var camera: Camera3D
var env: Environment

# Frame the head: AABB Y 1.49–1.746, center ~1.62.
var orbit_target: Vector3 = Vector3(0.0, 1.63, 0.0)
var orbit_yaw: float = -18.0
var orbit_pitch: float = 4.0
var orbit_dist: float = 0.46
var _drag_mode: int = 0

var key_yaw: float = -81.0
var key_pitch: float = -30.0
var fill_yaw: float = 21.0
var fill_pitch: float = 13.0
var rim_yaw: float = 51.0
var rim_pitch: float = -45.0

var _cap_prefix: String = ""
var _cap_frame: int = 0


func _ready() -> void:
	_setup_environment()
	_setup_lights()
	_setup_camera()
	var ok: bool = _load_and_wire()
	if not ok:
		push_error("[vit] failed to load/wire head")
		return
	_update_orbit_camera()
	if OS.has_environment("LOOKDEV_CAPTURE"):
		_cap_prefix = OS.get_environment("LOOKDEV_CAPTURE")
		print("[vit] CAPTURE MODE → ", _cap_prefix)


func _process(_delta: float) -> void:
	if _cap_prefix != "":
		_capture_tick()


func _capture_tick() -> void:
	_cap_frame += 1
	if _cap_frame == 24:
		_grab("%s_a.png" % _cap_prefix)
	elif _cap_frame == 30:
		# Prove the slider→material binding is live: push SSS, orbit a touch.
		skin_mat.set_shader_parameter("subsurface_scattering_strength", 0.85)
		skin_mat.set_shader_parameter("skin_smoothness", 3.0)
		orbit_yaw = 18.0
		orbit_dist = 0.40
		_update_orbit_camera()
	elif _cap_frame == 54:
		_grab("%s_b.png" % _cap_prefix)
	elif _cap_frame == 60:
		print("[vit] capture done, quitting")
		get_tree().quit()


func _grab(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(path)
	print("[vit] grabbed %s (err %d, %dx%d)" % [path, err, img.get_width(), img.get_height()])


# ── Scene construction ───────────────────────────────────────────────────────

func _setup_environment() -> void:
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.07, 0.12)
	sky_mat.sky_horizon_color = Color(0.06, 0.08, 0.12)
	sky_mat.ground_horizon_color = Color(0.04, 0.04, 0.05)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.energy_multiplier = 0.6
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.10
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Realism playbook: AgX (not ACES) + SSIL.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssil_enabled = true
	env.ssao_enabled = true
	env.ssao_radius = 0.4
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.9
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.1
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	we.name = "WorldEnvironment"
	add_child(we)

	# High-quality SSS at this distance.
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH)
	RenderingServer.sub_surface_scattering_set_scale(0.08, 0.02)

	# Backdrop (matches look_dev's dark radial card).
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(0.20, 0.19, 0.17))
	grad.add_point(0.5, Color(0.10, 0.10, 0.10))
	grad.set_color(1, Color(0.035, 0.037, 0.043))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 1024
	tex.height = 1024
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.30)
	tex.fill_to = Vector2(0.92, 0.78)
	var bm: StandardMaterial3D = StandardMaterial3D.new()
	bm.albedo_texture = tex
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane: MeshInstance3D = MeshInstance3D.new()
	plane.name = "Backdrop"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(7.0, 7.0)
	plane.mesh = quad
	plane.material_override = bm
	plane.position = Vector3(0.0, 1.55, -1.2)
	add_child(plane)


func _setup_lights() -> void:
	key_light = DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_energy = 3.2
	key_light.light_color = Color(1.0, 0.90, 0.76)
	key_light.shadow_enabled = true
	key_light.shadow_bias = 0.04
	key_light.shadow_normal_bias = 2.0
	key_light.shadow_blur = 3.0
	key_light.light_angular_distance = 4.5
	key_light.rotation = Vector3(deg_to_rad(key_pitch), deg_to_rad(key_yaw), 0.0)
	add_child(key_light)

	rim_light = DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.light_energy = 3.0
	rim_light.light_specular = 0.25
	rim_light.light_color = Color(0.34, 0.58, 1.0)
	rim_light.rotation = Vector3(deg_to_rad(rim_pitch), deg_to_rad(rim_yaw), 0.0)
	add_child(rim_light)

	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.7
	fill_light.light_color = Color(0.5, 0.62, 1.0)
	fill_light.rotation = Vector3(deg_to_rad(fill_pitch), deg_to_rad(fill_yaw), 0.0)
	add_child(fill_light)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.02
	camera.far = 50.0
	camera.current = true
	camera.fov = 28.0
	add_child(camera)
	# Cleaner capture.
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _load_and_wire() -> bool:
	var scene: PackedScene = load(HEAD_GLB)
	if scene == null:
		return false
	var inst: Node = scene.instantiate()
	inst.name = "Character"
	add_child(inst)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	skin_mat = _make_skin()
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		print("[vit] mesh '%s' surfaces=%d" % [mi.name, mesh.get_surface_count()])
		# Wire by surface MATERIAL NAME (probe-confirmed), never trust index order.
		for s in range(mesh.get_surface_count()):
			var m: Material = mesh.surface_get_material(s)
			var nm: String = m.resource_name if m else ""
			match nm:
				"VitSkin":   mi.set_surface_override_material(s, skin_mat)
				"VitSclera": mi.set_surface_override_material(s, _make_sclera())
				"VitIris":   mi.set_surface_override_material(s, _make_iris())
				"VitMouth":  mi.set_surface_override_material(s, _make_mouth())
				"VitPupil":  mi.set_surface_override_material(s, _make_pupil())
				"VitBrows":  mi.set_surface_override_material(s, _make_brows())
				_:           pass
	return true


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


func _tex(p: String) -> Texture2D:
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


func _make_sclera() -> StandardMaterial3D:
	# White of the eye (+ cornea shell, same UDIM tile). Wet glossy via clearcoat.
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _tex("res://vit_sclera.png")
	m.albedo_color = Color(1, 1, 1)
	m.roughness = 0.4
	m.metallic = 0.0
	m.metallic_specular = 0.45
	m.clearcoat_enabled = true
	m.clearcoat = 0.35
	m.clearcoat_roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_iris() -> StandardMaterial3D:
	# Keep gloss modest so the iris texture reads instead of mirroring the rim.
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _tex("res://vit_iris.png")
	m.albedo_color = Color(1, 1, 1)
	m.roughness = 0.35
	m.metallic = 0.0
	m.metallic_specular = 0.5
	m.clearcoat_enabled = true
	m.clearcoat = 0.4
	m.clearcoat_roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_pupil() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.025)
	m.roughness = 0.12
	m.metallic = 0.0
	m.metallic_specular = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_mouth() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _tex("res://vit_mouth.png")
	m.albedo_color = Color(0.85, 0.78, 0.76)
	m.roughness = 0.42
	m.metallic = 0.0
	return m


func _make_brows() -> StandardMaterial3D:
	# No alpha atlas shipped → opaque dark-brown strips (spike-grade groom).
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.085, 0.060, 0.042)
	m.roughness = 0.68
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_skin() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://scenes/skin_shader_local.gdshader") as Shader
	mat.set_shader_parameter("texture_albedo", load("res://vit_face_bc.png") as Texture2D)
	mat.set_shader_parameter("albedo", Color(1, 1, 1, 1))
	mat.set_shader_parameter("texture_normal", load("res://vit_face_n.png") as Texture2D)
	mat.set_shader_parameter("normal_strength", 1.0)
	mat.set_shader_parameter("texture_roughness", load("res://vit_face_rough.png") as Texture2D)
	mat.set_shader_parameter("roughness", 0.95)
	mat.set_shader_parameter("specular", 0.35)
	mat.set_shader_parameter("double_specularity", false)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("metallic_texture_channel", Plane(1, 0, 0, 0))
	mat.set_shader_parameter("use_subsurface_scattering", true)
	mat.set_shader_parameter("use_noise", false)
	mat.set_shader_parameter("subsurface_scattering_strength", 0.34)
	mat.set_shader_parameter("skin_smoothness", 1.4)
	mat.set_shader_parameter("skin_fallof_smoothness", 1.05)
	mat.set_shader_parameter("sss_depth_scale", 6.0)
	mat.set_shader_parameter("old_lightwarp_fallof", false)
	mat.set_shader_parameter("tinted_shadow_penumbra", true)
	# Vitruvian's pore detail is already in the displacement-derived normal → no
	# tiled micro_detail. No cavity AO map (binding the wrong one zeroes SSS).
	mat.set_shader_parameter("use_micro_detail", false)
	mat.set_shader_parameter("micro_normal_strength", 0.0)
	mat.set_shader_parameter("use_ambient_occlusion", false)
	mat.set_shader_parameter("translucency", false)
	mat.set_shader_parameter("use_scatter_map", false)
	mat.set_shader_parameter("uv1_scale", Vector3(1, 1, 1))
	mat.set_shader_parameter("uv1_offset", Vector3(0, 0, 0))
	mat.set_shader_parameter("uv2_scale", Vector3(1, 1, 1))
	mat.set_shader_parameter("uv2_offset", Vector3(0, 0, 0))
	return mat


# ── Orbit camera ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					orbit_dist = maxf(0.12, orbit_dist * 0.9)
					_update_orbit_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					orbit_dist = minf(8.0, orbit_dist * 1.1)
					_update_orbit_camera()
			MOUSE_BUTTON_LEFT:
				_drag_mode = 1 if mb.pressed else 0
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_drag_mode = 2 if mb.pressed else 0
	elif event is InputEventMouseMotion and _drag_mode != 0:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if _drag_mode == 1:
			orbit_yaw -= rel.x * 0.35
			orbit_pitch = clampf(orbit_pitch + rel.y * 0.35, -89.0, 89.0)
		else:
			var basis: Basis = camera.global_transform.basis
			var scale: float = orbit_dist * 0.0016
			orbit_target -= basis.x * (rel.x * scale)
			orbit_target += basis.y * (rel.y * scale)
		_update_orbit_camera()


func _update_orbit_camera() -> void:
	if camera == null:
		return
	var p: float = deg_to_rad(orbit_pitch)
	var y: float = deg_to_rad(orbit_yaw)
	var dir: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	camera.position = orbit_target + dir * orbit_dist
	camera.look_at(orbit_target, Vector3.UP)
