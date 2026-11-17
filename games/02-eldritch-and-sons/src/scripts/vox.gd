## vox.gd : the blocky look. Procedural 16x16 pixel textures, materials and box builders.
## Every surface in the game is a textured box: big boxes tile the 16px texture once per metre
## (world-space triplanar), so a 6m wall looks like 6 Minecraft-ish blocks without 6 meshes.
class_name Vox

static var _tex := {}
static var _mat := {}
static var _art := {}

## Tom's hand-made pixel art: res://assets/textures/<name>.png wins over the generated texture.
static func art(name: String) -> Texture2D:
	if not _art.has(name):
		var path := "res://assets/textures/%s.png" % name
		_art[name] = load(path) if ResourceLoader.exists(path) else null
	return _art[name]

## a material showing one hand-made texture, once per `tiles_per_m` metres (objects, not walls)
static func art_mat(name: String, scale := 1.0, emissive := 0.0) -> StandardMaterial3D:
	var key := "art_%s_%s_%s" % [name, scale, emissive]
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex(name)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
		m.roughness = 1.0
		if emissive > 0.0:
			m.emission_enabled = true
			m.emission_texture = m.albedo_texture
			m.emission_energy_multiplier = emissive
		_mat[key] = m
	return _mat[key]

## a flat textured card (product sprites, faces, signs). Faces +Z unless rotated.
static func card(parent: Node3D, name: String, pos: Vector3, width: float, glow := 0.0) -> Sprite3D:
	var t := art(name)
	if t == null: return null
	var s := Sprite3D.new()
	s.texture = t
	s.pixel_size = width / t.get_width()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = glow <= 0.0
	s.double_sided = false
	s.position = pos
	if glow > 0.0: s.modulate = Color(1, 1, 1) * (1.0 + glow)
	parent.add_child(s)
	return s

# --------------------------------------------------------------------------- textures
static func _noise_img(base: Color, seed_: int, amount := 0.08) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for y in 16:
		for x in 16:
			var k := rng.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + k, base.g + k, base.b + k, base.a))
	return img

static func _shade(img: Image, x: int, y: int, k: float) -> void:
	var c := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1), c.a))

static func _make(name: String) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var img: Image
	match name:
		"planks", "darkplanks", "redplanks":
			var base := Color(0.55, 0.38, 0.22)
			if name == "darkplanks": base = Color(0.32, 0.21, 0.13)
			if name == "redplanks": base = Color(0.45, 0.16, 0.13)
			img = _noise_img(base, 11, 0.05)
			for y in 16:
				for x in 16:
					if y % 4 == 3: _shade(img, x, y, -0.14)
					var off := (y / 4) * 5
					if (x + off) % 8 == 0: _shade(img, x, y, -0.1)
		"floor":
			img = _noise_img(Color(0.42, 0.29, 0.18), 12, 0.04)
			for y in 16:
				for x in 16:
					if x % 4 == 3: _shade(img, x, y, -0.12)
					if (y + (x / 4) * 6) % 16 == 0: _shade(img, x, y, -0.1)
		"stone", "cobble":
			img = _noise_img(Color(0.42, 0.42, 0.45), 13, 0.07)
			for i in 9:
				var cx := rng.randi_range(0, 15)
				var cy := rng.randi_range(0, 15)
				for d in 3:
					_shade(img, (cx + d) % 16, cy, -0.16)
					_shade(img, cx, (cy + d) % 16, -0.12)
		"brick":
			img = _noise_img(Color(0.52, 0.24, 0.2), 14, 0.05)
			for y in 16:
				for x in 16:
					var off := 0 if (y / 4) % 2 == 0 else 4
					if y % 4 == 3 or (x + off) % 8 == 7:
						img.set_pixel(x, y, Color(0.7, 0.68, 0.62))
		"plaster":
			img = _noise_img(Color(0.78, 0.74, 0.64), 15, 0.03)
		"wallpaper":
			img = _noise_img(Color(0.35, 0.42, 0.36), 16, 0.03)
			for y in 16:
				for x in 16:
					if (x + y) % 8 == 0 or (x - y + 16) % 8 == 0: _shade(img, x, y, 0.08)
		"grass":
			img = _noise_img(Color(0.22, 0.34, 0.2), 17, 0.08)
		"dirt":
			img = _noise_img(Color(0.33, 0.24, 0.16), 18, 0.08)
		"roof":
			img = _noise_img(Color(0.22, 0.2, 0.24), 19, 0.04)
			for y in 16:
				for x in 16:
					if y % 4 == 0: _shade(img, x, y, -0.1)
		"glass":
			img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.55, 0.7, 0.75, 0.35))
			for i in 16:
				img.set_pixel(i, 0, Color(0.3, 0.25, 0.2, 1)); img.set_pixel(i, 15, Color(0.3, 0.25, 0.2, 1))
				img.set_pixel(0, i, Color(0.3, 0.25, 0.2, 1)); img.set_pixel(15, i, Color(0.3, 0.25, 0.2, 1))
			for i in 4:
				img.set_pixel(3 + i, 3 + i, Color(1, 1, 1, 0.6))
		"metal":
			img = _noise_img(Color(0.5, 0.52, 0.55), 20, 0.03)
			for i in 16: _shade(img, i, 0, 0.15)
		"cardboard":
			img = _noise_img(Color(0.68, 0.52, 0.32), 21, 0.04)
			for i in 16:
				img.set_pixel(i, 7, Color(0.75, 0.68, 0.45)); img.set_pixel(i, 8, Color(0.75, 0.68, 0.45))
		"bed":
			img = _noise_img(Color(0.55, 0.15, 0.15), 22, 0.03)
			for y in 16:
				for x in 16:
					if (x / 4 + y / 4) % 2 == 0: _shade(img, x, y, 0.08)
		"void":
			img = _noise_img(Color(0.04, 0.02, 0.07), 23, 0.03)
			for i in 6:
				img.set_pixel(rng.randi_range(0, 15), rng.randi_range(0, 15), Color(0.6, 0.3, 0.9))
		_:
			img = _noise_img(Color(1, 0, 1), 1, 0.0)
	return img

static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var a := art(name)
		_tex[name] = a if a else ImageTexture.create_from_image(_make(name))
	return _tex[name]

## flat-ish colour texture with a little pixel noise (characters, products)
static func tint_tex(c: Color) -> ImageTexture:
	var key := "tint_" + c.to_html()
	if not _tex.has(key):
		_tex[key] = ImageTexture.create_from_image(_noise_img(c, hash(key), 0.045))
	return _tex[key]

# --------------------------------------------------------------------------- materials
## world material: one texture tile per metre, pixel-sharp
static func mat(name: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := name + tint.to_html()
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex(name)
		m.albedo_color = tint
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE
		m.roughness = 1.0
		if name == "glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat[key] = m
	return _mat[key]

## object material: pixel noise in local space, denser pixels (16 per 0.25 m)
static func obj_mat(c: Color, emissive := false) -> StandardMaterial3D:
	var key := "obj" + c.to_html() + str(emissive)
	if not _mat.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = tint_tex(c)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(4, 4, 4)
		m.roughness = 1.0
		if emissive:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 1.6
		_mat[key] = m
	return _mat[key]

# --------------------------------------------------------------------------- builders
## a textured box, optionally solid. pos = centre.
static func box(parent: Node, pos: Vector3, size: Vector3, material: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	return mi

## a box given by its min corner and size (handier for building layouts)
static func block(parent: Node, from: Vector3, size: Vector3, material: Material, solid := true) -> MeshInstance3D:
	return box(parent, from + size * 0.5, size, material, solid)

## a pixel-font 3D label (signs, speech bubbles)
static func label(parent: Node, text: String, pos: Vector3, size := 48, color := Color.WHITE, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font = load("res://assets/fonts/PixelifySans.ttf")
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l
