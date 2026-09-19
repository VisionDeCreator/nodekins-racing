class_name KartPartsAssembler
extends RefCounted
## Shared by menu previews and race visuals; changes mesh children only.
const LIBRARY: CustomizationLibrary = preload("res://resources/customization/library.tres")

static func apply(assembly: Node3D, profile: CustomizationProfile, glider_socket: Node3D = null) -> Dictionary:
	var fitted: Dictionary = {}
	if not LIBRARY.accepts(profile):
		return fitted
	for slot: CustomizationSlot in LIBRARY.kart.slots:
		if slot.is_palette:
			continue
		var definition: CustomizationPart = slot.entry(int(profile.get(slot.field)))
		var source_root: Node = definition.asset.instantiate()
		var source: MeshInstance3D = source_root.find_child(String(definition.mesh_name),true,false) as MeshInstance3D
		var material: ShaderMaterial = LIBRARY.make_material(definition,profile)
		var instances: Array[MeshInstance3D] = []
		for socket_name: String in slot.sockets:
			var socket: Node3D = glider_socket if socket_name == "socket_glider" and glider_socket != null else assembly.get_node(socket_name) as Node3D
			for child: Node in socket.get_children():
				if child is MeshInstance3D:
					socket.remove_child(child)
					child.queue_free()
			var mesh := MeshInstance3D.new()
			mesh.name = definition.mesh_name
			mesh.mesh = source.mesh
			mesh.transform = source.transform
			mesh.material_override = material
			socket.add_child(mesh)
			instances.append(mesh)
		fitted[slot.field] = instances
		source_root.free()
	return fitted
