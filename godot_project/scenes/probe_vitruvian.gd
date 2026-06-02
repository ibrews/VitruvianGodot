extends SceneTree

# Headless probe: load vitruvian_head.glb, dump mesh instances, surface count,
# per-surface material names, AABB, and which UV layers exist.
# Usage: Godot --headless --import ; then --script scenes/probe_vitruvian.gd --path godot_project

func _init() -> void:
	var scene: PackedScene = load("res://vitruvian_head.glb")
	if scene == null:
		printerr("[probe_vit] FAIL: could not load res://vitruvian_head.glb")
		quit(1)
		return
	var root: Node = scene.instantiate()
	print("[probe_vit] root: ", root.name, " (", root.get_class(), ")")
	_walk(root, 0)
	quit(0)

func _walk(node: Node, depth: int) -> void:
	var indent: String = "  ".repeat(depth)
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mesh: Mesh = mi.mesh
		var ns: int = mesh.get_surface_count() if mesh != null else 0
		print("%s%s (MeshInstance3D) surfaces=%d aabb=%s" % [indent, node.name, ns, str(mi.get_aabb())])
		for s in range(ns):
			var m: Material = mesh.surface_get_material(s)
			var mname: String = m.resource_name if m else "<none>"
			if m is BaseMaterial3D:
				mname += " [albedo=%s]" % str((m as BaseMaterial3D).albedo_color)
			print("%s  surf %d -> %s" % [indent, s, mname])
	else:
		print("%s%s (%s)" % [indent, node.name, node.get_class()])
	for child in node.get_children():
		_walk(child, depth + 1)
