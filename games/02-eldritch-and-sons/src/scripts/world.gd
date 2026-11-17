## world.gd : builds the shop, the storeroom and the little street outside, all from textured boxes.
## Layout (metres, y up, floor top at y = 0):
##   shop floor x -7..7, z -5..5   front door at z = 5 (x -1..1), street beyond z > 6
##   storeroom x -4..4, z -10..-5  (deliveries + your bed)
##   counter on the left by the window; customers queue on the door side, you stand behind it
class_name World
extends Node3D

var game
var shelves: Array[Shelf] = []
var lamps: Array[OmniLight3D] = []
var lamp_meshes: Array[Node3D] = []
var street_lights: Array[OmniLight3D] = []
var window_glows: Array[MeshInstance3D] = []
var sun: DirectionalLight3D
var env: Environment
var cctv_viewport: SubViewport
var cctv_cam: Camera3D
var sign_label: Label3D
var register_label: Label3D
var mystery_house: Node3D
var agnes_house: Node3D        # across the street; boarded up from Thursday
var agnes_glows: Array = []
var empty_lot: Node3D
var letter: Interactable
var fancy := false   # true on Forward+ (desktop): shadows, volumetric fog, glow, SSAO

# customer navigation points
const SPAWNS := [Vector3(-17, 0, 7.6), Vector3(17, 0, 7.6)]
const DOOR_OUT := Vector3(0, 0, 7.2)
const DOOR_IN := Vector3(0, 0, 3.9)
const HUB := Vector3(-2.1, 0, 0.6)
const QUEUE := [Vector3(-4.6, 0, 3.25), Vector3(-3.5, 0, 3.7), Vector3(-2.4, 0, 4.1), Vector3(-1.3, 0, 4.4)]
const DELIVERY := Vector3(1.2, 0, -8.6)
const PLAYER_START := Vector3(-4.6, 0, 0.7)

func build(g) -> void:
	game = g
	_ground_and_street()
	_decor()
	_shop_shell()
	_storeroom()
	_counter()
	_shelves()
	_lights()
	_neighbourhood()
	_cctv()

# --------------------------------------------------------------------------- pieces
func _ground_and_street() -> void:
	Vox.block(self, Vector3(-70, -1.2, -70), Vector3(140, 1.0, 140), Vox.mat("grass"))
	Vox.block(self, Vector3(-40, -0.3, 6), Vector3(80, 0.3, 3), Vox.mat("stone", Color(1.15, 1.15, 1.15)))
	Vox.block(self, Vector3(-40, -0.35, 9), Vector3(80, 0.25, 5), Vox.mat("cobble", Color(0.75, 0.75, 0.8)))
	Vox.block(self, Vector3(-40, -0.3, 14), Vector3(80, 0.3, 2), Vox.mat("stone", Color(1.15, 1.15, 1.15)))
	# invisible walls so you can't wander off into the fog
	for x in [-34.0, 34.0]:
		var wall := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(1, 10, 60)
		cs.shape = sh
		wall.position = Vector3(x, 4, 10)
		wall.add_child(cs)
		add_child(wall)
	var back := StaticBody3D.new()
	var bcs := CollisionShape3D.new()
	var bsh := BoxShape3D.new()
	bsh.size = Vector3(70, 10, 1)
	bcs.shape = bsh
	back.position = Vector3(0, 4, 26)
	back.add_child(bcs)
	add_child(back)

func _shop_shell() -> void:
	var paper := Vox.mat("wallpaper")
	var brick := Vox.mat("brick")
	Vox.block(self, Vector3(-7, -1, -5), Vector3(14, 1, 11), Vox.mat("floor"))
	Vox.block(self, Vector3(-8, 0, -6), Vector3(1, 4, 12), paper)                 # left
	Vox.block(self, Vector3(7, 0, -6), Vector3(1, 4, 12), paper)                  # right
	# back wall with a doorway to the storeroom
	Vox.block(self, Vector3(-8, 0, -6), Vector3(7, 4, 1), paper)
	Vox.block(self, Vector3(1, 0, -6), Vector3(7, 4, 1), paper)
	Vox.block(self, Vector3(-1, 2.6, -6), Vector3(2, 1.4, 1), paper)
	# front wall: door gap + two big shop windows
	Vox.block(self, Vector3(-8, 0, 5), Vector3(2.5, 4, 1), brick)
	Vox.block(self, Vector3(-5.5, 0, 5), Vector3(3.5, 1, 1), brick)
	Vox.block(self, Vector3(-5.5, 2.6, 5), Vector3(3.5, 1.4, 1), brick)
	Vox.block(self, Vector3(-2, 0, 5), Vector3(1, 4, 1), brick)
	Vox.block(self, Vector3(-1, 2.8, 5), Vector3(2, 1.2, 1), brick)
	Vox.block(self, Vector3(1, 0, 5), Vector3(1, 4, 1), brick)
	Vox.block(self, Vector3(2, 0, 5), Vector3(3.5, 1, 1), brick)
	Vox.block(self, Vector3(2, 2.6, 5), Vector3(3.5, 1.4, 1), brick)
	Vox.block(self, Vector3(5.5, 0, 5), Vector3(2.5, 4, 1), brick)
	Vox.block(self, Vector3(-5.5, 1, 5.4), Vector3(3.5, 1.6, 0.2), Vox.mat("glass"))
	Vox.block(self, Vector3(2, 1, 5.4), Vector3(3.5, 1.6, 0.2), Vox.mat("glass"))
	# ceiling + facade trim + roof
	Vox.block(self, Vector3(-8, 4, -6), Vector3(16, 0.5, 12), Vox.mat("darkplanks"))
	Vox.block(self, Vector3(-8.3, 4.5, -6.3), Vector3(16.6, 1.6, 12.6), Vox.mat("roof"))
	Vox.block(self, Vector3(-8.2, 3.3, 6.0), Vector3(16.4, 0.8, 0.3), Vox.mat("darkplanks"))
	if Vox.card(self, "sign", Vector3(0, 3.7, 6.33), 4.6) == null:
		var name_sign := Vox.label(self, "ELDRITCH & SONS", Vector3(0, 3.72, 6.2), 110, Color(1, 0.85, 0.5))
		name_sign.pixel_size = 0.006
	Vox.label(self, "Fine Goods & Curiosities", Vector3(0, 2.95, 6.06), 40, Color(0.85, 0.8, 0.7))
	# door frame + the OPEN/CLOSED sign you flip from inside
	Vox.block(self, Vector3(-1.1, 0, 4.85), Vector3(0.12, 2.9, 0.3), Vox.mat("darkplanks"), false)
	Vox.block(self, Vector3(0.98, 0, 4.85), Vector3(0.12, 2.9, 0.3), Vox.mat("darkplanks"), false)
	var board := Vox.box(self, Vector3(1.6, 1.9, 4.95), Vector3(0.8, 0.4, 0.06), Vox.obj_mat(Color(0.35, 0.22, 0.12)), false)
	sign_label = Vox.label(self, "CLOSED", Vector3(1.6, 1.9, 4.91), 46, Color(1, 0.4, 0.3))
	sign_label.rotation.y = PI
	var it := Interactable.make(self, Vector3(1.6, 1.9, 4.95), Vector3(0.9, 0.5, 0.2),
		func(g): return g.sign_prompt(), func(g): g.toggle_open())
	# grandpa's letter on the doormat (day 1)
	letter = Interactable.make(self, Vector3(0.6, 0.03, 4.1), Vector3(0.5, 0.1, 0.4),
		func(g): return "[E] Read the letter", func(g): g.read_letter())
	Vox.box(letter, Vector3.ZERO, Vector3(0.32, 0.02, 0.24), Vox.art_mat("paper", 3.0) if Vox.art("paper") else Vox.obj_mat(Color(0.95, 0.92, 0.82)), false)

func _storeroom() -> void:
	var plank := Vox.mat("planks")
	Vox.block(self, Vector3(-4, -1, -10), Vector3(8, 1, 5), Vox.mat("floor"))
	Vox.block(self, Vector3(-5, 0, -11), Vector3(1, 4, 6), plank)
	Vox.block(self, Vector3(4, 0, -11), Vector3(1, 4, 6), plank)
	Vox.block(self, Vector3(-5, 0, -11), Vector3(10, 4, 1), plank)
	Vox.block(self, Vector3(-5, 4, -11), Vector3(10, 0.5, 6), Vox.mat("darkplanks"))
	# back delivery door
	Vox.block(self, Vector3(0.4, 0, -10.08), Vector3(1.6, 2.6, 0.1), Vox.mat("redplanks"), false)
	Vox.label(self, "DELIVERIES", Vector3(1.2, 2.8, -10.0), 40, Color(0.9, 0.85, 0.7))
	# bed
	if prop("bed", Vector3(-3.1, 0, -8.7), Vector3(1.4, 1.2, 2.2)):
		Vox.block(self, Vector3(-3.8, 0, -9.8), Vector3(1.4, 0.45, 2.2), Vox.mat("bed")).visible = false  # keeps the collision
	else:
		Vox.block(self, Vector3(-3.8, 0, -9.8), Vector3(1.4, 0.45, 2.2), Vox.mat("bed"))
		Vox.block(self, Vector3(-3.7, 0.45, -9.7), Vector3(1.2, 0.18, 0.5), Vox.obj_mat(Color(0.92, 0.9, 0.85)), false)
	Interactable.make(self, Vector3(-3.1, 0.4, -8.7), Vector3(1.4, 0.8, 2.2),
		func(g): return g.bed_prompt(), func(g): g.go_to_bed())
	# grandpa's old crates for atmosphere
	Vox.block(self, Vector3(2.6, 0, -9.8), Vector3(1.2, 1.2, 1.2), Vox.mat("cardboard"))
	Vox.block(self, Vector3(2.8, 1.2, -9.6), Vector3(0.8, 0.8, 0.8), Vox.mat("cardboard"))

func _counter() -> void:
	Vox.block(self, Vector3(-6.2, 0, 1.6), Vector3(3.2, 1.05, 1.0), Vox.mat("darkplanks"))
	Vox.block(self, Vector3(-6.3, 1.05, 1.55), Vector3(3.4, 0.08, 1.1), Vox.obj_mat(Color(0.5, 0.33, 0.2)), false)
	# till
	if not prop("till", Vector3(-4.6, 1.12, 2.05), Vector3(0.7, 0.55, 0.55), PI):
		var till := Vox.box(self, Vector3(-4.6, 1.3, 2.05), Vector3(0.6, 0.36, 0.46), Vox.obj_mat(Color(0.55, 0.5, 0.42)), false)
		Vox.box(till, Vector3(0, 0.26, 0.1), Vector3(0.4, 0.16, 0.08), Vox.obj_mat(Color(0.1, 0.25, 0.12), true), false)
	register_label = Vox.label(self, "TILL", Vector3(-4.6, 1.52, 1.9), 30, Color(0.6, 1, 0.6))
	register_label.pixel_size = 0.0025
	register_label.rotation.y = PI
	var reg := Interactable.make(self, Vector3(-4.6, 1.3, 2.05), Vector3(0.8, 0.6, 0.7),
		func(g): return g.register_prompt(), func(g): g.register_use())
	reg.alt_prompt_fn = func(g): return g.register_alt_prompt()
	reg.alt_use_fn = func(g): g.register_refuse()
	# the order catalogue
	Vox.box(self, Vector3(-3.5, 1.14, 2.0), Vector3(0.38, 0.08, 0.38), Vox.obj_mat(Color(0.35, 0.15, 0.4)), false)
	var cover := Vox.card(self, "catalogue", Vector3(-3.5, 1.185, 2.0), 0.36)
	if cover: cover.rotation = Vector3(-PI / 2, PI, 0)
	var cat_label := Vox.label(self, "CATALOGUE", Vector3(-3.5, 1.2, 1.83), 30, Color(0.85, 0.7, 1.0))
	cat_label.pixel_size = 0.002
	cat_label.rotation.y = PI
	Interactable.make(self, Vector3(-3.5, 1.2, 2.0), Vector3(0.6, 0.35, 0.5),
		func(g): return "[E] Order stock (catalogue)", func(g): g.open_catalogue())
	# notice board with the shop rules
	Vox.box(self, Vector3(-6.93, 2.0, -0.6), Vector3(0.06, 1.0, 1.4), Vox.obj_mat(Color(0.55, 0.4, 0.25)), false)
	for i in 4:
		var paper := Vox.box(self, Vector3(-6.89, 1.75 + (i % 2) * 0.45, -1.0 + (i / 2) * 0.7), Vector3(0.02, 0.32, 0.4), Vox.art_mat("paper", 2.6) if Vox.art("paper") else Vox.obj_mat(Color(0.92, 0.9, 0.8)), false)
		paper.rotation.x = sin(i * 1.7) * 0.1
	var nb := Interactable.make(self, Vector3(-6.85, 2.0, -0.6), Vector3(0.3, 1.1, 1.5),
		func(g): return "[E] Read the shop rules (or press Tab)", func(g): g.ui.toggle_notebook())

func _shelves() -> void:
	var spots := [
		[Vector3(-5.6, 0, -4.65), 0.0], [Vector3(-3.3, 0, -4.65), 0.0],
		[Vector3(3.3, 0, -4.65), 0.0], [Vector3(5.6, 0, -4.65), 0.0],
		[Vector3(6.65, 0, -1.9), -PI / 2], [Vector3(6.65, 0, 0.6), -PI / 2],
	]
	for i in spots.size():
		var s := Shelf.new()
		s.position = spots[i][0]
		s.rotation.y = spots[i][1]
		add_child(s)
		s.build(i)
		shelves.append(s)

func _lamp(pos: Vector3, energy := 1.4, range_ := 9.0) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1, 0.78, 0.5)
	l.light_energy = energy
	l.omni_range = range_
	add_child(l)
	lamps.append(l)
	var pm := prop_node("lamp", pos + Vector3(0, 0.1, 0), Vector3(0.45, 0.5, 0.45))
	if pm:
		_no_shadows(pm)
		lamp_meshes.append(pm)
		return
	var m := Vox.box(self, pos + Vector3(0, 0.25, 0), Vector3(0.3, 0.2, 0.3), Vox.obj_mat(Color(1, 0.85, 0.5), true), false)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # the bulb mustn't shadow its own ceiling
	lamp_meshes.append(m)
	Vox.box(self, pos + Vector3(0, 0.45, 0), Vector3(0.04, 0.3, 0.04), Vox.obj_mat(Color(0.2, 0.2, 0.2)), false)

func _lights() -> void:
	_lamp(Vector3(-3.8, 3.4, 0.4))
	_lamp(Vector3(3.2, 3.4, -1.4))
	_lamp(Vector3(0, 3.4, -7.8), 1.1, 7.0)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.6
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.5, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.55, 0.58)
	env.fog_density = 0.035
	we.environment = env
	add_child(we)
	# Forward+ has a RenderingDevice; Compatibility (web, old GPUs) doesn't
	fancy = RenderingServer.get_rendering_device() != null
	if fancy: _fancy_lighting()

## the good stuff, desktop only: lamp shadows, light you can see in the fog, glowing eyes
func _fancy_lighting() -> void:
	for l in lamps:
		l.shadow_enabled = true
		l.shadow_blur = 1.5
		l.light_volumetric_fog_energy = 3.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	env.fog_density = 0.018
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.85, 0.87, 0.9)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.4
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1

func _house(from: Vector3, size: Vector3, wall: String, tint := Color.WHITE, facing := 1) -> Node3D:
	var h := Node3D.new()
	add_child(h)
	Vox.block(h, from, size, Vox.mat(wall, tint))
	Vox.block(h, from + Vector3(-0.3, size.y, -0.3), Vector3(size.x + 0.6, 0.9, size.z + 0.6), Vox.mat("roof"))
	var fz := from.z + (size.z + 0.02 if facing > 0 else -0.02)
	var nwin := int(size.x / 3.0)
	for i in nwin:
		for floor_i in int(size.y / 3.0):
			var wx := from.x + 1.2 + i * 3.0
			var glow := Vox.box(h, Vector3(wx + 0.5, 1.6 + floor_i * 2.8, fz), Vector3(1.0, 1.2, 0.06), Vox.obj_mat(Color(1, 0.8, 0.45), true), false)
			window_glows.append(glow)
	var door_x := from.x + size.x * 0.5
	Vox.block(h, Vector3(door_x - 0.6, 0, fz - (0.05 if facing > 0 else -0.05)), Vector3(1.2, 2.4, 0.1), Vox.mat("darkplanks"), false)
	return h

func _neighbourhood() -> void:
	# neighbours on either side of the shop
	_house(Vector3(-20, 0, -8), Vector3(11.5, 6, 13.6), "brick", Color(0.85, 0.85, 0.9))
	_house(Vector3(8.5, 0, -8), Vector3(11, 5, 13.6), "plaster", Color(0.8, 0.85, 0.75))
	# across the street (facing the shop, so windows on the -Z side)
	_house(Vector3(-27, 0, 16.5), Vector3(9, 6, 7), "brick", Color(0.7, 0.7, 0.75), -1)
	var g0 := window_glows.size()
	agnes_house = _house(Vector3(-15, 0, 16.5), Vector3(9, 5, 7), "plaster", Color(0.75, 0.7, 0.6), -1)
	agnes_glows = window_glows.slice(g0)
	_house(Vector3(9, 0, 16.5), Vector3(9, 6, 7), "darkplanks", Color.WHITE, -1)
	_house(Vector3(20, 0, 16.5), Vector3(8, 5, 7), "brick", Color(0.6, 0.55, 0.55), -1)
	# the empty lot... for now
	empty_lot = Node3D.new()
	add_child(empty_lot)
	Vox.block(empty_lot, Vector3(-4, -0.15, 16.5), Vector3(11, 0.1, 7), Vox.mat("dirt"), false)
	for i in 6:
		Vox.block(empty_lot, Vector3(-4 + i * 2.1, 0, 16.4), Vector3(0.15, 1.0, 0.15), Vox.mat("darkplanks"), false)
	Vox.block(empty_lot, Vector3(-4, 0.6, 16.42), Vector3(10.6, 0.1, 0.06), Vox.mat("darkplanks"), false)
	var lot_sign := Vox.label(empty_lot, "LOT FOR SALE", Vector3(1.5, 1.5, 16.35), 60, Color(0.9, 0.85, 0.7))
	lot_sign.rotation.y = PI
	var glows_before := window_glows.size()
	mystery_house = _house(Vector3(-3.5, 0, 16.5), Vector3(10, 7, 7), "void", Color.WHITE, -1)
	# its windows are never dark, and never quite the right colour
	for i in range(glows_before, window_glows.size()):
		window_glows[i].material_override = Vox.obj_mat(Color(0.6, 0.3, 1.0), true)
	window_glows.resize(glows_before)
	Vox.block(mystery_house, Vector3(1.0, 0, 16.3), Vector3(1.2, 2.4, 0.08), Vox.obj_mat(Color(0.02, 0.0, 0.04)), false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(1.5, 2.0, 15.6)
	lamp.light_color = Color(0.6, 0.3, 1.0)
	lamp.light_energy = 1.2
	lamp.omni_range = 6.0
	mystery_house.add_child(lamp)
	mystery_house.visible = false
	mystery_house.process_mode = Node.PROCESS_MODE_DISABLED
	# street lamps
	for x in [-14.0, 0.0, 14.0]:
		var pole := Vox.block(self, Vector3(x - 0.12, 0, 8.4), Vector3(0.24, 3.6, 0.24), Vox.obj_mat(Color(0.15, 0.15, 0.17)))
		var sl := prop_node("streetlamp", Vector3(x, 0, 8.5), Vector3(0.9, 4.1, 0.9))
		if sl:
			_no_shadows(sl)
			pole.visible = false   # keeps the collision
		else:
			Vox.box(self, Vector3(x, 3.75, 8.5), Vector3(0.5, 0.35, 0.5), Vox.obj_mat(Color(1, 0.85, 0.55), true), false).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var l := OmniLight3D.new()
		l.position = Vector3(x, 3.4, 8.5)
		l.light_color = Color(1, 0.8, 0.5)
		l.light_volumetric_fog_energy = 5.0
		l.omni_range = 9.0
		l.light_energy = 0.0
		add_child(l)
		street_lights.append(l)

## Agnes stopped coming in. Her windows and door are boarded up. From the inside, somehow.
func board_up_agnes() -> void:
	var wood := Vox.mat("darkplanks", Color(0.75, 0.7, 0.65))
	for gl in agnes_glows:
		window_glows.erase(gl)
		gl.material_override = Vox.obj_mat(Color(0.03, 0.03, 0.04))
		for i in 3:
			var b := Vox.box(agnes_house, gl.position + Vector3(0, -0.4 + i * 0.4, -0.05), Vector3(1.3, 0.16, 0.05), wood, false)
			b.rotation.z = sin(i * 2.1 + gl.position.x) * 0.12
	var door_x := -15.0 + 4.5
	for i in 4:
		var b := Vox.box(agnes_house, Vector3(door_x, 0.5 + i * 0.55, 16.4), Vector3(1.5, 0.18, 0.05), wood, false)
		b.rotation.z = sin(i * 1.3) * 0.18
	var x := Vox.label(agnes_house, "KEEP OUT", Vector3(door_x, 2.65, 16.36), 44, Color(0.75, 0.1, 0.1))
	x.rotation.y = PI

func show_mystery_house() -> void:
	empty_lot.visible = false
	for c in empty_lot.get_children(): c.process_mode = Node.PROCESS_MODE_DISABLED
	mystery_house.visible = true
	mystery_house.process_mode = Node.PROCESS_MODE_INHERIT

# --------------------------------------------------------------------------- CCTV
## A security camera in the corner feeds the little monitor on the counter.
## It renders visual layer 1 only: anything on layer 2 (certain customers...) doesn't show up.
func _cctv() -> void:
	cctv_viewport = SubViewport.new()
	cctv_viewport.size = Vector2i(240, 180)
	cctv_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cctv_viewport.world_3d = get_viewport().world_3d
	add_child(cctv_viewport)
	cctv_cam = Camera3D.new()
	cctv_cam.cull_mask = 1
	cctv_cam.fov = 85
	cctv_viewport.add_child(cctv_cam)
	cctv_cam.position = Vector3(-6.4, 3.5, 4.4)
	cctv_cam.look_at_from_position(cctv_cam.position, Vector3(-1.5, 0.8, 1.0))
	if not prop("cctv", Vector3(-6.5, 3.45, 4.5), Vector3(0.35, 0.35, 0.45), PI * 0.75):
		Vox.box(self, Vector3(-6.5, 3.6, 4.5), Vector3(0.25, 0.2, 0.35), Vox.obj_mat(Color(0.2, 0.2, 0.22)), false)
		Vox.box(self, Vector3(-6.4, 3.6, 4.32), Vector3(0.05, 0.05, 0.02), Vox.obj_mat(Color(1, 0.1, 0.1), true), false)
	# monitor on the counter, screen facing the shopkeeper (a model keeps the live picture in front of it)
	var monitor_model := prop("monitor", Vector3(-5.75, 1.11, 2.17), Vector3(0.6, 0.52, 0.4), PI)
	if not monitor_model:
		Vox.box(self, Vector3(-5.75, 1.36, 2.15), Vector3(0.56, 0.44, 0.4), Vox.obj_mat(Color(0.25, 0.25, 0.27)), false)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.48, 0.36)
	screen.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = cctv_viewport.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = Color(0.75, 1.0, 0.8)
	screen.material_override = m
	screen.position = Vector3(-5.75, 1.36, 1.94 if not monitor_model else 1.95)
	screen.rotation.y = PI
	screen.layers = 4   # the camera must never film its own monitor (feedback loop)
	add_child(screen)
	Vox.label(self, "CAM 1", Vector3(-5.75, 1.62, 1.93), 22, Color(0.6, 1, 0.6)).rotation.y = PI

# --------------------------------------------------------------------------- Tom's prop models
## Drop res://assets/models/props/<id>.glb in and it replaces the blocky stand-in:
##   till, monitor, cctv, lamp, bed, streetlamp, crate (crate.gd)
## and these only appear once a model exists: bench, mailbox, bin, plant, clock, barrel, mirror
## Any scale works: the model is shrunk/grown to fit its slot (w x h x d), standing on `pos`.
func prop_node(id: String, pos: Vector3, slot: Vector3, rot_y := 0.0) -> Node3D:
	var m := Products.model("props/" + id)
	if m == null: return null
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(m)
	Products.fit_model(m, slot, false)
	holder.position = pos
	holder.rotation.y = rot_y
	return holder

func prop(id: String, pos: Vector3, slot: Vector3, rot_y := 0.0) -> bool:
	return prop_node(id, pos, slot, rot_y) != null

func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D: (n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children(): _no_shadows(c)

## optional street furniture: nothing is placed until Tom makes the model
func _decor() -> void:
	prop("bench", Vector3(-4.6, 0, 7.0), Vector3(1.8, 1.0, 0.7), PI)
	prop("mailbox", Vector3(3.0, 0, 6.9), Vector3(0.5, 1.3, 0.5), PI)
	prop("bin", Vector3(-2.4, 0, 6.8), Vector3(0.6, 0.9, 0.6))
	prop("barrel", Vector3(-3.6, 0, -9.0) + Vector3(6.0, 0, 0.3), Vector3(0.7, 0.9, 0.7))
	prop("plant", Vector3(6.2, 0, 4.1), Vector3(0.7, 1.4, 0.7))
	prop("clock", Vector3(-0.2, 0, -5.3), Vector3(0.8, 2.2, 0.5))
	prop("mirror", Vector3(-6.9, 1.2, -3.2), Vector3(0.1, 1.2, 0.8), PI / 2)
