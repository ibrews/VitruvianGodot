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

const FaceExtras = preload("res://scenes/face_extras.gd")
const HEAD_GLB: String = "res://vitruvian_head.glb"
# Hair Tool cards (real authored cards + baked strand atlas) replace the old
# flat-card hair that read as a dark helmet. Old GLB kept for reference/revert.
const HAIR_GLB: String = "res://hairtool_cards.glb"
const HAIR_GLB_LEGACY: String = "res://vitruvian_hair.glb"
const BODY_GLB: String = "res://vitruvian_body.glb"
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
var vit_hair_mat: ShaderMaterial      # hairtool_card.gdshader (Hair Tool cards)
var vit_scalp_mat: ShaderMaterial    # scalp_cap.gdshader (dark crown base)
var vit_brow_mat: ShaderMaterial      # hair_card.gdshader (eyebrow cards)
var lash_mats: Array[ShaderMaterial] = []     # hair_card.gdshader (eyelashes, L+R)
var eyeball_mats: Array[ShaderMaterial] = []  # eyeball_shader (L+R)
var cornea_mats: Array[ShaderMaterial] = []   # cornea (L+R)
# iris fibre ramp shared across both eyes (3 editable stops)
var iris_grad: Gradient
var iris_ramp_tex: GradientTexture1D
var iris_col_dark: Color = Color(0.025, 0.016, 0.010)   # dark limbal/pupil-edge fibres
var iris_col_mid: Color = Color(0.20, 0.115, 0.050)     # rich mid brown
var iris_col_bright: Color = Color(0.46, 0.31, 0.145)   # warm bright fleck
# body + clothing
var body_skin_mat: ShaderMaterial   # same skin shader as the face → consistent neck (no tan line)
var shirt_mat: StandardMaterial3D
var pants_mat: StandardMaterial3D
var _body_root: Node3D
var _body_meshes: Array[MeshInstance3D] = []   # body+clothing meshes (for show_body toggle)
var show_body: bool = true

# animation / rig (head + hair ride the body Head bone so the body can animate)
const HAIR_RIGGED: String = "res://vitruvian_hair_rigged.glb"   # spring-bone chain
const HEAD_BONE: String = "mixamorig_Head"
var anim: AnimationPlayer
var skel: Skeleton3D
var head_rig: Node3D
var hair_spring: HairSpring
var _anim_names: PackedStringArray = PackedStringArray()
var _cur_clip: String = "Idle"
var _anim_buttons: Dictionary = {}             # clip name -> Button (for highlight)

# facial animation (CC0 ARKit blendshapes on the head + eyeball nodes)
var face_mi: MeshInstance3D
var bshapes: Dictionary = {}
var eye_nodes: Array = []
var upper_lids: Array = []          # [{node, rest_basis}] upper eyelids (rotate down to blink)
# Godot 4.6.3 won't RENDER blend shapes on this mesh (data is fine, render is broken),
# so we morph the vertices DIRECTLY at runtime instead. _morph_* holds the base mesh +
# per-shape position deltas; _apply_morph rebuilds the surface when weights change.
var _morph_arrays: Array = []
var _morph_base: PackedVector3Array
var _morph_deltas: Dictionary = {}  # shape name -> PackedVector3Array delta
var _morph_mat: Material
var _morph_key: String = "_init_"
var _gaze: Vector2 = Vector2.ZERO
# resting-gaze correction (audit: gaze sat slightly down + inward = doll stare).
# Calibrated via GAZE_TUNE + EYE_SHOT captures; euler x = vertical, z = horizontal.
const GAZE_PITCH_BIAS: float = 0.05    # lift gaze up to camera height
const GAZE_DIVERGE: float = 0.012      # rotate each eye slightly OUTWARD (un-cross)
var _face_mode: String = "auto"                # auto | neutral | smile | surprise | frown | blink
var _expr_buttons: Dictionary = {}

var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var hair_light: DirectionalLight3D
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
var hair_light_yaw: float = -12.0
var hair_light_pitch: float = -80.0

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
	FaceExtras.make_floor(self)        # soft pool-of-light ground (no grey void / horizon)
	FaceExtras.make_vignette(self)
	_setup_lights()
	_setup_camera()
	_character = Node3D.new()
	_character.name = "Character"
	add_child(_character)
	if not _load_and_wire():
		push_error("[vit] failed to load/wire head")
		return
	# Drive the face with NATIVE blend shapes (set_blend_shape_value) — it deforms ALL
	# surfaces (skin + the VitMouth teeth/tongue interior). The old CPU-rebuild path
	# (_setup_face_morph/_apply_morph) only rebuilt surface 0, so it could not move the
	# mouth interior; left in the file as dead code for reference.
	_build_ui()
	_update_orbit_camera()
	if OS.has_environment("EYESHADOW_TEST"):   # force eyeshadow on for a capture
		_eyeshadow_set_a().call(float(OS.get_environment("EYESHADOW_TEST")))
	if OS.has_environment("NECK_SHOT"):        # hide hair + frame the neck/collar
		if _ui_layer: _ui_layer.visible = false
		if head_rig:
			var hn: Node = head_rig.get_node_or_null("Hair")
			if hn: (hn as Node3D).visible = false
		var nyaw: float = float(OS.get_environment("NECK_SHOT")) if OS.get_environment("NECK_SHOT").is_valid_float() else 0.0
		orbit_target = Vector3(0.0, 1.40, 0.0); orbit_dist = 0.46; orbit_yaw = nyaw; orbit_pitch = 6.0
		_update_orbit_camera()
	if OS.has_environment("FACE_FORCE"):
		# inspection hook: hold an expression, hide hair/UI, frame the face
		_set_face_mode(OS.get_environment("FACE_FORCE"))
		if OS.has_environment("HIDE_FACE") and face_mi:
			face_mi.visible = false
			print("[face] HID face_mi=", face_mi.get_path())
		if _ui_layer: _ui_layer.visible = false
		if head_rig:
			var h: Node = head_rig.get_node_or_null("Hair")
			if h: (h as Node3D).visible = false
		orbit_target = Vector3(0.0, 1.60, 0.0); orbit_dist = 0.95; orbit_yaw = -10.0; orbit_pitch = 2.0
		_update_orbit_camera()
	if OS.has_environment("HIDE_LIDS"):
		for l in upper_lids: (l["node"] as Node3D).visible = false
		if head_rig:
			for c in head_rig.find_children("Lid*", "MeshInstance3D", true, false):
				(c as Node3D).visible = false
	if OS.has_environment("CLIP") and anim and anim.has_animation(OS.get_environment("CLIP")):
		anim.play(OS.get_environment("CLIP"))
		_cur_clip = OS.get_environment("CLIP")
	if OS.has_environment("EYE_SHOT"):
		if _ui_layer: _ui_layer.visible = false
		if head_rig:
			var hh: Node = head_rig.get_node_or_null("Hair")
			if hh: (hh as Node3D).visible = false
		orbit_target = Vector3(0.0, 1.626, -0.05); orbit_dist = 0.34; orbit_yaw = -8.0; orbit_pitch = -2.0
		_update_orbit_camera()
	if OS.has_environment("HAIR_SHOT"):
		if _ui_layer: _ui_layer.visible = false
		var yaw: float = float(OS.get_environment("HAIR_SHOT")) if OS.get_environment("HAIR_SHOT").is_valid_float() else -18.0
		orbit_target = Vector3(0.0, 1.50, 0.0); orbit_dist = 1.05; orbit_yaw = yaw; orbit_pitch = 4.0
		_update_orbit_camera()
	if OS.has_environment("FRAME_BODY"):
		_frame_view("full")
	if not OS.has_environment("NO_LOAD_SETTINGS"):
		_load_settings()
	if OS.has_environment("LOOKDEV_CAPTURE"):
		_cap_prefix = OS.get_environment("LOOKDEV_CAPTURE")
		if _ui_layer:
			_ui_layer.visible = false   # clean frames for inspection (no panel overlay)
		print("[vit] CAPTURE MODE → ", _cap_prefix)


func _process(delta: float) -> void:
	_time += delta
	var _shot_at: float = float(OS.get_environment("SHOT_AT")) if OS.get_environment("SHOT_AT").is_valid_float() else (3.0 if OS.has_environment("HAIR_SHOT") else 1.0)
	if (OS.has_environment("UI_SHOT") or OS.has_environment("HAIR_SHOT")) and _time > _shot_at and _cap_prefix == "":
		_cap_prefix = "_uishot_done"   # guard so we only grab once
		_grab(ProjectSettings.globalize_path("res://").path_join("..").path_join("out").path_join("ui_shot.png"))
		get_tree().quit()
		return
	if hair_spring:
		hair_spring.step(delta)
	_drive_face(delta)
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
		if OS.has_environment("FRAME_BODY"):
			orbit_yaw = 22.0; _update_orbit_camera(); return
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
	sky_mat.sun_angle_max = 0.0   # NO sun discs: 4 directional lights were
	sky_mat.sun_curve = 0.02      # painting a giant white halo band on the horizon
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
	env.ssao_radius = 0.6          # larger radius = smoother, less blocky contact AO
	env.ssao_intensity = 1.0       # gentler so the chin→neck AO isn't a hard dark band
	env.ssao_detail = 0.2
	env.ssao_power = 1.5
	# HIGH-quality SSAO + soft shadows so the neck shadow reads smooth, not stair-stepped
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
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
	# offsets/colors assigned wholesale — Gradient.new() ships a WHITE point at 1.0
	# and set_color(1) after add_point() recolors the wrong point (white far field).
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0.20, 0.19, 0.17), Color(0.10, 0.10, 0.10), Color(0.035, 0.037, 0.043)])
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
	key_light.shadow_bias = 0.03
	key_light.shadow_normal_bias = 1.2
	key_light.shadow_blur = 3.5
	key_light.light_angular_distance = 4.5
	# concentrate the 4096 shadow map on the CHARACTER (not the whole scene) so the
	# chin→neck contact shadow is high-res + soft, not the blocky stair-stepped band.
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key_light.directional_shadow_max_distance = 4.5
	key_light.directional_shadow_blend_splits = true
	_apply_light_rot(key_light, key_pitch, key_yaw)
	add_child(key_light)

	rim_light = DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.light_energy = 1.9
	rim_light.light_specular = 0.25   # lower spec: the blue rim was sparkling the dark hair
	rim_light.light_color = Color(0.40, 0.62, 1.0)
	_apply_light_rot(rim_light, rim_pitch, rim_yaw)
	add_child(rim_light)

	# Hair/kicker light from above-behind: rakes the crown so the (otherwise
	# unlit, side-keyed) top hair catches a sheen and the combed strand flow reads.
	# Energy CUT 3.2 → 1.5: at 3.2 it hue-shifted the whole side mass golden in profile.
	hair_light = DirectionalLight3D.new()
	hair_light.name = "HairLight"
	hair_light.light_energy = 1.5
	hair_light.light_specular = 0.1
	hair_light.light_color = Color(1.0, 0.94, 0.82)
	_apply_light_rot(hair_light, hair_light_pitch, hair_light_yaw)
	add_child(hair_light)

	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.9
	fill_light.light_color = Color(0.85, 0.84, 0.82)
	_apply_light_rot(fill_light, fill_pitch, fill_yaw)
	add_child(fill_light)

	catch_light = OmniLight3D.new()
	catch_light.name = "CatchLight"
	catch_light.light_energy = 0.35 # eye-spark only: cull-masked to the EYE layer (2), so
	catch_light.light_specular = 1.0 # it can be bright without flooding the neck/chin salmon
	catch_light.light_color = Color(1.0, 0.98, 0.95)
	catch_light.omni_range = 0.9
	catch_light.omni_attenuation = 2.6
	catch_light.light_cull_mask = 1 << 1        # ONLY layer 2 — the eyeball/cornea meshes
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
	# ── BODY first: provides the Skeleton3D + AnimationPlayer the head/hair ride ──
	if ResourceLoader.exists(BODY_GLB):
		var bscene: PackedScene = load(BODY_GLB)
		if bscene:
			var body: Node = bscene.instantiate()
			body.name = "Body"
			_character.add_child(body)
			_body_root = body as Node3D
			skel = _find_class(body, "Skeleton3D") as Skeleton3D
			anim = _find_class(body, "AnimationPlayer") as AnimationPlayer
			var bmeshes: Array[MeshInstance3D] = []
			_collect_meshes(body, bmeshes)
			for bmi in bmeshes:
				_body_meshes.append(bmi)
				for s in range(bmi.mesh.get_surface_count()):
					var bm2: Material = bmi.mesh.surface_get_material(s)
					var bnm: String = (bm2.resource_name if bm2 else "").split(".")[0]
					match bnm:
						"VitShirt": bmi.set_surface_override_material(s, _make_shirt())
						"VitPants": bmi.set_surface_override_material(s, _make_pants())
						_:          bmi.set_surface_override_material(s, _make_body_skin())
			if anim:
				for a in anim.get_animation_list():
					anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				_anim_names = anim.get_animation_list()

	# ── HEAD + HAIR ride the Head bone (so the body can animate) ──
	var head_parent: Node = _character
	if skel:
		var hbi: int = skel.find_bone(HEAD_BONE)
		if hbi >= 0:
			var att: BoneAttachment3D = BoneAttachment3D.new()
			att.name = "HeadAttach"
			skel.add_child(att)
			att.bone_idx = hbi
			head_rig = Node3D.new()
			head_rig.name = "HeadRig"
			att.add_child(head_rig)
			head_rig.global_transform = Transform3D.IDENTITY   # world-aligned at rest
			head_parent = head_rig

	var hscene: PackedScene = load(HEAD_GLB)
	if hscene == null:
		return skel != null
	var head: Node = hscene.instantiate()
	head.name = "Head"
	head_parent.add_child(head)
	if OS.has_environment("HIDE_HEAD"):
		(head as Node3D).visible = false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(head, meshes)
	for mi in meshes:
		for s in range(mi.mesh.get_surface_count()):
			var m: Material = mi.mesh.surface_get_material(s)
			var nm: String = (m.resource_name if m else "").split(".")[0]
			match nm:
				"VitSkin":    mi.set_surface_override_material(s, _make_skin())
				"VitEyeball": mi.set_surface_override_material(s, _make_eyeball())
				"VitCornea":  mi.set_surface_override_material(s, _make_cornea())
				"VitMouth":   mi.set_surface_override_material(s, _make_mouth())
				"VitScalp":   mi.set_surface_override_material(s, _make_scalp())
				"VitEyeshadow": mi.set_surface_override_material(s, _make_eyeshadow())
				"VitTearline": mi.set_surface_override_material(s, _make_tearline())
				"VitCaruncle": mi.set_surface_override_material(s, _make_caruncle())
				_:            pass
		# capture the face mesh (ARKit blend shapes) + eyeball spheres for the face driver
		if mi.mesh.get_blend_shape_count() > 0 and face_mi == null:
			face_mi = mi
			for bi in range(mi.mesh.get_blend_shape_count()):
				bshapes[String(mi.mesh.get_blend_shape_name(bi))] = bi
		if mi.name.begins_with("Eye_"):
			eye_nodes.append({"node": mi, "rest_basis": mi.transform.basis, "rest_pos": mi.position})
			mi.layers = 1 | (1 << 1)   # also on the EYE layer → catch-light spark hits eyes only
			if mi.name.ends_with("_eyeball"):
				FaceExtras.add_lid_ao(mi)   # lid-contact AO band (grounds the eyeball)
		if mi.name.begins_with("LidUp"):
			upper_lids.append({"node": mi, "rest_basis": mi.transform.basis})
		if mi.name.begins_with("Tearline"):
			mi.layers = 1 | (1 << 1)   # wet line catches the eye-spark light

	if OS.has_environment("DUMP_HEAD"):
		for mi in meshes:
			var mats: Array = []
			for s in range(mi.mesh.get_surface_count()):
				var mm: Material = mi.mesh.surface_get_material(s)
				mats.append(mm.resource_name if mm else "?")
			var am2: ArrayMesh = mi.mesh as ArrayMesh
			var vc: int = -1
			if am2: vc = (am2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("[DUMP] mi=", mi.name, " path=", mi.get_path(),
				" surf=", mi.mesh.get_surface_count(), " mats=", mats,
				" bs=", mi.mesh.get_blend_shape_count(), " verts=", vc,
				" visible=", mi.visible, " skin=", mi.skin != null,
				" skel=", mi.skeleton)

	# ── HAIR — rigged spring-bone chain (physics), rides the head, collides with body ──
	var hair_src: String = HAIR_RIGGED if ResourceLoader.exists(HAIR_RIGGED) else HAIR_GLB
	if OS.has_environment("HAIR_RIGGED_OVERRIDE"):
		hair_src = OS.get_environment("HAIR_RIGGED_OVERRIDE")
	if ResourceLoader.exists(hair_src):
		var hairscene: PackedScene = load(hair_src)
		if hairscene:
			var hair: Node = hairscene.instantiate()
			hair.name = "Hair"
			head_parent.add_child(hair)
			var hmeshes: Array[MeshInstance3D] = []
			_collect_meshes(hair, hmeshes)
			for hm in hmeshes:
				if hm.name.begins_with("VitBrow"):
					continue
				var hmat: ShaderMaterial = _make_hair()
				for s in range(hm.mesh.get_surface_count()):
					hm.set_surface_override_material(s, hmat)
			var hsk: Skeleton3D = _find_class(hair, "Skeleton3D") as Skeleton3D
			if hsk and skel:
				hair_spring = HairSpring.new()
				hair.add_child(hair_spring)
				hair_spring.setup(hsk)
				hair_spring.set_body_colliders(skel)

	# ── Eyebrows from the legacy hair GLB (brow meshes only), on the head ──
	if ResourceLoader.exists(HAIR_GLB_LEGACY):
		var legacy: PackedScene = load(HAIR_GLB_LEGACY)
		if legacy:
			var lhair: Node = legacy.instantiate()
			lhair.name = "HairLegacyBrows"
			head_parent.add_child(lhair)
			var lmeshes: Array[MeshInstance3D] = []
			_collect_meshes(lhair, lmeshes)
			for lm in lmeshes:
				if lm.name.begins_with("VitBrow"):
					var bmat: ShaderMaterial = _make_browcards()
					for s in range(lm.mesh.get_surface_count()):
						lm.set_surface_override_material(s, bmat)
				else:
					lm.visible = false

	for bmi2 in _body_meshes:
		bmi2.visible = show_body
	if anim and anim.has_animation("Idle"):
		anim.play("Idle")
		_cur_clip = "Idle"
	print("[vit] rig: skel=", skel != null, " anim=", anim != null, " clips=", _anim_names,
		" face_shapes=", bshapes.size(), " eyes=", eye_nodes.size())
	return true


func _setup_face_morph() -> void:
	# Grab the base surface + per-shape deltas, then swap in a unique ArrayMesh we rebuild.
	if face_mi == null:
		return
	var am: ArrayMesh = face_mi.mesh as ArrayMesh
	if am == null or am.get_blend_shape_count() == 0:
		return
	# keep only standard channels (imported meshes carry CUSTOM/byte channels that
	# add_surface_from_arrays rejects)
	var src: Array = am.surface_get_arrays(0)
	_morph_arrays = []; _morph_arrays.resize(Mesh.ARRAY_MAX)
	for idx in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		if idx < src.size() and src[idx] != null:
			_morph_arrays[idx] = src[idx]
	_morph_base = _morph_arrays[Mesh.ARRAY_VERTEX]
	var bsa: Array = am.surface_get_blend_shape_arrays(0)
	for bi in range(am.get_blend_shape_count()):
		var sv: PackedVector3Array = bsa[bi][Mesh.ARRAY_VERTEX]
		var dl: PackedVector3Array = PackedVector3Array(); dl.resize(sv.size())
		for i in range(sv.size()):
			dl[i] = sv[i] - _morph_base[i]
		_morph_deltas[String(am.get_blend_shape_name(bi))] = dl
	_morph_mat = face_mi.get_surface_override_material(0)
	# unique mesh without blend shapes (their renderer is broken in 4.6.3)
	var test_arrays: Array = _morph_arrays.duplicate()
	if OS.has_environment("SHRINK_TEST"):
		var jd2: PackedVector3Array = _morph_deltas.get("jawOpen", PackedVector3Array())
		var sv2: PackedVector3Array = PackedVector3Array(); sv2.resize(_morph_base.size())
		for i in range(_morph_base.size()): sv2[i] = _morph_base[i] + (jd2[i] if i < jd2.size() else Vector3.ZERO) * 4.0
		test_arrays[Mesh.ARRAY_VERTEX] = sv2
		_face_mode = "__raw__"   # stop _drive_face from overwriting this baked test mesh
		print("[face] SHRINK_TEST: baked jawOpen*4 into the setup mesh")
	var fresh: ArrayMesh = ArrayMesh.new()
	fresh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, test_arrays)
	face_mi.mesh = fresh
	if _morph_mat: face_mi.set_surface_override_material(0, _morph_mat)
	var jd: float = 0.0
	if _morph_deltas.has("jawOpen"):
		for v in (_morph_deltas["jawOpen"] as PackedVector3Array): jd = maxf(jd, v.length())
	print("[vit] face morph: base verts=", _morph_base.size(), " shapes=", _morph_deltas.size(),
		" jawOpen_maxdelta=", jd)


func _apply_morph(weights: Dictionary) -> void:
	# rebuild the face surface = base + Σ weight*delta (only when the weights change)
	if _morph_base.is_empty():
		return
	var key: String = ""
	for n in weights:
		if absf(weights[n]) > 0.004:
			key += "%s%.2f," % [n, weights[n]]
	if key == _morph_key:
		return
	_morph_key = key
	var verts: PackedVector3Array = _morph_base.duplicate()
	for n in weights:
		var w: float = weights[n]
		if absf(w) < 0.004 or not _morph_deltas.has(n):
			continue
		var dl: PackedVector3Array = _morph_deltas[n]
		for i in range(verts.size()):
			verts[i] += dl[i] * w
	var maxd: float = 0.0
	for i in range(verts.size()): maxd = maxf(maxd, verts[i].distance_to(_morph_base[i]))
	var arrays: Array = _morph_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	face_mi.mesh = m                                  # reassign forces a GPU refresh
	if _morph_mat: face_mi.set_surface_override_material(0, _morph_mat)
	if OS.has_environment("FACE_FORCE"):
		print("[morph] key=", key, " maxdisp=", maxd, " surfs=", m.get_surface_count())


func _find_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var r: Node = _find_class(c, cls)
		if r:
			return r
	return null


# ── animation + facial control ───────────────────────────────────────────────
# real Vitruvian FACS morphs (morphs/L3) — Mouth_Large_Opened moves the jaw + the
# lower teeth/tongue (surface 1) for a true open mouth; Happy/Sad/Angry are FACS emotions.
const FACE_POSES: Dictionary = {
	"neutral": {},
	"smile": {"Happy": 0.85},
	# surprise: mouth drop 0.5 → 0.3 — at 0.5 the full teeth ring bared and it read
	# GRIMACE; a softer "oh" + raised brows + wide eyes reads startled, not pained
	"surprise": {"Mouth_Large_Opened": 0.3, "Eyebrows_Raised_Left": 1.0, "Eyebrows_Raised_Right": 1.0, "Eyes_Opened_Max_Left": 0.9, "Eyes_Opened_Max_Right": 0.9},
	"jawopen": {"Mouth_Large_Opened": 1.0},
	"talk": {"Mouth_Large_Opened": 0.4, "Lips_Up_Funnel": 0.3},
	# sad: amplitude up + heavy lids — Sad 0.9 alone was indistinguishable from neutral
	"frown": {"Sad": 1.0, "Eyes_Closed_Max": 0.22},
	"angry": {"Angry": 1.0},
	"blink": {"Eyes_Closed_Max": 1.0},
}


func _sshape(n: String, v: float) -> void:
	if face_mi and bshapes.has(n):
		face_mi.set_blend_shape_value(bshapes[n], v)


func _play_clip(clip: String) -> void:
	if anim and anim.has_animation(clip):
		anim.play(clip, 0.3)
		_cur_clip = clip
		_refresh_btn_tint(_anim_buttons, clip)


func _set_face_mode(mode: String) -> void:
	_face_mode = mode
	_refresh_btn_tint(_expr_buttons, mode)


func _refresh_btn_tint(dict: Dictionary, active: String) -> void:
	for key in dict:
		var b: Button = dict[key]
		b.modulate = Color(0.6, 0.85, 1.0) if key == active else Color(1, 1, 1)


func _drive_face(delta: float) -> void:
	if face_mi == null or _face_mode == "__raw__":
		return
	# NATIVE blend shapes (set_blend_shape_value) — deforms BOTH surfaces (skin + the
	# VitMouth interior), so the FACS jaw morphs move the lower teeth/tongue too.
	for n in bshapes:
		face_mi.set_blend_shape_value(bshapes[n], 0.0)   # clear, then set this frame's pose
	var saccade: bool = true
	var blink_amt: float = 0.0
	if _face_mode == "auto":
		var bt: float = fmod(_time + 0.6, 3.2)
		blink_amt = sin(bt / 0.16 * PI) if bt < 0.16 else 0.0   # a blink every ~3s (Eyes_Closed_Max)
		_sshape("Smile_Lips_Closed", 0.45)                      # gentle resting smile (no teeth)
		_sshape("Happy", 0.10)
		# LIVENESS: asymmetric resting face (perfect symmetry reads mannequin) +
		# occasional micro-expressions — a brief "thinking" flicker and an eye squint.
		_sshape("Lips_Up_Corner_Wide_Left", 0.07)
		_sshape("Eyebrows_Raised_Left", 0.05)
		var ft: float = fmod(_time, 11.0)
		if ft > 8.0 and ft < 9.4:
			_sshape("Thinking", 0.22 * sin((ft - 8.0) / 1.4 * PI))
		var f2: float = fmod(_time + 5.0, 17.0)
		if f2 < 1.1:
			_sshape("Eyes_Squint", 0.18 * sin(f2 / 1.1 * PI))
		_sshape("Eyes_Closed_Max", clampf(blink_amt, 0.0, 1.0))
		if blink_amt > 0.4: saccade = false
	else:
		var pose: Dictionary = FACE_POSES.get(_face_mode, {})
		for k in pose:
			_sshape(k, pose[k])
		if _face_mode == "blink":
			blink_amt = 1.0
			saccade = false
	# eye saccades (procedural eyeballs; don't dart while the eye is shut)
	if saccade and blink_amt < 0.4 and eye_nodes.size() > 0:
		var k: int = int(_time / 2.0)
		var target: Vector2 = Vector2(sin(float(k) * 12.9898) * 0.22, sin(float(k) * 4.1413) * 0.13)
		_gaze = _gaze.lerp(target, clampf(delta * 16.0, 0.0, 1.0))
	# resting-gaze bias (lift to camera height; the tuned look stared down/inward) +
	# per-eye DIVERGENCE (un-cross). Applied even when saccades are frozen so
	# NO_SACCADE / FACE_FORCE captures show the corrected rest gaze.
	if eye_nodes.size() > 0:
		var pitch_bias: float = GAZE_PITCH_BIAS
		var diverge: float = GAZE_DIVERGE
		if OS.has_environment("GAZE_TUNE"):   # calibration hook: GAZE_TUNE="<pitch>,<diverge>"
			var parts: PackedStringArray = OS.get_environment("GAZE_TUNE").split(",")
			if parts.size() >= 1: pitch_bias = float(parts[0])
			if parts.size() >= 2: diverge = float(parts[1])
		var g: Vector2 = Vector2.ZERO if OS.has_environment("NO_SACCADE") else _gaze
		for e in eye_nodes:
			var side: float = 1.0 if (e["rest_pos"] as Vector3).x > 0.0 else -1.0
			var gr: Basis = Basis.from_euler(Vector3(g.y + pitch_bias, 0.0, -g.x + diverge * side))
			(e["node"] as MeshInstance3D).transform.basis = gr * (e["rest_basis"] as Basis)
	# LIVENESS: head micro-sway (multi-frequency, ~1°) — stillness between anims is the
	# deepest mannequin trigger. Skipped under NO_SACCADE so captures stay deterministic.
	if head_rig and not OS.has_environment("NO_SACCADE"):
		head_rig.rotation = Vector3(
			sin(_time * 0.31) * 0.012 + sin(_time * 0.83) * 0.005,
			sin(_time * 0.23 + 1.7) * 0.018 + sin(_time * 0.61) * 0.006,
			sin(_time * 0.40 + 0.6) * 0.008)


# ── one-click lighting presets ───────────────────────────────────────────────
func _apply_light_preset(name: String) -> void:
	match name:
		"Hero":
			# authored hero look: soft motivated warm key with wrap, cool rim from
			# behind-left, NEGATIVE fill (near-black shadow side), restrained kicker.
			key_light.light_energy = 2.7; key_light.light_color = Color(1.0, 0.93, 0.84)
			key_yaw = -58.0; key_pitch = -26.0
			fill_light.light_energy = 0.22; fill_light.light_color = Color(0.62, 0.70, 0.86)
			fill_yaw = 38.0; fill_pitch = 8.0
			rim_light.light_energy = 2.3; rim_light.light_color = Color(0.55, 0.70, 1.0)
			rim_yaw = 138.0; rim_pitch = -32.0
			hair_light.light_energy = 1.5
			env.ambient_light_energy = 0.14; env.tonemap_exposure = 1.0
		"Portrait":
			key_light.light_energy = 3.2; key_light.light_color = Color(1.0, 0.90, 0.76)
			key_yaw = -81.0; key_pitch = -30.0
			fill_light.light_energy = 0.9; fill_light.light_color = Color(0.85, 0.84, 0.82)
			fill_yaw = 21.0; fill_pitch = 13.0
			rim_light.light_energy = 1.9; rim_light.light_color = Color(0.40, 0.62, 1.0)
			rim_yaw = 51.0; rim_pitch = -45.0
			hair_light.light_energy = 1.5
			env.ambient_light_energy = 0.10; env.tonemap_exposure = 1.0
		"Studio":
			key_light.light_energy = 2.4; key_light.light_color = Color(1.0, 0.98, 0.95)
			key_yaw = -55.0; key_pitch = -28.0
			fill_light.light_energy = 1.7; fill_light.light_color = Color(0.92, 0.94, 1.0)
			fill_yaw = 46.0; fill_pitch = 10.0
			rim_light.light_energy = 1.2; rim_light.light_color = Color(0.9, 0.93, 1.0)
			rim_yaw = 150.0; rim_pitch = -40.0
			hair_light.light_energy = 1.8
			env.ambient_light_energy = 0.55; env.tonemap_exposure = 1.0
		"Dramatic":
			key_light.light_energy = 1.7; key_light.light_color = Color(1.0, 0.95, 0.87)
			key_yaw = -62.0; key_pitch = -22.0
			fill_light.light_energy = 0.07; fill_light.light_color = Color(0.45, 0.60, 1.0)
			fill_yaw = 46.0; fill_pitch = 10.0
			rim_light.light_energy = 2.6; rim_light.light_color = Color(0.5, 0.7, 1.0)
			rim_yaw = 145.0; rim_pitch = -38.0
			hair_light.light_energy = 2.6
			env.ambient_light_energy = 0.05; env.tonemap_exposure = 0.82
		"Backlit":
			key_light.light_energy = 1.0; key_light.light_color = Color(1.0, 0.92, 0.82)
			key_yaw = -70.0; key_pitch = -24.0
			fill_light.light_energy = 0.4; fill_light.light_color = Color(0.7, 0.8, 1.0)
			rim_light.light_energy = 4.2; rim_light.light_color = Color(0.7, 0.82, 1.0)
			rim_yaw = 165.0; rim_pitch = -30.0
			hair_light.light_energy = 3.4
			env.ambient_light_energy = 0.12; env.tonemap_exposure = 0.95
	_apply_light_rot(key_light, key_pitch, key_yaw)
	_apply_light_rot(fill_light, fill_pitch, fill_yaw)
	_apply_light_rot(rim_light, rim_pitch, rim_yaw)
	_toast("Lighting: " + name)


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
	mat.set_shader_parameter("sss_depth_scale", 1.1)
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
	# Shared across both eyes; the 3 stops are live-editable via the Eyes sliders.
	if iris_ramp_tex == null:
		iris_grad = Gradient.new()
		iris_grad.set_color(0, iris_col_dark)
		iris_grad.add_point(0.5, iris_col_mid)
		iris_grad.set_color(1, iris_col_bright)
		iris_ramp_tex = GradientTexture1D.new()
		iris_ramp_tex.gradient = iris_grad
		iris_ramp_tex.width = 256
	return iris_ramp_tex


func _rebuild_iris_ramp() -> void:
	if iris_grad == null:
		return
	iris_grad.set_color(0, iris_col_dark)
	# middle stop is index 1 (we added a point at 0.5)
	if iris_grad.get_point_count() >= 3:
		iris_grad.set_color(1, iris_col_mid)
		iris_grad.set_color(2, iris_col_bright)
	else:
		iris_grad.set_color(1, iris_col_bright)
	iris_ramp_tex.gradient = iris_grad   # nudge the texture to regenerate


func _make_eyeball() -> ShaderMaterial:
	# Procedural iris/pupil/sclera (blackears eyeball_shader, MIT) — radial UV.
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://addons/eyeball_shader/shaders/eyeball_shader.gdshader") as Shader
	mat.set_shader_parameter("iris_radius", 0.32)
	mat.set_shader_parameter("iris_margin", 0.018)
	mat.set_shader_parameter("pupil_radius", 0.10)
	mat.set_shader_parameter("eye_white", Color(0.86, 0.83, 0.80))   # warm off-white sclera (not pure white)
	mat.set_shader_parameter("pupil_color", Color(0.012, 0.010, 0.014))
	mat.set_shader_parameter("texture_iris_color", _iris_ramp())
	mat.set_shader_parameter("eye_cell_scale", 19.0)
	mat.set_shader_parameter("eye_cell_jitter", 0.7)
	mat.set_shader_parameter("iris_pinch", 0.72)
	mat.set_shader_parameter("eyeball_roughness", 0.07)
	mat.set_shader_parameter("eyeball_specular", 0.06)
	mat.set_shader_parameter("sclera_shade", 0.5)
	mat.set_shader_parameter("sclera_edge_tint", Color(0.80, 0.66, 0.60))
	mat.set_shader_parameter("rand_seed", 12345)
	mat.set_shader_parameter("uv1_scale", Vector3(1, 1, 1))
	mat.set_shader_parameter("uv1_offset", Vector3(0, 0, 0))
	eyeball_mats.append(mat)
	return mat


func _make_cornea() -> ShaderMaterial:
	# Glassy additive specular shell over the eyeball (blackears cornea, MIT).
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://addons/eyeball_shader/shaders/cornea.gdshader") as Shader
	mat.set_shader_parameter("shininess", 480.0)
	mat.set_shader_parameter("spec_intensity", 0.5)
	mat.set_shader_parameter("alpha_max", 0.7)
	cornea_mats.append(mat)
	return mat


func _make_mouth() -> ShaderMaterial:
	# Depth-darkened mouth bag (cavity falls to black behind the lip line) — the old
	# evenly-lit StandardMaterial read "muppet": bright cavity, slab tongue, denture ring.
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://scenes/mouth_interior.gdshader") as Shader
	m.set_shader_parameter("tex_albedo", _tex("res://vit_mouth.png"))
	return m


func _make_body_skin() -> ShaderMaterial:
	# SAME skin shader as the face (flat tone, no textures) so the neck/hands shade
	# identically to the face — fixes the 'blocky tan line' where head meets body.
	if body_skin_mat == null:
		body_skin_mat = ShaderMaterial.new()
		body_skin_mat.shader = load("res://scenes/skin_shader_local.gdshader") as Shader
		# REAL skin textures: tiles 1001-1004 atlas-baked (bake_skin_textures.py); the
		# body UVs are remapped to the atlas in _mixamo_retarget.py. The neck shares
		# tile 1001 with the face, so the tone finally matches across the jaw seam.
		body_skin_mat.set_shader_parameter("texture_albedo", _tex("res://vit_body_bc.png"))
		body_skin_mat.set_shader_parameter("albedo", Color(1, 1, 1))
		body_skin_mat.set_shader_parameter("texture_normal", _tex("res://vit_body_n.png"))
		body_skin_mat.set_shader_parameter("texture_roughness", _tex("res://vit_body_rough.png"))
		body_skin_mat.set_shader_parameter("normal_strength", 1.0)
		body_skin_mat.set_shader_parameter("roughness", 0.9)
		body_skin_mat.set_shader_parameter("specular", 0.30)
		body_skin_mat.set_shader_parameter("double_specularity", false)
		body_skin_mat.set_shader_parameter("metallic", 0.0)
		body_skin_mat.set_shader_parameter("metallic_texture_channel", Plane(1, 0, 0, 0))
		body_skin_mat.set_shader_parameter("use_subsurface_scattering", true)
		body_skin_mat.set_shader_parameter("use_noise", false)
		body_skin_mat.set_shader_parameter("subsurface_scattering_strength", 0.55)
		body_skin_mat.set_shader_parameter("skin_smoothness", 1.8)
		body_skin_mat.set_shader_parameter("skin_fallof_smoothness", 1.05)
		body_skin_mat.set_shader_parameter("sss_depth_scale", 1.1)
		body_skin_mat.set_shader_parameter("old_lightwarp_fallof", false)
		body_skin_mat.set_shader_parameter("tinted_shadow_penumbra", true)
		body_skin_mat.set_shader_parameter("use_micro_detail", false)
		body_skin_mat.set_shader_parameter("micro_normal_strength", 0.0)
		body_skin_mat.set_shader_parameter("use_ambient_occlusion", false)
		body_skin_mat.set_shader_parameter("translucency", false)
		body_skin_mat.set_shader_parameter("use_scatter_map", false)
		body_skin_mat.set_shader_parameter("uv1_scale", Vector3(1, 1, 1))
		body_skin_mat.set_shader_parameter("uv1_offset", Vector3(0, 0, 0))
		body_skin_mat.set_shader_parameter("uv2_scale", Vector3(1, 1, 1))
		body_skin_mat.set_shader_parameter("uv2_offset", Vector3(0, 0, 0))
	return body_skin_mat


func _make_shirt() -> StandardMaterial3D:
	if shirt_mat == null:
		shirt_mat = StandardMaterial3D.new()
		shirt_mat.albedo_color = Color(0.18, 0.22, 0.30)   # muted blue tee
		shirt_mat.roughness = 0.88
		shirt_mat.metallic = 0.0
		# knit weave (triplanar so the CharMorph cloth needs no UV work)
		shirt_mat.normal_enabled = true
		shirt_mat.normal_texture = _tex("res://vit_fabric_n.png")
		shirt_mat.normal_scale = 0.55
		shirt_mat.uv1_triplanar = true
		shirt_mat.uv1_scale = Vector3(26, 26, 26)
		shirt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # collar notch = seeing through the culled inner side
	return shirt_mat


func _make_pants() -> StandardMaterial3D:
	if pants_mat == null:
		pants_mat = StandardMaterial3D.new()
		pants_mat.albedo_color = Color(0.12, 0.12, 0.14)   # dark slacks
		pants_mat.roughness = 0.82
		pants_mat.metallic = 0.0
		pants_mat.normal_enabled = true
		pants_mat.normal_texture = _tex("res://vit_fabric_n.png")
		pants_mat.normal_scale = 0.4
		pants_mat.uv1_triplanar = true
		pants_mat.uv1_scale = Vector3(40, 40, 40)   # finer twill read than the tee
		pants_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return pants_mat


func _make_scalp() -> ShaderMaterial:
	# HELMET REMOVED: the baked VitScalp "dome" (a duplicated, pushed-out crown skin
	# cap from the head export) is what read as a helmet whenever the hair cards were
	# scissored away. We discard it entirely — the Hair Tool cards are the only crown
	# hair now. (Toggle `show_scalp_base` if you ever want a dark backing again.)
	vit_scalp_mat = ShaderMaterial.new()
	vit_scalp_mat.shader = load("res://scenes/hidden_discard.gdshader") as Shader
	return vit_scalp_mat


func _make_hair_card(color: Color, threshold: float, root_dark: float, rough: float,
		atlas: String = "res://vit_hair_atlas.png", spec: float = 0.14) -> ShaderMaterial:
	# Alpha-clipped hair-card shader reading the procedural strand atlas (R channel).
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://scenes/hair_card.gdshader") as Shader
	mat.set_shader_parameter("hair_color", color)
	mat.set_shader_parameter("coverage_atlas", _tex(atlas))
	mat.set_shader_parameter("use_red_mask", true)
	mat.set_shader_parameter("invert_mask", false)
	mat.set_shader_parameter("alpha_threshold", threshold)
	mat.set_shader_parameter("root_darkening", root_dark)
	mat.set_shader_parameter("roughness_val", rough)
	mat.set_shader_parameter("specular_val", spec)
	return mat


func _make_hair() -> ShaderMaterial:
	# HAIR TOOL CARDS: real authored cards carrying a baked strand atlas. The NORMAL
	# map fans across each card so the crown catches the side key light (fixes the
	# flat-dark dome), and ALPHA-SCISSOR cutout carves the dense card shell into
	# wispy strands with gaps (fixes the solid-helmet read). Opaque cutout (not
	# alpha-blend) → no glassy translucency across the 100k+ overlapping cards.
	if vit_hair_mat == null:
		vit_hair_mat = ShaderMaterial.new()
		vit_hair_mat.shader = load("res://scenes/hairtool_card.gdshader") as Shader
		vit_hair_mat.set_shader_parameter("tex_diffuse", _tex("res://vit_hair_diffuse.png"))
		vit_hair_mat.set_shader_parameter("tex_normal", _tex("res://vit_hair_normal.png"))
		vit_hair_mat.set_shader_parameter("tex_ao", _tex("res://vit_hair_ao.png"))
		vit_hair_mat.set_shader_parameter("tex_opacity", _tex("res://vit_hair_opacity.png"))
		vit_hair_mat.set_shader_parameter("root_color", Color(0.34, 0.24, 0.15, 1.0))
		vit_hair_mat.set_shader_parameter("tip_color", Color(0.66, 0.52, 0.36, 1.0))   # lighter tips = depth
		vit_hair_mat.set_shader_parameter("brightness", 3.4)
		vit_hair_mat.set_shader_parameter("diffuse_mix", 1.0)
		vit_hair_mat.set_shader_parameter("normal_strength", 0.8)   # strand relief (AtC edges now soft, so safe)
		vit_hair_mat.set_shader_parameter("flip_green", false)
		vit_hair_mat.set_shader_parameter("ao_strength", 0.7)
		vit_hair_mat.set_shader_parameter("roughness_val", 0.84)
		vit_hair_mat.set_shader_parameter("specular_val", 0.12)
		vit_hair_mat.set_shader_parameter("anisotropy_val", 0.30)   # strand-flow highlight band = the key 'hair' cue
		vit_hair_mat.set_shader_parameter("tonal_variation", 0.45)
		vit_hair_mat.set_shader_parameter("clump_count", 55.0)
		vit_hair_mat.set_shader_parameter("tip_lighten", 0.18)
		vit_hair_mat.set_shader_parameter("emit", 0.13)             # lift the shadow side off black
		vit_hair_mat.set_shader_parameter("backlight_color", Color(0.30, 0.17, 0.08, 1.0))
		vit_hair_mat.set_shader_parameter("backlight_strength", 0.35)  # light through hair = depth
		vit_hair_mat.set_shader_parameter("density", 1.0)
		vit_hair_mat.set_shader_parameter("scissor", 0.10)          # carve much finer strand gaps (de-ribbon)
	return vit_hair_mat


func _make_browcards() -> ShaderMaterial:
	if vit_brow_mat == null:
		# MATTE to match the scalp hair (was shiny: low roughness + strong anisotropic
		# highlight). High roughness, near-zero specular + anisotropy = no shine.
		vit_brow_mat = _make_hair_card(Color(0.11, 0.078, 0.05), 0.28, 0.45, 0.92, "res://vit_hair_atlas.png", 0.02)
		vit_brow_mat.set_shader_parameter("anisotropy", 0.05)
		vit_brow_mat.set_shader_parameter("tonal_variation", 0.2)
	return vit_brow_mat


func _make_lash() -> ShaderMaterial:
	# Single-lash atlas (one solid tapered lash per column) → distinct curved lashes.
	var m: ShaderMaterial = _make_hair_card(Color(0.022, 0.016, 0.013), 0.34, 0.2, 0.5,
		"res://vit_lash_atlas.png")
	m.set_shader_parameter("anisotropy", 0.4)
	m.set_shader_parameter("tonal_variation", 0.15)
	lash_mats.append(m)
	return m


# eyeshadow: a tinted, soft-edged shell over the upper lid. Opacity starts at 0 (no
# make-up); the look-dev slider raises it. Transparent so it reads as colour on the skin.
var eyeshadow_mats: Array[StandardMaterial3D] = []
func _make_eyeshadow() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.30, 0.16, 0.26, 0.0)   # alpha 0 = off by default
	m.roughness = 0.62
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	eyeshadow_mats.append(m)
	return m


# Tearline: the wet meniscus where the lid meets the eyeball (shipped CharMorph
# asset, pre-fitted). Glossy, mostly-transparent — reads as the eye being WET.
func _make_tearline() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.30, 0.36, 0.42, 0.12)  # dark wet crevice; the GLINT comes from spec, not albedo
	m.roughness = 0.04
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


# Lacrimal caruncle: the fleshy pink nub in the inner eye corner (shipped asset).
func _make_caruncle() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.70, 0.34, 0.30)
	m.roughness = 0.38
	return m


func _eyeshadow_set_c() -> Callable:
	return func(c: Color):
		for m in eyeshadow_mats:
			m.albedo_color = Color(c.r, c.g, c.b, m.albedo_color.a)


func _eyeshadow_set_a() -> Callable:
	return func(v: float):
		for m in eyeshadow_mats:
			var c: Color = m.albedo_color
			m.albedo_color = Color(c.r, c.g, c.b, v)


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


func _frame_view(which: String) -> void:
	# camera framing presets for head-bust vs full figure
	match which:
		"full":
			orbit_target = Vector3(0.0, 0.95, 0.0); orbit_yaw = -16.0; orbit_pitch = 4.0
			orbit_dist = 3.0; _orbit_fov = 40.0
		"upper":
			orbit_target = Vector3(0.0, 1.35, 0.0); orbit_yaw = -16.0; orbit_pitch = 4.0
			orbit_dist = 1.4; _orbit_fov = 34.0
		_:  # head
			orbit_target = DEFAULT_CAM_TARGET; orbit_yaw = DEFAULT_CAM_YAW
			orbit_pitch = DEFAULT_CAM_PITCH; orbit_dist = DEFAULT_CAM_DIST; _orbit_fov = 28.0
	if camera: camera.fov = _orbit_fov
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

	# framing presets
	var frame_row: HBoxContainer = HBoxContainer.new()
	vb.add_child(frame_row)
	var fl: Label = Label.new(); fl.text = "Frame:"; fl.add_theme_font_size_override("font_size", 12)
	frame_row.add_child(fl)
	for fp in [["Head", "head"], ["Upper", "upper"], ["Full body", "full"]]:
		var fb: Button = Button.new()
		fb.text = fp[0]
		var which: String = fp[1]
		fb.pressed.connect(func(): _frame_view(which))
		frame_row.add_child(fb)

	# ── ANIMATION ──
	_hdr(vb, "Animation (Mixamo clips)")
	var anim_grid: GridContainer = GridContainer.new()
	anim_grid.columns = 3
	vb.add_child(anim_grid)
	for clip in ["Idle", "Sway", "Walk", "Turn", "Wave", "HappyIdle"]:
		var ab: Button = Button.new()
		ab.text = clip
		ab.disabled = not (anim and anim.has_animation(clip))
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c: String = clip
		ab.pressed.connect(func(): _play_clip(c))
		anim_grid.add_child(ab)
		_anim_buttons[clip] = ab
	var apause: HBoxContainer = HBoxContainer.new()
	vb.add_child(apause)
	var pause_btn: Button = Button.new()
	pause_btn.text = "Pause"
	pause_btn.pressed.connect(func(): if anim: anim.pause())
	apause.add_child(pause_btn)
	var resume_btn: Button = Button.new()
	resume_btn.text = "Resume"
	resume_btn.pressed.connect(func(): if anim and _cur_clip != "": anim.play(_cur_clip))
	apause.add_child(resume_btn)

	# ── FACIAL EXPRESSION ──
	_hdr(vb, "Facial expression")
	var expr_grid: GridContainer = GridContainer.new()
	expr_grid.columns = 3
	vb.add_child(expr_grid)
	for ex in ["auto", "neutral", "smile", "jawopen", "talk", "surprise", "frown", "angry", "blink"]:
		var eb: Button = Button.new()
		eb.text = ex
		eb.disabled = bshapes.is_empty()
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var em: String = ex
		eb.pressed.connect(func(): _set_face_mode(em))
		expr_grid.add_child(eb)
		_expr_buttons[ex] = eb

	# ── LIGHTING PRESETS ──
	_hdr(vb, "Lighting presets")
	var lp_grid: GridContainer = GridContainer.new()
	lp_grid.columns = 2
	vb.add_child(lp_grid)
	for lp in ["Hero", "Portrait", "Studio", "Dramatic", "Backlit"]:
		var lb: Button = Button.new()
		lb.text = lp
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ln: String = lp
		lb.pressed.connect(func(): _apply_light_preset(ln))
		lp_grid.add_child(lb)
	_refresh_btn_tint(_anim_buttons, _cur_clip)
	_refresh_btn_tint(_expr_buttons, _face_mode)

	# ── BODY & CLOTHING ──
	_hdr(vb, "Body & clothing")
	_mkcheck(vb, "show_body", "show body (off = head only)", true, func(on):
		show_body = on
		for bmi in _body_meshes: bmi.visible = on)
	_mkcolor(vb, "body_skin_color", "body skin", Color(1, 1, 1), func(c): if body_skin_mat: body_skin_mat.set_shader_parameter("albedo", c))
	_mkcolor(vb, "shirt_color", "shirt colour", Color(0.18, 0.22, 0.30), func(c): if shirt_mat: shirt_mat.albedo_color = c)
	_mkslider(vb, "shirt_rough", "shirt roughness", 0.0, 1.0, 0.01, 0.85, func(v): if shirt_mat: shirt_mat.roughness = v)
	_mkcolor(vb, "pants_color", "pants colour", Color(0.12, 0.12, 0.14), func(c): if pants_mat: pants_mat.albedo_color = c)
	_mkslider(vb, "pants_rough", "pants roughness", 0.0, 1.0, 0.01, 0.8, func(v): if pants_mat: pants_mat.roughness = v)

	# ── SKIN ──
	_hdr(vb, "Skin")
	_mkslider(vb, "SKIN_NRM", "normal_strength", 0.0, 8.0, 0.01, 1.0, _skin_setter("normal_strength"))
	_mkslider(vb, "SKIN_SSS", "subsurface_scattering", 0.0, 1.0, 0.01, 0.55, _skin_setter("subsurface_scattering_strength"))
	_mkslider(vb, "SKIN_SMOOTH", "skin_smoothness", 0.0, 6.0, 0.01, 1.8, _skin_setter("skin_smoothness"))
	_mkslider(vb, "sss_depth", "sss_depth_scale", 0.5, 12.0, 0.1, 1.1, _skin_setter("sss_depth_scale"))
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
	_mkslider(vb, "CATCH", "energy", 0.0, 4.0, 0.01, 0.1, func(v): catch_light.light_energy = v)

	# ── ENVIRONMENT ──
	_hdr(vb, "Environment")
	_mkslider(vb, "AMBIENT", "ambient energy", 0.0, 3.0, 0.01, 0.10, func(v): env.ambient_light_energy = v)
	_mkslider(vb, "EXPOSURE", "exposure", 0.2, 3.0, 0.01, 1.0, func(v): env.tonemap_exposure = v)
	_mkslider(vb, "saturation", "saturation", 0.0, 3.0, 0.01, 1.02, func(v): env.adjustment_saturation = v)
	_mkslider(vb, "contrast", "contrast", 0.0, 3.0, 0.01, 1.03, func(v): env.adjustment_contrast = v)
	_mkslider(vb, "backdrop_bright", "backdrop brightness", 0.0, 4.0, 0.01, 1.0, func(v): backdrop_bright = v; _apply_backdrop())
	_mkcolor(vb, "backdrop_tint", "backdrop tint", Color("332d28"), func(c): backdrop_tint = c; _apply_backdrop())

	# ── HAIR (Hair Tool cards) ──
	_hdr(vb, "Hair — colour")
	_mkcolor(vb, "hair_root_color", "root colour", Color(0.50, 0.40, 0.28), _hair_set_c("root_color"))
	_mkcolor(vb, "hair_tip_color", "tip colour", Color(0.62, 0.50, 0.36), _hair_set_c("tip_color"))
	_mkslider(vb, "hair_brightness", "brightness", 0.0, 8.0, 0.01, 3.4, _hair_set("brightness"))
	_mkslider(vb, "hair_diffuse_mix", "use baked texture", 0.0, 1.0, 0.01, 1.0, _hair_set("diffuse_mix"))
	_mkslider(vb, "hair_tonal", "lock-to-lock variation", 0.0, 1.0, 0.01, 0.45, _hair_set("tonal_variation"))
	_mkslider(vb, "hair_clumps", "variation clump count", 4.0, 80.0, 1.0, 28.0, _hair_set("clump_count"))
	_mkslider(vb, "hair_tip_lighten", "tip lighten", 0.0, 1.0, 0.01, 0.18, _hair_set("tip_lighten"))

	_hdr(vb, "Hair — shape / coverage")
	_mkslider(vb, "hair_density", "density (fuller→wispier)", 0.2, 3.0, 0.01, 1.0, _hair_set("density"))
	_mkslider(vb, "hair_scissor", "cutout threshold", 0.0, 0.95, 0.005, 0.12, _hair_set("scissor"))
	_mkslider(vb, "hair_normal", "normal strength", 0.0, 4.0, 0.01, 0.8, _hair_set("normal_strength"))
	_mkcheck(vb, "hair_flip_green", "flip normal green", false, _hair_set_b("flip_green"))

	_hdr(vb, "Hair — shading")
	_mkslider(vb, "hair_rough", "roughness", 0.0, 1.0, 0.01, 0.84, _hair_set("roughness_val"))
	_mkslider(vb, "hair_spec", "specular", 0.0, 1.0, 0.01, 0.12, _hair_set("specular_val"))
	_mkslider(vb, "hair_aniso", "anisotropy (strand sheen)", -1.0, 1.0, 0.01, 0.3, _hair_set("anisotropy_val"))
	_mkslider(vb, "hair_ao", "AO strength", 0.0, 1.0, 0.01, 0.6, _hair_set("ao_strength"))
	_mkslider(vb, "hair_emit", "shadow lift (emission)", 0.0, 1.0, 0.01, 0.13, _hair_set("emit"))
	_mkcolor(vb, "hair_backlight_color", "backlight tint", Color(0.18, 0.10, 0.05), _hair_set_c("backlight_color"))
	_mkslider(vb, "hair_backlight", "backlight (light-thru)", 0.0, 1.0, 0.01, 0.35, _hair_set("backlight_strength"))
	_mkcolor(vb, "scalp_color", "scalp base colour", Color(0.05, 0.035, 0.024), func(c): if vit_scalp_mat: vit_scalp_mat.set_shader_parameter("hair_color", c))

	# ── HAIR / KICKER LIGHT ──
	_hdr(vb, "Hair light (kicker)")
	_mkslider(vb, "hairlight_energy", "energy", 0.0, 8.0, 0.01, 1.5, func(v): hair_light.light_energy = v)
	_mkcolor(vb, "hairlight_color", "color", Color("ffefd1"), func(c): hair_light.light_color = c)
	_mkslider(vb, "hairlight_spec", "specular", 0.0, 1.0, 0.01, 0.1, func(v): hair_light.light_specular = v)
	_mkslider(vb, "hairlight_yaw", "yaw", -180.0, 180.0, 1.0, hair_light_yaw, func(v): hair_light_yaw = v; _apply_light_rot(hair_light, hair_light_pitch, hair_light_yaw))
	_mkslider(vb, "hairlight_pitch", "pitch", -90.0, 30.0, 1.0, hair_light_pitch, func(v): hair_light_pitch = v; _apply_light_rot(hair_light, hair_light_pitch, hair_light_yaw))

	# ── EYEBROWS ──
	_hdr(vb, "Eyebrows")
	_mkcolor(vb, "brow_color", "eyebrow colour", Color("1f160e"), func(c): if vit_brow_mat: vit_brow_mat.set_shader_parameter("hair_color", c))
	_mkslider(vb, "brow_threshold", "density", 0.02, 0.7, 0.005, 0.28, func(v): if vit_brow_mat: vit_brow_mat.set_shader_parameter("alpha_threshold", v))

	# ── EYE MAKE-UP (eyeshadow) ──
	_hdr(vb, "Eye make-up")
	_mkcolor(vb, "shadow_color", "eyeshadow colour", Color(0.30, 0.16, 0.26), _eyeshadow_set_c())
	_mkslider(vb, "shadow_opacity", "eyeshadow amount", 0.0, 1.0, 0.01, 0.0, _eyeshadow_set_a())

	# ── EYES (iris / pupil / sclera) ──
	_hdr(vb, "Eyes — iris & pupil")
	_mkslider(vb, "eye_iris_radius", "iris radius", 0.05, 0.6, 0.005, 0.32, _eye_set("iris_radius"))
	_mkslider(vb, "eye_iris_margin", "iris edge softness", 0.0, 0.2, 0.002, 0.018, _eye_set("iris_margin"))
	_mkslider(vb, "eye_pupil_radius", "pupil radius", 0.02, 0.4, 0.002, 0.10, _eye_set("pupil_radius"))
	_mkcolor(vb, "eye_pupil_color", "pupil colour", Color(0.012, 0.010, 0.014), _eye_set_c("pupil_color"))
	_mkslider(vb, "eye_cell_scale", "iris fibre scale", 1.0, 20.0, 0.1, 19.0, _eye_set("eye_cell_scale"))
	_mkslider(vb, "eye_cell_jitter", "iris fibre jitter", 0.0, 1.0, 0.01, 0.7, _eye_set("eye_cell_jitter"))
	_mkslider(vb, "eye_iris_pinch", "iris pinch", 0.0, 1.0, 0.01, 0.72, _eye_set("iris_pinch"))

	_hdr(vb, "Eyes — iris colour ramp")
	_mkcolor(vb, "iris_dark", "fibre (dark)", iris_col_dark, func(c): iris_col_dark = c; _rebuild_iris_ramp())
	_mkcolor(vb, "iris_mid", "fibre (mid)", iris_col_mid, func(c): iris_col_mid = c; _rebuild_iris_ramp())
	_mkcolor(vb, "iris_bright", "fibre (limbal)", iris_col_bright, func(c): iris_col_bright = c; _rebuild_iris_ramp())

	_hdr(vb, "Eyes — sclera & surface")
	_mkcolor(vb, "eye_white", "sclera (white)", Color(0.86, 0.83, 0.80), _eye_set_c("eye_white"))
	_mkslider(vb, "eye_sclera_shade", "sclera shading", 0.0, 1.0, 0.01, 0.5, _eye_set("sclera_shade"))
	_mkcolor(vb, "eye_sclera_tint", "sclera edge tint", Color(0.80, 0.66, 0.60), _eye_set_c("sclera_edge_tint"))
	_mkslider(vb, "eye_rough", "eyeball roughness", 0.0, 1.0, 0.01, 0.07, _eye_set("eyeball_roughness"))
	_mkslider(vb, "eye_spec", "eyeball specular", 0.0, 1.0, 0.01, 0.06, _eye_set("eyeball_specular"))

	_hdr(vb, "Eyes — cornea (wet shell)")
	_mkslider(vb, "cornea_shininess", "shininess", 0.0, 800.0, 1.0, 480.0, _cornea_set("shininess"))
	_mkslider(vb, "cornea_spec", "spec intensity", 0.0, 1.0, 0.01, 0.5, _cornea_set("spec_intensity"))
	_mkslider(vb, "cornea_alpha", "max alpha", 0.0, 1.0, 0.01, 0.7, _cornea_set("alpha_max"))

	# ── CAMERA / DOF ──
	_hdr(vb, "Camera / DOF")
	_mkslider(vb, "fov", "FOV", 8.0, 90.0, 0.5, 28.0, func(v): _set_fov(v))
	_mkcheck(vb, "dof_enabled", "DOF enabled", true, func(on): dof_enabled = on; _apply_dof())
	_mkslider(vb, "dof_focus", "focus distance", 0.1, 4.0, 0.01, 0.52, func(v): dof_focus = v; _apply_dof())
	_mkslider(vb, "dof_blur", "blur amount", 0.0, 1.0, 0.005, 0.06, func(v): dof_blur = v; _apply_dof())

	_build_corner_ui(layer)
	_build_panel_handle(layer)


# ── Setter factories / helpers ───────────────────────────────────────────────

func _hair_set(param: String) -> Callable:
	return func(v: float) -> void:
		if vit_hair_mat: vit_hair_mat.set_shader_parameter(param, v)

func _hair_set_c(param: String) -> Callable:
	return func(c: Color) -> void:
		if vit_hair_mat: vit_hair_mat.set_shader_parameter(param, c)

func _hair_set_b(param: String) -> Callable:
	return func(on: bool) -> void:
		if vit_hair_mat: vit_hair_mat.set_shader_parameter(param, on)

func _lash_set(param: String) -> Callable:
	return func(v: float) -> void:
		for m in lash_mats:
			m.set_shader_parameter(param, v)

func _lash_set_c(param: String) -> Callable:
	return func(c: Color) -> void:
		for m in lash_mats:
			m.set_shader_parameter(param, c)

func _eye_set(param: String) -> Callable:
	return func(v: float) -> void:
		for m in eyeball_mats:
			m.set_shader_parameter(param, v)

func _eye_set_c(param: String) -> Callable:
	return func(c: Color) -> void:
		for m in eyeball_mats:
			m.set_shader_parameter(param, c)

func _cornea_set(param: String) -> Callable:
	return func(v: float) -> void:
		for m in cornea_mats:
			m.set_shader_parameter(param, v)


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
