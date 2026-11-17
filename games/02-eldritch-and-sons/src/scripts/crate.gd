## crate.gd : a delivery box full of one product. Pick it up, carry it to a shelf, stock it.
class_name Crate
extends Node3D

var product := ""
var units := 0
var body: StaticBody3D
var tag: Label3D
var mesh: MeshInstance3D

func build(id: String, n: int) -> void:
	product = id
	units = n
	var beyond: bool = Products.info(id).get("beyond", false)
	var mat: Material = Vox.art_mat("cardboard", 1.8) if not beyond else Vox.obj_mat(Color(0.25, 0.12, 0.3))
	var model := Products.model("props/crate")
	if model and not beyond:
		add_child(model)
		Products.fit_model(model, Vector3(0.6, 0.5, 0.5), false)
	else:
		mesh = Vox.box(self, Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.5), mat, false)
	# a product-coloured stripe so you can tell boxes apart at a glance
	Vox.box(self, Vector3(0, 0.25, 0.262), Vector3(0.6, 0.12, 0.01), Vox.obj_mat(Products.info(id)["color"]), false)
	body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.5, 0.5)
	cs.shape = shape
	cs.position = Vector3(0, 0.25, 0)
	body.add_child(cs)
	body.set_meta("interact", self)
	add_child(body)
	tag = Vox.label(self, "", Vector3(0, 0.62, 0), 32, Color(1, 0.95, 0.8), true)
	refresh()

func refresh() -> void:
	tag.text = "%s x%d" % [Products.pname(product), units]

func set_held(h: bool) -> void:
	body.process_mode = Node.PROCESS_MODE_DISABLED if h else Node.PROCESS_MODE_INHERIT
	body.collision_layer = 0 if h else 1
	tag.visible = not h

func prompt(game) -> String:
	if game.player.held != null: return ""
	return "[E] Pick up %s x%d" % [Products.pname(product), units]

func use(game) -> void:
	if game.player.held == null:
		game.player.pick_up(self)
