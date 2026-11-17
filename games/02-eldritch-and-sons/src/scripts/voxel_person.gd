## voxel_person.gd : an articulated blocky humanoid.
## Rigid box parts hang off pivot nodes (shoulder -> elbow, hip -> knee, neck), so the body
## can walk, reach, carry and cower with plain rotations - no skinning, no weight painting.
## Faces -Z (Godot's forward). Feet at y = 0.
class_name VoxelPerson
extends Node3D

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm := {}   # "l"/"r" -> { shoulder, elbow }
var leg := {}   # "l"/"r" -> { hip, knee }
var extras: Array[Node3D] = []  # tentacles etc. that wiggle
var eye_meshes: Array[MeshInstance3D] = []

var speed := 0.0          # m/s, set by the owner; drives the walk cycle
var pose := "idle"        # idle | reach | carry | pay | scared | wave | stare
var phase := 0.0
var t := 0.0
var flicker := false      # low-sanity face glitch
var _blend := {}          # smoothed joint angles

const SKIN_TONES := [Color(0.96, 0.8, 0.66), Color(0.82, 0.62, 0.46), Color(0.6, 0.42, 0.3), Color(0.42, 0.28, 0.2), Color(0.9, 0.72, 0.6)]

func _part(parent: Node3D, pos: Vector3, size: Vector3, c: Color, layer := 1, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Vox.obj_mat(c, glow)
	mi.position = pos
	mi.layers = layer
	parent.add_child(mi)
	return mi

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

## look: { skin, shirt, pants, shoes, hair, hat, eyes, height, width, layer, weird: [] }
func build(look: Dictionary) -> void:
	var layer: int = look.get("layer", 1)
	var skin: Color = look.get("skin", SKIN_TONES[0])
	var shirt: Color = look.get("shirt", Color(0.3, 0.4, 0.6))
	var pants: Color = look.get("pants", Color(0.2, 0.2, 0.25))
	var shoes: Color = look.get("shoes", Color(0.12, 0.1, 0.08))
	var eyes: Color = look.get("eyes", Color(0.1, 0.1, 0.12))
	var weird: Array = look.get("weird", [])
	var h: float = look.get("height", 1.0)
	var w: float = look.get("width", 1.0)
	var glow_eyes := weird.has("glow_eyes")
	var arm_len := 1.35 if weird.has("long_arms") else 1.0

	scale = Vector3(w, h, w)
	hips = _pivot(self, Vector3(0, 0.8, 0))
	torso = _pivot(hips, Vector3.ZERO)
	_part(torso, Vector3(0, 0.3, 0), Vector3(0.46, 0.62, 0.26), shirt, layer)
	if look.has("coat"):
		_part(torso, Vector3(0, 0.22, 0.0), Vector3(0.5, 0.5, 0.3), look["coat"], layer)
	# legs: hip -> thigh, knee -> shin + shoe
	for side in ["l", "r"]:
		var sx := -0.12 if side == "l" else 0.12
		var hip := _pivot(hips, Vector3(sx, 0, 0))
		_part(hip, Vector3(0, -0.2, 0), Vector3(0.21, 0.42, 0.23), pants, layer)
		var knee := _pivot(hip, Vector3(0, -0.4, 0))
		_part(knee, Vector3(0, -0.18, 0), Vector3(0.2, 0.38, 0.22), pants, layer)
		_part(knee, Vector3(0, -0.37, -0.03), Vector3(0.22, 0.07, 0.28), shoes, layer)
		leg[side] = { "hip": hip, "knee": knee }
	# arms: shoulder -> upper arm, elbow -> forearm + hand
	for side in ["l", "r"]:
		var sx := -0.32 if side == "l" else 0.32
		var sh := _pivot(torso, Vector3(sx, 0.56, 0))
		_part(sh, Vector3(0, -0.16 * arm_len, 0), Vector3(0.17, 0.34 * arm_len, 0.19), shirt, layer)
		var el := _pivot(sh, Vector3(0, -0.32 * arm_len, 0))
		_part(el, Vector3(0, -0.14 * arm_len, 0), Vector3(0.16, 0.3 * arm_len, 0.18), look.get("sleeve", shirt), layer)
		_part(el, Vector3(0, -0.32 * arm_len, 0), Vector3(0.15, 0.1, 0.15), skin, layer)
		arm[side] = { "shoulder": sh, "elbow": el }
	if weird.has("extra_arms"):
		for side in ["l", "r"]:
			var sx := -0.3 if side == "l" else 0.3
			var sh := _pivot(torso, Vector3(sx, 0.32, 0))
			_part(sh, Vector3(0, -0.2, 0), Vector3(0.12, 0.4, 0.12), skin.darkened(0.2), layer)
			extras.append(sh)
	# head
	head = _pivot(torso, Vector3(0, 0.62, 0))
	var face_tex: Texture2D = Vox.art(look.get("face", "")) if look.has("face") else null
	if face_tex:
		# Tom's face art on the front; the rest of the head borrows its skin and hair colours
		var img := face_tex.get_image()
		if img.is_compressed(): img.decompress()
		var fskin := img.get_pixel(img.get_width() / 2, int(img.get_height() * 0.72))
		var fhair := img.get_pixel(img.get_width() / 2, 1)
		_part(head, Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4), fskin, layer)
		if fhair.a > 0.5 and Vector3(fhair.r - fskin.r, fhair.g - fskin.g, fhair.b - fskin.b).length() > 0.15:
			_part(head, Vector3(0, 0.39, 0.02), Vector3(0.42, 0.06, 0.42), fhair, layer)
			_part(head, Vector3(0, 0.24, 0.19), Vector3(0.42, 0.32, 0.05), fhair, layer)
		var face := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.4, 0.4)
		face.mesh = q
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = face_tex
		fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		fm.roughness = 1.0
		if glow_eyes:
			fm.emission_enabled = true
			fm.emission_texture = face_tex
			fm.emission_energy_multiplier = 0.7
		face.material_override = fm
		face.position = Vector3(0, 0.2, -0.203)
		face.rotation.y = PI
		face.layers = layer
		head.add_child(face)
		look.erase("hair")
	else:
		_part(head, Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4), skin, layer)
	if not weird.has("no_face") and face_tex == null:
		var eye_y := 0.22
		var eye_xs: Array = [-0.09, 0.09]
		if weird.has("three_eyes"): eye_xs = [-0.11, 0.0, 0.11]
		for ex in eye_xs:
			var ey: float = eye_y + (0.07 if (weird.has("three_eyes") and ex == 0.0) else 0.0)
			_part(head, Vector3(ex, ey, -0.201), Vector3(0.075, 0.06, 0.01), Color(0.95, 0.95, 0.95), layer)
			eye_meshes.append(_part(head, Vector3(ex, ey, -0.207), Vector3(0.04, 0.05, 0.01), eyes, layer, glow_eyes))
		_part(head, Vector3(0, 0.1, -0.201), Vector3(0.14, 0.03, 0.01), skin.darkened(0.35), layer)
	if look.has("hair"):
		_part(head, Vector3(0, 0.39, 0.02), Vector3(0.42, 0.08, 0.42), look["hair"], layer)
		_part(head, Vector3(0, 0.25, 0.19), Vector3(0.42, 0.3, 0.06), look["hair"], layer)
	if look.has("hat"):
		_part(head, Vector3(0, 0.43, 0), Vector3(0.5, 0.04, 0.5), look["hat"], layer)
		_part(head, Vector3(0, 0.55, 0), Vector3(0.34, 0.22, 0.34), look["hat"], layer)
	if weird.has("tentacle_beard"):
		for i in 4:
			var piv := _pivot(head, Vector3(-0.12 + i * 0.08, 0.02, -0.16))
			_part(piv, Vector3(0, -0.12, 0), Vector3(0.05, 0.24, 0.05), Color(0.45, 0.25, 0.4), layer)
			extras.append(piv)
	if weird.has("antlers"):
		for s in [-1, 1]:
			_part(head, Vector3(0.14 * s, 0.5, 0.02), Vector3(0.05, 0.25, 0.05), Color(0.85, 0.82, 0.75), layer)
			_part(head, Vector3(0.22 * s, 0.6, 0.02), Vector3(0.2, 0.05, 0.05), Color(0.85, 0.82, 0.75), layer)

func _ease(key: String, target: float, rate: float, dt: float) -> float:
	var v: float = _blend.get(key, 0.0)
	v = lerpf(v, target, minf(1.0, rate * dt))
	_blend[key] = v
	return v

func _process(dt: float) -> void:
	if hips == null: return
	t += dt
	var moving := _ease("move", clampf(speed / 1.4, 0.0, 1.0), 8.0, dt)   # legs settle instead of snapping
	phase += dt * speed * 4.2
	var s := sin(phase)
	# legs: swing from the hip, bend the knee on the back-swing
	var swing := s * 0.55 * moving
	leg["l"]["hip"].rotation.x = swing
	leg["r"]["hip"].rotation.x = -swing
	leg["l"]["knee"].rotation.x = -maxf(0.0, -s) * 0.9 * moving
	leg["r"]["knee"].rotation.x = -maxf(0.0, s) * 0.9 * moving
	hips.position.y = 0.8 + absf(cos(phase)) * 0.03 * moving
	# arms by pose (positive x rotation = forward, since the body faces -Z)
	var la := -swing * 0.8
	var ra := swing * 0.8
	var le := 0.15
	var re := 0.15
	var spread := 0.0
	var head_x := 0.0
	var torso_x := 0.0
	match pose:
		"reach":
			ra = 1.5 + sin(t * 3.0) * 0.05; re = 0.2
		"carry":
			la = 1.1; ra = 1.1; le = 0.7; re = 0.7
		"pay":
			ra = 1.15; re = 0.35
		"wave":
			ra = 2.7; re = 0.4 + sin(t * 10.0) * 0.4
		"scared":
			la = 2.6; ra = 2.6; le = 1.0; re = 1.0; torso_x = -0.15
			hips.position.x = sin(t * 40.0) * 0.01
		"stare":
			head_x = -0.08; la = 0.0; ra = 0.0
		_:
			la += sin(t * 1.7) * 0.03; ra -= sin(t * 1.7) * 0.03
	arm["l"]["shoulder"].rotation.x = _ease("la", la, 10.0, dt)
	arm["r"]["shoulder"].rotation.x = _ease("ra", ra, 10.0, dt)
	arm["l"]["elbow"].rotation.x = _ease("le", le, 10.0, dt)
	arm["r"]["elbow"].rotation.x = _ease("re", re, 10.0, dt)
	arm["l"]["shoulder"].rotation.z = _ease("ls", -spread, 8.0, dt)
	arm["r"]["shoulder"].rotation.z = _ease("rs", spread, 8.0, dt)
	torso.rotation.x = _ease("tx", torso_x, 6.0, dt)
	head.rotation.x = _ease("hx", head_x + sin(t * 1.3) * 0.02, 6.0, dt)
	for i in extras.size():
		extras[i].rotation.x = sin(t * 3.0 + i) * 0.35
		extras[i].rotation.z = cos(t * 2.3 + i * 0.7) * 0.2
	if flicker:
		head.visible = fmod(t, 0.9) > 0.08
	elif not head.visible:
		head.visible = true

## random ordinary townsfolk
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var shirts := [Color(0.55, 0.2, 0.2), Color(0.2, 0.35, 0.55), Color(0.3, 0.45, 0.3), Color(0.6, 0.5, 0.25), Color(0.45, 0.3, 0.5), Color(0.75, 0.72, 0.65)]
	var pants := [Color(0.2, 0.2, 0.25), Color(0.3, 0.25, 0.2), Color(0.25, 0.3, 0.4), Color(0.15, 0.15, 0.15)]
	var hairs := [Color(0.15, 0.1, 0.06), Color(0.45, 0.3, 0.15), Color(0.8, 0.7, 0.4), Color(0.6, 0.6, 0.6), Color(0.6, 0.25, 0.1)]
	var look := {
		"skin": SKIN_TONES[rng.randi() % SKIN_TONES.size()],
		"shirt": shirts[rng.randi() % shirts.size()],
		"pants": pants[rng.randi() % pants.size()],
		"height": rng.randf_range(0.88, 1.08),
		"width": rng.randf_range(0.92, 1.1),
	}
	if rng.randf() < 0.75: look["hair"] = hairs[rng.randi() % hairs.size()]
	look["face"] = "face_townsfolk_%d" % rng.randi_range(1, 4)
	if rng.randf() < 0.25: look["hat"] = [Color(0.2, 0.18, 0.15), Color(0.35, 0.15, 0.12), Color(0.15, 0.2, 0.3)][rng.randi() % 3]
	if rng.randf() < 0.3: look["coat"] = [Color(0.35, 0.3, 0.25), Color(0.2, 0.22, 0.28)][rng.randi() % 2]
	return look
