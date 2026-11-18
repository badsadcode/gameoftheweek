## basement.gd : the trapdoor in the storeroom floor, and whatever lives under it.
## Padlocked until Thursday (or until a customer pays you with a warm iron key). Once open, you
## can visit once a day: the Thing Below is very polite and buys stock at silly prices.
## It asks for bread on Thursday. Future-you says don't. Grandpa's ghost says do. Grandpa is
## wrong exactly once all week.
class_name Basement
extends Node3D

const POS := Vector3(-1.5, 0.0, -7.2)
var game
var lid: Node3D
var hole: Node3D
var open_t := 0.0              # > 0 while the lid is up

func build(g) -> void:
	game = g
	position = POS
	var wood := Vox.mat("darkplanks", Color(0.8, 0.75, 0.7))
	var iron := Vox.obj_mat(Color(0.25, 0.25, 0.27))
	# the dark below (only shown while open)
	hole = Node3D.new()
	add_child(hole)
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0)
	Vox.box(hole, Vector3(0, 0.004, 0), Vector3(0.96, 0.004, 0.96), black, false)
	for x in [-0.08, 0.08]:
		Vox.box(hole, Vector3(x, 0.008, 0.1), Vector3(0.05, 0.004, 0.03), Vox.obj_mat(Color(0.8, 0.45, 1.0), true), false)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.2, 0)
	glow.light_color = Color(0.6, 0.3, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 2.5
	hole.add_child(glow)
	hole.visible = false
	# the lid, hinged on its back edge
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.01, -0.5)
	add_child(hinge)
	lid = hinge
	Vox.box(hinge, Vector3(0, 0.02, 0.5), Vector3(1.0, 0.04, 1.0), wood, false)
	Vox.box(hinge, Vector3(0, 0.05, 0.85), Vector3(0.18, 0.02, 0.04), iron, false)          # ring
	Vox.box(hinge, Vector3(0.3, 0.05, 0.95), Vector3(0.1, 0.06, 0.04), iron, false)          # hasp
	var padlock := Vox.box(hinge, Vector3(0.3, 0.07, 1.0), Vector3(0.09, 0.1, 0.05), Vox.obj_mat(Color(0.7, 0.55, 0.25)), false)
	padlock.name = "Padlock"
	# look-only collider (layer 2): you walk over it, but you can look at it
	var look := StaticBody3D.new()
	look.collision_layer = 2
	look.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 0.12, 1.0)
	cs.shape = sh
	cs.position = Vector3(0, 0.06, 0)
	look.add_child(cs)
	look.set_meta("interact", self)
	add_child(look)

var talking := false

func _process(_dt: float) -> void:
	var pl := lid.get_node_or_null("Padlock")
	if pl and game: pl.visible = not unlocked()
	# the lid shuts whenever the conversation ends (a button, or Esc)
	if talking and not game.ui.is_open():
		talking = false
		_close()

func unlocked() -> bool:
	return game.day >= 4 or game.flags.get("basement_unlocked", false)

func prompt(_g) -> String:
	if open_t > 0.0: return ""
	if not unlocked():
		if game.flags.get("items", []).has("key"): return "[E] Unlock the trapdoor with the warm key"
		return "A padlocked trapdoor. It's warm to the touch."
	if game.flags.get("below_day_%d" % game.day, false): return "Something below is resting. (Tomorrow.)"
	return "[E] Open the trapdoor"

func use(_g) -> void:
	if open_t > 0.0: return
	if not unlocked():
		if game.flags.get("items", []).has("key"):
			game.flags["basement_unlocked"] = true
			game.flags["items"].erase("key")
			Sfx.play("click", 0.9, 0.5)
			game.ui.toast("The key turns by itself the last half-turn.", UI.C_PURPLE, 5.0)
		else:
			Sfx.play("knock", 0.25, 0.5)
		return
	if game.flags.get("below_day_%d" % game.day, false): return
	game.flags["below_day_%d" % game.day] = true
	open_t = 0.01
	hole.visible = true
	Sfx.play("drone", 0.7, 0.6)
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", -1.9, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_talk)

func prompt_alt(_g) -> String:
	return ""

func use_alt(_g) -> void:
	pass

func _close() -> void:
	var tw := create_tween()
	tw.tween_property(lid, "rotation:x", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		Sfx.play("box", 0.9, 0.6)
		hole.visible = false
		open_t = 0.0)

## what it wants today
func _talk() -> void:
	var g = game
	var opts := []
	var body := ""
	var ask := ""
	var n := 0
	var price := 0
	if g.day == 4:
		ask = "bread"; n = 4; price = 9
		body = "Stairs go down further than the storeroom is tall. At the bottom, two lights blink slowly.\n\n\"Good evening, shopkeeper. How kind of you to visit. I wonder... do you have bread? I have heard so much about bread.\""
	elif g.day >= 5 and g.flags.get("items", []).has("photo"):
		body = "\"Shopkeeper. You have something of yours that isn't yours. A picture. I would like it very much.\""
		opts.append(["Give it the photograph (+15 sanity)", func():
			g.flags["items"].erase("photo")
			g.sanity = minf(100.0, g.sanity + 15.0)
			g.flags["below_photo"] = true
			g.ui.toast("It takes the photograph. You feel watched slightly less.", UI.C_PURPLE, 5.0)
			pass, UI.C_PURPLE])
	else:
		# something you actually have, at a silly price
		var best: Shelf = null
		for s in g.world.shelves:
			if s.product != "" and s.product != "bread" and s.count >= 3 and (best == null or s.count > best.count): best = s
		if best:
			ask = best.product; n = 3; price = int(Products.info(ask)["price"]) * 3
		body = "Two lights blink at the bottom of the stairs.\n\n\"Shopkeeper. What a pleasure. " + (("I would like some %s, if it isn't too much trouble.\"" % Products.pname(ask).to_lower()) if ask != "" else "I would buy something, but your shelves are so... empty. Another time.\"")
	if ask != "":
		var shelf: Shelf = g.find_shelf(ask)
		var have: int = shelf.count if shelf else 0
		var k: int = mini(n, have)
		if k > 0:
			opts.append(["Sell %d %s for $%d" % [k, Products.pname(ask), k * price], func():
				for i in k: g.find_shelf(ask).take_one()
				g.money += k * price
				g.today["income"] += k * price
				Sfx.play("coin", 0.8, 0.6)
				g.ui.toast("Coins come up the stairs one at a time. Warm ones.", UI.C_GOLD, 5.0)
				if ask == "bread":
					g.flags["bread_below"] = true
					g.lose_sanity(15.0)
					g.today["night"].append("Something below chews all night.\nIn the morning the floorboards near the trapdoor are... thinner.")
				pass, UI.C_GOLD])
		else:
			body += "\n\n(You have no %s on the shelves.)" % Products.pname(ask).to_lower()
	opts.append(["Politely decline", func():
		g.sanity = minf(100.0, g.sanity + 3.0)
		g.ui.toast("\"Of course. Another time, shopkeeper.\" It was very nice about it.", UI.C_PURPLE, 5.0)])
	opts.append(["Slam the trapdoor", func():
		g.flags["below_slammed"] = true
		g.lose_sanity(8.0, "It remembers.")
		pass, UI.C_RED])
	if GameSettings.data["stream"] and opts.size() >= 2:
		g.ui.chat_vote("The Thing Below asks nicely.", opts[0][0], opts[opts.size() - 2][0] if opts.size() > 2 else opts[1][0])
	g.ui.show_choice("Under the trapdoor", body, opts)
	talking = true
