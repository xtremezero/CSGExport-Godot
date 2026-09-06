@tool
extends EditorPlugin

var button_csg = Button.new()
var object_name = ""
var obj: CSGShape3D = null

var objcont = "" # .obj content
var matcont = "" # .mtl content
var fdialog: FileDialog


func _enter_tree() -> void:
	if get_editor_interface() and get_editor_interface().get_selection():
		get_editor_interface().get_selection().selection_changed.connect(_selectionchanged)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, button_csg)
	button_csg.text = "Export CSGMesh to .obj"
	button_csg.pressed.connect(_on_csg_pressed)


func _exit_tree() -> void:
	if button_csg:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, button_csg)
		button_csg.queue_free()
	if get_editor_interface() and get_editor_interface().get_selection():
		if get_editor_interface().get_selection().selection_changed.is_connected(_selectionchanged):
			get_editor_interface().get_selection().selection_changed.disconnect(_selectionchanged)


func _selectionchanged() -> void:
	var selected = get_editor_interface().get_selection().get_selected_nodes()
	if selected.size() == 1:
		if selected[0] is CSGShape3D:
			object_name = selected[0].name
			obj = selected[0] as CSGShape3D
			button_csg.visible = true
		else:
			button_csg.visible = false
	else:
		button_csg.visible = false


func _handles(object: Object) -> bool:
	return object is CSGShape3D


func _on_csg_pressed() -> void:
	exportcsg()


func _get_target_mesh(target_csg: CSGShape3D) -> Mesh:
	if target_csg == null:
		return null
		
	# 1. Resolve root CSG shape in hierarchy if target is a child shape
	var root_csg = target_csg
	while root_csg.get_parent() is CSGShape3D:
		root_csg = root_csg.get_parent() as CSGShape3D
		
	# 2. Try get_meshes() on target shape or root shape
	var meshes = target_csg.get_meshes()
	if meshes.size() < 2 and root_csg != target_csg:
		meshes = root_csg.get_meshes()
		
	if meshes.size() >= 2:
		if meshes[1] is Mesh:
			return meshes[1] as Mesh
		elif meshes[-1] is Mesh:
			return meshes[-1] as Mesh
			
	# 3. Fallback to bake_static_mesh() if available
	if target_csg.has_method("bake_static_mesh"):
		var baked = target_csg.bake_static_mesh()
		if baked != null and baked is Mesh and baked.get_surface_count() > 0:
			return baked
			
	if root_csg != target_csg and root_csg.has_method("bake_static_mesh"):
		var baked_root = root_csg.bake_static_mesh()
		if baked_root != null and baked_root is Mesh and baked_root.get_surface_count() > 0:
			return baked_root
			
	return null


func exportcsg() -> void:
	if obj == null:
		return
		
	objcont = ""
	matcont = ""
	var mesh: Mesh = _get_target_mesh(obj)
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("No mesh data found on selected CSG node or its parent CSG hierarchy.")
		return

	var vertcount = 0

	# OBJ Headers
	objcont += "mtllib " + object_name + ".mtl\n"
	objcont += "o " + object_name + "\n"

	# Blank material fallback
	var blank_material = StandardMaterial3D.new()
	blank_material.resource_name = "BlankMaterial"

	# Get surfaces and mesh info
	for t in range(mesh.get_surface_count()):
		var surface = mesh.surface_get_arrays(t)
		if surface.is_empty():
			continue
			
		var verts = surface[Mesh.ARRAY_VERTEX]
		var normals = surface[Mesh.ARRAY_NORMAL] if surface.size() > Mesh.ARRAY_NORMAL else null
		var UVs = surface[Mesh.ARRAY_TEX_UV] if surface.size() > Mesh.ARRAY_TEX_UV else null
		var mat = mesh.surface_get_material(t)
		var faces = []

		# create_faces_from_verts (Triangles)
		var tempv = 0
		for v in range(verts.size()):
			if tempv % 3 == 0:
				faces.append([])
			faces[-1].append(v + 1)
			tempv += 1
			tempv = tempv % 3

		# add vertices
		var tempvcount = 0
		for ver in verts:
			objcont += str("v ", ver.x, ' ', ver.y, ' ', ver.z) + "\n"
			tempvcount += 1

		# add UVs
		if UVs != null:
			for uv in UVs:
				objcont += str("vt ", uv.x, ' ', uv.y) + "\n"
				
		# add Normals
		if normals != null:
			for norm in normals:
				objcont += str("vn ", norm.x, ' ', norm.y, ' ', norm.z) + "\n"

		# add groups and materials
		objcont += "g surface" + str(t) + "\n"

		if mat == null:
			mat = blank_material

		objcont += "usemtl " + str(mat.resource_name if mat.resource_name != "" else mat) + "\n"

		# add faces
		for face in faces:
			var idx0 = face[0] + vertcount
			var idx1 = face[1] + vertcount
			var idx2 = face[2] + vertcount
			if UVs != null and normals != null:
				objcont += str("f ", idx2, "/", idx2, "/", idx2, ' ', idx1, "/", idx1, "/", idx1, ' ', idx0, "/", idx0, "/", idx0) + "\n"
			elif UVs != null:
				objcont += str("f ", idx2, "/", idx2, ' ', idx1, "/", idx1, ' ', idx0, "/", idx0) + "\n"
			elif normals != null:
				objcont += str("f ", idx2, "//", idx2, ' ', idx1, "//", idx1, ' ', idx0, "//", idx0) + "\n"
			else:
				objcont += str("f ", idx2, ' ', idx1, ' ', idx0) + "\n"

		# update verts
		vertcount += tempvcount

		# create Materials for current surface
		var mat_name = mat.resource_name if mat.resource_name != "" else str(mat)
		matcont += str("newmtl ", mat_name) + '\n'
		if mat is BaseMaterial3D:
			var base_mat = mat as BaseMaterial3D
			matcont += str("Kd ", base_mat.albedo_color.r, " ", base_mat.albedo_color.g, " ", base_mat.albedo_color.b) + '\n'
			if base_mat.emission_enabled:
				matcont += str("Ke ", base_mat.emission.r, " ", base_mat.emission.g, " ", base_mat.emission.b) + '\n'
			else:
				matcont += "Ke 0 0 0\n"
			matcont += str("d ", base_mat.albedo_color.a) + "\n"
		else:
			matcont += "Kd 1 1 1\nKe 0 0 0\nd 1\n"

	# Select file destination
	fdialog = FileDialog.new()
	fdialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fdialog.access = FileDialog.ACCESS_RESOURCES
	fdialog.show_hidden_files = false
	fdialog.title = "Export CSGMesh"
	fdialog.size = Vector2i(700, 450)

	get_editor_interface().get_base_control().add_child(fdialog)
	fdialog.dir_selected.connect(onFileDialogOK)
	fdialog.popup_centered()


func onFileDialogOK(path: String) -> void:
	var objfile = FileAccess.open(path + "/" + object_name + ".obj", FileAccess.WRITE)
	if objfile:
		objfile.store_string(objcont)

	var mtlfile = FileAccess.open(path + "/" + object_name + ".mtl", FileAccess.WRITE)
	if mtlfile:
		mtlfile.store_string(matcont)

	print("CSG Mesh Exported: ", path + "/" + object_name + ".obj")
	get_editor_interface().get_resource_filesystem().scan()
	if fdialog:
		fdialog.queue_free()
