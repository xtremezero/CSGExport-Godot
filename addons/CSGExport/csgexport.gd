@tool
extends EditorPlugin

var button_csg: Button = Button.new()
var object_name: String = ""
var obj: CSGShape3D = null

var objcont: String = ""
var matcont: String = ""
var fdialog: FileDialog = null
var checkbox_textures: CheckBox = null


func _enter_tree() -> void:
	if get_editor_interface() and get_editor_interface().get_selection():
		get_editor_interface().get_selection().selection_changed.connect(_selectionchanged)

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, button_csg)
	button_csg.text = "Export CSGMesh to .obj"
	button_csg.visible = false
	button_csg.pressed.connect(_on_csg_pressed)

	fdialog = FileDialog.new()
	fdialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fdialog.access = FileDialog.ACCESS_FILESYSTEM
	fdialog.show_hidden_files = false
	fdialog.title = "Export CSGMesh to .OBJ"
	fdialog.size = Vector2i(700, 480)

	checkbox_textures = CheckBox.new()
	checkbox_textures.text = "Export Material Textures (.png)"
	checkbox_textures.button_pressed = true
	fdialog.get_vbox().add_child(checkbox_textures)

	fdialog.dir_selected.connect(onFileDialogOK)
	get_editor_interface().get_base_control().add_child(fdialog)

	_selectionchanged()


func _exit_tree() -> void:
	if button_csg:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, button_csg)
		button_csg.queue_free()
	if fdialog:
		fdialog.queue_free()
	if get_editor_interface() and get_editor_interface().get_selection():
		if get_editor_interface().get_selection().selection_changed.is_connected(_selectionchanged):
			get_editor_interface().get_selection().selection_changed.disconnect(_selectionchanged)


func _selectionchanged() -> void:
	var selected = get_editor_interface().get_selection().get_selected_nodes()
	if selected.size() == 1 and selected[0] is CSGShape3D:
		object_name = selected[0].name
		obj = selected[0] as CSGShape3D
		button_csg.visible = true
	else:
		obj = null
		button_csg.visible = false


func _handles(object: Object) -> bool:
	return object is CSGShape3D


func _on_csg_pressed() -> void:
	if obj == null:
		return
	if fdialog:
		fdialog.popup_centered()


func _sanitize_name(p_name: String) -> String:
	var s = p_name.strip_edges()
	if s.is_empty() or s.begins_with("<"):
		return "Material"
	var clean = ""
	for i in range(s.length()):
		var c = s[i]
		if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-':
			clean += c
		else:
			clean += "_"
	return clean if not clean.is_empty() else "Material"


func _get_target_mesh(target_csg: CSGShape3D) -> Mesh:
	if target_csg == null:
		return null

	var root_csg = target_csg
	while root_csg.get_parent() is CSGShape3D:
		root_csg = root_csg.get_parent() as CSGShape3D

	var meshes = target_csg.get_meshes()
	if meshes.size() < 2 and root_csg != target_csg:
		meshes = root_csg.get_meshes()

	if meshes.size() >= 2:
		for idx in range(1, meshes.size(), 2):
			if meshes[idx] is Mesh:
				return meshes[idx] as Mesh

	if target_csg.has_method("bake_static_mesh"):
		var baked = target_csg.bake_static_mesh()
		if baked != null and baked is Mesh and baked.get_surface_count() > 0:
			return baked

	if root_csg != target_csg and root_csg.has_method("bake_static_mesh"):
		var baked_root = root_csg.bake_static_mesh()
		if baked_root != null and baked_root is Mesh and baked_root.get_surface_count() > 0:
			return baked_root

	return null


func _resolve_material(mesh: Mesh, surface_idx: int, target_csg: CSGShape3D) -> Material:
	var mat = mesh.surface_get_material(surface_idx)
	if mat != null:
		return mat

	if target_csg != null:
		if target_csg.material_override != null:
			return target_csg.material_override
		if target_csg.material != null:
			return target_csg.material

		var root = target_csg
		while root.get_parent() is CSGShape3D:
			root = root.get_parent() as CSGShape3D
		var found = _find_material_in_csg_tree(root, surface_idx)
		if found != null:
			return found

	return null


func _find_material_in_csg_tree(node: Node, target_idx: int) -> Material:
	var current_idx = 0
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var current = stack.pop_back()
		if current is CSGShape3D:
			var csg = current as CSGShape3D
			var m = csg.material_override if csg.material_override != null else csg.material
			if m != null:
				if current_idx == target_idx:
					return m
				current_idx += 1
		for child in current.get_children():
			stack.push_back(child)
	return null


func _export_texture(tex: Texture2D, dest_dir: String, prefix: String) -> String:
	if tex == null:
		return ""

	var tex_name = ""
	if not tex.resource_path.is_empty():
		tex_name = tex.resource_path.get_file().get_basename()
	elif not tex.resource_name.is_empty():
		tex_name = tex.resource_name

	if tex_name.is_empty():
		tex_name = prefix + "_" + str(tex.get_instance_id())

	tex_name = _sanitize_name(tex_name) + ".png"
	var dest_file_path = dest_dir.path_join(tex_name)

	var img: Image = tex.get_image()
	if img != null and not img.is_empty():
		var export_img = img.duplicate()
		if export_img.is_compressed():
			export_img.decompress()
		var err = export_img.save_png(dest_file_path)
		if err == OK:
			return tex_name

	return ""


func _build_mtl_entry(mat: Material, mat_name: String, dest_dir: String, p_export_textures: bool) -> String:
	var entry = "newmtl " + mat_name + "\n"
	if mat is BaseMaterial3D:
		var bmat = mat as BaseMaterial3D
		var col = bmat.albedo_color
		entry += str("Kd ", col.r, " ", col.g, " ", col.b, "\n")
		if bmat.emission_enabled:
			var em = bmat.emission * bmat.emission_energy_multiplier
			entry += str("Ke ", em.r, " ", em.g, " ", em.b, "\n")
		else:
			entry += "Ke 0 0 0\n"
		entry += str("d ", col.a, "\n")

		if p_export_textures:
			# Export Albedo Texture
			if bmat.albedo_texture != null:
				var map_file = _export_texture(bmat.albedo_texture, dest_dir, mat_name + "_albedo")
				if not map_file.is_empty():
					entry += str("map_Kd ", map_file, "\n")

			# Export Emission Texture
			if bmat.emission_enabled and bmat.emission_texture != null:
				var map_file = _export_texture(bmat.emission_texture, dest_dir, mat_name + "_emission")
				if not map_file.is_empty():
					entry += str("map_Ke ", map_file, "\n")

			# Export Normal Map
			if bmat.normal_enabled and bmat.normal_texture != null:
				var map_file = _export_texture(bmat.normal_texture, dest_dir, mat_name + "_normal")
				if not map_file.is_empty():
					entry += str("map_Bump ", map_file, "\n")

			# Export Roughness Map
			if bmat.roughness_texture != null:
				var map_file = _export_texture(bmat.roughness_texture, dest_dir, mat_name + "_roughness")
				if not map_file.is_empty():
					entry += str("map_Pr ", map_file, "\n")

			# Export Metallic Map
			if bmat.metallic_texture != null:
				var map_file = _export_texture(bmat.metallic_texture, dest_dir, mat_name + "_metallic")
				if not map_file.is_empty():
					entry += str("map_Pm ", map_file, "\n")

	elif mat is ShaderMaterial:
		var smat = mat as ShaderMaterial
		var col = Color(0.75, 0.75, 0.75, 1.0)
		for p in ["albedo", "albedo_color", "color", "base_color", "tint"]:
			var param = smat.get_shader_parameter(p)
			if param is Color:
				col = param
				break
		entry += str("Kd ", col.r, " ", col.g, " ", col.b, "\n")
		entry += "Ke 0 0 0\n"
		entry += str("d ", col.a, "\n")

		if p_export_textures:
			for tex_param in ["albedo_texture", "texture_albedo", "main_texture", "tex"]:
				var tex_param_val = smat.get_shader_parameter(tex_param)
				if tex_param_val is Texture2D:
					var map_file = _export_texture(tex_param_val as Texture2D, dest_dir, mat_name + "_albedo")
					if not map_file.is_empty():
						entry += str("map_Kd ", map_file, "\n")
					break
	else:
		entry += "Kd 1 1 1\nKe 0 0 0\nd 1\n"

	return entry


func exportcsg(dest_dir: String) -> void:
	if obj == null:
		return

	var export_textures: bool = checkbox_textures.button_pressed if checkbox_textures != null else true

	objcont = ""
	matcont = ""
	var mesh: Mesh = _get_target_mesh(obj)
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("CSGExport: No mesh data found on selected CSG node or parent hierarchy.")
		return

	var vert_offset := 0
	var uv_offset := 0
	var normal_offset := 0

	var mat_instance_map: Dictionary = {}
	var exported_mat_names: Dictionary = {}
	var fallback_material_count := 0

	var default_material = StandardMaterial3D.new()
	default_material.resource_name = "Default_Material"
	default_material.albedo_color = Color(0.75, 0.75, 0.75, 1.0)

	var safe_obj_name = _sanitize_name(object_name)
	if safe_obj_name.is_empty():
		safe_obj_name = "CSGMesh"

	# OBJ Header
	objcont += "mtllib " + safe_obj_name + ".mtl\n"
	objcont += "o " + safe_obj_name + "\n"

	# Iterate over surfaces
	for t in range(mesh.get_surface_count()):
		var surface = mesh.surface_get_arrays(t)
		if surface.is_empty():
			continue

		var verts = surface[Mesh.ARRAY_VERTEX] if surface.size() > Mesh.ARRAY_VERTEX else null
		if verts == null or verts.size() == 0:
			continue

		var normals = surface[Mesh.ARRAY_NORMAL] if surface.size() > Mesh.ARRAY_NORMAL else null
		var UVs = surface[Mesh.ARRAY_TEX_UV] if surface.size() > Mesh.ARRAY_TEX_UV else null
		var indices = surface[Mesh.ARRAY_INDEX] if surface.size() > Mesh.ARRAY_INDEX else null

		var mat = _resolve_material(mesh, t, obj)
		if mat == null:
			mat = default_material

		# Output vertices
		for ver in verts:
			objcont += str("v ", ver.x, " ", ver.y, " ", ver.z, "\n")

		# Output UVs
		if UVs != null:
			for uv in UVs:
				objcont += str("vt ", uv.x, " ", uv.y, "\n")

		# Output Normals
		if normals != null:
			for norm in normals:
				objcont += str("vn ", norm.x, " ", norm.y, " ", norm.z, "\n")

		# Group header
		objcont += "g surface" + str(t) + "\n"

		# Resolve material name & write MTL
		var instance_id = mat.get_instance_id()
		var mat_name = ""

		if mat_instance_map.has(instance_id):
			mat_name = mat_instance_map[instance_id]
		else:
			var base_name = mat.resource_name
			if base_name.is_empty():
				fallback_material_count += 1
				base_name = "Material_" + str(fallback_material_count)
			var clean = _sanitize_name(base_name)
			mat_name = clean
			var dup_counter = 1
			while exported_mat_names.has(mat_name):
				dup_counter += 1
				mat_name = clean + "_" + str(dup_counter)
			mat_instance_map[instance_id] = mat_name
			exported_mat_names[mat_name] = true
			matcont += _build_mtl_entry(mat, mat_name, dest_dir, export_textures)

		objcont += "usemtl " + mat_name + "\n"

		# Build triangle face indices (reversed winding order for standard OBJ orientation)
		var triangles: Array = []
		if indices != null and indices.size() > 0:
			for i in range(0, indices.size() - 2, 3):
				triangles.append([indices[i + 2], indices[i + 1], indices[i]])
		else:
			for i in range(0, verts.size() - 2, 3):
				triangles.append([i + 2, i + 1, i])

		# Output face lines
		for tri in triangles:
			var v0 = tri[0] + 1 + vert_offset
			var v1 = tri[1] + 1 + vert_offset
			var v2 = tri[2] + 1 + vert_offset

			if UVs != null and normals != null:
				var vt0 = tri[0] + 1 + uv_offset
				var vt1 = tri[1] + 1 + uv_offset
				var vt2 = tri[2] + 1 + uv_offset
				var vn0 = tri[0] + 1 + normal_offset
				var vn1 = tri[1] + 1 + normal_offset
				var vn2 = tri[2] + 1 + normal_offset
				objcont += str("f ", v0, "/", vt0, "/", vn0, " ", v1, "/", vt1, "/", vn1, " ", v2, "/", vt2, "/", vn2, "\n")
			elif UVs != null:
				var vt0 = tri[0] + 1 + uv_offset
				var vt1 = tri[1] + 1 + uv_offset
				var vt2 = tri[2] + 1 + uv_offset
				objcont += str("f ", v0, "/", vt0, " ", v1, "/", vt1, " ", v2, "/", vt2, "\n")
			elif normals != null:
				var vn0 = tri[0] + 1 + normal_offset
				var vn1 = tri[1] + 1 + normal_offset
				var vn2 = tri[2] + 1 + normal_offset
				objcont += str("f ", v0, "//", vn0, " ", v1, "//", vn1, " ", v2, "//", vn2, "\n")
			else:
				objcont += str("f ", v0, " ", v1, " ", v2, "\n")

		# Accumulate offsets for next surface
		vert_offset += verts.size()
		if UVs != null:
			uv_offset += UVs.size()
		if normals != null:
			normal_offset += normals.size()

	var safe_name = _sanitize_name(object_name)
	if safe_name.is_empty():
		safe_name = "CSGMesh"

	var obj_path = dest_dir.path_join(safe_name + ".obj")
	var mtl_path = dest_dir.path_join(safe_name + ".mtl")

	var objfile = FileAccess.open(obj_path, FileAccess.WRITE)
	if objfile:
		objfile.store_string(objcont)

	var mtlfile = FileAccess.open(mtl_path, FileAccess.WRITE)
	if mtlfile:
		mtlfile.store_string(matcont)

	print("CSG Mesh exported successfully to: ", obj_path)
	get_editor_interface().get_resource_filesystem().scan()


func onFileDialogOK(path: String) -> void:
	exportcsg(path)
