## tip_jar.gd : a glass jar on the counter. Happy customers drop in a coin or two.
## Unhappy ones occasionally drop in... other things. [E] empties it into the till.
class_name TipJar
extends Node3D

const POS := Vector3(-5.17, 1.09, 1.85)
const ODD_THINGS := [
	"a fingernail. Not yours. Probably.",
	"a live moth. It looks disappointed in you.",
	"a button from Grandpa's coat. He was buried in that coat.",
	"a tiny wet note that says HELLO.",
	"a baby tooth. Dr. Quill would want to know.",
	"a single eyelash, nine inches long.",
]

var game
var tips := 0
var odd: Array = []
var pile: MeshInstance3D

func build(g) -> void:
	game = g
	position = POS
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 0.95, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	Vox.box(self, Vector3(0, 0.12, 0), Vector3(0.18, 0.24, 0.18), glass, false)
	Vox.box(self, Vector3(0, 0.25, 0), Vector3(0.14, 0.02, 0.14), Vox.obj_mat(Color(0.3, 0.3, 0.32)), false)
	pile = Vox.box(self, Vector3(0, 0.01, 0), Vector3(0.15, 0.02, 0.15), Vox.obj_mat(Color(1, 0.8, 0.3), true), false)
	var l := Vox.label(self, "TIPS", Vector3(0, 0.15, -0.095), 22, Color(0.9, 0.85, 0.7))
	l.pixel_size = 0.002
	l.rotation.y = PI
	Interactable.make(self, Vector3(0, 0.12, 0), Vector3(0.25, 0.3, 0.25), func(gm): return prompt(), func(gm): empty())
	_refresh()

func add_tip(n: int) -> void:
	tips += n
	Sfx.play("coin", 0.35, 1.3)
	_refresh()

func add_odd(rng: RandomNumberGenerator) -> void:
	odd.append(ODD_THINGS[rng.randi() % ODD_THINGS.size()])

func prompt() -> String:
	if tips == 0 and odd.is_empty(): return "The tip jar. Empty."
	return "[E] Empty the tip jar ($%d%s)" % [tips, " and... something else" if not odd.is_empty() else ""]

func empty() -> void:
	if tips == 0 and odd.is_empty(): return
	if tips > 0:
		game.money += tips
		game.today["income"] += tips
		Sfx.play("coin", 0.8)
		game.ui.toast("+$%d in tips." % tips, UI.C_GOLD)
	for o in odd:
		game.ui.toast("Among the coins: " + o, UI.C_PURPLE, 6.0)
		game.lose_sanity(2.0)
	tips = 0
	odd.clear()
	_refresh()

func _refresh() -> void:
	var h := clampf(0.02 + tips * 0.012, 0.02, 0.2)
	pile.scale = Vector3(1, h / 0.02, 1)
	pile.position.y = h * 0.5
	pile.visible = tips > 0
