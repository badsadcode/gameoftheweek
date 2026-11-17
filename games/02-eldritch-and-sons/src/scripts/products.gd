## products.gd : everything the shop can sell.
## cost = what one delivery box of BOX_SIZE units costs; price = what one unit sells for.
## beyond = only in the Catalogue from Beyond (unlocks on `day`).
class_name Products

const BOX_SIZE := 8

const LIST := {
	"bread":   { "name": "Bread",          "cost": 14, "price": 3,  "color": Color(0.85, 0.65, 0.35), "beyond": false, "day": 1, "blurb": "Baked this morning. Probably." },
	"milk":    { "name": "Milk",           "cost": 14, "price": 3,  "color": Color(0.95, 0.95, 0.92), "beyond": false, "day": 1, "blurb": "From cows. Regular cows." },
	"tea":     { "name": "Tea",            "cost": 18, "price": 4,  "color": Color(0.35, 0.55, 0.3),  "beyond": false, "day": 1, "blurb": "Calms the nerves. You'll need it." },
	"candles": { "name": "Candles",        "cost": 20, "price": 5,  "color": Color(0.95, 0.9, 0.7),   "beyond": false, "day": 1, "blurb": "For the power cuts. There are many." },
	"salt":    { "name": "Salt",           "cost": 10, "price": 2,  "color": Color(0.85, 0.88, 0.95), "beyond": false, "day": 1, "blurb": "Locals buy a LOT of salt. Odd." },
	"oil":     { "name": "Lamp Oil",       "cost": 26, "price": 6,  "color": Color(0.75, 0.55, 0.15), "beyond": false, "day": 2, "blurb": "Keeps the lights on. Keep the lights on." },
	"rope":    { "name": "Rope",           "cost": 24, "price": 6,  "color": Color(0.6, 0.5, 0.35),   "beyond": false, "day": 2, "blurb": "Strong. Don't ask what for." },
	"silence": { "name": "Tinned Silence", "cost": 30, "price": 9,  "color": Color(0.25, 0.28, 0.35), "beyond": true,  "day": 1, "blurb": "Open only in emergencies. Do not shake." },
	"jar":     { "name": "Whispering Jar", "cost": 40, "price": 12, "color": Color(0.45, 0.75, 0.6),  "beyond": true,  "day": 2, "blurb": "It knows your name. Seal tightly." },
	"jerky":   { "name": "Tentacle Jerky", "cost": 28, "price": 8,  "color": Color(0.55, 0.25, 0.4),  "beyond": true,  "day": 2, "blurb": "Ethically sourced from somewhere." },
	"eyes":    { "name": "Fresh Eyes",     "cost": 44, "price": 13, "color": Color(0.9, 0.85, 0.85),  "beyond": true,  "day": 3, "blurb": "They blink. That's how you know they're fresh." },
	"idol":    { "name": "Unknown Idol",   "cost": 60, "price": 18, "color": Color(0.3, 0.6, 0.55),   "beyond": true,  "day": 4, "blurb": "Nobody remembers carving it." },
}

static func info(id: String) -> Dictionary:
	return LIST.get(id, {})

static func pname(id: String) -> String:
	return LIST[id]["name"] if LIST.has(id) else "???"

static func ordinary() -> Array:
	var out := []
	for id in LIST: if not LIST[id]["beyond"]: out.append(id)
	return out

static func available(day: int, beyond: bool) -> Array:
	var out := []
	for id in LIST:
		if LIST[id]["beyond"] == beyond and LIST[id]["day"] <= day: out.append(id)
	return out

# --------------------------------------------------------------------------- 3D models
## Hand-made product models live in res://assets/models/<id>.glb (e.g. Tom's milk bottle).
## Any size or scale works: fit_model() shrinks them into a shelf slot. No model? A box is used.
static var _models := {}

static func model(id: String) -> Node3D:
	if not _models.has(id):
		var path := "res://assets/models/%s.glb" % id
		_models[id] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _models[id]
	if ps == null: return null
	var n: Node3D = ps.instantiate()
	_pixelate(n)
	return n

## pixel-sharp textures, so models match the blocky world
static func _pixelate(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m is BaseMaterial3D:
				var mm: BaseMaterial3D = m.duplicate()
				mm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mi.set_surface_override_material(i, mm)
	for c in n.get_children(): _pixelate(c)

static func _bounds(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D: t = xf * (n as Node3D).transform
	var mi := n as MeshInstance3D
	if mi and mi.mesh:
		var box: AABB = t * mi.mesh.get_aabb()
		acc[0] = box if acc[0] == null else (acc[0] as AABB).merge(box)
	for c in n.get_children(): _bounds(c, t, acc)

## scale a model uniformly to fit a slot (w x h x d), standing on y = 0, centred
static func fit_model(n: Node3D, slot: Vector3, turn_long := true) -> void:
	var acc := [null]
	_bounds(n, Transform3D.IDENTITY, acc)
	if acc[0] == null: return
	var b: AABB = acc[0]
	if turn_long and b.size.z > b.size.x * 1.3:
		# long things (a loaf of bread) lie sideways along the shelf
		n.rotation.y += PI / 2
		acc = [null]
		_bounds(n, Transform3D.IDENTITY, acc)
		b = acc[0]
	var k := minf(minf(slot.x / maxf(b.size.x, 0.001), slot.y / maxf(b.size.y, 0.001)), slot.z / maxf(b.size.z, 0.001))
	n.scale = n.scale * k
	var c := b.get_center()
	n.position = Vector3(-c.x * k, -b.position.y * k, -c.z * k)
