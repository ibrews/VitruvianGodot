extends Node3D
# ════════════════════════════════════════════════════════════════════════════
# VITRUVIAN — cinematic real-time digital-human showcase (stock Godot 4.6).
# A CC0 / EULA-free character: rigged Mixamo body (live AnimationPlayer), head +
# eyes + lashes + Hair Tool cards bone-attached to mixamorig:Head, HAIR PHYSICS
# (spring jiggle), 3-point + rim cinematic lighting, AgX, bloom, DOF, hero camera.
# No MetaHuman, no Unreal, no Epic assets.
#
# Live:    Godot ... scenes/vitruvian_cinematic.tscn
# Capture: CINEMA_CAPTURE=<dir> Godot ... scenes/vitruvian_cinematic.tscn  → PNG frames
# ════════════════════════════════════════════════════════════════════════════

const BODY_GLB := "res://vitruvian_body.glb"
const HEAD_GLB := "res://vitruvian_head.glb"
const HAIR_GLB := "res://hairtool_cards.glb"
const HAIR_RIGGED := "res://vitruvian_hair_rigged.glb"   # spring-bone chain
const HAIR_LEGACY := "res://vitruvian_hair.glb"
const HEAD_BONE := "mixamorig_Head"
var hair_spring: HairSpring

var skel: Skeleton3D
var anim: AnimationPlayer
var head_bone_idx: int = -1
var head_rig: Node3D          # rides the Head bone
var hair_pivot: Node3D        # jiggles inside head_rig
var hair_node: Node3D

# hair spring state
var _hp_rot: Vector3 = Vector3.ZERO       # current jiggle euler (rad)
var _hp_vel: Vector3 = Vector3.ZERO
var _prev_head_basis: Basis
var _have_prev := false
var _dbg_done := false

var camera: Camera3D
var cam_attrs: CameraAttributesPractical
var catch_light: OmniLight3D
var key_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var env: Environment

# sequence timeline (seconds)
var _t: float = 0.0
var DUR := 31.0
# capture
var _movie := false

var skin_mats: Array[ShaderMaterial] = []

# ── facial animation (CC0 ARKit-style blendshapes on the head + eyeball nodes) ──
var face_mi: MeshInstance3D                 # face mesh carrying the blend shapes
var bshapes: Dictionary = {}                # ARKit name -> blend shape index
var eye_nodes: Array = []                   # [{node, rest_scale}] eyeball + cornea spheres
var upper_lids: Array = []                  # [{node, rest_basis}] upper eyelids (rotate down to blink)
var _gaze: Vector2 = Vector2.ZERO           # smoothed eye look (yaw,pitch rad)
# Godot 4.6.3 does not reliably render native blend-shape combos on this imported mesh
# (and normalized mode scales combined weights down). Drive the face by rebuilding the
# surface on the CPU = base + Σ weight*delta (additive, full strength). Matches lookdev.
var _morph_base: PackedVector3Array
var _morph_arrays: Array
var _morph_deltas: Dictionary = {}
var _morph_key: String = ""
var _morph_mat: Material


func _ready() -> void:
	_setup_env()
	_setup_lights()
	_setup_camera()
	_load_body()
	_load_head_and_hair()
	if anim:
		anim.play("Idle")
	print("[cine] anim=", anim, " list=", (anim.get_animation_list() if anim else []),
		" root_node=", (anim.root_node if anim else "n/a"), " skel=", skel,
		" idle_len=", (anim.get_animation("Idle").length if anim and anim.has_animation("Idle") else -1))
	if anim and anim.has_animation("Idle"):
		var a := anim.get_animation("Idle")
		print("[cine] Idle tracks=", a.get_track_count(), " t0path=", (a.track_get_path(0) if a.get_track_count() > 0 else "none"))
	# Movie Maker mode: fixed-timestep deterministic frames (run with --write-movie
	# + CINEMA_MOVIE=1 so the scene knows to auto-quit when the reel ends).
	_movie = OS.has_environment("CINEMA_MOVIE")
	for a in OS.get_cmdline_args():
		if a == "--write-movie":
			_movie = true
	if OS.has_environment("CINEMA_DUR"):
		DUR = float(OS.get_environment("CINEMA_DUR"))
	if _movie:
		get_viewport().msaa_3d = Viewport.MSAA_8X
		print("[cine] MOVIE mode — will quit after ", DUR, "s")


# ── environment ─────────────────────────────────────────────────────────────
func _setup_env() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.020, 0.028, 0.045)
	sky_mat.sky_horizon_color = Color(0.04, 0.05, 0.07)
	sky_mat.ground_horizon_color = Color(0.02, 0.02, 0.03)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sky_mat.energy_multiplier = 0.4
	var sky := Sky.new(); sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.08
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 2.0
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.95
	env.glow_bloom = 0.10
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.06, 0.09)
	env.fog_density = 0.012
	var we := WorldEnvironment.new(); we.environment = env
	add_child(we)
	RenderingServer.sub_surface_scattering_set_quality(RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH)
	RenderingServer.sub_surface_scattering_set_scale(0.08, 0.02)
	# floor catching a soft pool of light
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(12, 12)
	floor.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.05, 0.05, 0.06)
	fmat.roughness = 0.5
	fmat.metallic = 0.1
	floor.material_override = fmat
	floor.position = Vector3(0, 0, 0)
	add_child(floor)


func _setup_lights() -> void:
	var key := DirectionalLight3D.new()
	key.light_energy = 3.4
	key.light_color = Color(1.0, 0.89, 0.74)
	key.shadow_enabled = true
	key.shadow_blur = 2.5
	key.light_angular_distance = 3.0
	key.rotation_degrees = Vector3(-38, -68, 0)
	add_child(key)
	key_light = key

	var rim := DirectionalLight3D.new()
	rim.light_energy = 4.5
	rim.light_specular = 1.0
	rim.light_color = Color(0.42, 0.6, 1.0)
	rim.rotation_degrees = Vector3(-12, 145, 0)
	add_child(rim)
	rim_light = rim

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	fill.light_color = Color(0.7, 0.78, 0.9)
	fill.rotation_degrees = Vector3(8, 30, 0)
	add_child(fill)

	# hair/kicker from above-behind
	var hair := DirectionalLight3D.new()
	hair.light_energy = 2.6
	hair.light_specular = 0.6
	hair.light_color = Color(1.0, 0.92, 0.8)
	hair.rotation_degrees = Vector3(-72, -150, 0)
	add_child(hair)

	# eye catch-light: a small bright omni near the face for the wet eye spark
	# (without it the eyes read dead). Repositioned each frame in _update_camera.
	catch_light = OmniLight3D.new()
	catch_light.light_energy = 1.6
	catch_light.light_specular = 1.0
	catch_light.light_color = Color(1.0, 0.98, 0.95)
	catch_light.omni_range = 0.9
	catch_light.omni_attenuation = 2.6
	catch_light.position = Vector3(0.1, 1.62, 0.6)
	add_child(catch_light)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.near = 0.02
	camera.far = 60.0
	camera.fov = 34.0
	camera.current = true
	cam_attrs = CameraAttributesPractical.new()
	cam_attrs.dof_blur_far_enabled = true
	cam_attrs.dof_blur_near_enabled = true
	cam_attrs.dof_blur_amount = 0.08
	camera.attributes = cam_attrs
	add_child(camera)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


# ── body / head / hair ──────────────────────────────────────────────────────
func _load_body() -> void:
	var s: PackedScene = load(BODY_GLB)
	var b: Node = s.instantiate()
	add_child(b)
	skel = _find(b, "Skeleton3D") as Skeleton3D
	anim = _find(b, "AnimationPlayer") as AnimationPlayer
	if skel:
		head_bone_idx = skel.find_bone(HEAD_BONE)
		var meshes: Array[MeshInstance3D] = []
		_collect(skel, meshes)
		for mi in meshes:
			for si in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(si)
				var nm := (m.resource_name if m else "").split(".")[0]
				match nm:
					"VitShirt": mi.set_surface_override_material(si, _mat_shirt())
					"VitPants": mi.set_surface_override_material(si, _mat_pants())
					_:          mi.set_surface_override_material(si, _mat_body_skin())
	# loop anims forever; NORMAL playback (manual seek doesn't update the skin in
	# headless). Determinism comes from Movie Maker's fixed timestep (--write-movie
	# --fixed-fps), which renders skinning correctly.
	if anim:
		for a in anim.get_animation_list():
			var ar := anim.get_animation(a)
			ar.loop_mode = Animation.LOOP_LINEAR


func _load_head_and_hair() -> void:
	# BoneAttachment rides the Head bone; head_rig undoes the bone rest so the
	# (world-authored) head/hair sit correctly at rest and follow the animation.
	var att := BoneAttachment3D.new()
	att.name = "HeadAttach"
	skel.add_child(att)
	att.bone_idx = head_bone_idx
	var rest_g: Transform3D = skel.global_transform * skel.get_bone_global_rest(head_bone_idx)

	head_rig = Node3D.new(); head_rig.name = "HeadRig"
	att.add_child(head_rig)
	head_rig.global_transform = Transform3D.IDENTITY  # world-aligned at rest

	# HEAD (static: skin/eyes/lashes/mouth)
	var hs: PackedScene = load(HEAD_GLB)
	var head: Node = hs.instantiate()
	head.name = "Head"
	head_rig.add_child(head)
	var hmeshes: Array[MeshInstance3D] = []
	_collect(head, hmeshes)
	for mi in hmeshes:
		for si in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(si)
			var nm := (m.resource_name if m else "").split(".")[0]
			match nm:
				"VitSkin":    mi.set_surface_override_material(si, _mat_skin())
				"VitEyeball": mi.set_surface_override_material(si, _mat_eyeball())
				"VitCornea":  mi.set_surface_override_material(si, _mat_cornea())
				"VitMouth":   mi.set_surface_override_material(si, _mat_mouth())
				"VitScalp":   mi.set_surface_override_material(si, _mat_discard())
				"VitLash":    mi.set_surface_override_material(si, _mat_lash())
				_: pass
		# capture the face mesh (carries ARKit blend shapes) + eyeball spheres
		if mi.mesh.get_blend_shape_count() > 0 and face_mi == null:
			face_mi = mi
			for bi in range(mi.mesh.get_blend_shape_count()):
				bshapes[String(mi.mesh.get_blend_shape_name(bi))] = bi
		if mi.name.begins_with("Eye_"):
			eye_nodes.append({"node": mi, "rest_basis": mi.transform.basis, "rest_pos": mi.position})
		if mi.name.begins_with("LidUp"):
			upper_lids.append({"node": mi, "rest_basis": mi.transform.basis})
	print("[cine] face blendshapes=", bshapes.size(), " eye_nodes=", eye_nodes.size())
	_setup_face_morph()

	# HAIR — dynamic SPRING-BONE chain (rides the head via head_rig; HR1..n simulate)
	var hairscene: PackedScene = load(HAIR_RIGGED)
	hair_node = hairscene.instantiate()
	hair_node.name = "Hair"
	head_rig.add_child(hair_node)
	var hmesh2: Array[MeshInstance3D] = []
	_collect(hair_node, hmesh2)
	for mi in hmesh2:
		for si in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(si, _mat_hair())
	var hsk: Skeleton3D = _find(hair_node, "Skeleton3D") as Skeleton3D
	if hsk:
		hair_spring = HairSpring.new()
		hair_node.add_child(hair_spring)
		hair_spring.setup(hsk)
		print("[cine] hair spring bones=", hair_spring.joints.size())
	# eyebrows from legacy GLB (static, on the head)
	if ResourceLoader.exists(HAIR_LEGACY):
		var lg: Node = load(HAIR_LEGACY).instantiate()
		head_rig.add_child(lg)
		var lm: Array[MeshInstance3D] = []
		_collect(lg, lm)
		for mi in lm:
			if mi.name.begins_with("VitBrow"):
				for si in range(mi.mesh.get_surface_count()):
					mi.set_surface_override_material(si, _mat_brow())
			else:
				mi.visible = false


# ── hair jiggle (spring) ────────────────────────────────────────────────────
func _update_jiggle(dt: float) -> void:
	if hair_pivot == null or head_bone_idx < 0 or not _have_prev:
		return
	dt = clampf(dt, 1.0 / 120.0, 1.0 / 30.0)
	var cur: Basis = (skel.global_transform * skel.get_bone_global_pose(head_bone_idx)).basis
	# angular delta of the head this step → impulse into the spring (opposite = lag)
	var d: Basis = cur * _prev_head_basis.inverse()
	var av: Vector3 = d.get_rotation_quaternion().get_euler()   # small-angle ≈ angular vel
	_prev_head_basis = cur
	var stiffness := 70.0
	var damping := 7.5
	var drive: Vector3 = -av * 260.0
	var accel: Vector3 = drive - _hp_rot * stiffness - _hp_vel * damping
	_hp_vel += accel * dt
	_hp_rot += _hp_vel * dt
	_hp_rot.x = clampf(_hp_rot.x, -0.5, 0.5)
	_hp_rot.y = clampf(_hp_rot.y, -0.6, 0.6)
	_hp_rot.z = clampf(_hp_rot.z, -0.5, 0.5)
	hair_pivot.rotation = _hp_rot


# ── timeline / hero camera / sequence (deterministic seek) ──────────────────
const SEGMENTS := [
	{"clip": "Idle", "start": 0.0,  "end": 5.0},
	{"clip": "Sway", "start": 5.0,  "end": 10.0},
	{"clip": "Walk", "start": 10.0, "end": 17.0},
	{"clip": "Turn", "start": 17.0, "end": 23.0},
	{"clip": "Wave", "start": 23.0, "end": 28.0},
	{"clip": "Idle", "start": 28.0, "end": 31.0},
]

func _process(delta: float) -> void:
	_t += delta
	# fast close-up preview: drive face+camera at a fixed time (CINE_PREVIEW=<secs>),
	# let the rig settle a moment, grab one frame, quit. (Body pose ≈ irrelevant for a
	# face exposure / mouth check.)
	if OS.has_environment("CINE_PREVIEW"):
		var pt: float = float(OS.get_environment("CINE_PREVIEW"))
		_drive_anim(_t)
		if hair_spring: hair_spring.step(delta)
		_drive_face(pt, delta)
		_update_camera(pt)
		if _t > 1.6:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://").path_join("..").path_join("out").path_join("cine_preview.png"))
			get_tree().quit()
		return
	_drive_anim(_t)
	_drive_face(_t, delta)
	if hair_spring: hair_spring.step(delta)
	_update_camera(_t)
	if _movie and _t >= DUR + 0.05:
		print("[cine] done @ ", _t)
		get_tree().quit()


func _drive_anim(t: float) -> void:
	if anim == null: return
	if not _movie: t = fmod(t, DUR)   # loop forever when running live
	var seg: Dictionary = SEGMENTS[SEGMENTS.size() - 1]
	for s in SEGMENTS:
		if t >= s["start"] and t < s["end"]:
			seg = s; break
	var clip: String = seg["clip"]
	if anim.current_animation != clip:
		anim.play(clip, 0.35)   # normal playback + crossfade; auto-advances + loops


func _sshape(n: String, v: float) -> void:
	if face_mi and bshapes.has(n):
		face_mi.set_blend_shape_value(bshapes[n], v)


func _setup_face_morph() -> void:
	if face_mi == null:
		return
	var am: ArrayMesh = face_mi.mesh as ArrayMesh
	if am == null or am.get_blend_shape_count() == 0:
		return
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
	var fresh: ArrayMesh = ArrayMesh.new()
	fresh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _morph_arrays.duplicate())
	face_mi.mesh = fresh
	if _morph_mat: face_mi.set_surface_override_material(0, _morph_mat)
	print("[cine] face morph: base verts=", _morph_base.size(), " shapes=", _morph_deltas.size())


func _apply_morph(weights: Dictionary) -> void:
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
	var arrays: Array = _morph_arrays.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	face_mi.mesh = m
	if _morph_mat: face_mi.set_surface_override_material(0, _morph_mat)


func _drive_face(t: float, delta: float) -> void:
	# Procedural face idle: periodic blink, eye saccades, and a soft expression arc
	# (a warm smile blooms during the face close-up, plus a silent "spoken word" so the
	# now-working mouth articulation is visible). Composes with the body anim; morphs are
	# applied by rebuilding the surface (_apply_morph), gaze/lids ride the eye/lid nodes.
	if face_mi == null:
		return
	var tt: float = t if _movie else fmod(t, DUR)

	# ── blink: a quick lid close every ~3s (real upper-lid geometry sweeps down) ──
	var bt: float = fmod(tt + 0.6, 3.0)
	var blink: float = 0.0
	if bt < 0.18:
		blink = sin(bt / 0.18 * PI)
	var lid_ang: float = blink * deg_to_rad(60.0)
	for l in upper_lids:
		(l["node"] as MeshInstance3D).transform.basis = Basis(Vector3(1, 0, 0), -lid_ang) * (l["rest_basis"] as Basis)

	# ── expression arc (additive weights → _apply_morph) ──
	var closeup: float = smoothstep(26.5, 28.5, tt)
	var browflash: float = smoothstep(17.6, 18.4, tt) * (1.0 - smoothstep(19.6, 21.0, tt)) * 0.45
	# a silent "hello" — TWO clear mouth-opens in the tight close-up so the (now real,
	# teeth-and-all) jaw articulation reads unmistakably on camera.
	var speak: float = 0.0
	if tt > 28.6 and tt < 30.9:
		speak = maxf(0.0, sin((tt - 28.6) / 2.3 * PI * 4.0)) * 0.42
	# warm close-up smile, but let the jaw-open take over while "speaking" (a smile +
	# wide jaw at once reads as a distorted grin and detaches the static lower teeth).
	var smile: float = (0.10 + 0.5 * closeup) * (1.0 - clampf(speak * 2.2, 0.0, 0.85))
	var w: Dictionary = {
		"mouthSmileLeft": smile, "mouthSmileRight": smile,
		"browInnerUp": browflash + smile * 0.12,
		"browOuterUpLeft": browflash * 0.6, "browOuterUpRight": browflash * 0.6,
		"jawOpen": speak, "mouthFunnel": speak * 0.25,
	}
	_apply_morph(w)

	# ── eye saccades: snap to a new gaze target every ~2s, hold; freeze while blinking ──
	if blink < 0.4:
		var k: int = int(tt / 2.0)
		var target: Vector2 = Vector2(sin(float(k) * 12.9898) * 0.20, sin(float(k) * 4.1413) * 0.12)
		_gaze = _gaze.lerp(target, clampf(delta * 16.0, 0.0, 1.0))   # fast saccade, then steady
	var gaze_rot: Basis = Basis.from_euler(Vector3(_gaze.y, 0.0, -_gaze.x))
	for e in eye_nodes:
		(e["node"] as MeshInstance3D).transform.basis = gaze_rot * (e["rest_basis"] as Basis)


func _update_camera(t: float) -> void:
	# slow hero orbit + breathing dolly around the upper body / face
	var tt = t if _movie else fmod(t, DUR)
	tt = min(tt, DUR)
	# mostly FULL-BODY (walk/turn/wave shown wide); push to the face for the FINAL idle
	# beat (28-31s) where the hand is down + a warm smile reads (the wave hand would
	# otherwise occlude the face during 23-28s).
	var closeness := smoothstep(26.5, 28.5, tt)
	var orbit := deg_to_rad(-24.0 + 34.0 * sin(tt / DUR * TAU))
	orbit = lerpf(orbit, deg_to_rad(-9.0), closeness)    # near-frontal in the close-up so the FACE (eyes/mouth) reads
	# TIGHT face close-up — fill the frame with the head so the (now working) blink,
	# gaze, smile and the silent "hello" jaw-open are clearly visible, not a tiny head.
	var target_y := lerpf(0.98, 1.60, closeness)
	var dist := lerpf(3.1, 0.92, closeness)
	var fov := lerpf(40.0, 26.0, closeness)
	var tgt := Vector3(0, target_y, 0)
	var p := deg_to_rad(4.0)
	var dir := Vector3(sin(orbit) * cos(p), sin(p), cos(orbit) * cos(p))
	camera.position = tgt + dir * dist
	camera.look_at(tgt, Vector3.UP)
	camera.fov = fov
	# the tight face close-up otherwise blows out (key/rim + the near omni catch-light all
	# pile onto a frame-filling face) — pull exposure + the hot lights down as we close in.
	if env:
		env.tonemap_exposure = lerpf(1.0, 0.70, closeness)
	if catch_light:
		catch_light.light_energy = lerpf(1.6, 0.45, closeness)
	if key_light:
		key_light.light_energy = lerpf(3.4, 2.1, closeness)
	if rim_light:
		rim_light.light_energy = lerpf(4.5, 2.4, closeness)
	var focus := camera.global_position.distance_to(tgt)
	cam_attrs.dof_blur_far_distance = focus + 0.15
	cam_attrs.dof_blur_near_distance = maxf(0.05, focus - 0.35)
	# eye catch-light rides just off the camera axis, in front of the face (the spark)
	if catch_light:
		var face := Vector3(0.0, maxf(target_y, 1.55), 0.0)
		catch_light.position = face + (camera.global_position - face).normalized() * 0.45 + Vector3(0.06, 0.16, 0.0)


# ── helpers ─────────────────────────────────────────────────────────────────
func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls: return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null

func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: out.append(n)
	for c in n.get_children(): _collect(c, out)

func _tex(p: String) -> Texture2D:
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


# ── materials (reuse the tuned look-dev shaders/values) ─────────────────────
func _mat_skin() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/skin_shader_local.gdshader") as Shader
	m.set_shader_parameter("texture_albedo", _tex("res://vit_face_bc.png"))
	m.set_shader_parameter("albedo", Color(1,1,1,1))
	m.set_shader_parameter("texture_normal", _tex("res://vit_face_n.png"))
	m.set_shader_parameter("normal_strength", 1.0)
	m.set_shader_parameter("texture_roughness", _tex("res://vit_face_rough.png"))
	m.set_shader_parameter("roughness", 0.95)
	m.set_shader_parameter("specular", 0.35)
	m.set_shader_parameter("metallic", 0.0)
	m.set_shader_parameter("metallic_texture_channel", Plane(1,0,0,0))
	m.set_shader_parameter("use_subsurface_scattering", true)
	m.set_shader_parameter("subsurface_scattering_strength", 0.6)
	m.set_shader_parameter("skin_smoothness", 1.8)
	m.set_shader_parameter("skin_fallof_smoothness", 1.05)
	m.set_shader_parameter("sss_depth_scale", 6.0)
	m.set_shader_parameter("tinted_shadow_penumbra", true)
	m.set_shader_parameter("double_specularity", false)
	m.set_shader_parameter("use_noise", false)
	m.set_shader_parameter("old_lightwarp_fallof", false)
	m.set_shader_parameter("use_micro_detail", false)
	m.set_shader_parameter("micro_normal_strength", 0.0)
	m.set_shader_parameter("use_ambient_occlusion", false)
	m.set_shader_parameter("translucency", false)
	m.set_shader_parameter("use_scatter_map", false)
	m.set_shader_parameter("uv1_scale", Vector3(1,1,1))
	m.set_shader_parameter("uv1_offset", Vector3(0,0,0))
	m.set_shader_parameter("uv2_scale", Vector3(1,1,1))
	m.set_shader_parameter("uv2_offset", Vector3(0,0,0))
	skin_mats.append(m)
	return m

func _iris_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0.025, 0.016, 0.010))
	g.add_point(0.5, Color(0.20, 0.115, 0.050))
	g.set_color(1, Color(0.46, 0.31, 0.145))
	var t := GradientTexture1D.new(); t.gradient = g; t.width = 256
	return t

func _mat_eyeball() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://addons/eyeball_shader/shaders/eyeball_shader.gdshader") as Shader
	m.set_shader_parameter("iris_radius", 0.32)
	m.set_shader_parameter("iris_margin", 0.018)
	m.set_shader_parameter("pupil_radius", 0.10)
	m.set_shader_parameter("eye_white", Color(0.86, 0.83, 0.80))
	m.set_shader_parameter("pupil_color", Color(0.012, 0.010, 0.014))
	m.set_shader_parameter("texture_iris_color", _iris_ramp())
	m.set_shader_parameter("eye_cell_scale", 19.0)
	m.set_shader_parameter("eye_cell_jitter", 0.7)
	m.set_shader_parameter("iris_pinch", 0.72)
	m.set_shader_parameter("eyeball_roughness", 0.22)
	m.set_shader_parameter("eyeball_specular", 0.7)
	m.set_shader_parameter("sclera_shade", 0.55)
	m.set_shader_parameter("sclera_edge_tint", Color(0.80, 0.66, 0.60))
	m.set_shader_parameter("rand_seed", 12345)
	m.set_shader_parameter("uv1_scale", Vector3(1,1,1))
	m.set_shader_parameter("uv1_offset", Vector3(0,0,0))
	return m

func _mat_cornea() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://addons/eyeball_shader/shaders/cornea.gdshader") as Shader
	m.set_shader_parameter("shininess", 480.0)
	m.set_shader_parameter("spec_intensity", 0.5)
	m.set_shader_parameter("alpha_max", 0.7)
	return m

func _mat_mouth() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("res://vit_mouth.png")
	m.albedo_color = Color(0.85, 0.78, 0.76)
	m.roughness = 0.42
	return m

func _mat_hair() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/hairtool_card.gdshader") as Shader
	m.set_shader_parameter("tex_diffuse", _tex("res://vit_hair_diffuse.png"))
	m.set_shader_parameter("tex_normal", _tex("res://vit_hair_normal.png"))
	m.set_shader_parameter("tex_ao", _tex("res://vit_hair_ao.png"))
	m.set_shader_parameter("tex_opacity", _tex("res://vit_hair_opacity.png"))
	m.set_shader_parameter("root_color", Color(0.50, 0.40, 0.28, 1.0))
	m.set_shader_parameter("tip_color", Color(0.62, 0.50, 0.36, 1.0))
	m.set_shader_parameter("brightness", 3.4)
	m.set_shader_parameter("diffuse_mix", 1.0)
	m.set_shader_parameter("normal_strength", 0.6)    # softer normals → no plastic sparkle
	m.set_shader_parameter("flip_green", false)
	m.set_shader_parameter("ao_strength", 0.7)
	m.set_shader_parameter("roughness_val", 0.90)     # matte → less ribbon sheen
	m.set_shader_parameter("specular_val", 0.08)
	m.set_shader_parameter("anisotropy_val", 0.08)
	m.set_shader_parameter("tonal_variation", 0.7)
	m.set_shader_parameter("clump_count", 40.0)
	m.set_shader_parameter("tip_lighten", 0.2)
	m.set_shader_parameter("emit", 0.13)
	m.set_shader_parameter("backlight_color", Color(0.18, 0.10, 0.05, 1.0))
	m.set_shader_parameter("backlight_strength", 0.45)
	m.set_shader_parameter("density", 1.0)
	m.set_shader_parameter("scissor", 0.10)            # carve finer strand gaps (de-ribbon)
	return m

func _mat_brow() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/hair_card.gdshader") as Shader
	m.set_shader_parameter("hair_color", Color(0.11, 0.078, 0.05, 1.0))
	m.set_shader_parameter("coverage_atlas", _tex("res://vit_hair_atlas.png"))
	m.set_shader_parameter("use_red_mask", true)
	m.set_shader_parameter("alpha_threshold", 0.28)
	m.set_shader_parameter("root_darkening", 0.45)
	m.set_shader_parameter("roughness_val", 0.72)
	m.set_shader_parameter("specular_val", 0.14)
	m.set_shader_parameter("anisotropy", 0.5)
	return m

func _mat_lash() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/hair_card.gdshader") as Shader
	m.set_shader_parameter("hair_color", Color(0.022, 0.016, 0.013, 1.0))
	m.set_shader_parameter("coverage_atlas", _tex("res://vit_lash_atlas.png"))
	m.set_shader_parameter("use_red_mask", true)
	m.set_shader_parameter("alpha_threshold", 0.34)
	m.set_shader_parameter("root_darkening", 0.2)
	m.set_shader_parameter("roughness_val", 0.5)
	m.set_shader_parameter("specular_val", 0.14)
	m.set_shader_parameter("anisotropy", 0.4)
	return m

func _mat_discard() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/hidden_discard.gdshader") as Shader
	return m

func _mat_body_skin() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.69, 0.53, 0.49)
	m.roughness = 0.62
	m.metallic = 0.0
	m.metallic_specular = 0.4
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.25
	return m

func _mat_shirt() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.20, 0.29)
	m.roughness = 0.8
	return m

func _mat_pants() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.11, 0.11, 0.13)
	m.roughness = 0.78
	return m
