#This script is created by: mohammedzero43 (Xtremezero), please give credits if remixed or shared
#feel free to report bugs and suggest improvements at mohammedzero43@gmail.com

### Godot 4.x+
### To apply Collisions :
###		- Add the .obj into the scene
###		- Select the Instantiated Mesh
###		- Click the "Mesh" button in the editor top bar
###		- Generate static body trimesh collision
###		- Make sure you have the correct layers selected in :
###		- StaticBody3D > CollisionObject3D > Collision > Layer(object)/Mask(others)

@tool
extends EditorPlugin

var button_csg = Button.new()
var object_name = ""
var obj = null

var objcont = "" #.obj content
var matcont = "" #.mat content
var fdialog: FileDialog

func _enter_tree() -> void:
	get_editor_interface().get_selection().selection_changed.connect(_selectionchanged)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU,button_csg)
	button_csg.text = "Export CSGMesh to .obj"

func _ready() -> void:
	button_csg.pressed.connect(_on_csg_pressed)

func _exit_tree() -> void:
	button_csg.queue_free()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU,button_csg)

func _selectionchanged() -> void:
	var selected = get_editor_interface().get_selection().get_selected_nodes()
	if selected.size() == 1:

		if selected[0] is CSGCombiner3D:
			object_name= selected[0].name
			obj = selected[0]
			button_csg.visible = true
		else:
			button_csg.visible = false
	else:
		button_csg.visible = false

func handles(obj):
	if obj is CSGCombiner3D:
		return true

func _on_csg_pressed() -> void:
	exportcsg()

func exportcsg() -> void:
	#Variables
	objcont = "" #.obj content
	matcont = "" #.mat content
	var csgMesh= obj.get_meshes();
	var vertcount=0

	#OBJ Headers
	objcont+="mtllib "+object_name+".mtl\n"
	objcont+="o " + object_name + "\n";#CHANGE WITH SELECTION NAME";

	#Blank material
	var blank_material : StandardMaterial3D = StandardMaterial3D.new()
	blank_material.set_name("BlankMaterial")

	#Get surfaces and mesh info
	for t in range(csgMesh[-1].get_surface_count()):
		var surface = csgMesh[-1].surface_get_arrays(t)
		var verts = surface[0]
		var UVs = surface[4]
		var normals = surface[1]
		var mat : StandardMaterial3D = csgMesh[-1].surface_get_material(t)
		var faces = []

		#create_faces_from_verts (Triangles)
		var tempv=0
		for v in range(verts.size()):
			if tempv%3==0:
				faces.append([])
			faces[-1].append(v+1)
			tempv+=1
			tempv= tempv%3

		#add verticies
		var tempvcount =0
		for ver in verts:
			objcont+=str("v ",ver[0],' ',ver[1],' ',ver[2])+"\n"
			tempvcount +=1

		#add UVs
		for uv in UVs:
			objcont+=str("vt ",uv[0],' ',uv[1])+"\n"
		for norm in normals:
			objcont+=str("vn ",norm[0],' ',norm[1],' ',norm[2])+"\n"

		#add groups and materials
		objcont+="g surface"+str(t)+"\n"

		if mat == null:
			mat = blank_material

		objcont+="usemtl "+str(mat)+"\n"

		#add faces
		for face in faces:
			objcont+=str("f ", face[2]+vertcount,"/",face[2]+vertcount,"/",face[2]+vertcount,
			' ',face[1]+vertcount,"/",face[1]+vertcount,"/",face[1]+vertcount,
			' ',face[0]+vertcount,"/",face[0]+vertcount,"/",face[0]+vertcount)+"\n"
		#update verts
		vertcount+=tempvcount

		#create Materials for current surface
		matcont+=str("newmtl "+str(mat))+'\n'
		matcont+=str("Kd ",mat.albedo_color.r," ",mat.albedo_color.g," ",mat.albedo_color.b)+'\n'
		matcont+=str("Ke ",mat.emission.r," ",mat.emission.g," ",mat.emission.b)+'\n'
		matcont+=str("d ",mat.albedo_color.a)+"\n"

	#Select file destination
	fdialog = FileDialog.new()
	fdialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fdialog.access = FileDialog.ACCESS_RESOURCES
	# fdialog.add_filter("*.obj; Wavefront File")
	# fdialog.show_hidden_files = false # false is a default value, thus, we do not need to specify it
	fdialog.title = "Export CSGMesh"
	fdialog.name = "CSGExporter"

	# The next commented line allows the Engine to wait for a frame before instanciating -
	# - A new FileDialog instance. Doing this will prevent to have FileDialog named "CSGExporter2"
	# Since the previous instance will have time to be freed before the new one
	# However, this is not necessary and can be removed
	# await get_tree().process_frame
	get_editor_interface().get_editor_main_screen().add_child(fdialog, true)

	fdialog.dir_selected.connect(onFileDialogOK)
	fdialog.canceled.connect(onFileDialogCancel)
	fdialog.popup_centered(Vector2(720, 700))

func onFileDialogOK(path: String) -> void:
	#Write to files
	var objfile = FileAccess.open(path + "/" + object_name + ".obj", FileAccess.WRITE)
	objfile.store_string(objcont)
	objfile = null # godot 4.0 way to close, will flush automatically

	var mtlfile = FileAccess.open(path + "/" + object_name + ".mtl", FileAccess.WRITE)
	mtlfile.store_string(matcont)
	mtlfile = null # godot 4.0 way to close, will flush automatically

	#output message
	print("CSG Mesh Exported")
	get_editor_interface().get_resource_filesystem().scan()

	# Clear instantiated FileDialog "CSGExporter" and set fdialog to null
	free_other_exporter_instances()

# Clear instantiated FileDialog "CSGExporter" and set fdialog to null
func onFileDialogCancel() -> void:
	free_other_exporter_instances()

func free_other_exporter_instances() -> void:
	var editor_main_screen = get_editor_interface().get_editor_main_screen()
	for child in editor_main_screen.get_children():
		# Clunky way to check but works for now as we set the same of the FileDialog
		if "CSGExporter" in child.name:
			child.call_deferred("queue_free")

	# Clear fdialog reference
	fdialog = null
