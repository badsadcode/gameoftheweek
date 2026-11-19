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
var ending := false
var guide: Guide
var phone: Phone
var basement: Basement
var tip_jar: TipJar
var haunting: Haunting
var night_walk := false        # the interactive 3 AM walk (Wednesday night)
var walk_lines: Array = []
var walk_t := 0.0
var walk_figure: VoxelPerson

# --------------------------------------------------------------------------- setup
func _ready() -> void:
	rng.randomize()
	GameSettings.load_settings()
	GameSettings.apply()
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
	guide = Guide.new()
	add_child(guide)
	guide.setup(self)
	phone = Phone.new()
	add_child(phone)
	phone.build(self)
	basement = Basement.new()
	add_child(basement)
	basement.build(self)
	tip_jar = TipJar.new()
	add_child(tip_jar)
	tip_jar.build(self)
	haunting = Haunting.new()
	add_child(haunting)
	haunting.setup(self)
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
	elif OS.get_cmdline_user_args().has("--systems-test"):
		_systems_test()
	elif OS.get_cmdline_user_args().has("--kerb-test"):
		_kerb_test()
	elif OS.get_cmdline_user_args().has("--ui-shots"):
		_ui_shots()
	elif skip_title:
		start_game()
	else:
		player.frozen = true
		ui.show_title(_new_game, _continue_game if SaveGame.exists() else Callable())

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
	if day == 1: ui.toast("Monday. Grandpa left a letter on the doormat.", UI.C_GOLD, 6.0)
	else: ui.toast("%s morning. There's something on the doormat." % day_name().capitalize(), UI.C_GOLD, 6.0)

func _new_game() -> void:
	SaveGame.clear()
	start_game()

## "Continue": back to the morning the save was made
func _continue_game() -> void:
	SaveGame.load_into(self)
	player.global_position = Vector3(-2.2, 0.05, -8.0)
	player.rotation.y = 0.0
	world.letter.visible = true
	world.letter.process_mode = Node.PROCESS_MODE_INHERIT
	start_game()

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
	player.sensitivity = GameSettings.mouse_sensitivity()
	ui.update_hud()
	if not started or ui.is_open() or ending: return
	if night_walk:
		_night_walk_tick(dt)
		return
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
	_chat_votes()
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
	if world.hq():
		world.env.volumetric_fog_albedo = sky.lerp(Color(0.85, 0.87, 0.9), 0.5)
		world.env.volumetric_fog_density = lerpf(0.07, 0.025, day_k)
	world.env.ambient_light_energy = lerpf(0.18, 0.65, day_k)
	world.sun.light_energy = lerpf(0.0, 0.7, day_k)
	world.sun.light_color = Color(1, 0.95, 0.9).lerp(Color(1, 0.6, 0.4), dusk)
	var wrong := (day == 5 and m >= CLOSE_MIN) or night_walk
	for l in world.street_lights:
		l.light_energy = night * 1.6
		l.light_color = Color(0.65, 0.3, 1.0) if wrong else Color(1, 0.8, 0.5)
	if wrong and world.hq(): world.env.volumetric_fog_density = 0.11
	if day == 5 and m >= CLOSE_MIN and not flags.get("friday_lamps", false) and started and not night_walk:
		flags["friday_lamps"] = true
		Sfx.play("drone", 0.7, 0.6)
		ui.toast("The street lamps have changed colour. The road out of town ends in fog.", UI.C_PURPLE, 7.0)
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
	if not flags.has("broken_log"): flags["broken_log"] = []
	flags["broken_log"].append(text)
	Sfx.play("wrong", 0.9)
	Sfx.play("drone", 0.6)
	lose_sanity(sanity_cost, "Something feels wrong. (" + text + ")")
	if night_line != "": today["night"].append(night_line)

func keep_rule(text: String) -> void:
	today["kept"].append(text)
	if not flags.has("kept_log"): flags["kept_log"] = []
	flags["kept_log"].append(text)
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
	if s == null or not GameSettings.data["voices"]: return
	voice.stream = s
	voice.volume_db = linear_to_db(Sfx.volume)
	voice.play()
	hum.volume_db = linear_to_db(0.06)

func bed_prompt() -> String:
	if night_walk: return "[E] Go back to sleep"
	if day == 5 and not flags.get("rent_paid", false): return "You can't sleep. The Landlord is coming."
	if minute < CLOSE_MIN: return "Too early to sleep (the shop closes at 20:00)"
	if _inside_count() > 0: return "There are still customers inside"
	return "[E] Go to sleep"

func go_to_bed() -> void:
	if night_walk:
		_finish_night_walk()
		return
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
const NAMES := ["Mrs. Abernathy", "Old Tom", "Ms. Pike", "Mr. Gray", "Barnaby", "Mrs. Lumley", "Silas", "Edna", "Mr. Crane", "Prudence", "Jonah", "Wilma", "Ezekiel", "Hattie", "Mr. Fogg"]

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
	# one customer a day (from Tuesday) is short of money and offers something else
	var odd: String = ODD_BY_DAY.get(day, "")
	if odd != "" and not flags.get("odd_day_%d" % day, false) and minute >= 9 * 60 and minute < 17 * 60 and rng.randf() < 0.25:
		flags["odd_day_%d" % day] = true
		c.flags["offer"] = odd

func door_passed(c: Customer) -> void:
	if c.flags.get("rang", 0) < 2 and c.position.z > 3.0:
		c.flags["rang"] = c.flags.get("rang", 0) + 1
		Sfx.play("bell", 0.5)

func on_entered(c: Customer) -> void:
	if c.kind == "echo":
		c.state = "linger"
		c.flags["linger_until"] = clock_t + 45.0
		c.flags["linger_pose"] = "stare"
		c.say("We are Mr. Whitlock.", 6.0)
		return
	if not is_open and c.kind == "normal":
		c.leave("Closed?")
		return
	if c.flags.has("hello"): c.say(c.flags["hello"], 4.0)

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
	if rng.randf() < 0.3: tip_jar.add_odd(rng)
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
	if c.flags.has("offer"):
		return "%s can't pay $%d. Offers you %s instead.\n[E] Accept it     [R] Insist on money" % [c.cname, c.basket_total(), ODDITIES[c.flags["offer"]]["name"].to_lower()]
	match c.kind:
		"tooth_buyer":
			return "[E] Sell %s the tooth ($45)" % c.cname
		"returner":
			return "[E] Refund $%d for %s\n(%s hasn't bought it yet)" % [Products.info(c.refund_item)["price"], Products.pname(c.refund_item), c.cname]
		"landlord":
			var due := _rent_due()
			if money >= due: return ("[E] Pay $%d + the blinking coin" % due) if due < RENT else ("[E] Pay the rent ($%d)" % RENT)
			return "You only have $%d of $%d..." % [money, due]
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
	if c.flags.has("offer"):
		_accept_oddity(c)
		return
	match c.kind:
		"tooth_buyer":
			money += 45
			today["income"] += 45
			_pop_money(45)
			flags["items"].erase("tooth")
			Sfx.play("till", 0.8)
			c.say("Splendid. Still warm.", 4.0)
			ui.toast("Dr. Quill wraps the tooth in a handkerchief and leaves humming.", UI.C_GOLD, 5.0)
			c.leave()
			return
		"returner":
			var price: int = Products.info(c.refund_item)["price"]
			money -= price
			today["spent"] += price
			_pop_money(-price)
			flags["thorne_owes"] = c.refund_item
			keep_rule("Refunded something not yet bought")
			c.say("Thank you, dear. See you tomorrow.", 4.0)
			c.leave()
			return
		"landlord":
			var due := _rent_due()
			if money < due:
				Sfx.play("wrong", 0.4, 1.4)
				ui.toast("Not enough. He waits. Patiently. Forever, if necessary.", UI.C_PURPLE)
				return
			if due < RENT:
				flags["items"].erase("coin")
				ui.toast("The Landlord holds the blinking coin up to one of his eyes. It blinks back. He seems pleased.", UI.C_PURPLE, 6.0)
			money -= due
			_pop_money(-due)
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
		c.say(["...", "...", "...thank you.", "", "We thank you."][clampi(day - 1, 0, 4)], 4.0)
		flags["whitlock_served"] = flags.get("whitlock_served", 0) + 1
		keep_rule("Mr. Whitlock got his Tinned Silence")
	elif c.kind == "thorne_buyer":
		total *= 2
		c.say("Exactly as I remembered. Keep the change.", 4.0)
	elif c.flags.has("bye"):
		c.say(c.flags["bye"], 4.0)
	else:
		c.say(["Thanks!", "Lovely.", "Ta.", "Bless you.", "Mm."][rng.randi() % 5], 2.5)
	_pop_money(total)
	if c.kind == "normal" and rng.randf() < 0.3: tip_jar.add_tip(rng.randi_range(1, 2))
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
	if c.flags.has("offer"):
		# fine, they find the money after all
		c.flags.erase("offer")
		c.flags["bye"] = "Suit yourself."
		register_use()
		return
	match c.kind:
		"tooth_buyer":
			c.say("A pity. Teeth don't keep.", 4.0)
			c.leave()
			return
		"landlord":
			flags["rent_paid"] = true
			flags["paid_with"] = "sanity"
			if GameSettings.data["stream"]: ui.toast("Chat has spoken.", UI.C_PURPLE)
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
	if rng.randf() < 0.3: tip_jar.add_odd(rng)
	c.leave("How rude!")

# --------------------------------------------------------------------------- strange customers
func _specials() -> void:
	# Mr. Whitlock, every evening at six (ish)
	if not flags["whitlock_done"] and minute >= 17 * 60 + 40 and minute < CLOSE_MIN:
		flags["whitlock_done"] = true
		# a little taller every day. He stares from Wednesday. On Thursday he forgot his face.
		var look := { "skin": Color(0.86, 0.86, 0.82), "shirt": Color(0.3, 0.3, 0.33), "pants": Color(0.12, 0.12, 0.14),
			"coat": Color(0.08, 0.08, 0.1), "hat": Color(0.06, 0.06, 0.07), "height": 1.22 + 0.05 * (day - 1), "width": 0.82, "eyes": Color(0.02, 0.02, 0.02), "face": "face_whitlock" }
		if day == 4:
			look.erase("face")
			look["weird"] = ["no_face"]
		var c := _new_customer(look, "whitlock", World.SPAWNS[0])
		if day >= 3: c.flags["stare"] = true
		if day == 5:
			# ...and on Friday there are two of him
			var e := _new_customer(look, "echo", World.SPAWNS[1])
			e.cname = "Mr. Whitlock"
			e.speed = 1.1
			e.flags["silent"] = true
			ui.toast("Mr. Whitlock is coming up the street. From both directions.", UI.C_PURPLE, 6.0)
		c.cname = "Mr. Whitlock"
		c.wants = ["silence"]
		c.speed = 1.1
		c.flags["silent"] = true
		c.flags["patient"] = true
		if not is_open:
			c.flags["outside"] = true
	# the regulars
	_regulars()
	# whoever wants the tooth comes the day after you get it
	if flags.get("items", []).has("tooth") and day > int(flags.get("tooth_day", 99)) and not flags.get("tooth_buyer_done", false) and minute >= 12 * 60 and is_open:
		flags["tooth_buyer_done"] = true
		var look := { "skin": Color(0.93, 0.9, 0.86), "shirt": Color(0.9, 0.9, 0.88), "pants": Color(0.2, 0.2, 0.25), "coat": Color(0.85, 0.85, 0.82),
			"hair": Color(0.1, 0.1, 0.1), "height": 1.12, "width": 0.85, "face": "face_townsfolk_2", "eyes": Color(0.1, 0.1, 0.1) }
		var c := _new_customer(look, "tooth_buyer")
		c.cname = "Dr. Quill"
		c.flags["direct_queue"] = true
		c.flags["patient"] = true
		c.flags["hello"] = "I believe you have a tooth of mine. Well. Not mine."
	# the one the camera can't see
	if not flags["unseen_done"] and minute >= flags["unseen_at"] and is_open:
		flags["unseen_done"] = true
		var look := VoxelPerson.random_look(rng)
		look["layer"] = 2
		look["face"] = "face_unseen"
		var c := _new_customer(look, "unseen")
		c.cname = ["Mr. Hollis", "Mr. Vane", "Mr. Lowe"][rng.randi() % 3]
		c.wants = ["salt", ["bread", "candles", "tea"][rng.randi() % 3]] if rng.randf() < 0.75 else ["bread", "milk"]
		# lamps hiccup as he crosses the threshold
		for l in world.lamps: l.light_energy = 0.2
	# Mrs. Thorne returns something she hasn't bought yet
	if not flags["thorne_done"] and minute >= flags["thorne_at"] and is_open:
		flags["thorne_done"] = true
		var look := { "skin": Color(0.9, 0.75, 0.65), "shirt": Color(0.55, 0.2, 0.45), "pants": Color(0.25, 0.15, 0.25),
			"hair": Color(0.85, 0.85, 0.88), "coat": Color(0.4, 0.15, 0.35), "height": 0.9, "face": "face_thorne" }
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
			"hair": Color(0.85, 0.85, 0.88), "coat": Color(0.4, 0.15, 0.35), "height": 0.9, "face": "face_thorne" }
		var c := _new_customer(look, "thorne_buyer")
		c.cname = "Mrs. Thorne"
		c.wants = [flags["thorne_owes"]]
	# the evening collector (after sunset)
	if not flags["collector_done"] and minute >= flags["collector_at"] and is_open:
		flags["collector_done"] = true
		var look := { "skin": Color(0.35, 0.3, 0.45), "shirt": Color(0.2, 0.1, 0.25), "pants": Color(0.15, 0.08, 0.18),
			"coat": Color(0.25, 0.12, 0.3), "eyes": Color(0.9, 0.8, 0.3), "weird": ["glow_eyes", "extra_arms"], "height": 1.1, "face": "face_collector" }
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
			"height": 1.45, "width": 1.2, "face": "face_landlord" }
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


# --------------------------------------------------------------------------- the till drawer (things that aren't money)
const ODD_BY_DAY := { 2: "tooth", 3: "key", 4: "coin", 5: "photo" }
const ODDITIES := {
	"tooth": { "name": "A human tooth", "say": "It's mine. Was mine.", "note": "Wrapped in a page from a dentist's diary. Somebody will want it." },
	"key": { "name": "A warm iron key", "say": "It opens something under your feet.", "note": "Always slightly warm. The customer said it opens something under your feet." },
	"coin": { "name": "A coin that blinks", "say": "It's worth more than it looks. It's also looking.", "note": "Gold, heavy, and it blinks when you aren't watching. Rent money?" },
	"photo": { "name": "A photograph of you, sleeping", "say": "I took it last night.", "note": "Taken from inside your room. Last night." },
}

func _accept_oddity(c: Customer) -> void:
	var id: String = c.flags["offer"]
	c.flags.erase("offer")
	if not flags.has("items"): flags["items"] = []
	flags["items"].append(id)
	if id == "tooth": flags["tooth_day"] = day
	today["served"] += 1
	today["sales"] += c.basket.size()
	Sfx.play("till", 0.6, 0.7)
	c.say(ODDITIES[id]["say"], 4.5)
	ui.toast("You put %s in the till drawer. (Tab: notebook)" % ODDITIES[id]["name"].to_lower(), UI.C_PURPLE, 5.0)
	if id == "photo":
		lose_sanity(8.0)
		today["night"].append("You look at the photograph again before bed.\nIn it, you're awake now. Looking at the camera.")
	c.leave()

func _rent_due() -> int:
	return RENT - (50 if flags.get("items", []).has("coin") else 0)

# --------------------------------------------------------------------------- stream mode
## big decisions at the till get a "CHAT DECIDES" banner (once per customer)
func _chat_votes() -> void:
	if not GameSettings.data["stream"]: return
	var c := _front()
	if c == null or c.flags.get("voted", false): return
	var q := ""
	var a := ""
	var b := ""
	if c.flags.has("offer"):
		q = "%s offers %s instead of money." % [c.cname, ODDITIES[c.flags["offer"]]["name"].to_lower()]
		a = "Take it"; b = "Insist on money"
	elif c.kind == "landlord":
		q = "The Landlord wants the rent."
		a = "Pay in money"; b = "Pay in... something else"
	elif c.kind == "returner":
		q = "Mrs. Thorne wants a refund for something she hasn't bought yet."
		a = "Refund her"; b = "Refuse"
	elif c.kind == "unseen" and c.basket.has("salt"):
		q = "Someone the camera can't see wants salt."
		a = "Sell it"; b = "Refuse"
	elif c.basket.has("jar") and minute >= SUNSET:
		q = "A Whispering Jar, after sunset."
		a = "Sell it"; b = "Refuse"
	if q == "": return
	c.flags["voted"] = true
	ui.chat_vote(q, a, b)

# --------------------------------------------------------------------------- the Saturday paper
func _newspaper(title: String) -> Array:
	var broken: Array = flags.get("broken_log", [])
	var kept: Array = flags.get("kept_log", [])
	var has_broken := func(word: String) -> bool:
		for b in broken:
			if word.to_lower() in String(b).to_lower(): return true
		return false
	var stories := []
	# the headline: the most remarkable thing that happened
	if title == "EVICTED":
		stories.append(["SHOP UNDER NEW MANAGEMENT. AGAIN.", "Nobody in Hollowmere remembers the previous owner. \"There was a previous owner?\" asked everyone."])
	elif title == "WHO RUNS THE SHOP NOW?":
		stories.append(["SHOPKEEPER \"NEVER HAPPIER\", SAYS SHOPKEEPER", "Customers report the new owner of Eldritch & Sons smiles at all times, including while asleep, which is also all times."])
	elif flags.get("paid_with", "") == "sanity":
		stories.append(["LANDLORD PAID IN \"SOMETHING\"; SHOPKEEPER CANNOT SAY WHAT", "\"It was adequate,\" said the Landlord, from inside a shadow that wasn't there a moment ago."])
	elif has_broken.call("camera"):
		stories.append(["LOCAL SHOP SELLS SALT TO INVISIBLE MAN", "\"He seemed nice,\" said the shopkeeper, pointing at nothing. All the salt in the shop has since turned black."])
	elif flags.get("bread_below", false):
		stories.append(["SOMETHING UNDER ELDRITCH & SONS \"VERY FOND OF BREAD\"", "Floorboards thinner than last week. Local bakers delighted. Local floorboards less so."])
	elif int(flags.get("whitlock_served", 0)) >= 5:
		stories.append(["MAN RECEIVES SILENCE FIVE NIGHTS RUNNING", "\"...\" said Mr. Whitlock. \"...\" added Mr. Whitlock."])
	else:
		stories.append(["NEW OWNER SURVIVES FIRST WEEK", "Eldritch & Sons stays open. The town is relieved, mostly. The rent was paid in actual money, which the Landlord described as \"adequate\"."])
	# the rest of the page
	if day >= 4: stories.append(["Woman's House Boarded Up From The Inside", "Neighbours \"not surprised\". Agnes unavailable for comment, or anything."])
	stories.append(["Man Buys Bread And Milk, Again", "Mr. Pell, who has bought bread and milk every morning for ninety years, says he is \"the same as always\". He has more arms than last week."])
	if has_broken.call("jar"): stories.append(["Jars Heard Whispering Until Dawn", "Residents ask that Whispering Jars be sold in daylight, as is traditional."])
	if has_broken.call("refund"): stories.append(["Pensioner's Laugh Heard In Stairwells Citywide", "Hollowmere has no stairwells."])
	if flags.get("tooth_buyer_done", false) and not flags.get("items", []).has("tooth"): stories.append(["Dentist Recovers Lost Tooth", "Dr. Quill: \"It was not mine, and I could not be happier.\""])
	if flags.get("below_slammed", false): stories.append(["Trapdoor Slammed; Something \"Remembers\"", "It has asked us to print that it is not angry. Just disappointed."])
	if day >= 3: stories.append(["Building Appears On Empty Lot Overnight", "Planning office: \"We approved it. We think. Nobody remembers the meeting.\""])
	stories = stories.slice(0, 4)
	stories.append(["CLASSIFIEDS", "WANTED: Tinned Silence, any quantity. LOST: one shadow, answers to nothing. FOR SALE: lot, empty (not any more). Rules kept this week: %d. Rules broken: %d." % [kept.size(), broken.size()]])
	return stories

# --------------------------------------------------------------------------- regulars (they change a little every day)
const PELL_HELLO := ["Morning! The usual.", "Morning. The usual.", "Morning. The us-ual.", "MORNING. THE. USUAL.", "Have we met? The usual."]
const PELL_BYE := ["See you tomorrow!", "See you tomorrow.", "See you tomorrow. And tomorrow.", "SEE YOU.", "Same time forever."]
const AGNES_HELLO := ["Hello, dear! I live just across the street.", "Did you hear that hammering last night?", "Someone knocks on my door at night. I don't answer."]
const AGNES_BYE := ["Your grandfather was a lovely man.", "Lock your doors, dear.", "If I stop coming in... don't come looking."]

func _regulars() -> void:
	if not is_open or day > 5: return
	# Mr. Pell: every morning, bread and milk, slightly less like Mr. Pell each time
	if not flags.get("pell_day_%d" % day, false) and minute >= 8 * 60 + 40:
		flags["pell_day_%d" % day] = true
		var weird := []
		if day >= 3: weird.append("glow_eyes")
		if day >= 4: weird.append("long_arms")
		if day >= 5: weird.append("extra_arms")
		var look := { "skin": Color(0.88, 0.72, 0.6), "shirt": Color(0.45, 0.35, 0.25), "pants": Color(0.2, 0.18, 0.15),
			"hair": Color(0.3, 0.22, 0.15), "hat": Color(0.25, 0.2, 0.15), "height": 1.0 + 0.045 * (day - 1), "face": "face_townsfolk_1",
			"eyes": Color(0.9, 0.85, 0.3), "weird": weird }
		var c := _new_customer(look)
		c.cname = "Mr. Pell"
		c.wants = ["bread", "milk"]
		c.flags["hello"] = PELL_HELLO[day - 1]
		c.flags["bye"] = PELL_BYE[day - 1]
	# Agnes from across the street: Monday to Wednesday. Then her house is boarded up.
	if day <= 3 and not flags.get("agnes_day_%d" % day, false) and minute >= 11 * 60:
		flags["agnes_day_%d" % day] = true
		var look := { "skin": Color(0.92, 0.8, 0.72), "shirt": Color(0.4, 0.45, 0.6), "pants": Color(0.3, 0.3, 0.4),
			"hair": Color(0.88, 0.88, 0.9), "height": 0.9, "face": "face_townsfolk_3" }
		var c := _new_customer(look, "normal", World.SPAWNS[0])
		c.cname = "Agnes"
		c.wants = [["tea", "candles"], ["tea", "bread"], ["candles", "salt", "salt"]][day - 1]
		c.flags["hello"] = AGNES_HELLO[day - 1]
		c.flags["bye"] = AGNES_BYE[day - 1]

# --------------------------------------------------------------------------- juice
## "+$12" floats up from the till and a few coins hop out
func _pop_money(amount: int) -> void:
	var at := Vector3(-4.6, 1.5, 2.05)
	var l := Vox.label(world, ("+$%d" % amount) if amount >= 0 else ("-$%d" % -amount), at, 56, UI.C_GOLD if amount >= 0 else UI.C_RED, true)
	l.no_depth_test = true
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", at + Vector3(0, 0.4, 0), 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 1.3).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)
	if amount <= 0: return
	var coin_mat := Vox.obj_mat(Color(1, 0.8, 0.3), true)
	for i in mini(6, 2 + amount / 5):
		var coin := Vox.box(world, at, Vector3(0.07, 0.025, 0.07), coin_mat, false)
		var side := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.25, 0.1))
		var ct := coin.create_tween()
		ct.tween_interval(i * 0.05)
		ct.tween_property(coin, "position", at + side * 0.5 + Vector3(0, rng.randf_range(0.3, 0.5), 0), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ct.tween_property(coin, "position", at + side + Vector3(0, -0.2, 0), 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		ct.tween_callback(coin.queue_free)
		coin.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, 0)

# --------------------------------------------------------------------------- 3 AM (Wednesday night)
func _start_night_walk(lines: Array) -> void:
	night_walk = true
	walk_lines = lines
	walk_t = 0.0
	flags["walk_seen"] = false
	minute = 27 * 60 + 7
	player.global_position = Vector3(-2.2, 0.05, -8.0)
	player.rotation.y = 0.0
	player.frozen = false
	_apply_time_of_day()
	for i in world.lamps.size():
		world.lamps[i].light_energy = 0.35 if i == 2 else 0.0
		world.lamp_meshes[i].visible = i == 2
	# something at the far end of the street
	walk_figure = VoxelPerson.new()
	add_child(walk_figure)
	walk_figure.build({ "skin": Color(0.16, 0.13, 0.2), "shirt": Color(0.1, 0.08, 0.13), "pants": Color(0.08, 0.07, 0.1),
		"coat": Color(0.13, 0.1, 0.17), "eyes": Color(0.85, 0.4, 1.0), "weird": ["glow_eyes", "long_arms"], "height": 1.5, "width": 0.9 })
	walk_figure.position = Vector3(-10.5, 0, 10.2)
	walk_figure.rotation.y = -PI / 2
	# a dim purple light from the street side: you see the shape, not the details
	var glow := OmniLight3D.new()
	walk_figure.add_child(glow)
	glow.global_position = walk_figure.position + Vector3(3.0, 2.2, -1.5)
	glow.light_color = Color(0.7, 0.4, 1.0)
	glow.light_energy = 2.5
	glow.omni_range = 7.0
	Sfx.play("knock", 1.0, 0.8)
	ui.toast("03:07. Someone is knocking on the front door. Three times.", UI.C_PURPLE, 6.0)

func _night_walk_tick(dt: float) -> void:
	walk_t += dt
	var seen: bool = flags.get("walk_seen", false)
	if not seen and fmod(walk_t, 7.0) < dt:
		Sfx.play("knock", 0.9, 0.8)
	if walk_figure == null: return
	walk_figure.rotation.y = lerp_angle(walk_figure.rotation.y, atan2(-(player.global_position.x - walk_figure.position.x), -(player.global_position.z - walk_figure.position.z)), dt * 2.0)
	if not seen and player.global_position.z > 5.0:
		if not flags.has("walk_out_t"):
			flags["walk_out_t"] = walk_t
			Sfx.play("whisper", 0.7, 0.8)
			ui.toast("Nobody at the door. But there's someone at the end of the street.", UI.C_PURPLE, 5.0)
		if walk_t - float(flags["walk_out_t"]) > 3.5:
			flags["walk_seen"] = true
			walk_figure.queue_free()
			walk_figure = null
			Sfx.play("drone", 1.0, 0.5)
			for l in world.street_lights: l.light_energy = 0.0
			ui.toast("Go back to sleep.", UI.C_PURPLE, 6.0)
			get_tree().create_timer(1.2).timeout.connect(_apply_time_of_day)

func _finish_night_walk() -> void:
	night_walk = false
	flags.erase("walk_out_t")
	if walk_figure:
		walk_figure.queue_free()
		walk_figure = null
	var lines := walk_lines.duplicate()
	if flags.get("walk_seen", false): lines.append("You don't remember walking back to bed.\nYour shoes are wet.")
	else: lines.append("You pull the blanket over your head. The knocking stops at dawn.")
	player.frozen = true
	ui.night_card(lines, _next_day)

# --------------------------------------------------------------------------- end of day
const NIGHTS := {
	1: ["You lock up and climb into grandpa's old bed.", "At 3 AM, someone knocks on the back door. Three times.", "In the morning there's nobody there. Just wet footprints.\nLeading in."],
	2: ["The fog rolls in thick tonight.", "Across the street: hammering. All night long.", "Nobody builds anything at this hour."],
	3: ["You dream of the shop. In the dream the shelves go on forever.", "Grandpa is standing in aisle three.\n\"Don't let them see you're scared,\" he says."],
	4: ["The town is very quiet tonight.", "Somewhere under the floorboards, something is counting coins.", "Tomorrow is Friday."],
}

const LOW_NIGHTS := [
	"You count the ceiling boards. There's one more than yesterday.",
	"Your reflection goes to bed a few seconds after you do.",
	"Someone in the shop downstairs is restocking the shelves. You live alone.",
	"The bell over the door rings all night. Nobody comes in.",
	"You dream you are a customer. The shopkeeper has your face.",
	"The tins of Silence are humming. Very, very quietly.",
]

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
	if sanity < 50.0: night_lines.append(LOW_NIGHTS[rng.randi() % LOW_NIGHTS.size()])
	if day == 3: night_lines.append("Across the street, Agnes's lights go out one by one.\nThen they come back on. Purple.")
	if today["night"].size() > 0: lose_sanity(5.0 * today["night"].size())
	if ending: return
	print("[day %d] %s" % [day, " | ".join(lines)])
	if autotest:
		_next_day()
		return
	if day == 3:
		ui.show_summary(lines, func(): _start_night_walk(night_lines))
	else:
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
	if day == 4 and not flags.get("basement_unlocked", false):
		ui.toast("The padlock on the storeroom trapdoor is lying on the floor. Still locked.", UI.C_PURPLE, 7.0)
	if day == 4:
		world.board_up_agnes()
		ui.toast("Agnes's house across the street is boarded up. From the inside.", UI.C_PURPLE, 7.0)
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
	# orders placed last night arrive this morning (their time was counted past midnight)
	for d in deliveries:
		d["at"] = maxf(7 * 60 + 5, float(d["at"]) - 24 * 60)
	if not autotest and not OS.get_cmdline_user_args().has("--ui-shots"): SaveGame.save(self)

func _week_won() -> void:
	var how: String = flags.get("paid_with", "money")
	var title := "OPEN FOR BUSINESS" if how == "money" else "PAID IN FULL (SORT OF)"
	var body := "The Landlord steps backwards into a shadow that wasn't there a moment ago.\n\nThe shop is yours for another week.\n\nMoney left: $%d\nReputation: %.1f / 5\nSanity: %d\nMr. Whitlock served: %d times" % [money, rep, int(sanity), flags.get("whitlock_served", 0)]
	if how != "money": body = "You paid the rent in something that wasn't money. You'd tell people what, if you could remember.\n\n" + body
	_ending(title, body, UI.C_GOLD)

func _ending(title: String, body: String, color: Color) -> void:
	ending = true
	if not autotest: SaveGame.clear()
	print("[ending] %s | day %d | money %d | sanity %d" % [title, day, money, int(sanity)])
	if autotest:
		get_tree().quit()
		return
	player.frozen = true
	ui.show_newspaper(_newspaper(title), func(): ui.show_ending(title, body, color, func(): _restart(true)))

# --------------------------------------------------------------------------- systems test (--systems-test)
## save/continue round trip, overnight deliveries, the phone, an odd payment, the coin and the rent
func _systems_test() -> void:
	var ok := func(name: String, cond: bool) -> void: print("[sys] %-38s %s" % [name, "PASS" if cond else "FAIL"])
	started = true
	# --- save / load
	day = 3; money = 123; sanity = 77.0; rep = 4.2
	flags["items"] = ["coin"]
	world.shelves[2].product = "jar"; world.shelves[2].count = 5
	deliveries = [{ "id": "tea", "at": 24 * 60 + 7 * 60 + 5, "beyond": false }]
	SaveGame.save(self)
	day = 1; money = 0; flags = {}; world.shelves[2].product = ""; world.shelves[2].count = 0; deliveries = []
	ok.call("save file exists", SaveGame.exists() and SaveGame.day_saved() == 3)
	SaveGame.load_into(self)
	ok.call("loaded day/money/sanity", day == 3 and money == 123 and int(sanity) == 77)
	ok.call("loaded shelf + items", world.shelves[2].product == "jar" and world.shelves[2].count == 5 and flags["items"].has("coin"))
	ok.call("world rebuilt for Wednesday", world.mystery_house.visible)
	# --- overnight delivery lands in the morning
	_next_day()
	ok.call("overnight delivery due this morning", deliveries.size() == 1 and float(deliveries[0]["at"]) <= 7 * 60 + 5)
	SaveGame.clear()
	ok.call("save cleared", not SaveGame.exists())
	# --- the coin knocks $50 off the rent
	ok.call("rent with the coin", _rent_due() == RENT - 50)
	# --- the phone rings on Thursday at 10:40 and can be answered
	ui.close_panel()
	day = 4; minute = 639.0
	await get_tree().create_timer(1.0).timeout
	ok.call("phone rings", phone.is_ringing())
	phone.answer()
	ok.call("call shows on screen", ui.is_open() and not phone.is_ringing())
	ui.close_panel()
	# --- a customer pays with a tooth
	day = 2
	var c := _new_customer(VoxelPerson.random_look(rng))
	c.cname = "Test"
	c.basket = ["bread"]
	c.flags["offer"] = "tooth"
	queue = [c]
	c.state = "wait"
	ok.call("till offers the tooth", register_prompt().contains("tooth"))
	var m0 := money
	register_use()
	ok.call("tooth in the drawer, no money", flags["items"].has("tooth") and money == m0)
	# --- tip jar
	tip_jar.add_tip(3)
	var m1 := money
	tip_jar.empty()
	ok.call("tip jar empties into the till", money == m1 + 3 and tip_jar.tips == 0)
	# --- the basement: locked on Tuesday, open with the key, sells bread on Thursday
	day = 2
	ok.call("trapdoor locked on Tuesday", not basement.unlocked())
	flags["items"].append("key")
	basement.use(self)
	ok.call("warm key unlocks it", basement.unlocked() and not flags["items"].has("key"))
	day = 4
	world.shelves[0].product = "bread"; world.shelves[0].count = 6
	basement.use(self)
	await get_tree().create_timer(1.0).timeout
	ok.call("Thing Below asks (dialogue open)", ui.is_open())
	ui.close_panel()
	await get_tree().create_timer(0.6).timeout
	ok.call("lid shuts after Esc", basement.open_t == 0.0)
	ok.call("once a day", basement.prompt(self).contains("resting"))
	# --- Grandpa appears and can be listened to
	day = 3; minute = 16 * 60 - 1
	haunting.ghost_day = 0
	await get_tree().create_timer(0.5).timeout
	ok.call("Grandpa appears", haunting.ghost != null)
	haunting.use(self)
	ok.call("Grandpa gives his hint", ui.is_open() and haunting.ghost == null)
	ui.close_panel()
	# --- low sanity: an unseen shelf changes its label, then changes back
	sanity = 20.0
	player.global_position = Vector3(0, 0, 3.0)
	player.rotation.y = PI          # looking at the street: every shelf is behind you
	haunting.shift_t = 0.0
	await get_tree().create_timer(0.3).timeout
	var faked: Array = world.shelves.filter(func(sh): return sh.fake != "")
	ok.call("an unseen shelf lies", faked.size() == 1)
	# --- the newspaper
	flags["broken_log"] = ["Sold salt to someone the camera couldn't see"]
	var paper := _newspaper("OPEN FOR BUSINESS")
	ok.call("newspaper headline", paper[0][0] == "LOCAL SHOP SELLS SALT TO INVISIBLE MAN" and paper.back()[0] == "CLASSIFIEDS")
	ui.show_newspaper(paper, func(): pass)
	ok.call("newspaper shows", ui.is_open())
	ui.close_panel()
	# --- stream mode banner
	GameSettings.data["stream"] = true
	var lc := _new_customer(VoxelPerson.random_look(rng), "landlord")
	queue = [lc]
	lc.state = "wait"
	_chat_votes()
	ok.call("chat vote banner", ui.vote_box.visible and lc.flags.get("voted", false))
	GameSettings.data["stream"] = false
	# --- graphics quality (only meaningful on Forward+)
	if world.fancy:
		GameSettings.data["hq"] = false
		world.apply_quality()
		var low: bool = not world.env.volumetric_fog_enabled and not world.sun.shadow_enabled and not world.lamps[0].shadow_enabled
		GameSettings.data["hq"] = true
		world.apply_quality()
		var high: bool = world.env.volumetric_fog_enabled and world.sun.shadow_enabled and world.env.ssao_enabled
		ok.call("quality low/high switches effects", low and high)
	else:
		print("[sys] (not Forward+ here: quality toggle skipped)")
	get_tree().quit()

# --------------------------------------------------------------------------- kerb test (--kerb-test)
## Tom got stuck on the grass below the kerb. Walk from the grass back onto the pavement.
func _kerb_test() -> void:
	started = true
	player.global_position = Vector3(25, 0.0, 3.0)
	player.rotation.y = PI          # facing +Z, towards the street
	await get_tree().create_timer(0.5).timeout
	print("[kerb] start ", player.global_position)
	Input.action_press("forward")
	await get_tree().create_timer(2.0).timeout
	Input.action_release("forward")
	var p := player.global_position
	print("[kerb] end ", p, "  ", "PASS" if p.z > 6.5 else "FAIL")
	# and the road -> far pavement -> back
	player.global_position = Vector3(25, 0.0, 11.0)
	await get_tree().create_timer(0.3).timeout
	Input.action_press("forward")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("forward")
	p = player.global_position
	print("[kerb] far side ", p, "  ", "PASS" if p.z > 16.0 else "FAIL")
	# the front door: shut blocks you, open lets you out, opens itself for customers
	player.global_position = Vector3(0, 0, 3.4)
	player.rotation.y = PI
	await get_tree().create_timer(0.3).timeout
	Input.action_press("forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("forward")
	print("[door] shut: z=%.2f  %s" % [player.global_position.z, "PASS" if player.global_position.z < 5.2 else "FAIL"])
	player.global_position = Vector3(0, 0, 4.4)
	await get_tree().create_timer(0.2).timeout
	player.look_target = world.door
	player.interact()
	await get_tree().create_timer(0.8).timeout
	Input.action_press("forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("forward")
	print("[door] propped: z=%.2f angle=%.2f  %s" % [player.global_position.z, world.door.angle, "PASS" if player.global_position.z > 6.3 else "FAIL"])
	world.door.use(self)
	player.global_position = Vector3(-4.6, 0, 0.7)
	await get_tree().create_timer(1.0).timeout
	var shut_angle: float = world.door.angle
	var c := _new_customer(VoxelPerson.random_look(rng), "normal", Vector3(0, 0, 9.0))
	c.wants = ["bread"]
	var max_angle := 0.0
	for i in 40:
		await get_tree().create_timer(0.1).timeout
		max_angle = maxf(max_angle, world.door.angle)
	print("[door] closed again: %.2f, opened for customer: %.2f  %s" % [shut_angle, max_angle, "PASS" if shut_angle < 0.02 and max_angle > 1.0 else "FAIL"])
	get_tree().quit()

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
	# close-up of the milk shelf (hand-made models)
	player.global_position = Vector3(-3.3, 0, -2.6)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.32
	minute = 11 * 60
	_apply_time_of_day()
	await snap.call("shelf_closeup")
	# character line-up: every face side by side
	var lineup := [
		{ "face": "face_townsfolk_1", "shirt": Color(0.55, 0.2, 0.2) }, { "face": "face_townsfolk_2", "shirt": Color(0.2, 0.35, 0.55) },
		{ "face": "face_townsfolk_3", "shirt": Color(0.3, 0.45, 0.3) }, { "face": "face_townsfolk_4", "shirt": Color(0.6, 0.5, 0.25) },
		{ "face": "face_unseen", "shirt": Color(0.35, 0.35, 0.4) }, { "face": "face_thorne", "shirt": Color(0.55, 0.2, 0.45), "height": 0.9 },
		{ "face": "face_whitlock", "shirt": Color(0.3, 0.3, 0.33), "coat": Color(0.08, 0.08, 0.1), "height": 1.15 },
		{ "face": "face_collector", "shirt": Color(0.2, 0.1, 0.25), "weird": ["glow_eyes"] },
		{ "face": "face_landlord", "shirt": Color(0.04, 0.03, 0.06), "weird": ["glow_eyes", "tentacle_beard"], "height": 1.2 },
	]
	var people: Array = []
	for i in lineup.size():
		var vp := VoxelPerson.new()
		add_child(vp)
		var lk: Dictionary = lineup[i]
		lk["pants"] = Color(0.18, 0.18, 0.22)
		vp.build(lk)
		vp.position = Vector3(-3.4 + i * 0.85, 0, 0.9)
		vp.rotation.y = PI
		people.append(vp)
	player.global_position = Vector3(0, 0, 4.4)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.12
	player.cam.fov = 70
	await snap.call("lineup")
	for vp in people: vp.queue_free()
	player.cam.fov = 75
	# the shop front from across the street (Tom's sign)
	player.global_position = Vector3(0.5, 0, 13.5)
	player.rotation.y = 0.0
	player.cam.rotation.x = 0.1
	minute = 10 * 60
	_apply_time_of_day()
	await snap.call("facade")
	minute = 22 * 60
	_apply_time_of_day()
	await snap.call("street_night")
	player.global_position = Vector3(3.0, 0, 3.6)
	player.rotation.y = atan2(7.0, 7.1)
	player.cam.rotation.x = -0.05
	await snap.call("shop_night")
	sanity = 25.0
	minute = 21 * 60
	_apply_time_of_day()
	ui.update_hud()
	await snap.call("low_sanity")
	sanity = 100.0
	ui.update_hud()
	# day 1: carrying a box -> the guide arrow + the glowing shelf
	day = 1
	minute = 9 * 60
	_apply_time_of_day()
	world.letter.visible = false
	var box := spawn_crate("candles", 8, Vector3(0, 0, -1))
	player.pick_up(box)
	player.global_position = Vector3(0.5, 0, 0.5)
	player.rotation.y = 0.35
	player.cam.rotation.x = -0.05
	await snap.call("guide")
	player.put_down()
	box.queue_free()
	# shoppers with want-bubbles
	var shoppers := []
	for i in 3:
		var c := _new_customer(VoxelPerson.random_look(rng), "normal", Vector3(-2.5 + i * 1.6, 0, 1.8))
		c.wants = [["bread", "milk", "tea"][i]]
		c.path = [Vector3(-2.5 + i * 1.6, 0, -3.0)]
		c.speed = 0.3
		shoppers.append(c)
	player.global_position = Vector3(-0.5, 0, 4.3)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.12
	_pop_money(24)
	await snap.call("bubbles")
	for c in shoppers:
		customers.erase(c)
		c.queue_free()
	# the money pop at the till, from the shopkeeper's side
	player.global_position = Vector3(-4.6, 0, 0.6)
	player.rotation.y = PI
	player.cam.rotation.x = -0.25
	_pop_money(31)
	await get_tree().create_timer(0.0).timeout
	await snap.call("money")
	# Thursday: Agnes's house. Friday night: the lamps go wrong.
	world.show_mystery_house()
	world.board_up_agnes()
	player.global_position = Vector3(-5.0, 0, 11.5)
	player.rotation.y = 3.0 * PI / 4.0
	player.cam.rotation.x = 0.05
	minute = 12 * 60
	_apply_time_of_day()
	await snap.call("agnes_boarded")
	day = 5
	minute = 21 * 60
	flags["landlord_came"] = true   # not now, thank you
	player.global_position = Vector3(2.0, 0, 11.0)
	player.rotation.y = PI / 2
	_apply_time_of_day()
	await snap.call("friday_street")
	# 3 AM: something at the end of the street
	day = 3
	_start_night_walk([])
	player.global_position = Vector3(0.0, 0, 6.6)
	player.rotation.y = 1.90
	player.cam.rotation.x = 0.02
	await snap.call("night_walk")
	night_walk = false
	if walk_figure: walk_figure.queue_free()
	# the front door, from inside: shut (with the prompt), then open for a customer
	minute = 11 * 60
	_apply_time_of_day()
	player.global_position = Vector3(0.3, 0, 3.2)
	player.rotation.y = PI
	player.cam.rotation.x = 0.0
	await snap.call("door_shut")
	var visitor := _new_customer(VoxelPerson.random_look(rng), "normal", Vector3(0, 0, 8.0))
	visitor.wants = ["bread"]
	await get_tree().create_timer(1.0).timeout
	await snap.call("door_open")
	customers.erase(visitor)
	visitor.queue_free()
	# batch B: the phone ringing + tip jar, from behind the counter
	day = 2
	minute = 11 * 60 + 30
	_apply_time_of_day()
	tip_jar.add_tip(9)
	player.global_position = Vector3(-5.2, 0, 0.4)
	player.rotation.y = PI / 2 + 0.35
	player.cam.rotation.x = -0.2
	await get_tree().create_timer(0.5).timeout
	await snap.call("phone")
	ui.close_panel()
	# Grandpa in the aisle
	day = 3
	minute = 16 * 60 - 1
	haunting.ghost_day = 0
	await get_tree().create_timer(0.2).timeout
	player.global_position = Vector3(0.0, 0, 1.6)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.08
	await snap.call("grandpa")
	haunting._vanish(false)
	# the trapdoor, open, and the Thing Below's offer (stream mode on for the banner)
	day = 4
	minute = 15 * 60
	_apply_time_of_day()
	world.shelves[0].product = "bread"; world.shelves[0].count = 8; world.shelves[0].refresh()
	player.global_position = Vector3(-1.5, 0, -5.6)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.75
	GameSettings.data["stream"] = true
	basement.use(self)
	await get_tree().create_timer(1.0).timeout
	await snap.call("basement")
	ui.close_panel()
	GameSettings.data["stream"] = false
	ui.vote_box.visible = false
	ui.vote_t = 0.0
	# the Saturday paper
	flags["broken_log"] = ["Sold a Whispering Jar after sunset"]
	flags["kept_log"] = ["a", "b", "c", "d", "e", "f", "g"]
	flags["whitlock_served"] = 5
	day = 5
	ui.show_newspaper(_newspaper("OPEN FOR BUSINESS"), func(): pass)
	await snap.call("newspaper")
	ui.close_panel()
	# screen effects, one at a time, in the shop by day
	sanity = 100.0
	minute = 11 * 60
	_apply_time_of_day()
	player.global_position = Vector3(-4.6, 0, 0.9)
	player.rotation.y = PI
	player.cam.rotation.x = -0.1
	for fx in ["", "fx_grain", "fx_vhs", "fx_crt", "fx_pixels"]:
		for k in GameSettings.LABELS: GameSettings.data[k] = (k == fx)
		ui.update_hud()
		await snap.call("fx_" + (fx.substr(3) if fx != "" else "none"))
	GameSettings.data["fx_grain"] = true
	ui.show_settings(func(): pass)
	await snap.call("settings")
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
			print("[bot] quit-at reached: money %d, served %d, sales %d, angry %d" % [money, today["served"], today["sales"], today["angry"]])
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
