extends RefCounted
# (no class_name: scenes preload this script as `FaceExtras` so direct scene runs
# work without an editor import pass refreshing the global class cache)
# Small shared scene-dressing helpers used by both the look-dev and cinematic scenes:
#  • lid-contact AO band — a thin dark gradient shell hugging the upper eyeball, so the
#    eye stops "floating" in the socket (fakes lid-contact occlusion + lash shadow).
#  • vignette — full-screen subtle darkened corners (canvas layer above the 3D view).
#  • floor — soft "pool of light" ground plane (radial gradient to black, receives the
#    character's real contact shadow) replacing the grey void / hard horizon.


# Dark occlusion band over the upper third of an eyeball. Parented next to the eye
# node (static relative to the head — real lid AO doesn't follow gaze).
static func add_lid_ao(eye_mi: MeshInstance3D, eye_r: float = 0.012) -> MeshInstance3D:
	var R: float = eye_r * 1.06          # just proud of the eyeball, under the skin lid
	var el0: float = deg_to_rad(6.0)     # fades to 0 here (lower edge, over the iris top)
	var el1: float = deg_to_rad(58.0)    # full dark at the lid line
	var azmax: float = deg_to_rad(72.0)
	var NAZ: int = 16
	var NEL: int = 6
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var band_col := Color(0.07, 0.045, 0.035)
	for ie in range(NEL + 1):
		var f: float = float(ie) / float(NEL)
		var el: float = lerpf(el0, el1, f)
		var a: float = 0.78 * smoothstep(0.0, 0.5, f)            # alpha ramps up toward the lid
		for ia in range(NAZ + 1):
			var az: float = lerpf(-azmax, azmax, float(ia) / float(NAZ))
			var edge: float = 1.0 - smoothstep(0.72, 1.0, absf(az) / azmax)  # feather the corners
			var d := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
			verts.append(d * R)
			cols.append(Color(band_col.r, band_col.g, band_col.b, a * edge))
	for ie in range(NEL):
		for ia in range(NAZ):
			var r0: int = ie * (NAZ + 1) + ia
			var r1: int = (ie + 1) * (NAZ + 1) + ia
			idx.append_array(PackedInt32Array([r0, r0 + 1, r1 + 1, r0, r1 + 1, r1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	am.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = eye_mi.name.replace("Eye_", "LidAO_")
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye_mi.get_parent().add_child(mi)
	mi.position = eye_mi.position
	return mi


static func make_vignette(root: Node, amount: float = 0.30, softness: float = 0.55) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 0                      # above the 3D view, below the UI CanvasLayers
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://scenes/vignette.gdshader") as Shader
	m.set_shader_parameter("amount", amount)
	m.set_shader_parameter("softness", softness)
	rect.material = m
	layer.add_child(rect)
	root.add_child(layer)
	return layer


# Soft pool-of-light floor: radial gradient (lit under the character → black at the
# edges) so there is no visible horizon line, while real shadows still land on it.
static func make_floor(parent: Node, pool_tint: Color = Color(0.05, 0.048, 0.05)) -> MeshInstance3D:
	var grad := Gradient.new()
	grad.set_color(0, pool_tint)
	grad.add_point(0.32, Color(pool_tint.r * 0.3, pool_tint.g * 0.3, pool_tint.b * 0.3))
	grad.set_color(1, Color(0.004, 0.004, 0.005))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 512
	tex.height = 512
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1)
	mat.roughness = 0.72
	mat.metallic = 0.0
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9.0, 9.0)
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(0, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
