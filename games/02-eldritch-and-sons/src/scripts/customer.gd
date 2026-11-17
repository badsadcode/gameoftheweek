## customer.gd : a shopper. Walks in, finds what they want on the shelves, queues at the till,
## pays (or gets refused) and leaves. Special customers (kind != "normal") are driven by main.gd's
## rules, which hook in through `kind` and `flags`.
class_name Customer
extends Node3D

var game
var body: VoxelPerson
var bubble: Label3D
var kind := "normal"
var cname := "Customer"
var wants: Array = []          # product ids still to find
var basket: Array = []         # product ids picked up
var missed := 0                # wanted things that weren't on the shelves
var state := "arrive"          # arrive | browse | queue | wait | leave | gone | linger
var path: Array = []
var speed := 1.5
var wait_t := 0.0
var patience := 55.0
var reach_t := 0.0
var target_shelf: Shelf = null
var exit_spawn := Vector3.ZERO
var flags := {}                # rule-specific data
var refund_item := ""          # for customers who come to return something
var bubble_t := 0.0

func setup(g, look: Dictionary, spawn: Vector3) -> void:
	game = g
	body = VoxelPerson.new()
	add_child(body)
	body.build(look)
	bubble = Vox.label(self, "", Vector3(0, 2.25 * look.get("height", 1.0) + 0.1, 0), 64, Color(1, 1, 1), true)
	position = spawn
	exit_spawn = World.SPAWNS[1] if spawn.x < 0 else World.SPAWNS[0]
	path = [World.DOOR_OUT, World.DOOR_IN]

func say(text: String, dur := 2.5) -> void:
	bubble.text = text
	bubble_t = dur

func basket_total() -> int:
	var t := 0
	for id in basket: t += int(Products.info(id)["price"])
	return t

func basket_text() -> String:
	var names := {}
	for id in basket: names[id] = names.get(id, 0) + 1
	var parts: Array = []
	for id in names: parts.append("%s x%d" % [Products.pname(id), names[id]] if names[id] > 1 else Products.pname(id))
	return ", ".join(parts)

func at_counter() -> bool:
	return state == "wait"

func _walk(dt: float) -> bool:
	## follows `path`; returns true when it's empty
	if path.is_empty():
		body.speed = 0.0
		return true
	var target: Vector3 = path[0]
	var to := target - position
	to.y = 0
	var d := to.length()
	if d < 0.08:
		path.pop_front()
		if position.distance_to(World.DOOR_OUT) < 0.5 or position.distance_to(World.DOOR_IN) < 0.5:
			if not flags.get("silent", false): game.door_passed(self)
		return path.is_empty()
	var step := minf(d, speed * dt)
	position += to / d * step
	body.speed = speed
	var look_dir := Vector3(to.x, 0, to.z)
	if look_dir.length() > 0.01:
		var want := atan2(-look_dir.x, -look_dir.z)
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, dt * 10.0))
	return false

func _face(p: Vector3, dt: float) -> void:
	var v := p - position
	rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), minf(1.0, dt * 8.0))

func _next_shelf() -> void:
	while not wants.is_empty():
		var id: String = wants[0]
		var s: Shelf = game.find_shelf(id)
		if s:
			target_shelf = s
			path = [s.front_point()]
			state = "browse"
			return
		wants.pop_front()
		missed += 1
		say("?", 2.0)
		game.on_missed(self, id)
	# nothing left to find
	if basket.is_empty():
		leave(">:(" if missed > 0 else "...")
		game.on_left_empty(self)
	else:
		state = "queue"
		path = [World.HUB, Vector3(World.HUB.x, 0, 3.4)]
		game.join_queue(self)

func leave(msg := "") -> void:
	if msg != "": say(msg, 3.0)
	state = "leave"
	game.leave_queue(self)
	body.pose = "idle"
	var p := position
	path = []
	if p.z < 2.8 and p.x < -1.0: path.append(Vector3(-1.6, 0, p.z))
	path.append(Vector3(minf(p.x, 0.6) if p.z > 2.8 else 0.0, 0, 3.9))
	path.append(World.DOOR_IN)
	path.append(World.DOOR_OUT)
	path.append(exit_spawn)

func queue_spot_changed(i: int) -> void:
	if state == "queue" or state == "wait":
		state = "queue"
		var spot: Vector3 = World.QUEUE[mini(i, World.QUEUE.size() - 1)]
		if position.z < 3.0:
			# still among the shelves: go round the end of the counter, not through it
			path = [World.HUB, Vector3(World.HUB.x, 0, 3.4), spot]
		else:
			path = [spot]

func _process(dt: float) -> void:
	if bubble_t > 0.0:
		bubble_t -= dt
		if bubble_t <= 0.0: bubble.text = ""
	match state:
		"arrive":
			if _walk(dt):
				game.on_entered(self)
				if state != "arrive": return
				if flags.get("direct_queue", false):
					# came for the till, not the shelves (returns, rent...)
					state = "queue"
					game.join_queue(self)
				else:
					_next_shelf()
		"browse":
			if reach_t > 0.0:
				reach_t -= dt
				body.pose = "reach"
				if target_shelf: _face(target_shelf.global_position, dt)
				if reach_t <= 0.0:
					body.pose = "idle"
					var id: String = wants.pop_front()
					if target_shelf and target_shelf.product == id and target_shelf.take_one():
						basket.append(id)
						game.on_picked(self, id)
					else:
						missed += 1
						say("?", 2.0)
						game.on_missed(self, id)
					target_shelf = null
					_next_shelf()
			elif _walk(dt):
				reach_t = 0.9
		"queue":
			if _walk(dt):
				var i: int = game.queue.find(self)
				if i == 0:
					state = "wait"
					wait_t = 0.0
					if refund_item != "": say("RETURN", 999.0)
					elif kind == "landlord": say("RENT.", 999.0)
					else: say("$%d" % basket_total(), 999.0)
				_face(Vector3(-4.6, 0, 2.0), dt)
		"wait":
			body.pose = "pay" if fmod(wait_t, 6.0) < 1.2 else "idle"
			_face(Vector3(-4.6, 0, 1.0), dt)
			wait_t += dt
			if wait_t > patience and not flags.get("patient", false):
				game.on_impatient(self)
				leave(">:(")
		"linger":
			body.speed = 0.0
			body.pose = flags.get("linger_pose", "stare")
			_face(game.player.global_position, dt)
		"leave":
			if _walk(dt):
				state = "gone"
				game.on_gone(self)
				queue_free()
