extends Node3D

# ──────────────────────────────────────────────────────────────────────────
# VITRUVIAN look-dev tool — interactive sliders + orbit camera to dial in the
# skin / lighting / hair look of a CC0 "Vitruvian" (CharMorph) head rendered
# through the MatMADNESS skin_shader_local stack in stock Godot 4.6 Forward+.
#
# EULA-free sibling of the MetaHuman look-dev tool: same controls, same shaders,
# but a CC0 base mesh and ZERO MetaHuman assets. Ships its assets directly.
#
# Launch (windowed — NOT --headless):
#   Godot_v4.6 --path godot_project scenes/vitruvian_lookdev.tscn
# Controls: LMB orbit · wheel zoom · RMB/MMB pan · H hide UI · Esc quit
#
# Headless-ish capture: set NO_LOAD_SETTINGS=1 and LOOKDEV_CAPTURE=<prefix>,
# run at --resolution 1280x1280 → writes <prefix>_a.png / _b.png then quits.
# ──────────────────────────────────────────────────────────────────────────

const HEAD_GLB: String = "res://vitruvian_head.glb"
const HAIR_GLB: String = "res://vitruvian_hair.glb"
const SETTINGS_FILE: String = "look_settings.json"

const CREDITS_TEXT: String = """VitruvianGodot  •  Look-Dev

Tool and shaders: © 2026 Agile Lens — MIT License.
Skin / eye shaders are based on MatMADNESS HumanShaders (MIT), which build on
RustyRoboticsBV/GodotStandardLightShader.

— Character —
The head mesh and textures derive from the "Vitruvian" base of the CharMorph
Blender add-on, shipped under CC0 1.0 (public domain). Vitruvian by Sean Buckley
& Olaf Delgado-Friedrichs (relicensed from Antonia Polygon); skin LUT SirMaxim;
contributions per the CharMorph data. CharMorph add-on: Upliner (GPLv3 — add-on
code NOT included here, only CC0 output assets).

No MetaHuman / Epic assets are used. This demo is fully EULA-free."""

# ── Held live references (slider callbacks poke these) ──────────────────────
var skin_mats: Array[ShaderMaterial] = []
var vit_hair_mat: ShaderMaterial      # hair_card.gdshader (alpha strand atlas)
var vit_scalp_mat: StandardMaterial3D
var vit_brow_mat: ShaderMaterial      # hair_card.gdshader (eyebrow cards)

var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var catch_light: OmniLight3D
var env: Environment
var backdrop_mat: StandardMaterial3D
var camera: Camera3D
var cam_attrs: CameraAttributesPractical
var _character: Node3D

# Light orientation state (deg).
var key_yaw: float = -81.0
var key_pitch: float = -30.0
var fill_yaw: float = 21.0
var fill_pitch: float = 13.0
var rim_yaw: float = 51.0
var rim_pitch: float = -45.0

var backdrop_tint: Color = Color("332d28")
var backdrop_bright: float = 1.0

var dof_enabled: bool = true
var dof_focus: float = 0.52
var dof_blur: float = 0.06

# Orbit camera framing (head AABB Y 1.49–1.746).
const DEFAULT_CAM_TARGET: Vector3 = Vector3(0.0, 1.61, 0.0)
const DEFAULT_CAM_YAW: float = -16.0
const DEFAULT_CAM_PITCH: float = 5.0
const DEFAULT_CAM_DIST: float = 0.52
var orbit_target: Vector3 = DEFAULT_CAM_TARGET
var orbit_yaw: float = DEFAULT_CAM_YAW
var orbit_pitch: float = DEFAULT_CAM_PITCH
var orbit_dist: float = DEFAULT_CAM_DIST
var _drag_mode: int = 0
var auto_turntable: bool = false
const TURNTABLE_SPEED: float = 18.0
var _orbit_fov: float = 28.0

# Hero camera (wide→close push-in, ping-pong).
var _hero_cam: bool = false
var _hero_elapsed: float = 0.0
const HERO_DURATION: float = 12.0
const HERO_WIDE_POS: Vector3 = Vector3(0.0, 1.62, 1.2)
const HERO_CLOSE_POS: Vector3 = Vector3(0.06, 1.63, 0.40)
const HERO_WIDE_FOV: float = 34.0
const HERO_CLOSE_FOV: float = 22.0

var _defaults: Dictionary = {}
var _savers: Dictionary = {}
var _loaders: Dictionary = {}

# Panel state.
var _panel: PanelContainer
var _panel_width: float = 400.0
var _panel_prev_width: float = 400.0
var _panel_dragging: bool = false
var _panel_handle: Panel
var _panel_collapse_btn: Button

# UI / capture state.
var _ui_layer: CanvasLayer
var _hint_layer: CanvasLayer
var _credits_panel: Control
var _toast_label: Label
var _toast_until: float = 0.0
var _time: float = 0.0
var _out_dir: String = ""

var _cap_prefix: String = ""
var _cap_frame: int = 0

# Movie (turntable) recording.
var _movie_recording: bool = false
var _movie_frame: int = 0
var _movie_total: int = 144
var _movie_dir: String = ""
var _movie_stamp: String = ""
var _movie_start_yaw: float = 0.0
var _prev_scale_3d: float = 1.0

const ASSEMBLE_PY: String = """
import cv2, os, sys, glob
d, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(d, 'f*.png')))
if not files:
    sys.exit(2)
img = cv2.imread(files[0]); h, w = img.shape[:2]
for cc in ('avc1', 'mp4v'):
    vw = cv2.VideoWriter(out, cv2.VideoWriter_fourcc(*cc), 30, (w, h))
    if vw.isOpened():
        break
for f in files:
    vw.write(cv2.imread(f))
vw.release()
print('wrote', out, w, 'x', h, len(files), 'frames')
"""


func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("res://").path_join("..").path_join("out")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_setup_environment()
	_setup_backdrop()
	_setup_lights()
	_setup_camera()
	_character = Node3D.new()
	_character.name = "Character"
	add_child(_character)
	if not _load_and_wire():
		push_error("[vit] failed to load/wire head")
		return
	_build_ui()
	_update_orbit_camera()
	if not OS.has_environment("NO_LOAD_SETTINGS"):
		_load_settings()
	if OS.has_environment("LOOKDEV_CAPTURE"):
		_cap_prefix = OS.get_environment("LOOKDEV_CAPTURE")
		print("[vit] CAPTURE MODE → ", _cap_prefix)


func _process(delta: float) -> void:
	_time += delta
	if _toast_label and _toast_until > 0.0 and _time > _toast_until:
		_toast_label.visible = false
		_toast_until = 0.0
	if auto_turntable and _character:
		_character.rotation.y += deg_to_rad(TURNTABLE_SPEED) * delta
	if _hero_cam:
		_hero_elapsed += delta
		_update_hero_camera()
	if catch_light and camera:
		var to_cam: Vector3 = (camera.global_position - orbit_target)
		if to_cam.length() > 0.001:
			catch_light.position = orbit_target + to_cam.normalized() * 0.5 + Vector3(0.08, 0.18, 0.0)
	if _cap_prefix != "":
		_capture_tick()


func _capture_tick() -> void:
	_cap_frame += 1
	if _cap_frame == 24:
		_grab("%s_a.png" % _cap_prefix)
	elif _cap_frame == 30:
		if skin_mats.size() > 0:
			skin_mats[0].set_shader_parameter("subsurface_scattering_strength", 0.85)
		orbit_yaw = 18.0
		orbit_dist = 0.42
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


# ════════════════════════════════════════════════════════════════════════════
# Scene construction
# ════════════════════════════════════════════════════════════════════════════

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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX   # realism playbook: AgX, not ACES
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
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.02
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	we.name = "WorldEnvironment"
	add_child(we)
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH)
	RenderingServer.sub_surface_scattering_set_scale(0.08, 0.02)


func _setup_backdrop() -> void:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(0.20, 0.19, 0.17))
	grad.add_point(0.5, Color(0.10, 0.10, 0.10))
	grad.set_color(1, Color(0.035, 0.037, 0.043))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 1024
	tex.height = 1024
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.32)
	tex.fill_to = Vector2(0.92, 0.80)
	backdrop_mat = StandardMaterial3D.new()
	backdrop_mat.albedo_texture = tex
	backdrop_mat.albedo_color = Color(1, 1, 1)
	backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane: MeshInstance3D = MeshInstance3D.new()
	plane.name = "Backdrop"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(7.0, 7.0)
	plane.mesh = quad
	plane.material_override = backdrop_mat
	plane.position = Vector3(0.0, 1.55, -1.2)
	add_child(plane)
	_apply_backdrop()


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
	_apply_light_rot(key_light, key_pitch, key_yaw)
	add_child(key_light)

	rim_light = DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.light_energy = 1.9
	rim_light.light_specular = 0.4
	rim_light.light_color = Color(0.40, 0.62, 1.0)
	_apply_light_rot(rim_light, rim_pitch, rim_yaw)
	add_child(rim_light)

	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.9
	fill_light.light_color = Color(0.85, 0.84, 0.82)
	_apply_light_rot(fill_light, fill_pitch, fill_yaw)
	add_child(fill_light)

	catch_light = OmniLight3D.new()
	catch_light.name = "CatchLight"
	catch_light.light_energy = 0.12
	catch_light.light_specular = 1.0
	catch_light.light_color = Color(1.0, 0.98, 0.95)
	catch_light.omni_range = 1.2
	catch_light.omni_attenuation = 2.4
	catch_light.position = Vector3(0.22, 1.78, 0.45)
	add_child(catch_light)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.02
	camera.far = 50.0
	camera.current = true
	camera.fov = _orbit_fov
	cam_attrs = CameraAttributesPractical.new()
	cam_attrs.dof_blur_far_enabled = dof_enabled
	cam_attrs.dof_blur_near_enabled = dof_enabled
	camera.attributes = cam_attrs
	add_child(camera)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


# ── Material wiring ─────────────────────────────────────────────────────────

func _load_and_wire() -> bool:
	var hscene: PackedScene = load(HEAD_GLB)
	if hscene == null:
		return false
	var head: Node = hscene.instantiate()
	head.name = "Head"
	_character.add_child(head)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(head, meshes)
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		for s in range(mesh.get_surface_count()):
			var m: Material = mesh.surface_get_material(s)
			# Match by PREFIX — glTF/Blender may append ".001" to duplicated
			# material names (this silently blanked the 2nd eye before).
			var nm: String = (m.resource_name if m else "").split(".")[0]
			match nm:
				"VitSkin":    mi.set_surface_override_material(s, _make_skin())
				"VitEyeball": mi.set_surface_override_material(s, _make_eyeball())
				"VitCornea":  mi.set_surface_override_material(s, _make_cornea())
				"VitMouth":   mi.set_surface_override_material(s, _make_mouth())
				"VitScalp":   mi.set_surface_override_material(s, _make_scalp())
				_:            pass

	if ResourceLoader.exists(HAIR_GLB):
		var hairscene: PackedScene = load(HAIR_GLB)
		if hairscene:
			var hair: Node = hairscene.instantiate()
			hair.name = "Hair"
			_character.add_child(hair)
			var hmeshes: Array[MeshInstance3D] = []
			_collect_meshes(hair, hmeshes)
			for hm in hmeshes:
				var is_brow: bool = hm.name.begins_with("VitBrow")
				var hmat: ShaderMaterial = _make_browcards() if is_brow else _make_hair()
				for s in range(hm.mesh.get_surface_count()):
					hm.set_surface_override_material(s, hmat)
	return true


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


func _tex(p: String) -> Texture2D:
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


func _make_skin() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://scenes/skin_shader_local.gdshader") as Shader
	mat.set_shader_parameter("texture_albedo", _tex("res://vit_face_bc.png"))
	mat.set_shader_parameter("albedo", Color(1, 1, 1, 1))
	mat.set_shader_parameter("texture_normal", _tex("res://vit_face_n.png"))
	mat.set_shader_parameter("normal_strength", 1.0)
	mat.set_shader_parameter("texture_roughness", _tex("res://vit_face_rough.png"))
	mat.set_shader_parameter("roughness", 0.95)
	mat.set_shader_parameter("specular", 0.35)
	mat.set_shader_parameter("double_specularity", false)
	mat.set_shader_parameter("metallic", 0.0)
	mat.set_shader_parameter("metallic_texture_channel", Plane(1, 0, 0, 0))
	mat.set_shader_parameter("use_subsurface_scattering", true)
	mat.set_shader_parameter("use_noise", false)
	mat.set_shader_parameter("subsurface_scattering_strength", 0.55)
	mat.set_shader_parameter("skin_smoothness", 1.8)
	mat.set_shader_parameter("skin_fallof_smoothness", 1.05)
	mat.set_shader_parameter("sss_depth_scale", 6.0)
	mat.set_shader_parameter("old_lightwarp_fallof", false)
	mat.set_shader_parameter("tinted_shadow_penumbra", true)
	mat.set_shader_parameter("use_micro_detail", false)
	mat.set_shader_parameter("micro_normal_strength", 0.0)
	mat.set_shader_parameter("use_ambient_occlusion", false)
	mat.set_shader_parameter("translucency", false)
	mat.set_shader_parameter("use_scatter_map", false)
	mat.set_shader_parameter("uv1_scale", Vector3(1, 1, 1))
	mat.set_shader_parameter("uv1_offset", Vector3(0, 0, 0))
	mat.set_shader_parameter("uv2_scale", Vector3(1, 1, 1))
	mat.set_shader_parameter("uv2_offset", Vector3(0, 0, 0))
	skin_mats.append(mat)
	return mat


func _iris_ramp() -> GradientTexture1D:
	# Iris fibre colour ramp (sampled by the procedural voronoi luminance).
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(0.05, 0.035, 0.02))    # dark fibres
	g.add_point(0.5, Color(0.32, 0.20, 0.09))   # mid amber-brown
	g.set_color(1, Color(0.55, 0.40, 0.20))     # bright limbal
	var t: GradientTexture1D = GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t


func _make_eyeball() -> ShaderMaterial:
	# Procedural iris/pupil/sclera (blackears eyeball_shader, MIT) — radial UV.
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://addons/eyeball_shader/shaders/eyeball_shader.gdshader") as Shader
	mat.set_shader_parameter("iris_radius", 0.34)
	mat.set_shader_parameter("iris_margin", 0.03)
	mat.set_shader_parameter("pupil_radius", 0.13)
	mat.set_shader_parameter("eye_white", Color(0.92, 0.90, 0.88))
	mat.set_shader_parameter("pupil_color", Color(0.02, 0.02, 0.025))
	mat.set_shader_parameter("texture_iris_color", _iris_ramp())
	mat.set_shader_parameter("eye_cell_scale", 17.0)
	mat.set_shader_parameter("eye_cell_jitter", 0.6)
	mat.set_shader_parameter("iris_pinch", 0.6)
	mat.set_shader_parameter("rand_seed", 12345)
	mat.set_shader_parameter("uv1_scale", Vector3(1, 1, 1))
	mat.set_shader_parameter("uv1_offset", Vector3(0, 0, 0))
	return mat


func _make_cornea() -> ShaderMaterial:
	# Glassy additive specular shell over the eyeball (blackears cornea, MIT).
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://addons/eyeball_shader/shaders/cornea.gdshader") as Shader
	mat.set_shader_parameter("shininess", 360.0)
	mat.set_shader_parameter("spec_intensity", 0.32)
	mat.set_shader_parameter("alpha_max", 0.8)
	return mat


func _make_mouth() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _tex("res://vit_mouth.png")
	m.albedo_color = Color(0.85, 0.78, 0.76)
	m.roughness = 0.42
	m.metallic = 0.0
	return m


func _make_scalp() -> StandardMaterial3D:
	vit_scalp_mat = StandardMaterial3D.new()
	vit_scalp_mat.albedo_color = Color(0.045, 0.032, 0.022)
	vit_scalp_mat.roughness = 0.7
	vit_scalp_mat.metallic = 0.0
	return vit_scalp_mat


func _make_hair_card(color: Color, threshold: float, root_dark: float, rough: float) -> ShaderMaterial:
	# Alpha-clipped hair-card shader reading the procedural strand atlas (R channel).
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://scenes/hair_card.gdshader") as Shader
	mat.set_shader_parameter("hair_color", color)
	mat.set_shader_parameter("coverage_atlas", _tex("res://vit_hair_atlas.png"))
	mat.set_shader_parameter("use_red_mask", true)
	mat.set_shader_parameter("invert_mask", false)
	mat.set_shader_parameter("alpha_threshold", threshold)
	mat.set_shader_parameter("root_darkening", root_dark)
	mat.set_shader_parameter("roughness_val", rough)
	mat.set_shader_parameter("specular_val", 0.35)
	return mat


func _make_hair() -> ShaderMaterial:
	if vit_hair_mat == null:
		vit_hair_mat = _make_hair_card(Color(0.09, 0.064, 0.045), 0.10, 0.55, 0.6)
	return vit_hair_mat


func _make_browcards() -> ShaderMaterial:
	if vit_brow_mat == null:
		vit_brow_mat = _make_hair_card(Color(0.12, 0.085, 0.055), 0.12, 0.45, 0.7)
	return vit_brow_mat


# ════════════════════════════════════════════════════════════════════════════
# Orbit camera input
# ════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			_toggle_ui(); return
		if event.keycode == KEY_ESCAPE:
			if _credits_panel and _credits_panel.visible:
				_credits_panel.visible = false
			else:
				get_tree().quit()
			return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					orbit_dist = maxf(0.12, orbit_dist * 0.9); _update_orbit_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					orbit_dist = minf(8.0, orbit_dist * 1.1); _update_orbit_camera()
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
	if camera == null or _hero_cam:
		return
	var p: float = deg_to_rad(orbit_pitch)
	var y: float = deg_to_rad(orbit_yaw)
	var dir: Vector3 = Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	camera.position = orbit_target + dir * orbit_dist
	camera.look_at(orbit_target, Vector3.UP)
	camera.fov = _orbit_fov
	if dof_enabled:
		_apply_dof()


func _apply_dof() -> void:
	cam_attrs.dof_blur_far_enabled = dof_enabled
	cam_attrs.dof_blur_near_enabled = dof_enabled
	cam_attrs.dof_blur_far_distance = dof_focus
	cam_attrs.dof_blur_near_distance = maxf(0.05, dof_focus - 0.25)
	cam_attrs.dof_blur_amount = dof_blur


func _reset_camera() -> void:
	orbit_target = DEFAULT_CAM_TARGET
	orbit_yaw = DEFAULT_CAM_YAW
	orbit_pitch = DEFAULT_CAM_PITCH
	orbit_dist = DEFAULT_CAM_DIST
	_update_orbit_camera()


func _set_hero_cam(on: bool) -> void:
	_hero_cam = on
	if on:
		_hero_elapsed = 0.0
	else:
		if camera:
			camera.fov = _orbit_fov
		_update_orbit_camera()


func _update_hero_camera() -> void:
	if camera == null:
		return
	var phase: float = fmod(_hero_elapsed, 2.0 * HERO_DURATION) / HERO_DURATION
	var p: float = phase if phase <= 1.0 else (2.0 - phase)
	p = smoothstep(0.0, 1.0, p)
	camera.position = HERO_WIDE_POS.lerp(HERO_CLOSE_POS, p)
	camera.fov = lerpf(HERO_WIDE_FOV, HERO_CLOSE_FOV, p)
	camera.look_at(orbit_target, Vector3.UP)
	if dof_enabled:
		var focus: float = camera.global_transform.origin.distance_to(orbit_target)
		cam_attrs.dof_blur_far_distance = focus + 0.10
		cam_attrs.dof_blur_near_distance = maxf(0.05, focus - 0.30)


# ════════════════════════════════════════════════════════════════════════════
# UI
# ════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_ui_layer = layer

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_right = _panel_width
	panel.clip_contents = true
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.88)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	_panel = panel

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	scroll.add_child(vb)

	var title: Label = Label.new()
	title.text = "Vitruvian Look-Dev (CC0)"
	title.add_theme_font_size_override("font_size", 18)
	vb.add_child(title)
	var hint: Label = Label.new()
	hint.text = "LMB orbit · wheel zoom · RMB/MMB pan"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	hint.add_theme_font_size_override("font_size", 11)
	vb.add_child(hint)

	var btn_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(btn_row)
	var save_btn: Button = Button.new()
	save_btn.text = "Save settings"
	save_btn.pressed.connect(_save_settings)
	btn_row.add_child(save_btn)
	var load_btn: Button = Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func(): _load_settings())
	btn_row.add_child(load_btn)
	var reset_btn: Button = Button.new()
	reset_btn.text = "Reset cam"
	reset_btn.pressed.connect(_reset_camera)
	btn_row.add_child(reset_btn)

	var tt: CheckButton = CheckButton.new()
	tt.text = "Auto-turntable (spins model)"
	tt.toggled.connect(func(on): auto_turntable = on)
	vb.add_child(tt)
	var hero_tt: CheckButton = CheckButton.new()
	hero_tt.text = "Hero camera (wide → close, loops)"
	hero_tt.toggled.connect(_set_hero_cam)
	vb.add_child(hero_tt)

	# ── SKIN ──
	_hdr(vb, "Skin")
	_mkslider(vb, "SKIN_NRM", "normal_strength", 0.0, 8.0, 0.01, 1.0, _skin_setter("normal_strength"))
	_mkslider(vb, "SKIN_SSS", "subsurface_scattering", 0.0, 1.0, 0.01, 0.55, _skin_setter("subsurface_scattering_strength"))
	_mkslider(vb, "SKIN_SMOOTH", "skin_smoothness", 0.0, 6.0, 0.01, 1.8, _skin_setter("skin_smoothness"))
	_mkslider(vb, "sss_depth", "sss_depth_scale", 0.5, 12.0, 0.1, 6.0, _skin_setter("sss_depth_scale"))
	_mkslider(vb, "skin_rough", "roughness", 0.0, 1.0, 0.01, 0.95, _skin_setter("roughness"))
	_mkslider(vb, "skin_spec", "specular", 0.0, 2.0, 0.01, 0.35, _skin_setter("specular"))
	_mkcheck(vb, "use_sss", "use_subsurface_scattering", true, _skin_setter_b("use_subsurface_scattering"))
	_mkcheck(vb, "tinted_pen", "tinted_shadow_penumbra", true, _skin_setter_b("tinted_shadow_penumbra"))

	# ── KEY LIGHT ──
	_hdr(vb, "Key light")
	_mkslider(vb, "KEY", "energy", 0.0, 10.0, 0.01, 3.2, func(v): key_light.light_energy = v)
	_mkcolor(vb, "key_color", "color", Color("ffe6c2"), func(c): key_light.light_color = c)
	_mkslider(vb, "key_yaw", "yaw", -180.0, 180.0, 1.0, key_yaw, func(v): key_yaw = v; _apply_light_rot(key_light, key_pitch, key_yaw))
	_mkslider(vb, "key_pitch", "pitch", -90.0, 30.0, 1.0, key_pitch, func(v): key_pitch = v; _apply_light_rot(key_light, key_pitch, key_yaw))
	_mkslider(vb, "key_shadow_blur", "shadow blur", 0.0, 10.0, 0.1, 3.0, func(v): key_light.shadow_blur = v)

	# ── FILL LIGHT ──
	_hdr(vb, "Fill light")
	_mkslider(vb, "FILL", "energy", 0.0, 6.0, 0.01, 0.9, func(v): fill_light.light_energy = v)
	_mkcolor(vb, "fill_color", "color", Color("d9d6d1"), func(c): fill_light.light_color = c)
	_mkslider(vb, "fill_yaw", "yaw", -180.0, 180.0, 1.0, fill_yaw, func(v): fill_yaw = v; _apply_light_rot(fill_light, fill_pitch, fill_yaw))
	_mkslider(vb, "fill_pitch", "pitch", -90.0, 30.0, 1.0, fill_pitch, func(v): fill_pitch = v; _apply_light_rot(fill_light, fill_pitch, fill_yaw))

	# ── RIM LIGHT ──
	_hdr(vb, "Rim light")
	_mkslider(vb, "RIM", "energy", 0.0, 10.0, 0.01, 1.9, func(v): rim_light.light_energy = v)
	_mkcolor(vb, "rim_color", "color", Color("6699ff"), func(c): rim_light.light_color = c)
	_mkslider(vb, "rim_yaw", "yaw", -180.0, 180.0, 1.0, rim_yaw, func(v): rim_yaw = v; _apply_light_rot(rim_light, rim_pitch, rim_yaw))
	_mkslider(vb, "rim_pitch", "pitch", -90.0, 30.0, 1.0, rim_pitch, func(v): rim_pitch = v; _apply_light_rot(rim_light, rim_pitch, rim_yaw))

	# ── CATCHLIGHT ──
	_hdr(vb, "Catchlight (frontal omni)")
	_mkslider(vb, "CATCH", "energy", 0.0, 4.0, 0.01, 0.12, func(v): catch_light.light_energy = v)

	# ── ENVIRONMENT ──
	_hdr(vb, "Environment")
	_mkslider(vb, "AMBIENT", "ambient energy", 0.0, 3.0, 0.01, 0.10, func(v): env.ambient_light_energy = v)
	_mkslider(vb, "EXPOSURE", "exposure", 0.2, 3.0, 0.01, 1.0, func(v): env.tonemap_exposure = v)
	_mkslider(vb, "saturation", "saturation", 0.0, 3.0, 0.01, 1.02, func(v): env.adjustment_saturation = v)
	_mkslider(vb, "contrast", "contrast", 0.0, 3.0, 0.01, 1.03, func(v): env.adjustment_contrast = v)
	_mkslider(vb, "backdrop_bright", "backdrop brightness", 0.0, 4.0, 0.01, 1.0, func(v): backdrop_bright = v; _apply_backdrop())
	_mkcolor(vb, "backdrop_tint", "backdrop tint", Color("332d28"), func(c): backdrop_tint = c; _apply_backdrop())

	# ── HAIR ──
	_hdr(vb, "Hair")
	_mkcolor(vb, "hair_color", "hair color", Color("19120c"), func(c): if vit_hair_mat: vit_hair_mat.set_shader_parameter("hair_color", c))
	_mkcolor(vb, "scalp_color", "scalp color", Color("0b0806"), func(c): if vit_scalp_mat: vit_scalp_mat.albedo_color = c)
	_mkcolor(vb, "brow_color", "eyebrow color", Color("1f160e"), func(c): if vit_brow_mat: vit_brow_mat.set_shader_parameter("hair_color", c))
	_mkslider(vb, "hair_threshold", "hair density", 0.02, 0.6, 0.005, 0.10, func(v): if vit_hair_mat: vit_hair_mat.set_shader_parameter("alpha_threshold", v))

	# ── CAMERA / DOF ──
	_hdr(vb, "Camera / DOF")
	_mkslider(vb, "fov", "FOV", 8.0, 90.0, 0.5, 28.0, func(v): _set_fov(v))
	_mkcheck(vb, "dof_enabled", "DOF enabled", true, func(on): dof_enabled = on; _apply_dof())
	_mkslider(vb, "dof_focus", "focus distance", 0.1, 4.0, 0.01, 0.52, func(v): dof_focus = v; _apply_dof())
	_mkslider(vb, "dof_blur", "blur amount", 0.0, 1.0, 0.005, 0.06, func(v): dof_blur = v; _apply_dof())

	_build_corner_ui(layer)
	_build_panel_handle(layer)


# ── Setter factories / helpers ───────────────────────────────────────────────

func _skin_setter(param: String) -> Callable:
	return func(v: float) -> void:
		for m in skin_mats:
			m.set_shader_parameter(param, v)


func _skin_setter_b(param: String) -> Callable:
	return func(on: bool) -> void:
		for m in skin_mats:
			m.set_shader_parameter(param, on)


func _apply_light_rot(light: DirectionalLight3D, pitch: float, yaw: float) -> void:
	light.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)


func _apply_backdrop() -> void:
	if backdrop_mat:
		backdrop_mat.albedo_color = Color(
			backdrop_tint.r * backdrop_bright,
			backdrop_tint.g * backdrop_bright,
			backdrop_tint.b * backdrop_bright, 1.0)


func _set_fov(v: float) -> void:
	_orbit_fov = v
	if not _hero_cam and camera:
		camera.fov = v


# ── Panel handle / collapse ───────────────────────────────────────────────────

func _build_panel_handle(layer: CanvasLayer) -> void:
	var handle: Panel = Panel.new()
	handle.anchor_bottom = 1.0
	handle.offset_left = _panel_width
	handle.offset_right = _panel_width + 12.0
	handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	var hs: StyleBoxFlat = StyleBoxFlat.new()
	hs.bg_color = Color(0.20, 0.22, 0.28, 0.9)
	handle.add_theme_stylebox_override("panel", hs)
	handle.gui_input.connect(_on_handle_input)
	layer.add_child(handle)
	_panel_handle = handle
	var collapse: Button = Button.new()
	collapse.text = "‹‹"
	collapse.offset_left = _panel_width + 16.0
	collapse.offset_top = 12.0
	collapse.offset_right = _panel_width + 50.0
	collapse.offset_bottom = 40.0
	collapse.pressed.connect(_toggle_panel_collapse)
	layer.add_child(collapse)
	_panel_collapse_btn = collapse


func _on_handle_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_panel_dragging = (ev as InputEventMouseButton).pressed


func _input(event: InputEvent) -> void:
	if not _panel_dragging:
		return
	if event is InputEventMouseMotion:
		_set_panel_width((event as InputEventMouseMotion).position.x + 6.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_panel_dragging = false


func _set_panel_width(w: float) -> void:
	_panel_width = clampf(w, 0.0, 760.0)
	if _panel:
		_panel.offset_right = _panel_width
	if _panel_handle:
		_panel_handle.offset_left = _panel_width
		_panel_handle.offset_right = _panel_width + 12.0
	if _panel_collapse_btn:
		_panel_collapse_btn.offset_left = _panel_width + 16.0
		_panel_collapse_btn.offset_right = _panel_width + 50.0


func _toggle_panel_collapse() -> void:
	if _panel_width > 40.0:
		_panel_prev_width = _panel_width
		_set_panel_width(0.0)
		if _panel_collapse_btn: _panel_collapse_btn.text = "››"
	else:
		_set_panel_width(_panel_prev_width if _panel_prev_width > 40.0 else 400.0)
		if _panel_collapse_btn: _panel_collapse_btn.text = "‹‹"


# ── Corner UI ─────────────────────────────────────────────────────────────────

func _build_corner_ui(layer: CanvasLayer) -> void:
	var caps: VBoxContainer = VBoxContainer.new()
	caps.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	caps.offset_left = -260; caps.offset_top = -84; caps.offset_right = -12; caps.offset_bottom = -12
	caps.alignment = BoxContainer.ALIGNMENT_END
	caps.add_theme_constant_override("separation", 6)
	layer.add_child(caps)
	var shot_btn: Button = Button.new()
	shot_btn.text = "Screenshot"
	shot_btn.pressed.connect(_capture_screenshot)
	caps.add_child(shot_btn)
	var movie_btn: Button = Button.new()
	movie_btn.text = "Capture movie (turntable)"
	movie_btn.pressed.connect(_start_movie)
	caps.add_child(movie_btn)

	var hide_btn: Button = Button.new()
	hide_btn.text = "Hide UI  [H]"
	hide_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hide_btn.offset_left = -120; hide_btn.offset_top = 12; hide_btn.offset_right = -12; hide_btn.offset_bottom = 40
	hide_btn.pressed.connect(_toggle_ui)
	layer.add_child(hide_btn)

	var cred_btn: Button = Button.new()
	cred_btn.text = "Credits / Legal"
	cred_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cred_btn.offset_left = -120; cred_btn.offset_top = 46; cred_btn.offset_right = -12; cred_btn.offset_bottom = 74
	cred_btn.pressed.connect(_toggle_credits)
	layer.add_child(cred_btn)
	_build_credits_panel(layer)

	var quit_btn: Button = Button.new()
	quit_btn.text = "Quit  [Esc]"
	quit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quit_btn.offset_left = -120; quit_btn.offset_top = 80; quit_btn.offset_right = -12; quit_btn.offset_bottom = 108
	quit_btn.pressed.connect(func(): get_tree().quit())
	layer.add_child(quit_btn)

	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_label.offset_left = -400; _toast_label.offset_right = 400; _toast_label.offset_top = -48; _toast_label.offset_bottom = -20
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_toast_label.visible = false
	layer.add_child(_toast_label)

	_hint_layer = CanvasLayer.new()
	_hint_layer.name = "UIHint"
	add_child(_hint_layer)
	var hint: Label = Label.new()
	hint.text = "[H] show UI"
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -110; hint.offset_top = 12; hint.offset_right = -12; hint.offset_bottom = 36
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_hint_layer.add_child(hint)
	_hint_layer.visible = false


func _toggle_ui() -> void:
	if _ui_layer == null:
		return
	_ui_layer.visible = not _ui_layer.visible
	if _hint_layer:
		_hint_layer.visible = not _ui_layer.visible


func _build_credits_panel(layer: CanvasLayer) -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(scrim)
	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.10, 0.12, 0.98)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.35, 0.45)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 22; sb.content_margin_right = 22; sb.content_margin_top = 18; sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var body: Label = Label.new()
	body.text = CREDITS_TEXT + "\n\n— Engine —\nBuilt with Godot Engine %s (stock build, MIT). Forward+ renderer." % Engine.get_version_info().get("string", "4.6")
	body.add_theme_font_size_override("font_size", 14)
	body.custom_minimum_size = Vector2(680, 0)
	vb.add_child(body)
	var close: Button = Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_toggle_credits)
	vb.add_child(close)
	layer.add_child(center)
	_credits_panel = center


func _toggle_credits() -> void:
	if _credits_panel:
		_credits_panel.visible = not _credits_panel.visible


func _toast(msg: String) -> void:
	if _toast_label:
		_toast_label.text = msg
		_toast_label.visible = true
		_toast_until = _time + 4.0


# ── Capture ────────────────────────────────────────────────────────────────

func _begin_capture_quality() -> void:
	var vp: Viewport = get_viewport()
	_prev_scale_3d = vp.scaling_3d_scale
	if _prev_scale_3d < 2.0:
		vp.scaling_3d_scale = 2.0


func _end_capture_quality() -> void:
	get_viewport().scaling_3d_scale = _prev_scale_3d


func _capture_screenshot() -> void:
	var was_visible: bool = _ui_layer.visible
	_ui_layer.visible = false
	if _hint_layer: _hint_layer.visible = false
	_begin_capture_quality()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = _out_dir.path_join("vitruvian_shot_%s.png" % _stamp())
	var err: int = img.save_png(path)
	_end_capture_quality()
	_ui_layer.visible = was_visible
	print("[vit] screenshot → %s (err %d)" % [path, err])
	_toast("Saved %s" % path)


func _start_movie() -> void:
	if _movie_recording:
		return
	if OS.has_environment("MOVIE_FRAMES"):
		_movie_total = maxi(2, int(OS.get_environment("MOVIE_FRAMES")))
	_movie_stamp = _stamp()
	_movie_dir = _out_dir.path_join("vitruvian_movie_%s" % _movie_stamp)
	DirAccess.make_dir_recursive_absolute(_movie_dir)
	_begin_capture_quality()
	_movie_recording = true
	_movie_frame = 0
	_movie_start_yaw = _character.rotation.y if _character else 0.0
	_ui_layer.visible = false
	if _hint_layer: _hint_layer.visible = false
	print("[vit] recording turntable → ", _movie_dir)
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _on_frame_post_draw() -> void:
	if not _movie_recording:
		return
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/f%04d.png" % [_movie_dir, _movie_frame])
	_movie_frame += 1
	if _movie_frame >= _movie_total:
		_finish_movie()
	elif _character:
		_character.rotation.y = _movie_start_yaw + deg_to_rad(360.0) * float(_movie_frame) / float(_movie_total)


func _finish_movie() -> void:
	_movie_recording = false
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	_end_capture_quality()
	if _character:
		_character.rotation.y = _movie_start_yaw
	_ui_layer.visible = true
	var py: String = "%s/_assemble.py" % _movie_dir
	var pf: FileAccess = FileAccess.open(py, FileAccess.WRITE)
	if pf:
		pf.store_string(ASSEMBLE_PY); pf.close()
	var out_mp4: String = _out_dir.path_join("vitruvian_movie_%s.mp4" % _movie_stamp)
	var output: Array = []
	var code: int = OS.execute("python", [py, _movie_dir, out_mp4], output, true)
	if code == 0:
		print("[vit] movie → %s" % out_mp4)
		_toast("Movie saved: %s" % out_mp4)
	else:
		print("[vit] cv2 assemble failed (code %d); frames in %s" % [code, _movie_dir])
		_toast("Frames saved (assemble manually): %s" % _movie_dir)


func _stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")


# ── UI widget builders ───────────────────────────────────────────────────────

func _hdr(parent: Node, text: String) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	parent.add_child(spacer)
	var l: Label = Label.new()
	l.text = "── " + text + " ──"
	l.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)


func _reset_btn(key: String) -> Button:
	var b: Button = Button.new()
	b.text = "↺"
	b.tooltip_text = "Reset to default"
	b.custom_minimum_size = Vector2(26, 0)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func():
		if _loaders.has(key) and _defaults.has(key):
			_loaders[key].call(_defaults[key]))
	return b


func _mkslider(parent: Node, key: String, label: String, mn: float, mx: float,
		step: float, val: float, setter: Callable) -> HSlider:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = label
	l.custom_minimum_size.x = 150
	l.add_theme_font_size_override("font_size", 12)
	var s: HSlider = HSlider.new()
	s.min_value = mn; s.max_value = mx; s.step = step; s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 18
	var sp: SpinBox = SpinBox.new()
	sp.min_value = mn; sp.max_value = mx; sp.step = step
	sp.allow_greater = true; sp.allow_lesser = true; sp.value = val
	sp.custom_minimum_size.x = 76
	sp.add_theme_font_size_override("font_size", 12)
	s.value_changed.connect(func(v):
		sp.set_value_no_signal(v); setter.call(v))
	sp.value_changed.connect(func(v):
		s.set_value_no_signal(v); setter.call(v))
	row.add_child(l); row.add_child(s); row.add_child(sp); row.add_child(_reset_btn(key))
	parent.add_child(row)
	setter.call(val)
	_defaults[key] = val
	_savers[key] = func(): return sp.value
	_loaders[key] = func(x):
		var fx: float = float(x)
		sp.set_value_no_signal(fx); s.set_value_no_signal(fx); setter.call(fx)
	return s


func _mkcheck(parent: Node, key: String, label: String, val: bool, setter: Callable) -> CheckBox:
	var row: HBoxContainer = HBoxContainer.new()
	var c: CheckBox = CheckBox.new()
	c.text = label
	c.button_pressed = val
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_font_size_override("font_size", 12)
	c.toggled.connect(func(on): setter.call(on))
	row.add_child(c); row.add_child(_reset_btn(key))
	parent.add_child(row)
	setter.call(val)
	_defaults[key] = val
	_savers[key] = func(): return c.button_pressed
	_loaders[key] = func(x):
		c.button_pressed = bool(x); setter.call(bool(x))
	return c


func _mkcolor(parent: Node, key: String, label: String, col: Color, setter: Callable) -> ColorPickerButton:
	var row: HBoxContainer = HBoxContainer.new()
	var l: Label = Label.new()
	l.text = label
	l.custom_minimum_size.x = 158
	l.add_theme_font_size_override("font_size", 12)
	var cp: ColorPickerButton = ColorPickerButton.new()
	cp.color = col
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(80, 22)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp.color_changed.connect(func(c): setter.call(c))
	row.add_child(l); row.add_child(cp); row.add_child(_reset_btn(key))
	parent.add_child(row)
	setter.call(col)
	_defaults[key] = col.to_html(false)
	_savers[key] = func(): return cp.color.to_html(false)
	_loaders[key] = func(x):
		var c: Color = Color(str(x)); cp.color = c; setter.call(c)
	return cp


# ── Save / Load ──────────────────────────────────────────────────────────────

func _settings_paths() -> Array:
	var mirror: String = ProjectSettings.globalize_path("res://").path_join("..").path_join(SETTINGS_FILE)
	return [mirror, "user://".path_join(SETTINGS_FILE)]


func _save_settings() -> void:
	var d: Dictionary = {}
	for k in _savers:
		d[k] = _savers[k].call()
	d["cam_yaw"] = orbit_yaw
	d["cam_pitch"] = orbit_pitch
	d["cam_dist"] = orbit_dist
	var txt: String = JSON.stringify(d, "  ")
	var wrote: Array = []
	for p in _settings_paths():
		var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_string(txt); f.close(); wrote.append(p)
	if wrote.is_empty():
		_toast("Save FAILED — no writable path"); return
	print("[vit] saved settings → ", wrote)
	_toast("Saved → %s" % wrote[0])


func _load_settings() -> void:
	for p in _settings_paths():
		if not FileAccess.file_exists(p):
			continue
		var f: FileAccess = FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt: String = f.get_as_text(); f.close()
		var d: Variant = JSON.parse_string(txt)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		for k in d:
			if _loaders.has(k):
				_loaders[k].call(d[k])
		if d.has("cam_yaw"): orbit_yaw = float(d["cam_yaw"])
		if d.has("cam_pitch"): orbit_pitch = float(d["cam_pitch"])
		if d.has("cam_dist"): orbit_dist = float(d["cam_dist"])
		_update_orbit_camera()
		print("[vit] loaded settings ← ", p)
		return
	print("[vit] no saved settings found yet")
