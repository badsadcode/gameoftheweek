## haunting.gd : the shop is haunted, gently.
##  - Grandpa's ghost appears once a day in the aisle with one piece of advice. He is wrong
##    exactly once (Thursday: the bread).
##  - When your sanity is low, shelves you aren't looking at change: a label shows something that
##    doesn't exist, and when you look away again it's back to normal. Very low: two shelves swap.
class_name Haunting
extends Node3D

const HINTS := {
	1: "Salt. Always keep salt on the shelves. Don't ask me why. Ask THEM why.\n\nActually, don't.",
	2: "Lamp oil. People here are afraid of the dark.\n\nThey're right to be.",
	3: "If the camera can't see them, they aren't customers. They're visitors.\n\nVisitors don't get salt.",
	4: "The thing under the floor loves bread. Give it all the bread it wants.\n\nIt's harmless. Mostly harmless. It's fine.",
	5: "Pay the Landlord in money if you can.\n\nWhat he takes otherwise, you don't get back. I'd know.",
}
const FAKES := ["Bottled Yesterday  $7", "Your Name  $0", "Teeth (Assorted)  $4", "Grandpa  $1", "The Ninth Colour  $13",
	"Nothing  $9", "Tinned Screams  $9", "A Spare Shadow  $5", "Tomorrow  $3"]

var game
var ghost: VoxelPerson
var ghost_day := 0
var ghost_at := 0.0
var ghost_t := 0.0
var shift_t := 30.0
var swap_t := 90.0
var seen_t := {}                # shelf -> seconds looked at since it changed

func setup(g) -> void:
	game = g

func _process(dt: float) -> void:
	if not game.started or game.ending or game.night_walk or game.ui.is_open(): return
	_ghost(dt)
	_shift(dt)

# --------------------------------------------------------------------------- Grandpa
func _ghost(dt: float) -> void:
	if ghost_day != game.day:
		ghost_day = game.day
		ghost_at = game.rng.randf_range(10 * 60, 16 * 60)
		_vanish(false)
	if ghost == null and not game.flags.get("ghost_day_%d" % game.day, false) and game.minute >= ghost_at and game.minute < 18 * 60:
		game.flags["ghost_day_%d" % game.day] = true
		_appear()
	if ghost:
		ghost_t += dt
		var to: Vector3 = game.player.global_position - ghost.global_position
		ghost.rotation.y = lerp_angle(ghost.rotation.y, atan2(-to.x, -to.z), dt * 3.0)
		if ghost_t > 75.0:
			game.ui.toast("Grandpa fades before you can hear him.", UI.C_PURPLE, 4.0)
			_vanish(true)

func _appear() -> void:
	ghost = VoxelPerson.new()
	add_child(ghost)
	ghost.build({ "skin": Color(0.8, 0.85, 0.95), "shirt": Color(0.6, 0.65, 0.75), "pants": Color(0.45, 0.5, 0.6), "hair": Color(0.92, 0.94, 1.0),
		"coat": Color(0.55, 0.6, 0.72), "height": 0.95, "eyes": Color(0.6, 0.8, 1.0), "weird": ["glow_eyes"] })
	ghost.position = Vector3(0.0, 0, -2.9)
	ghost.flicker = true
	ghost_t = 0.0
	_ghostify(ghost)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.4, 0.4)
	l.light_color = Color(0.6, 0.75, 1.0)
	l.light_energy = 0.8
	l.omni_range = 3.0
	ghost.add_child(l)
	var look := StaticBody3D.new()
	look.collision_layer = 2
	look.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.7, 2.0, 0.5)
	cs.shape = sh
	cs.position = Vector3(0, 1.0, 0)
	look.add_child(cs)
	look.set_meta("interact", self)
	ghost.add_child(look)
	Sfx.play("whisper", 0.6, 0.7)
	game.ui.toast("There's someone standing in the aisle. He looks a lot like Grandpa.", UI.C_PURPLE, 5.0)

## see-through and pale blue
func _ghostify(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.material_override:
		var m: StandardMaterial3D = mi.material_override.duplicate()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(m.albedo_color.r, m.albedo_color.g, m.albedo_color.b, 0.45)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children(): _ghostify(c)

func _vanish(sound: bool) -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
		if sound: Sfx.play("whisper", 0.4, 1.3)

func prompt(_g) -> String:
	return "[E] Listen to Grandpa" if ghost else ""

func use(_g) -> void:
	if ghost == null: return
	var d: int = clampi(game.day, 1, 5)
	_vanish(true)
	game.ui.show_text("Grandpa (more or less)", HINTS[d], "He's gone")

func prompt_alt(_g) -> String:
	return ""

func use_alt(_g) -> void:
	pass

# --------------------------------------------------------------------------- shelves that change behind your back
func _seen(s: Shelf) -> bool:
	return game.player.cam.is_position_in_frustum(s.global_position + Vector3(0, 1.2, 0))

func _shift(dt: float) -> void:
	# look at a changed shelf for a moment, look away: it's normal again
	for s in seen_t.keys():
		if not is_instance_valid(s): continue
		if _seen(s): seen_t[s] += dt
		elif seen_t[s] > 1.0:
			s.set_fake("")
			seen_t.erase(s)
	if game.sanity >= 45.0: return
	shift_t -= dt
	if shift_t <= 0.0:
		shift_t = game.rng.randf_range(20.0, 40.0)
		var hidden := []
		for s in game.world.shelves:
			if not _seen(s) and not seen_t.has(s): hidden.append(s)
		if not hidden.is_empty():
			var s: Shelf = hidden[game.rng.randi() % hidden.size()]
			s.set_fake(FAKES[game.rng.randi() % FAKES.size()])
			seen_t[s] = 0.0
	if game.sanity >= 30.0: return
	swap_t -= dt
	if swap_t <= 0.0:
		swap_t = game.rng.randf_range(60.0, 120.0)
		var hidden := []
		for s in game.world.shelves:
			if not _seen(s): hidden.append(s)
		if hidden.size() >= 2:
			hidden.shuffle()
			var a: Shelf = hidden[0]
			var b: Shelf = hidden[1]
			var p := a.product; var c := a.count
			a.product = b.product; a.count = b.count
			b.product = p; b.count = c
			a.refresh(); b.refresh()
			Sfx.play("whisper", 0.3, 0.9)
