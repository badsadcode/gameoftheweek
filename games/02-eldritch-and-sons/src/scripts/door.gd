## door.gd : the shop's front door. Two glass-panelled leaves that swing out onto the street.
## [E] props it open / shuts it. It also opens by itself for customers walking through and
## closes behind them (unless you propped it open). It only blocks movement while fully shut,
## so a swinging door can never trap anybody, and it won't close on you in the doorway.
##
## Physics layers: layer 1 = solid (blocks the player), layer 2 = "look at me" only.
## The player's interaction ray checks both; the player's body only collides with layer 1.
class_name ShopDoor
extends Node3D

const W := 0.98                # one leaf
const OPEN := 1.45             # radians, fully open
var game
var pivots: Array[Node3D] = []
var blockers: Array[CollisionShape3D] = []
var propped := false
var angle := 0.0
var was_moving_open := false

func build(g) -> void:
	game = g
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * W, 0, 0)
		add_child(pivot)
		var leaf := Node3D.new()
		leaf.position = Vector3(-side * W * 0.5, 0, 0)
		pivot.add_child(leaf)
		Vox.box(leaf, Vector3(0, 1.38, 0), Vector3(W - 0.02, 2.72, 0.07), Vox.mat("darkplanks"), false)
		Vox.box(leaf, Vector3(0, 1.8, 0), Vector3(W - 0.28, 1.15, 0.09), Vox.mat("glass"), false)
		Vox.box(leaf, Vector3(-side * (W * 0.5 - 0.12), 1.15, 0), Vector3(0.05, 0.22, 0.14), Vox.obj_mat(Color(0.75, 0.6, 0.3)), false)
		# solid while shut
		var solid := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(W, 2.72, 0.12)
		cs.shape = shape
		cs.position = Vector3(0, 1.38, 0)
		solid.add_child(cs)
		leaf.add_child(solid)
		blockers.append(cs)
		# always lookable, never solid
		var look := StaticBody3D.new()
		look.collision_layer = 2
		look.collision_mask = 0
		var lcs := CollisionShape3D.new()
		var lshape := BoxShape3D.new()
		lshape.size = Vector3(W, 2.72, 0.14)
		lcs.shape = lshape
		lcs.position = Vector3(0, 1.38, 0)
		look.add_child(lcs)
		look.set_meta("interact", self)
		leaf.add_child(look)
		pivots.append(pivot)

func prompt(_g) -> String:
	return "[E] Close the door" if propped else "[E] Open the door"

func use(_g) -> void:
	propped = not propped

func prompt_alt(_g) -> String:
	return ""

func use_alt(_g) -> void:
	pass

func _near(p: Vector3, r: float) -> bool:
	var local := p - global_position
	return absf(local.x) < 1.3 and absf(local.z) < r

func _process(dt: float) -> void:
	if game.player == null: return
	var want := propped
	for c in game.customers:
		if is_instance_valid(c) and c.state != "gone" and c.body.speed > 0.1 and _near(c.position, 2.3):
			want = true
	# never swing shut on the player standing in the doorway
	if angle > 0.02 and _near(game.player.global_position, 0.9):
		want = true
	var target := OPEN if want else 0.0
	if want and not was_moving_open:
		Sfx.play("click", 0.5, 0.55)
	if not want and was_moving_open and angle > 0.3:
		Sfx.play("click", 0.4, 0.45)
	was_moving_open = want
	angle = move_toward(angle, target, dt * 3.0)
	pivots[0].rotation.y = -angle
	pivots[1].rotation.y = angle
	var shut := angle < 0.02
	for b in blockers: b.disabled = not shut
