## phone.gd : the old wall phone behind the counter. It rings at set times during the week.
## Suppliers, neighbours, the Catalogue... and you, calling from tomorrow with advice that is
## nearly right. Answer with [E]; unanswered calls give up after a while.
## Voice lines (optional, e.g. made with ElevenLabs): res://assets/voice/call_<id>.ogg
class_name Phone
extends Node3D

const POS := Vector3(-6.92, 1.55, 0.75)
const RING_FOR := 28.0          # real seconds before the caller gives up

## { id, day, at (minute), who, text }
const CALLS := [
	{ "id": 1, "day": 1, "at": 620, "who": "Ashford Wholesale",
		"text": "Ashford Wholesale, returning your grandfather's call from... 1987. Sorry for the wait.\n\nOrder before six and we deliver within the hour. Order in the evening and it comes first thing tomorrow. Order after midnight and please don't." },
	{ "id": 2, "day": 2, "at": 690, "who": "A neighbour",
		"text": "Is that the shop? Is the hammering coming from your side?\n\n...No?\n\nThen whose side is it coming from?" },
	{ "id": 3, "day": 2, "at": 1000, "who": "You",
		"text": "Don't hang up. It's me. You. From tomorrow.\n\nA little old lady is going to try to return something she hasn't bought yet. Don't give her the money. Trust me.\n\n...Wait. Or was it DO give her the money? It was do. Probably do." },
	{ "id": 4, "day": 3, "at": 790, "who": "The Catalogue from Beyond",
		"text": "We noticed you reading us.\n\nWe read you too. Your favourite colour is wrong.\n\nHave a pleasant day." },
	{ "id": 5, "day": 4, "at": 640, "who": "You",
		"text": "It's Thursday, right? Good. Listen.\n\nThere's a trapdoor in the storeroom. Whatever lives down there is very polite. Be polite back.\n\nAnd don't sell it the bread. I can't tell you why. I don't remember why." },
	{ "id": 6, "day": 4, "at": 1125, "who": "(breathing)",
		"text": "...\n\n...\n\n...thank you for the silence." },
	{ "id": 7, "day": 5, "at": 750, "who": "You",
		"text": "It's Friday. This is important.\n\nThe Landlord takes money. He also takes other things. Pay him with the coin that bl-\n\n(the line goes dead)" },
	{ "id": 8, "day": 5, "at": 1230, "who": "(no number)",
		"text": "THIRTY MINUTES." },
]

var game
var handset: Node3D
var ringing := {}               # the call ringing right now
var ring_t := 0.0
var bell_t := 0.0
var answered := {}              # id -> true

func build(g) -> void:
	game = g
	position = POS
	var black := Vox.obj_mat(Color(0.08, 0.07, 0.07))
	var brass := Vox.obj_mat(Color(0.7, 0.55, 0.25))
	Vox.box(self, Vector3(0, 0, 0), Vector3(0.08, 0.36, 0.24), Vox.obj_mat(Color(0.35, 0.2, 0.12)), false)   # wooden back plate
	Vox.box(self, Vector3(0.07, 0.02, 0), Vector3(0.08, 0.22, 0.18), black, false)
	Vox.box(self, Vector3(0.12, 0.02, 0), Vector3(0.02, 0.12, 0.12), brass, false)                          # dial
	Vox.box(self, Vector3(0.07, 0.2, -0.05), Vector3(0.06, 0.06, 0.06), brass, false)                        # bells
	Vox.box(self, Vector3(0.07, 0.2, 0.05), Vector3(0.06, 0.06, 0.06), brass, false)
	handset = Node3D.new()
	add_child(handset)
	Vox.box(handset, Vector3(0.11, -0.02, 0.15), Vector3(0.06, 0.26, 0.06), black, false)
	var l := Vox.label(self, "PHONE", Vector3(0.06, -0.26, 0), 26, Color(0.85, 0.8, 0.7))
	l.pixel_size = 0.002
	l.rotation.y = PI / 2
	Interactable.make(self, Vector3(0.08, 0, 0), Vector3(0.3, 0.5, 0.4), func(gm): return prompt(), func(gm): answer())

func prompt() -> String:
	if not ringing.is_empty(): return "[E] Answer the phone"
	return "The phone. It's quiet. For now."

func is_ringing() -> bool:
	return not ringing.is_empty()

func answer() -> void:
	if ringing.is_empty(): return
	var c: Dictionary = ringing
	ringing = {}
	answered[c["id"]] = true
	handset.rotation = Vector3.ZERO
	Sfx.play("click", 0.7, 0.7)
	var path := "res://assets/voice/call_%d.ogg" % c["id"]
	var replay := Callable()
	if ResourceLoader.exists(path) and GameSettings.data["voices"]:
		var s: AudioStream = load(path)
		replay = func(): _play_voice(s)
		_play_voice(s)
	game.ui.show_text("On the line: " + c["who"], c["text"], "Hang up", Callable(), true, replay)

func _play_voice(s: AudioStream) -> void:
	game.voice.stream = s
	game.voice.volume_db = linear_to_db(Sfx.volume)
	game.voice.play()

func _process(dt: float) -> void:
	if game == null or not game.started or game.ending or game.night_walk: return
	if ringing.is_empty():
		if game.ui.is_open(): return
		for c in CALLS:
			if c["day"] == game.day and game.minute >= c["at"] and game.minute < c["at"] + 90 and not answered.has(c["id"]) and not game.flags.get("call_missed_%d" % c["id"], false):
				ringing = c
				ring_t = 0.0
				bell_t = 0.0
				game.ui.toast("The phone is ringing.", UI.C_GOLD, 3.0)
				break
		return
	if game.ui.is_open(): return
	ring_t += dt
	bell_t -= dt
	# shake the handset while it rings, in bursts like an old bell phone
	var burst := fmod(ring_t, 2.2) < 1.0
	handset.rotation.x = sin(ring_t * 60.0) * 0.06 if burst else 0.0
	if bell_t <= 0.0:
		bell_t = 2.2
		var d: float = game.player.global_position.distance_to(global_position)
		Sfx.play("ring", clampf(1.2 - d / 25.0, 0.25, 1.0))
	if ring_t > RING_FOR:
		game.flags["call_missed_%d" % ringing["id"]] = true
		ringing = {}
		handset.rotation = Vector3.ZERO
		game.ui.toast("The phone stops ringing.", UI.C_TEXT, 3.0)
