## guide.gd : "what should I do now?"
## Works out the current objective from the game state every frame (nothing is scripted, so it
## can never get stuck), shows it on the HUD, lights up the right shelf when you carry a box,
## and on the first two days floats a bouncing arrow over the thing to go to.
class_name Guide
extends Node3D

const TILL := Vector3(-4.6, 1.95, 2.05)
const CATALOGUE := Vector3(-3.5, 1.65, 2.0)
const BED := Vector3(-3.1, 1.3, -8.7)

var game
var marker: Node3D
var t := 0.0
var text := ""
var target = null              # Vector3 or null

func setup(g) -> void:
	game = g
	marker = Node3D.new()
	add_child(marker)
	var m := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.32, 0.36, 0.12)
	m.mesh = pm
	m.rotation.z = PI                      # point down
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.82, 0.35)
	mat.no_depth_test = true               # visible through walls, so you can always find it
	mat.render_priority = 10
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(m)
	marker.visible = false

func _process(dt: float) -> void:
	t += dt
	_work_out()
	var show: bool = target != null and game.day <= 2 and game.started and not game.ui.is_open() and not game.ending
	marker.visible = show
	if show:
		marker.global_position = (target as Vector3) + Vector3(0, 0.12 * sin(t * 4.0), 0)
		marker.rotation.y = t * 2.0
	# the shelf this box belongs on glows
	var held = game.player.held
	var best: Shelf = shelf_for(held.product) if held else null
	for s in game.world.shelves: s.set_highlight(s == best)

## the best shelf for a box of `id`: one already holding it (not full), else an empty one
func shelf_for(id: String) -> Shelf:
	for s in game.world.shelves:
		if s.product == id and s.count < Shelf.CAPACITY: return s
	for s in game.world.shelves:
		if s.product == "": return s
	return null

func crates() -> Array:
	var out := []
	for c in game.world.get_children():
		if c is Crate and c != game.player.held: out.append(c)
	return out

func _crate_for(id := "") -> Crate:
	var all := crates()
	if all.is_empty(): return null
	if id != "":
		for c in all:
			if c.product == id: return c
	# prefer a box that can go somewhere
	for c in all:
		if shelf_for(c.product) != null: return c
	return null

func _aim(txt: String, at = null) -> void:
	text = txt
	target = at

func _work_out() -> void:
	var g = game
	if g.night_walk:
		if g.flags.get("walk_seen", false): _aim("Go back to sleep.", BED)
		else: _aim("Someone is knocking. Go and look.", null)
		return
	if g.world.letter.visible:
		_aim("Read the letter on the doormat", g.world.letter.global_position + Vector3(0, 0.6, 0))
		return
	var held = g.player.held
	if held:
		var s := shelf_for(held.product)
		if s: _aim("Put the %s on the glowing shelf" % Products.pname(held.product), s.global_position + Vector3(0, 2.95, 0))
		else: _aim("No free shelf! [R] at a shelf packs its stock back into a box", null)
		return
	var front: Customer = g._front()
	if front:
		if front.kind == "landlord": _aim("Pay the Landlord at the till", TILL)
		elif front.kind == "returner": _aim("Mrs. Thorne wants a refund at the till", TILL)
		else: _aim("Serve %s at the till" % front.cname, TILL)
		return
	if g.minute >= g.CLOSE_MIN:
		if g.day == 5 and not g.flags.get("rent_paid", false):
			if g.money >= g.RENT: _aim("Wait for the Landlord. You have the $%d." % g.RENT, null)
			else: _aim("The Landlord is coming for $%d. You have $%d." % [g.RENT, g.money], null)
		elif g._inside_count() > 0: _aim("Wait for the last customers to leave", null)
		elif g.is_open: _aim("Closing time: flip the sign to CLOSED", g.world.sign_label.global_position + Vector3(0, 0.55, 0))
		else: _aim("Go to bed (back room)", BED)
		return
	# Mr. Whitlock at six
	var whitlock_coming: bool = g.minute >= 16 * 60 and not g.flags["whitlock_done"]
	if whitlock_coming and g.find_shelf("silence") == null:
		var c := _crate_for("silence")
		if c: _aim("Mr. Whitlock comes at six: shelve the Tinned Silence", c.global_position + Vector3(0, 1.05, 0))
		elif not _incoming("silence"): _aim("Mr. Whitlock comes at six: order Tinned Silence!", CATALOGUE)
		else: _aim("Mr. Whitlock comes at six. The Silence is on its way...", null)
		return
	# restock
	var low := false
	for s in g.world.shelves:
		if s.product == "" or s.count <= 3: low = true
	if low:
		var c := _crate_for()
		if c:
			_aim("Restock: carry the %s box to a shelf" % Products.pname(c.product), c.global_position + Vector3(0, 1.05, 0))
			return
	if not g.is_open:
		_aim("Flip the sign by the door to OPEN", g.world.sign_label.global_position + Vector3(0, 0.55, 0))
		return
	if low and g.deliveries.is_empty():
		_aim("Shelves are emptying: order stock from the catalogue", CATALOGUE)
		return
	if g.today["served"] == 0: _aim("Wait for customers. They pay at the till.", null)
	else: _aim("Keep the shelves stocked and the customers happy", null)

func _incoming(id: String) -> bool:
	for d in game.deliveries:
		if d["id"] == id: return true
	return false

## a short line about boxes on their way, for the HUD
func deliveries_text() -> String:
	if game.deliveries.is_empty(): return ""
	var parts := []
	for d in game.deliveries:
		var at: float = d["at"]
		if d["beyond"]: parts.append("%s (soon...)" % Products.pname(d["id"]))
		elif at >= 24 * 60: parts.append("%s (tomorrow)" % Products.pname(d["id"]))
		else: parts.append("%s ~%02d:%02d" % [Products.pname(d["id"]), int(at) / 60, int(at) % 60])
	return "Coming: " + ", ".join(parts)
