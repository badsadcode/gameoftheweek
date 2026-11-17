## main.gd : the shop's day, money, customers, rules and nights.
## Week structure: Monday..Friday. Open 08:00-20:00, sleep, read the morning's letter, repeat.
## The Landlord collects $150 on Friday night.
##
## Map of the code (motto #001):
##   main.gd          this file: game state, day loop, register, rules, specials, endings
##   world.gd         builds the shop, storeroom, street, CCTV
##   player.gd        first-person controller, interact ray, carrying boxes
##   customer.gd      shopper AI (walk, browse, queue, pay, leave)
##   voxel_person.gd  articulated blocky humanoids + procedural animation
##   shelf.gd / crate.gd / interactable.gd   things you can use
##   products.gd      everything for sale
##   ui.gd            HUD + all panels;  sfx.gd  synthesized audio;  vox.gd  textures/boxes
extends Node3D

const DAY_NAMES := ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY"]
const OPEN_MIN := 8 * 60
const CLOSE_MIN := 20 * 60
const SUNSET := 19 * 60
const MIN_PER_SEC := 2.4      # game minutes per real second (a day is ~5 minutes)
const RENT := 150
const BILLS := 8
const MAX_CUSTOMERS := 5

static var skip_title := false

var world: World
var player: Player
var ui: UI
var rng := RandomNumberGenerator.new()

var started := false
var day := 1
var minute := 420.0
var clock_t := 0.0
var is_open := false
var money := 60
var rep := 3.0
var sanity := 100.0
var queue: Array = []
var customers: Array = []
var deliveries: Array = []    # { id, at, beyond }
var rules: Array = []
var spawn_t := 6.0
var flags := {}               # whole-run flags
var today := {}               # per-day counters + events
var crate_slot := 0
var card_speed := 1.0
var autotest := false
var hum: AudioStreamPlayer
var wind: AudioStreamPlayer
var voice: AudioStreamPlayer   # voiced letters (recorded by Tom with ElevenLabs)
var voices_on := true
var ending := false

# --------------------------------------------------------------------------- setup
func _ready() -> void:
	rng.randomize()
	_setup_input()
	autotest = OS.get_cmdline_user_args().has("--autotest") or OS.get_cmdline_args().has("--autotest")
	world = World.new()
	add_child(world)
	world.build(self)
	player = Player.new()
	add_child(player)
	player.setup(self)
	player.position = World.PLAYER_START
	player.rotation.y = PI
	ui = UI.new()
	add_child(ui)
	ui.setup(self)
	hum = Sfx.loop("hum", 0.18)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	wind = Sfx.loop("wind", 0.0)
	_new_week()
	_apply_time_of_day()
	if autotest:
		card_speed = 0.05
		Engine.time_scale = 6.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--min="): minute = float(a.substr(6))
			if a.begins_with("--day="):
				day = int(a.substr(6))
				_new_day_counters()
		start_game()
	elif OS.get_cmdline_user_args().has("--ui-shots"):
		_ui_shots()
	elif skip_title:
		start_game()
	else:
		player.frozen = true
		ui.show_title(start_game)

func _setup_input() -> void:
	var keys := {
		"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "interact": [KEY_E], "alt": [KEY_R], "drop": [KEY_Q], "notebook": [KEY_TAB], "pause": [KEY_ESCAPE],
	}
	for action in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)

func _new_week() -> void:
	day = 1
	minute = 7 * 60
	money = 60
	rep = 3.0
	sanity = 100.0
	rules = []
	flags = {}
	_new_day_counters()
	# grandpa left the shop half stocked
	world.shelves[0].product = "bread"; world.shelves[0].count = 8; world.shelves[0].refresh()
	world.shelves[1].product = "milk"; world.shelves[1].count = 8; world.shelves[1].refresh()
	spawn_crate("salt", 8, _next_crate_spot())
	spawn_crate("tea", 8, _next_crate_spot())
	spawn_crate("silence", 4, _next_crate_spot())

func _new_day_counters() -> void:
	today = { "income": 0, "spent": 0, "served": 0, "sales": 0, "missed": {}, "angry": 0, "broken": [], "kept": [], "night": [] }
	flags["unseen_at"] = rng.randf_range(600, 960) if day >= 2 else 99999.0
	flags["collector_at"] = rng.randf_range(SUNSET + 5, SUNSET + 45) if day >= 2 else 99999.0
	flags["thorne_at"] = rng.randf_range(540, 660) if day >= 3 else 99999.0
	flags["whitlock_done"] = false
	flags["unseen_done"] = false
	flags["collector_done"] = false
	flags["thorne_done"] = false

func start_game() -> void:
	started = true
	player.frozen = false
	if not autotest: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.toast("Monday. Grandpa left a letter on the doormat.", UI.C_GOLD, 6.0)

# --------------------------------------------------------------------------- input
func _unhandled_input(e: InputEvent) -> void:
	if not started or ending: return
	if e is InputEventMouseButton and e.pressed and not ui.is_open():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_LEFT:
			player.interact()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			player.interact_alt()
		return
	if e.is_action_pressed("pause"):
		if ui.is_open(): ui.close_panel()
		else: ui.show_pause(func(): _restart(false))
	elif e.is_action_pressed("notebook"):
		ui.toggle_notebook()
	elif ui.is_open():
		return
	elif e.is_action_pressed("interact"):
		player.interact()
	elif e.is_action_pressed("alt"):
		player.interact_alt()
	elif e.is_action_pressed("drop"):
		player.put_down()

func on_panel_opened() -> void:
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func on_panel_closed() -> void:
	if voice and voice.playing:
		voice.stop()
		hum.volume_db = linear_to_db(0.18 * Sfx.volume)
	if started and not ending:
		player.frozen = false
		if not autotest: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _restart(skip: bool) -> void:
	skip_title = skip
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

# --------------------------------------------------------------------------- main loop
func _process(dt: float) -> void:
	ui.update_hud()
	if not started or ui.is_open() or ending: return
	clock_t += dt
	minute += dt * MIN_PER_SEC
	_deliveries()
	if is_open and minute >= OPEN_MIN and minute < CLOSE_MIN:
		spawn_t -= dt
		if spawn_t <= 0.0:
			spawn_t = lerpf(30.0, 12.0, rep / 5.0) * rng.randf_range(0.7, 1.3)
			if customers.size() < MAX_CUSTOMERS: _spawn_normal()
	_specials()
	_lingerers()
	_apply_time_of_day()
	_weirdness(dt)
	if minute >= 26 * 60 and not ending:
		ui.toast("You fall asleep standing behind the counter...", UI.C_PURPLE)
		_end_day(true)
	if autotest: _bot(dt)

func day_name() -> String:
	return DAY_NAMES[clampi(day - 1, 0, 4)]

func rent_text() -> String:
	if flags.get("rent_paid", false): return "Rent paid. Breathe."
	if day == 5: return "RENT DUE TONIGHT: $%d" % RENT
	return "Rent $%d due Friday night" % RENT

# --------------------------------------------------------------------------- lighting
func _apply_time_of_day() -> void:
	var m := minute
	var day_k := clampf((m - 360.0) / 120.0, 0.0, 1.0) * (1.0 - clampf((m - SUNSET) / 90.0, 0.0, 1.0))
	var dusk := clampf(1.0 - absf(m - (SUNSET + 20.0)) / 70.0, 0.0, 1.0)
	var night := 1.0 - day_k
	var sky := Color(0.5, 0.55, 0.6).lerp(Color(0.04, 0.05, 0.1), night)
	sky = sky.lerp(Color(0.65, 0.38, 0.3), dusk * 0.6)
	world.env.background_color = sky
	world.env.fog_light_color = sky.lerp(Color(0.3, 0.3, 0.35), 0.3)
	world.env.ambient_light_energy = lerpf(0.18, 0.65, day_k)
	world.sun.light_energy = lerpf(0.0, 0.7, day_k)
	world.sun.light_color = Color(1, 0.95, 0.9).lerp(Color(1, 0.6, 0.4), dusk)
	for l in world.street_lights: l.light_energy = night * 1.6
	for g in world.window_glows: g.visible = night > 0.4
	if wind: wind.volume_db = linear_to_db(maxf(0.001, (0.05 + night * 0.25) * (1.0 if player.global_position.z > 5.0 else 0.4)))

func _weirdness(dt: float) -> void:
	var low := 1.0 - sanity / 100.0
	# lamps flicker when you're losing it (or when something unwelcome is inside)
	var unwelcome := false
	for c in customers:
		if c.kind in ["landlord", "collector"] and c.state != "gone": unwelcome = true
	var chance := low * low * 2.0 + (1.5 if unwelcome else 0.0)
	for i in world.lamps.size():
		var on := rng.randf() > chance * dt * 4.0
		world.lamps[i].light_energy = (1.1 if i == 2 else 1.4) if on else 0.15
		world.lamp_meshes[i].visible = on
	for c in customers:
		c.body.flicker = sanity < 35.0 and c.kind == "normal" and fmod(clock_t + c.position.x, 7.0) < 1.2
	if sanity < 50.0 and rng.randf() < dt * low * 0.08:
		Sfx.play("whisper", 0.4 * low, rng.randf_range(0.8, 1.2))

# --------------------------------------------------------------------------- sanity / reputation
func lose_sanity(n: float, why := "") -> void:
	sanity = maxf(0.0, sanity - n)
	if why != "": ui.toast(why, UI.C_PURPLE, 5.0)
	if sanity <= 0.0 and not ending:
		_ending("WHO RUNS THE SHOP NOW?", "You're still behind the counter. You smile at every customer, even the ones with too many eyes.\n\nYou no longer remember being anything other than the shopkeeper.\n\nEldritch & Sons is open. It is always open.", UI.C_PURPLE)

func change_rep(d: float) -> void:
	rep = clampf(rep + d, 0.0, 5.0)

func break_rule(text: String, sanity_cost: float, night_line := "") -> void:
	today["broken"].append(text)
	Sfx.play("wrong", 0.9)
	Sfx.play("drone", 0.6)
	lose_sanity(sanity_cost, "Something feels wrong. (" + text + ")")
	if night_line != "": today["night"].append(night_line)

func keep_rule(text: String) -> void:
	today["kept"].append(text)
	sanity = minf(100.0, sanity + 3.0)
	Sfx.play("good", 0.6)

# --------------------------------------------------------------------------- the sign, the letter, the bed
func sign_prompt() -> String:
	return "[E] Flip the sign to %s" % ("CLOSED" if is_open else "OPEN")

func toggle_open() -> void:
	is_open = not is_open
	world.sign_label.text = "OPEN" if is_open else "CLOSED"
	world.sign_label.modulate = Color(0.5, 1, 0.5) if is_open else Color(1, 0.4, 0.3)
	Sfx.play("click", 0.8)
	if is_open and minute < OPEN_MIN:
		ui.toast("Open early! Customers start coming at 08:00.", UI.C_GREEN)
	elif is_open and minute >= CLOSE_MIN:
		ui.toast("Open after dark. The night crowd is... different.", UI.C_PURPLE)
	elif is_open:
		ui.toast("We're open!", UI.C_GREEN)
	else:
		ui.toast("Closed.", UI.C_RED)

const LETTERS := {
	1: ["A letter from Grandpa",
		"Dear grandchild,\n\nIf you're reading this, the shop is yours now. I'm sorry. And congratulations.\n\nEldritch & Sons has served this town for ninety years. The town is... particular. Keep the shelves stocked and the customers happy and you'll do fine. A few rules (I've pinned them to the board):\n\n1. Mr. Whitlock comes in at six every evening. Always have Tinned Silence for him.\n2. Never sell salt to anyone the camera can't see. Check the monitor.\n3. Rent is due Friday night. The Landlord collects in person. Have $150.\n\nOrder stock from the catalogue on the counter. Only one of the suppliers is normal.\n\n- Grandpa\n\nP.S. Flip the sign by the door to OPEN when you're ready.",
		["Mr. Whitlock comes at six every evening. Always have Tinned Silence.", "Never sell salt to anyone the camera can't see.", "Rent: $150, Friday night. The Landlord collects in person."]],
	2: ["A note from the Supplier",
		"To the new proprietor,\n\nOur condolences on your inheritance.\n\nPlease note: WHISPERING JARS MUST NOT BE SOLD AFTER SUNSET (19:00). Not to anyone. Not for any price.\n\nWe accept no responsibility for what happens if they are.\n\n- The Supplier\n(Catalogue from Beyond, est. before)",
		["No Whispering Jars after sunset (19:00)."]],
	3: ["Grandpa's handwriting, tucked into the till",
		"Forgot one.\n\nIf somebody tries to return something they haven't bought yet, give them the refund. Don't argue. Don't ask how.\n\nThey always come back to buy it.\n\n- G",
		["If someone returns something they haven't bought yet: refund them."]],
	4: ["A note under the door",
		"The man across the street says the new house has always been there.\n\nDon't argue with him either.\n\n- G\n\nP.S. Tomorrow is Friday. Count your money.",
		[]],
	5: ["A black card. No envelope.",
		"RENT.\nTONIGHT.\n$150.\n\n- THE MANAGEMENT",
		["Pay the Landlord tonight. Do not be late."]],
}

func read_letter() -> void:
	var l: Array = LETTERS.get(day, [])
	if l.is_empty(): return
	world.letter.visible = false
	world.letter.process_mode = Node.PROCESS_MODE_DISABLED
	for r in l[2]:
		if not rules.has(r): rules.append(r)
	Sfx.play("page", 0.8)
	if autotest: return
	var replay := Callable()
	if _letter_voice(day) != null:
		replay = func(): play_letter_voice(day)
		play_letter_voice(day)
	ui.show_text(l[0], l[1], "Put it away" + ("  (rules added to your notebook)" if not l[2].is_empty() else ""), Callable(), true, replay)

func _letter_voice(d: int) -> AudioStream:
	var path := "res://assets/voice/letter_day%d.ogg" % d
	return load(path) if ResourceLoader.exists(path) else null

## letters are read aloud (grandpa, the Supplier, the Landlord) while the text stays on screen
func play_letter_voice(d: int) -> void:
	var s := _letter_voice(d)
	if s == null or not voices_on: return
	voice.stream = s
	voice.volume_db = linear_to_db(Sfx.volume)
	voice.play()
	hum.volume_db = linear_to_db(0.06)

func bed_prompt() -> String:
	if day == 5 and not flags.get("rent_paid", false): return "You can't sleep. The Landlord is coming."
	if minute < CLOSE_MIN: return "Too early to sleep (the shop closes at 20:00)"
	if _inside_count() > 0: return "There are still customers inside"
	return "[E] Go to sleep"

func go_to_bed() -> void:
	if bed_prompt() != "[E] Go to sleep": return
	_end_day(false)

func _inside_count() -> int:
	var n := 0
	for c in customers:
		if c.state != "gone" and c.position.z < 6.0: n += 1
	return n

# --------------------------------------------------------------------------- catalogue + deliveries
func open_catalogue() -> void:
	ui.show_catalogue()

func order(id: String) -> bool:
	var info := Products.info(id)
	if money < info["cost"]:
		ui.toast("Not enough money for %s." % info["name"], UI.C_RED)
		Sfx.play("wrong", 0.3, 1.5)
		return false
	money -= int(info["cost"])
	today["spent"] += int(info["cost"])
	var beyond: bool = info["beyond"]
	var at := minute + (randf_range(4, 10) if beyond else 60.0)
	if at > CLOSE_MIN + 120 and not beyond: at = 24 * 60 + 7 * 60 + 5  # tomorrow morning
	deliveries.append({ "id": id, "at": at, "beyond": beyond })
	Sfx.play("coin", 0.6, 0.8)
	if beyond: ui.toast("Ordered %s. You feel it was received." % info["name"], UI.C_PURPLE)
	else: ui.toast("Ordered %s. Delivery around %02d:%02d." % [info["name"], int(at) / 60 % 24, int(at) % 60], UI.C_GOLD)
	return true

func _deliveries() -> void:
	for i in range(deliveries.size() - 1, -1, -1):
		var d: Dictionary = deliveries[i]
		if minute >= d["at"]:
			deliveries.remove_at(i)
			spawn_crate(d["id"], Products.BOX_SIZE, _next_crate_spot())
			if d["beyond"]:
				ui.toast("There's a new box in the storeroom. Nobody came in.", UI.C_PURPLE)
			else:
				Sfx.play("knock", 0.7)
				ui.toast("Delivery at the back door: %s." % Products.pname(d["id"]), UI.C_GOLD)

func _next_crate_spot() -> Vector3:
	var i := crate_slot % 8
	crate_slot += 1
	return World.DELIVERY + Vector3((i % 4) * 0.75 - 1.2, 0, (i / 4) * 0.7)

func spawn_crate(id: String, n: int, pos: Vector3) -> Crate:
	var c := Crate.new()
	world.add_child(c)
	c.build(id, n)
	c.global_position = Vector3(pos.x, 0.0 if pos.y < 0.6 else pos.y - 0.3, pos.z)
	return c

func on_stocked(id: String, n: int) -> void:
	pass

func find_shelf(id: String) -> Shelf:
	for s in world.shelves:
		if s.product == id and s.count > 0: return s
	return null

# --------------------------------------------------------------------------- customers
const NAMES := ["Mrs. Abernathy", "Old Tom", "Ms. Pike", "Mr. Gray", "Agnes", "Barnaby", "Mrs. Lumley", "Silas", "Edna", "Mr. Crane", "Prudence", "Jonah", "Wilma", "Ezekiel", "Hattie", "Mr. Fogg"]

func _random_wants(odd: bool) -> Array:
	var pool := [["bread", 5.0], ["milk", 5.0], ["salt", 4.0], ["tea", 3.0], ["candles", 3.0]]
	if day >= 2: pool.append_array([["oil", 2.0], ["rope", 1.5]])
	var out := []
	var n := rng.randi_range(1, 3)
	for i in n:
		var total := 0.0
		for e in pool: total += e[1]
		var r := rng.randf() * total
		for e in pool:
			r -= e[1]
			if r <= 0.0:
				out.append(e[0]); break
	if odd:
		var weird := Products.available(day, true)
		weird.erase("silence")
		if not weird.is_empty(): out.append(weird[rng.randi() % weird.size()])
	return out

func _new_customer(look: Dictionary, kind := "normal", spawn := Vector3.INF) -> Customer:
	if autotest and kind != "normal": print("[special] day %d %02d:%02d %s arrives" % [day, int(minute) / 60, int(minute) % 60, kind])
	var c := Customer.new()
	add_child(c)
	if spawn == Vector3.INF: spawn = World.SPAWNS[rng.randi() % 2]
	c.setup(self, look, spawn)
	c.kind = kind
	customers.append(c)
	return c

func _spawn_normal() -> void:
	var c := _new_customer(VoxelPerson.random_look(rng))
	c.cname = NAMES[rng.randi() % NAMES.size()]
	c.wants = _random_wants(rng.randf() < 0.12 * day)

func door_passed(c: Customer) -> void:
	if c.flags.get("rang", 0) < 2 and c.position.z > 3.0:
		c.flags["rang"] = c.flags.get("rang", 0) + 1
		Sfx.play("bell", 0.5)

func on_entered(c: Customer) -> void:
	if not is_open and c.kind == "normal":
		c.leave("Closed?")

func on_picked(c: Customer, id: String) -> void:
	pass

var _missed_toast_t := 0.0
func on_missed(c: Customer, id: String) -> void:
	today["missed"][id] = today["missed"].get(id, 0) + 1
	if c.kind == "normal":
		change_rep(-0.04)
		if clock_t - _missed_toast_t > 8.0:
			_missed_toast_t = clock_t
			ui.toast("%s wanted %s, but there was none on the shelves." % [c.cname, Products.pname(id)])

func on_left_empty(c: Customer) -> void:
	if c.kind == "whitlock":
		_whitlock_unserved(c)
	elif c.kind == "normal":
		change_rep(-0.1)
		today["angry"] += 1

func on_impatient(c: Customer) -> void:
	change_rep(-0.25)
	today["angry"] += 1
	ui.toast("%s got tired of waiting at the till." % c.cname, UI.C_RED)

func on_gone(c: Customer) -> void:
	if autotest and c.kind != "normal": print("[special] day %d %02d:%02d %s gone (basket %s)" % [day, int(minute) / 60, int(minute) % 60, c.kind, str(c.basket)])
	customers.erase(c)
	queue.erase(c)

func join_queue(c: Customer) -> void:
	if not queue.has(c): queue.append(c)
	c.queue_spot_changed(queue.size() - 1)

func leave_queue(c: Customer) -> void:
	if not queue.has(c): return
	queue.erase(c)
	for i in queue.size(): queue[i].queue_spot_changed(i)

func _front() -> Customer:
	if queue.is_empty(): return null
	var c: Customer = queue[0]
	return c if c.at_counter() else null

func _lingerers() -> void:
	for c in customers:
		if c.state == "linger" and clock_t > c.flags.get("linger_until", 0.0):
			c.flags["silent"] = true
			c.leave()

# --------------------------------------------------------------------------- the register
func register_prompt() -> String:
	var c := _front()
	if c == null:
		return "The till. Nobody is waiting."
	match c.kind:
		"returner":
			return "[E] Refund $%d for %s\n(%s hasn't bought it yet)" % [Products.info(c.refund_item)["price"], Products.pname(c.refund_item), c.cname]
		"landlord":
			if money >= RENT: return "[E] Pay the rent ($%d)" % RENT
			return "You only have $%d of $%d..." % [money, RENT]
	return "[E] Ring up %s: %s  ($%d)" % [c.cname, c.basket_text(), c.basket_total()]

func register_alt_prompt() -> String:
	var c := _front()
	if c == null: return ""
	if c.kind == "landlord": return "[R] Offer to pay in... something else"
	if c.kind == "returner": return "[R] Refuse the refund"
	return "[R] Refuse to serve"

func register_use() -> void:
	var c := _front()
	if c == null: return
	match c.kind:
		"returner":
			var price: int = Products.info(c.refund_item)["price"]
			money -= price
			today["spent"] += price
			flags["thorne_owes"] = c.refund_item
			keep_rule("Refunded something not yet bought")
			c.say("Thank you, dear. See you tomorrow.", 4.0)
			c.leave()
			return
		"landlord":
			if money < RENT:
				Sfx.play("wrong", 0.4, 1.4)
				ui.toast("Not enough. He waits. Patiently. Forever, if necessary.", UI.C_PURPLE)
				return
			money -= RENT
			flags["rent_paid"] = true
			flags["paid_with"] = "money"
			Sfx.play("till", 1.0, 0.6)
			c.say("...ADEQUATE.", 5.0)
			ui.toast("The Landlord counts the coins twice. The rent is paid.", UI.C_GOLD, 6.0)
			c.leave()
			return
	# an ordinary sale... mostly
	var total := c.basket_total()
	if c.basket.has("jar") and minute >= SUNSET:
		break_rule("Sold a Whispering Jar after sunset", 12.0, "The jars whisper until dawn. They know your name now.")
		lose_sanity(10.0)
	if c.kind == "unseen" and c.basket.has("salt"):
		break_rule("Sold salt to someone the camera couldn't see", 25.0, "All the salt in the shop turned black overnight.")
		flags["salt_cursed"] = true
		for l in world.lamps: l.light_energy = 0.0
	if c.kind == "whitlock":
		c.say("...", 3.0)
		flags["whitlock_served"] = flags.get("whitlock_served", 0) + 1
		keep_rule("Mr. Whitlock got his Tinned Silence")
	elif c.kind == "thorne_buyer":
		total *= 2
		c.say("Exactly as I remembered. Keep the change.", 4.0)
	else:
		c.say(["Thanks!", "Lovely.", "Ta.", "Bless you.", "Mm."][rng.randi() % 5], 2.5)
	money += total
	today["income"] += total
	today["served"] += 1
	today["sales"] += c.basket.size()
	change_rep(0.04 * c.basket.size())
	Sfx.play("till", 0.8)
	Sfx.play("coin", 0.5, rng.randf_range(0.9, 1.1))
	c.leave()

func register_refuse() -> void:
	var c := _front()
	if c == null: return
	match c.kind:
		"landlord":
			flags["rent_paid"] = true
			flags["paid_with"] = "sanity"
			c.say("...ACCEPTABLE.", 5.0)
			lose_sanity(45.0, "He takes something from you. You can't remember what it was.")
			c.leave()
			return
		"returner":
			break_rule("Refused a refund for something not yet bought", 12.0, "Mrs. Thorne's laugh echoes up the stairwell. You don't have a stairwell.")
			flags["thorne_refused"] = c.refund_item
			c.say("Oh. Oh dear. You'll see.", 4.0)
			c.leave()
			return
		"unseen":
			if c.basket.has("salt"):
				keep_rule("Refused salt to someone the camera couldn't see")
				c.say("...wise.", 4.0)
				ui.toast("He glances at the camera. Then at you. Then he's gone.", UI.C_PURPLE)
				c.leave()
				return
		"collector":
			if c.basket.has("jar") and minute >= SUNSET:
				keep_rule("Refused to sell a jar after sunset")
				c.say("Another night, then.", 4.0)
				c.leave()
				return
	if c.basket.has("jar") and minute >= SUNSET:
		keep_rule("Refused to sell a jar after sunset")
		c.leave("Fine.")
		return
	change_rep(-0.2)
	today["angry"] += 1
	c.leave("How rude!")

# --------------------------------------------------------------------------- strange customers
func _specials() -> void:
	# Mr. Whitlock, every evening at six (ish)
	if not flags["whitlock_done"] and minute >= 17 * 60 + 40 and minute < CLOSE_MIN:
		flags["whitlock_done"] = true
		var look := { "skin": Color(0.86, 0.86, 0.82), "shirt": Color(0.3, 0.3, 0.33), "pants": Color(0.12, 0.12, 0.14),
			"coat": Color(0.08, 0.08, 0.1), "hat": Color(0.06, 0.06, 0.07), "height": 1.22, "width": 0.82, "eyes": Color(0.02, 0.02, 0.02) }
		var c := _new_customer(look, "whitlock", World.SPAWNS[0])
		c.cname = "Mr. Whitlock"
		c.wants = ["silence"]
		c.speed = 1.1
		c.flags["silent"] = true
		c.flags["patient"] = true
		if not is_open:
			c.flags["outside"] = true
	# the one the camera can't see
	if not flags["unseen_done"] and minute >= flags["unseen_at"] and is_open:
		flags["unseen_done"] = true
		var look := VoxelPerson.random_look(rng)
		look["layer"] = 2
		var c := _new_customer(look, "unseen")
		c.cname = ["Mr. Hollis", "Mr. Vane", "Mr. Lowe"][rng.randi() % 3]
		c.wants = ["salt", ["bread", "candles", "tea"][rng.randi() % 3]] if rng.randf() < 0.75 else ["bread", "milk"]
		# lamps hiccup as he crosses the threshold
		for l in world.lamps: l.light_energy = 0.2
	# Mrs. Thorne returns something she hasn't bought yet
	if not flags["thorne_done"] and minute >= flags["thorne_at"] and is_open:
		flags["thorne_done"] = true
		var look := { "skin": Color(0.9, 0.75, 0.65), "shirt": Color(0.55, 0.2, 0.45), "pants": Color(0.25, 0.15, 0.25),
			"hair": Color(0.85, 0.85, 0.88), "coat": Color(0.4, 0.15, 0.35), "height": 0.9 }
		var c := _new_customer(look, "returner")
		c.cname = "Mrs. Thorne"
		var opts := Products.available(day, true)
		opts.erase("silence")
		c.refund_item = opts[rng.randi() % opts.size()] if not opts.is_empty() else "jar"
		c.flags["direct_queue"] = true
		c.flags["patient"] = true
	# ...and comes back the next day to buy it
	if flags.has("thorne_owes") and flags.get("thorne_owes_day", -1) == day and not flags.get("thorne_buy_done", false) and minute >= 600 and is_open:
		flags["thorne_buy_done"] = true
		var look := { "skin": Color(0.9, 0.75, 0.65), "shirt": Color(0.55, 0.2, 0.45), "pants": Color(0.25, 0.15, 0.25),
			"hair": Color(0.85, 0.85, 0.88), "coat": Color(0.4, 0.15, 0.35), "height": 0.9 }
		var c := _new_customer(look, "thorne_buyer")
		c.cname = "Mrs. Thorne"
		c.wants = [flags["thorne_owes"]]
	# the evening collector (after sunset)
	if not flags["collector_done"] and minute >= flags["collector_at"] and is_open:
		flags["collector_done"] = true
		var look := { "skin": Color(0.35, 0.3, 0.45), "shirt": Color(0.2, 0.1, 0.25), "pants": Color(0.15, 0.08, 0.18),
			"coat": Color(0.25, 0.12, 0.3), "eyes": Color(0.9, 0.8, 0.3), "weird": ["glow_eyes", "extra_arms"], "height": 1.1 }
		var c := _new_customer(look, "collector")
		c.cname = "The Collector"
		c.wants = ["jar"]
		c.speed = 1.2
	# the Landlord, Friday night
	if day == 5 and minute >= 21 * 60 and not flags.get("landlord_came", false):
		flags["landlord_came"] = true
		Sfx.play("knock", 1.0, 0.7)
		ui.toast("Three knocks at the front door. It's Friday.", UI.C_PURPLE, 6.0)
		var look := { "skin": Color(0.05, 0.03, 0.08), "shirt": Color(0.04, 0.03, 0.06), "pants": Color(0.03, 0.02, 0.05),
			"coat": Color(0.08, 0.05, 0.12), "eyes": Color(0.85, 0.35, 1.0), "weird": ["three_eyes", "glow_eyes", "long_arms", "tentacle_beard"],
			"height": 1.45, "width": 1.2 }
		var c := _new_customer(look, "landlord", World.DOOR_OUT + Vector3(0, 0, 1.5))
		c.cname = "The Landlord"
		c.flags["direct_queue"] = true
		c.flags["patient"] = true
		c.flags["silent"] = true
		c.speed = 0.9
		Sfx.play("drone", 1.0, 0.7)
	if day == 5 and minute >= 23 * 60 + 50 and not flags.get("rent_paid", false) and not ending:
		_ending("EVICTED", "At midnight the Landlord stops waiting.\n\nThe shop is still there in the morning. So are the shelves, and the till, and the bell over the door.\n\nYou are not. Nobody in town remembers there was ever a new owner.", UI.C_RED)
	# Whitlock waiting outside a closed shop
	for c in customers:
		if c.kind == "whitlock" and c.flags.get("outside", false) and c.state == "arrive" and c.path.size() == 1:
			c.path = []
			c.state = "linger"
			c.flags["linger_until"] = clock_t + 60.0
			_whitlock_unserved(c, true)

func _whitlock_unserved(c: Customer, outside := false) -> void:
	c.state = "linger"
	c.flags["linger_until"] = clock_t + (60.0 if outside else 25.0)
	c.say("...", 8.0)
	break_rule("Mr. Whitlock didn't get his Tinned Silence", 10.0, "Mr. Whitlock stands outside your window all night. He doesn't blink. You check twice.")

# --------------------------------------------------------------------------- end of day
const NIGHTS := {
	1: ["You lock up and climb into grandpa's old bed.", "At 3 AM, someone knocks on the back door. Three times.", "In the morning there's nobody there. Just wet footprints.\nLeading in."],
	2: ["The fog rolls in thick tonight.", "Across the street: hammering. All night long.", "Nobody builds anything at this hour."],
	3: ["You dream of the shop. In the dream the shelves go on forever.", "Grandpa is standing in aisle three.\n\"Don't let them see you're scared,\" he says."],
	4: ["The town is very quiet tonight.", "Somewhere under the floorboards, something is counting coins.", "Tomorrow is Friday."],
}

func _end_day(collapsed: bool) -> void:
	if day == 5:
		if flags.get("rent_paid", false): _week_won()
		return
	for c in customers.duplicate():
		c.queue_free()
	customers.clear()
	queue.clear()
	if is_open: toggle_open()
	money -= BILLS
	var lines := []
	lines.append("+$%d from %d sales (%d customers)" % [today["income"], today["sales"], today["served"]])
	lines.append("-$%d on stock" % today["spent"])
	lines.append("-$%d bills (lamp oil, water, the usual)" % BILLS)
	lines.append("Money: $%d     Reputation: %.1f / 5     Sanity: %d" % [money, rep, int(sanity)])
	var worst := ""
	var worst_n := 0
	for id in today["missed"]:
		if today["missed"][id] > worst_n: worst = id; worst_n = today["missed"][id]
	if worst != "": lines.append("Most wanted but missing: %s (%dx)" % [Products.pname(worst), worst_n])
	if today["angry"] > 0: lines.append("-%d customers left unhappy" % today["angry"])
	for k in today["kept"]: lines.append("!Rule kept: " + k)
	for b in today["broken"]: lines.append("!RULE BROKEN: " + b)
	if collapsed: lines.append("!You fell asleep at the counter.")
	var night_lines: Array = NIGHTS.get(day, []).duplicate()
	for n in today["night"]: night_lines.append(n)
	if today["night"].size() > 0: lose_sanity(5.0 * today["night"].size())
	if ending: return
	print("[day %d] %s" % [day, " | ".join(lines)])
	if autotest:
		_next_day()
		return
	ui.show_summary(lines, func(): ui.night_card(night_lines, _next_day))

func _next_day() -> void:
	if ending: return
	day += 1
	minute = 7 * 60
	_new_day_counters()
	player.global_position = Vector3(-2.2, 0.05, -8.0)
	player.rotation.y = 0.0
	player.frozen = false
	world.letter.visible = true
	world.letter.process_mode = Node.PROCESS_MODE_INHERIT
	if day == 3: world.show_mystery_house()
	if flags.has("thorne_owes") and not flags.has("thorne_owes_day"): flags["thorne_owes_day"] = day
	if flags.has("thorne_refused"):
		var id: String = flags["thorne_refused"]
		flags.erase("thorne_refused")
		for s in world.shelves:
			if s.product == id:
				s.product = ""; s.count = 0; s.refresh()
		ui.toast("Every %s in the shop is gone. The shelf is warm." % Products.pname(id), UI.C_PURPLE, 6.0)
	if flags.get("salt_cursed", false):
		flags["salt_cursed"] = false
		for s in world.shelves:
			if s.product == "salt":
				s.product = ""; s.count = 0; s.refresh()
		ui.toast("The salt turned black overnight. You threw it all out.", UI.C_PURPLE, 6.0)
	ui.toast("%s. There's something on the doormat." % day_name(), UI.C_GOLD, 6.0)
	if day == 5: ui.toast("Rent is due tonight: $%d." % RENT, UI.C_RED, 8.0)

func _week_won() -> void:
	var how: String = flags.get("paid_with", "money")
	var title := "OPEN FOR BUSINESS" if how == "money" else "PAID IN FULL (SORT OF)"
	var body := "The Landlord steps backwards into a shadow that wasn't there a moment ago.\n\nThe shop is yours for another week.\n\nMoney left: $%d\nReputation: %.1f / 5\nSanity: %d\nMr. Whitlock served: %d times" % [money, rep, int(sanity), flags.get("whitlock_served", 0)]
	if how != "money": body = "You paid the rent in something that wasn't money. You'd tell people what, if you could remember.\n\n" + body
	_ending(title, body, UI.C_GOLD)

func _ending(title: String, body: String, color: Color) -> void:
	ending = true
	print("[ending] %s | day %d | money %d | sanity %d" % [title, day, money, int(sanity)])
	if autotest:
		get_tree().quit()
		return
	player.frozen = true
	ui.show_ending(title, body, color, func(): _restart(true))

# --------------------------------------------------------------------------- UI screenshots (--ui-shots)
func _ui_shots() -> void:
	var snap := func(name: String) -> void:
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("user://ui_%s.png" % name)
		print("[ui-shot] ", name)
	player.global_position = Vector3(-4.6, 0, 0.9)
	player.rotation.y = PI
	ui.show_title(start_game)
	await snap.call("title")
	ui.close_panel()
	started = true
	day = 1
	read_letter()
	await snap.call("letter")
	ui.close_panel()
	ui.show_catalogue()
	await snap.call("catalogue")
	ui.close_panel()
	ui.toggle_notebook()
	await snap.call("notebook")
	ui.close_panel()
	today["income"] = 112; today["sales"] = 31; today["served"] = 17; today["spent"] = 44
	today["kept"] = ["Mr. Whitlock got his Tinned Silence"]
	today["broken"] = ["Sold a Whispering Jar after sunset"]
	var lines := ["+$112 from 31 sales (17 customers)", "-$44 on stock", "-$8 bills (lamp oil, water, the usual)", "Money: $120     Reputation: 4.2 / 5     Sanity: 88", "!Rule kept: Mr. Whitlock got his Tinned Silence", "!RULE BROKEN: Sold a Whispering Jar after sunset"]
	ui.show_summary(lines, func(): pass)
	await snap.call("summary")
	ui.close_panel()
	sanity = 25.0
	minute = 21 * 60
	_apply_time_of_day()
	ui.update_hud()
	await snap.call("low_sanity")
	get_tree().quit()

# --------------------------------------------------------------------------- test bot (--autotest)
## camera shots the bot takes along the way (saved to user://shot_*.png)
var _shots := [
	{ "day": 1, "min": 560, "pos": Vector3(-4.6, 0, 0.7), "look": Vector3(0, 1.2, 4.5), "name": "counter" },
	{ "day": 1, "min": 700, "pos": Vector3(3.0, 0, 3.6), "look": Vector3(-4.0, 1.0, -3.5), "name": "aisles" },
	{ "day": 1, "min": 820, "pos": Vector3(-2.6, 0, -3.0), "look": Vector3(-5.0, 1.0, 3.0), "name": "customers" },
	{ "day": 2, "min": 1150, "pos": Vector3(3.5, 0, 12.5), "look": Vector3(0, 2.5, 5.0), "name": "street_dusk" },
	{ "day": 3, "min": 520, "pos": Vector3(1.0, 0, 8.0), "look": Vector3(1.5, 3.0, 18.0), "name": "mystery_house" },
	{ "day": 5, "min": 1272, "pos": Vector3(-4.6, 0, 0.7), "look": Vector3(-3.0, 1.6, 4.0), "name": "landlord" },
]
var _pending_shot := ""

func _take_shots() -> void:
	if _pending_shot != "":
		get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % _pending_shot)
		print("[shot] ", _pending_shot)
		_pending_shot = ""
	for sh in _shots:
		if sh["day"] == day and minute >= sh["min"] and not sh.get("done", false):
			sh["done"] = true
			player.global_position = sh["pos"]
			var to: Vector3 = sh["look"] - (sh["pos"] + Vector3(0, 1.62, 0))
			player.rotation.y = atan2(-to.x, -to.z)
			player.cam.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
			_pending_shot = sh["name"]
			return

var _bot_t := 0.0
var _bot_log_day := 0
func _bot(dt: float) -> void:
	_take_shots()
	_bot_t -= dt
	if _bot_t > 0.0: return
	_bot_t = 0.3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quit-at=") and minute >= float(a.substr(10)):
			print("[bot] quit-at reached")
			get_tree().quit()
	if OS.get_cmdline_user_args().has("--trace"):
		for c in customers:
			if c.kind == "whitlock" and int(minute) % 10 == 0:
				print("[trace] %02d:%02d whitlock state=%s pos=(%.1f,%.1f) path=%d queue_i=%d" % [int(minute) / 60, int(minute) % 60, c.state, c.position.x, c.position.z, c.path.size(), queue.find(c)])
	if world.letter.visible: read_letter()
	if not is_open and minute >= OPEN_MIN - 20 and minute < CLOSE_MIN: toggle_open()
	if is_open and minute >= CLOSE_MIN + 10: toggle_open()
	# keep shelves stocked: what the bot sells
	var wanted := ["bread", "milk", "salt", "silence", "tea", "candles"]
	if day >= 2: wanted = ["bread", "milk", "salt", "silence", "jar", "candles"]
	for i in wanted.size():
		var s: Shelf = world.shelves[i]
		var id: String = wanted[i]
		if s.product != "" and s.product != id: continue
		var pending := false
		for d in deliveries: if d["id"] == id: pending = true
		for c in world.get_children(): if c is Crate and c.product == id: pending = true
		var reserve := RENT if day == 5 else 30
		if s.count <= 3 and not pending and money - int(Products.info(id)["cost"]) >= reserve and minute < CLOSE_MIN - 60:
			order(id)
	# unpack any crates straight onto shelves (the bot has very long arms)
	for c in world.get_children():
		if c is Crate:
			for s in world.shelves:
				if (s.product == c.product or s.product == "") and s.count < Shelf.CAPACITY:
					var moved := mini(c.units, Shelf.CAPACITY - s.count)
					s.product = c.product; s.count += moved; s.refresh()
					c.units -= moved
					if c.units <= 0: break
			if c.units <= 0: c.queue_free()
			else: c.refresh()
	# serve, following the rules
	var f := _front()
	if f:
		var refuse := (f.kind == "unseen" and f.basket.has("salt")) or (f.basket.has("jar") and minute >= SUNSET)
		if f.kind == "landlord" and money < RENT: refuse = true
		if refuse:
			register_refuse()
		else:
			register_use()
	if minute >= CLOSE_MIN + 20 and _inside_count() == 0 and day < 5:
		_end_day(false)
	if day == 5 and flags.get("rent_paid", false) and _inside_count() == 0:
		_end_day(false)
	if day != _bot_log_day:
		_bot_log_day = day
		print("[bot] day %d start: money %d rep %.1f sanity %d" % [day, money, rep, int(sanity)])
