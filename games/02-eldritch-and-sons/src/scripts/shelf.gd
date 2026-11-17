## shelf.gd : a wooden shelf unit holding one product type (up to CAPACITY units).
## Built facing +Z locally; customers stand at front_point(). Interactable: stock it with a crate.
class_name Shelf
extends Node3D

const CAPACITY := 12
var product := ""
var count := 0
var items_node: Node3D
var sign_label: Label3D
var index := 0
var highlight := false
var _hl_t := 0.0

func build(idx: int) -> void:
	index = idx
	var wood := Vox.obj_mat(Color(0.42, 0.28, 0.16))
	var dark := Vox.obj_mat(Color(0.3, 0.2, 0.12))
	# frame: two sides, back, three boards
	Vox.box(self, Vector3(-0.97, 1.1, 0), Vector3(0.06, 2.2, 0.6), dark, false)
	Vox.box(self, Vector3(0.97, 1.1, 0), Vector3(0.06, 2.2, 0.6), dark, false)
	Vox.box(self, Vector3(0, 1.1, -0.27), Vector3(2.0, 2.2, 0.06), wood, false)
	for i in 3:
		Vox.box(self, Vector3(0, 0.15 + i * 0.7, 0), Vector3(1.94, 0.06, 0.58), wood, false)
	Vox.box(self, Vector3(0, 2.22, 0), Vector3(2.0, 0.06, 0.6), dark, false)
	# one collision box for the whole unit, tagged as interactable
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 2.25, 0.62)
	cs.shape = shape
	cs.position = Vector3(0, 1.12, 0)
	body.add_child(cs)
	body.set_meta("interact", self)
	add_child(body)
	items_node = Node3D.new()
	add_child(items_node)
	sign_label = Vox.label(self, "", Vector3(0, 2.38, 0.31), 40, Color(1, 0.92, 0.7))
	refresh()

func front_point() -> Vector3:
	return to_global(Vector3(0, 0, 1.15))

## lit up (by guide.gd) when you're carrying a box that belongs here
func set_highlight(on: bool) -> void:
	if on == highlight: return
	highlight = on
	_sign()

func _process(dt: float) -> void:
	if highlight:
		_hl_t += dt
		sign_label.modulate = Color(0.45, 1, 0.5).lerp(Color(0.85, 1, 0.85), 0.5 + 0.5 * sin(_hl_t * 6.0))

func _sign() -> void:
	if product == "":
		sign_label.text = "(empty shelf)"
		sign_label.modulate = Color(0.7, 0.7, 0.7)
	else:
		var info := Products.info(product)
		sign_label.text = "%s  $%d" % [info["name"], info["price"]]
		sign_label.modulate = Color(0.8, 0.6, 1.0) if info["beyond"] else Color(1, 0.92, 0.7)
	if highlight: sign_label.text += "\nSTOCK HERE"

## rebuilds the items; units from `pop_from` up pop in one by one (fresh stock)
func refresh(pop_from := -1) -> void:
	for c in items_node.get_children(): c.queue_free()
	_sign()
	if product == "": return
	var info := Products.info(product)
	var col: Color = info["color"]
	for i in count:
		var before := items_node.get_child_count()
		var row := i / 4
		var colm := i % 4
		var pos := Vector3(-0.66 + colm * 0.44, 0.18 + row * 0.7 + 0.14, 0.02)
		var model := Products.model(product)
		if model:
			# a hand-made model, standing in its slot
			var holder := Node3D.new()
			holder.position = pos - Vector3(0, 0.14, 0)
			holder.rotation.y = sin(i * 2.3) * 0.25
			items_node.add_child(holder)
			holder.add_child(model)
			Products.fit_model(model, Vector3(0.38, 0.42, 0.3))
		elif Vox.art(product):
			# Tom's pixel art as a little standing card, Minecraft-item style
			var card := Vox.card(items_node, product, pos + Vector3(0, 0.03, 0.04), 0.36)
			card.rotation.y = sin(i * 2.3) * 0.12
		else:
			var it := Vox.box(items_node, pos, Vector3(0.26, 0.28, 0.26), Vox.obj_mat(col, product == "eyes" or product == "jar"), false)
			it.rotation.y = sin(i * 2.3) * 0.15
		if pop_from >= 0 and i >= pop_from and items_node.get_child_count() > before:
			var n: Node3D = items_node.get_child(items_node.get_child_count() - 1)
			var full := n.scale
			n.scale = full * 0.01
			var tw := n.create_tween()
			tw.tween_interval((i - pop_from) * 0.07)
			tw.tween_property(n, "scale", full * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(n, "scale", full, 0.08)

func take_one() -> bool:
	if count <= 0: return false
	count -= 1
	if count == 0: product = ""
	refresh()
	return true

func prompt(game) -> String:
	var held = game.player.held
	if held == null:
		return "" if product == "" else "%s  (%d/%d)" % [Products.pname(product), count, CAPACITY]
	if product != "" and product != held.product:
		return "Shelf holds %s - empty it first" % Products.pname(product)
	if count >= CAPACITY:
		return "Shelf is full"
	return "[E] Stock %s (%d in box)" % [Products.pname(held.product), held.units]

func use(game) -> void:
	var held = game.player.held
	if held == null: return
	if product != "" and product != held.product: return
	var moved := mini(held.units, CAPACITY - count)
	if moved <= 0: return
	var before := count
	product = held.product
	count += moved
	held.units -= moved
	refresh(before)
	Sfx.play("stock", 0.8)
	game.on_stocked(product, moved)
	if held.units <= 0:
		game.player.drop_empty()
	else:
		held.refresh()

## [R] clear a shelf so it can hold something else (items go back into a box)
func prompt_alt(game) -> String:
	if game.player.held == null and product != "": return "[R] Pack %s back into a box" % Products.pname(product)
	return ""

func use_alt(game) -> void:
	if game.player.held != null or product == "": return
	var c = game.spawn_crate(product, count, game.player.global_position + Vector3(0, 0.3, 0))
	product = ""
	count = 0
	refresh()
	game.player.pick_up(c)
