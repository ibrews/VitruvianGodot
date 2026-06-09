extends Node
class_name HairSpring
# VRM-style spring-bone simulation for the hair chain (HR0 rigid root follows the
# head; HR1..n swing/lag/settle under gravity + inertia from the head/body motion).
# Attach as a child of the hair GLB instance; it finds the HairRig Skeleton3D.

@export var stiffness := 0.030     # pull back toward rest (lower = more lag/swing)
@export var drag := 0.10           # velocity damping (lower = more overshoot/bounce)
@export var gravity := 0.022       # downward settle per step (more = hangs down, not out)
@export var comb_back := 0.012     # gentle back-bias only (just keep hair off the face). Higher
                                   # values swept the hair into a stiff 'hairsprayed' back-comb.
@export var comb_back_sign := -1.0 # head +Z is the face dir for this rig → back = -Z
@export var root_bone := "HR0"     # rigid root (not simulated)

var skel: Skeleton3D
var joints: Array = []             # each: {idx, parent, axis(Vector3 local), length, init_rot(Quaternion), tail(V3), prev(V3)}
var GRAV := Vector3(0, -1, 0)
var _ready_ok := false

# body collision: spheres sampled from the body skeleton each step so the hair
# can't pass through the head / neck / torso / shoulders as the body animates.
var body_skel: Skeleton3D
var colliders: Array = []          # each: {idx:int, r:float, fwd:float} (fwd = push centre forward along face dir)
var head_idx := -1

func setup(s: Skeleton3D) -> void:
	skel = s
	_build()

# Call after setup() with the BODY skeleton; builds collider spheres from named bones.
func set_body_colliders(bskel: Skeleton3D) -> void:
	body_skel = bskel
	colliders.clear()
	if bskel == null: return
	head_idx = bskel.find_bone("mixamorig_Head")
	# (bone, radius_m, fwd_offset_m) — coarse capsule-of-spheres for head + upper body.
	# fwd_offset shifts the sphere toward the FACE so the front of the head is covered too
	# (keeps hair from sinking into / curtaining over the face).
	var spec := [
		["mixamorig_Head", 0.105, 0.0], ["mixamorig_Head", 0.110, 0.060],  # skull + big face-shield bulge
		["mixamorig_Neck", 0.066, 0.0], ["mixamorig_Neck", 0.070, 0.050],  # neck + front-of-neck
		# torso: spine spheres PLUS forward-offset spheres so the hair rests on the CHEST
		# surface (front of the torso) instead of sinking toward the spine centreline.
		["mixamorig_Spine2", 0.150, 0.0], ["mixamorig_Spine2", 0.130, 0.090],  # upper chest + front bulge
		["mixamorig_Spine1", 0.150, 0.0], ["mixamorig_Spine1", 0.130, 0.085],
		["mixamorig_Spine", 0.145, 0.0], ["mixamorig_Spine", 0.125, 0.075],
		# shoulders / clavicle / upper arms (hair draping over + behind the shoulders)
		["mixamorig_LeftShoulder", 0.095, 0.0], ["mixamorig_RightShoulder", 0.095, 0.0],
		["mixamorig_LeftArm", 0.095, 0.0], ["mixamorig_RightArm", 0.095, 0.0],
	]
	for s in spec:
		var bi: int = bskel.find_bone(s[0])
		if bi >= 0:
			colliders.append({"idx": bi, "r": float(s[1]), "fwd": float(s[2])})

func _face_dir() -> Vector3:
	# head's forward (face) direction in world; back = comb_back_sign * this.
	if body_skel == null or head_idx < 0:
		return Vector3(0, 0, 1)
	return (body_skel.global_transform * body_skel.get_bone_global_pose(head_idx)).basis.z.normalized()

func _resolve_collisions(head_w: Vector3, tail: Vector3, length: float) -> Vector3:
	if body_skel == null or colliders.is_empty():
		return tail
	var fdir: Vector3 = _face_dir()
	for c in colliders:
		var ctr: Vector3 = (body_skel.global_transform * body_skel.get_bone_global_pose(c["idx"])).origin
		if c["fwd"] != 0.0:
			ctr += fdir * (comb_back_sign * -1.0) * float(c["fwd"])  # shift toward the face
		var r: float = c["r"]
		var d: Vector3 = tail - ctr
		var dist: float = d.length()
		if dist < r and dist > 0.00001:
			tail = ctr + d / dist * r                 # push tail to sphere surface
	# keep the strand roughly its rest length from the head after pushing out
	return head_w + (tail - head_w).normalized() * length

func _build() -> void:
	if skel == null: return
	# collect the chain bones in parent->child order (HR0..HRn)
	var order: Array[int] = []
	for i in range(skel.get_bone_count()):
		if skel.get_bone_name(i).begins_with("HR"):
			order.append(i)
	order.sort_custom(func(a, b): return skel.get_bone_name(a) < skel.get_bone_name(b))
	for bi in order:
		if skel.get_bone_name(bi) == root_bone:
			continue   # rigid root, not simulated
		var parent := skel.get_bone_parent(bi)
		# child (for tail axis/length): the next HR bone whose parent is bi
		var child := -1
		for cj in order:
			if skel.get_bone_parent(cj) == bi:
				child = cj; break
		var axis: Vector3
		var length: float
		if child >= 0:
			var off := skel.get_bone_rest(child).origin
			length = off.length()
			axis = off.normalized()
		else:
			var off2 := skel.get_bone_rest(bi).origin
			length = max(0.08, off2.length())
			axis = off2.normalized()
		var init_rot := skel.get_bone_rest(bi).basis.get_rotation_quaternion()
		var parent_g: Transform3D = skel.global_transform * skel.get_bone_global_pose(parent)
		var head_w: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bi)).origin
		var rest_world: Basis = parent_g.basis * Basis(init_rot)
		var tail0: Vector3 = head_w + (rest_world * axis) * length
		joints.append({"idx": bi, "parent": parent, "axis": axis, "length": length,
			"init_rot": init_rot, "tail": tail0, "prev": tail0})
	_ready_ok = joints.size() > 0


func step(delta: float) -> void:
	if not _ready_ok: return
	var dscale := clampf(delta * 60.0, 0.5, 2.0)   # normalize to ~60Hz
	for j in joints:
		var bi: int = j["idx"]
		var parent_g: Transform3D = skel.global_transform * skel.get_bone_global_pose(j["parent"])
		var head_w: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bi)).origin
		var rest_world: Basis = parent_g.basis * Basis(j["init_rot"])
		var rest_dir: Vector3 = (rest_world * (j["axis"] as Vector3)).normalized()
		var length: float = j["length"]
		# verlet integrate the tail (+ gentle comb-back so hair doesn't curtain the face)
		var back: Vector3 = _face_dir() * comb_back_sign
		var inertia: Vector3 = (j["tail"] - j["prev"]) * (1.0 - drag)
		var next_tail: Vector3 = j["tail"] + inertia + rest_dir * (stiffness * dscale) \
			+ GRAV * (gravity * dscale) + back * (comb_back * dscale)
		next_tail = head_w + (next_tail - head_w).normalized() * length
		next_tail = _resolve_collisions(head_w, next_tail, length)   # push out of body
		j["prev"] = j["tail"]
		j["tail"] = next_tail
		# rotation aligning rest_dir -> actual tail dir, applied to the rest world basis
		var to_dir: Vector3 = (next_tail - head_w).normalized()
		var q := Quaternion(rest_dir, to_dir)
		var new_world: Basis = Basis(q) * rest_world
		var new_local: Basis = parent_g.basis.inverse() * new_world
		skel.set_bone_pose_rotation(bi, new_local.get_rotation_quaternion().normalized())
