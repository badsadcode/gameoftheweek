## ui.gd : HUD, prompts, toasts, catalogue, notebook, letters, night cards, day summary, menus.
## Everything is built in code so the whole game stays readable as plain text.
class_name UI
extends CanvasLayer

var game
var font: FontFile
var mono: FontFile
var hud: Control
var clock_label: Label
var day_label: Label
var money_label: Label
var rep_bar: ProgressBar
var sanity_bar: ProgressBar
var rent_label: Label
var prompt_label: Label
var crosshair: Label
var toast_box: VBoxContainer
var held_label: Label
var goal_label: Label
var deliv_label: Label
var panel_layer: Control
var open_panel: Control = null
var fade: ColorRect
var post: ColorRect

const C_TEXT := Color(0.93, 0.9, 0.82)
const C_GOLD := Color(1, 0.82, 0.45)
const C_PURPLE := Color(0.78, 0.6, 1.0)
const C_RED := Color(1, 0.45, 0.4)
const C_GREEN := Color(0.6, 1, 0.65)

func setup(g) -> void:
	game = g
	font = load("res://assets/fonts/PixelifySans.ttf")
	mono = load("res://assets/fonts/VT323.ttf")
	# sanity post-process sits under the HUD
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://scripts/sanity.gdshader")
	post.material = sm
	post_layer.add_child(post)
	layer = 1
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	_build_hud()
	panel_layer = Control.new()
	panel_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel_layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

# --------------------------------------------------------------------------- helpers
func lbl(text: String, size := 22, color := C_TEXT, f: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f if f else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l

func box_style(bg := Color(0.06, 0.05, 0.08, 0.9), border := Color(0.55, 0.45, 0.3)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_content_margin_all(14)
	return s

func panel(w: float, h: float, border := Color(0.55, 0.45, 0.3)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box_style(Color(0.06, 0.05, 0.08, 0.94), border))
	p.custom_minimum_size = Vector2(w, h)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = Vector2(-w / 2, -h / 2)
	return p

func button(text: String, cb: Callable, size := 20, color := C_TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", C_GOLD)
	b.add_theme_stylebox_override("normal", box_style(Color(0.14, 0.11, 0.1, 1), Color(0.4, 0.32, 0.22)))
	b.add_theme_stylebox_override("hover", box_style(Color(0.24, 0.18, 0.12, 1), C_GOLD))
	b.add_theme_stylebox_override("pressed", box_style(Color(0.3, 0.22, 0.14, 1), C_GOLD))
	b.add_theme_stylebox_override("disabled", box_style(Color(0.1, 0.1, 0.1, 1), Color(0.25, 0.25, 0.25)))
	b.add_theme_stylebox_override("focus", box_style(Color(0.24, 0.18, 0.12, 1), C_GOLD))
	b.pressed.connect(func():
		Sfx.play("click", 0.6)
		cb.call())
	return b

func bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(200, 14)
	b.show_percentage = false
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.6)
	var fg := StyleBoxFlat.new(); fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b

# --------------------------------------------------------------------------- HUD
func _build_hud() -> void:
	var tl := PanelContainer.new()
	tl.add_theme_stylebox_override("panel", box_style(Color(0.05, 0.04, 0.07, 0.7)))
	tl.position = Vector2(14, 14)
	hud.add_child(tl)
	var v := VBoxContainer.new()
	tl.add_child(v)
	day_label = lbl("MONDAY", 22, C_GOLD)
	clock_label = lbl("07:00  CLOSED", 26)
	rent_label = lbl("", 16, Color(0.8, 0.75, 0.7))
	v.add_child(day_label); v.add_child(clock_label); v.add_child(rent_label)
	# what to do next + boxes on the way (guide.gd)
	goal_label = lbl("", 18, C_GOLD)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.custom_minimum_size = Vector2(300, 0)
	v.add_child(goal_label)
	deliv_label = lbl("", 15, Color(0.75, 0.8, 0.9))
	deliv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deliv_label.custom_minimum_size = Vector2(300, 0)
	v.add_child(deliv_label)

	var tr := PanelContainer.new()
	tr.add_theme_stylebox_override("panel", box_style(Color(0.05, 0.04, 0.07, 0.7)))
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-264, 14)
	tr.custom_minimum_size = Vector2(250, 0)
	hud.add_child(tr)
	var v2 := VBoxContainer.new()
	tr.add_child(v2)
	money_label = lbl("$0", 30, C_GOLD)
	v2.add_child(money_label)
	v2.add_child(lbl("REPUTATION", 14, Color(0.75, 0.75, 0.75)))
	rep_bar = bar(Color(0.95, 0.75, 0.3)); rep_bar.max_value = 5.0
	v2.add_child(rep_bar)
	v2.add_child(lbl("SANITY", 14, Color(0.75, 0.7, 0.85)))
	sanity_bar = bar(Color(0.6, 0.4, 0.9)); sanity_bar.max_value = 100.0
	v2.add_child(sanity_bar)

	crosshair = lbl("+", 28, Color(1, 1, 1, 0.7))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-7, -18)
	hud.add_child(crosshair)

	prompt_label = lbl("", 22, C_TEXT)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(-400, -150)
	prompt_label.custom_minimum_size = Vector2(800, 0)
	hud.add_child(prompt_label)

	held_label = lbl("", 18, Color(0.85, 0.8, 0.7))
	held_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	held_label.position = Vector2(18, -44)
	hud.add_child(held_label)

	var hint := lbl("[Tab] Notebook   [Esc] Pause", 15, Color(0.7, 0.7, 0.7))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-300, -34)
	hud.add_child(hint)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(-380, 110)
	toast_box.custom_minimum_size = Vector2(760, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toast_box)

func update_hud() -> void:
	var g = game
	day_label.text = "%s  ·  DAY %d" % [g.day_name(), g.day]
	var h := int(g.minute) / 60 % 24
	var m := int(g.minute) % 60
	clock_label.text = "%02d:%02d   %s" % [h, m, "OPEN" if g.is_open else "CLOSED"]
	clock_label.add_theme_color_override("font_color", C_GREEN if g.is_open else C_RED)
	rent_label.text = g.rent_text()
	goal_label.text = ("> " + g.guide.text) if g.guide and g.guide.text != "" and g.started else ""
	deliv_label.text = g.guide.deliveries_text() if g.guide else ""
	money_label.text = "$%d" % g.money
	rep_bar.value = g.rep
	sanity_bar.value = g.sanity
	var p: String = g.player.current_prompt() if open_panel == null else ""
	prompt_label.text = p
	crosshair.visible = open_panel == null
	held_label.text = ("Carrying: %s x%d" % [Products.pname(g.player.held.product), g.player.held.units]) if g.player.held else ""
	var k: float = 1.0 - g.sanity / 100.0
	var sm := post.material as ShaderMaterial
	sm.set_shader_parameter("strength", clampf(k * 1.25, 0.0, 1.0) * k)
	sm.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	for fx in ["grain", "vhs", "crt", "pixels"]:
		sm.set_shader_parameter(fx, 1.0 if GameSettings.data["fx_" + fx] else 0.0)

func toast(text: String, color := C_TEXT, dur := 4.0) -> void:
	var l := lbl(text, 22, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(760, 0)
	toast_box.add_child(l)
	if toast_box.get_child_count() > 4: toast_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

# --------------------------------------------------------------------------- panels
func is_open() -> bool:
	return open_panel != null

func close_panel() -> void:
	if open_panel:
		open_panel.queue_free()
		open_panel = null
	game.on_panel_closed()

func _show(p: Control) -> void:
	if open_panel: open_panel.queue_free()
	var root := p
	if p is PanelContainer:
		# centre panels whatever size their content ends up
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.set_anchors_preset(Control.PRESET_TOP_LEFT)
		p.position = Vector2.ZERO
		cc.add_child(p)
		root = cc
	open_panel = root
	panel_layer.add_child(root)
	game.on_panel_opened()

func show_text(title: String, body: String, close_text := "Close", on_close := Callable(), typewriter := true, replay := Callable()) -> void:
	var p := panel(720, 460, Color(0.7, 0.6, 0.4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(lbl(title, 30, C_GOLD))
	var b := lbl(body, 24, Color(0.92, 0.9, 0.84), mono if typewriter else font)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(660, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(690, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(b)
	v.add_child(scroll)
	if replay.is_valid():
		v.add_child(button("Listen again", replay, 18, C_PURPLE))
	v.add_child(button(close_text, func():
		close_panel()
		if on_close.is_valid(): on_close.call()))
	_show(p)

func toggle_notebook() -> void:
	if open_panel:
		close_panel()
		return
	var p := panel(720, 520, Color(0.55, 0.45, 0.3))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(lbl("SHOP RULES", 30, C_GOLD))
	if game.rules.is_empty():
		v.add_child(lbl("(Nothing written down yet.)", 22, Color(0.7, 0.7, 0.7), mono))
	for r in game.rules:
		var l := lbl("- " + r, 24, Color(0.9, 0.88, 0.8), mono)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(680, 0)
		v.add_child(l)
	v.add_child(lbl("\nCONTROLS", 22, C_GOLD))
	v.add_child(lbl("WASD move · Shift run · Mouse look · E use · R refuse/alternate · Q put a box down", 20, Color(0.8, 0.8, 0.8), mono))
	v.add_child(button("Close", close_panel))
	_show(p)

func show_catalogue() -> void:
	var p := panel(980, 600, Color(0.5, 0.35, 0.6))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	p.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(lbl("ORDER STOCK", 30, C_GOLD))
	var money := lbl("   You have $%d" % game.money, 24, C_TEXT)
	head.add_child(money)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	root.add_child(cols)
	for beyond in [false, true]:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(450, 0)
		col.add_theme_constant_override("separation", 6)
		cols.add_child(col)
		col.add_child(lbl("THE CATALOGUE FROM BEYOND" if beyond else "ASHFORD WHOLESALE", 22, C_PURPLE if beyond else C_GOLD))
		col.add_child(lbl("Arrives... somehow. You won't hear it." if beyond else "Delivered to the back door in about an hour.", 16, Color(0.7, 0.7, 0.7), mono))
		for id in Products.LIST:
			var info: Dictionary = Products.LIST[id]
			if info["beyond"] != beyond: continue
			var unlocked: bool = info["day"] <= game.day
			var row := HBoxContainer.new()
			col.add_child(row)
			var text := "%s  ·  box of %d  ·  $%d" % [info["name"], Products.BOX_SIZE, info["cost"]] if unlocked else "??? (appears on day %d)" % info["day"]
			var on_order := func():
				if game.order(id):
					money.text = "   You have $%d" % game.money
			var b := button(text, on_order, 18, C_PURPLE if beyond else C_TEXT)
			b.custom_minimum_size = Vector2(440, 0)
			b.disabled = not unlocked
			b.tooltip_text = info["blurb"] + "  Sells for $%d each." % info["price"]
			row.add_child(b)
	root.add_child(lbl("Hover an item for details. Boxes sell for about twice what they cost.", 16, Color(0.7, 0.7, 0.7), mono))
	root.add_child(button("Close catalogue", close_panel))
	_show(p)

func show_summary(lines: Array, on_continue: Callable) -> void:
	var p := panel(700, 520, Color(0.6, 0.5, 0.35))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(lbl("END OF %s" % game.day_name(), 32, C_GOLD))
	for line in lines:
		var col: Color = C_TEXT
		var text: String = line
		if text.begins_with("+"): col = C_GREEN
		elif text.begins_with("-"): col = C_RED
		elif text.begins_with("!"): col = C_PURPLE; text = text.substr(1)
		v.add_child(lbl(text, 24, col, mono))
	v.add_child(button("Sleep until morning", func():
		close_panel()
		on_continue.call(), 22))
	_show(p)

func night_card(lines: Array, on_done: Callable) -> void:
	game.player.frozen = true
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 1)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_layer.add_child(cover)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-420, -160)
	v.custom_minimum_size = Vector2(840, 0)
	v.add_theme_constant_override("separation", 18)
	cover.add_child(v)
	var tw := create_tween()
	cover.modulate.a = 0.0
	tw.tween_property(cover, "modulate:a", 1.0, 0.8)
	for line in lines:
		var l := lbl(line, 28, Color(0.85, 0.8, 0.95), mono)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(840, 0)
		l.modulate.a = 0.0
		v.add_child(l)
		tw.tween_property(l, "modulate:a", 1.0, 0.9)
		tw.tween_interval(1.6 * game.card_speed)
	tw.tween_interval(1.0 * game.card_speed)
	tw.tween_property(cover, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		cover.queue_free()
		on_done.call())

func show_title(on_start: Callable) -> void:
	var p := Control.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-360, -250)
	v.custom_minimum_size = Vector2(720, 0)
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var t := lbl("ELDRITCH & SONS", 84, C_GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := lbl("Fine Goods & Curiosities", 30, C_PURPLE)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var tag := lbl("Running the shop should feel normal. The town around it... less so.", 22, Color(0.8, 0.78, 0.72), mono)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	v.add_child(Control.new())
	v.add_child(button("Open the shop", func():
		close_panel()
		on_start.call(), 28, C_GOLD))
	v.add_child(button("Settings", func(): show_settings(func(): show_title(on_start)), 22))
	v.add_child(button("Quit", func(): get_tree().quit(), 22))
	var c := lbl("Bad Ideas Works  ·  Games of the Week  ·  Week 2\nLetters voiced by Tom (made with ElevenLabs)", 16, Color(0.6, 0.6, 0.7))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	_show(p)

func show_pause(on_title: Callable) -> void:
	var p := panel(420, 300)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(lbl("PAUSED", 34, C_GOLD))
	v.add_child(button("Resume", close_panel, 24))
	v.add_child(button("Shop rules", func():
		close_panel()
		toggle_notebook(), 22))
	v.add_child(button("Settings", func(): show_settings(func(): show_pause(on_title)), 22))
	v.add_child(button("Quit to title", func():
		close_panel()
		on_title.call(), 22))
	_show(p)

func show_ending(title: String, body: String, color: Color, on_again: Callable) -> void:
	var p := panel(760, 480, color)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(lbl(title, 40, color))
	var b := lbl(body, 26, C_TEXT, mono)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(720, 260)
	v.add_child(b)
	v.add_child(button("Start a new week", func():
		close_panel()
		on_again.call(), 24, C_GOLD))
	_show(p)

# --------------------------------------------------------------------------- settings
func _toggle_row(v: VBoxContainer, key: String, text: String) -> void:
	var label_of := func() -> String: return "%s:  %s" % [text, "On" if GameSettings.data[key] else "Off"]
	var b := button(label_of.call(), func(): pass, 20)
	b.pressed.connect(func():
		GameSettings.data[key] = not GameSettings.data[key]
		GameSettings.save_settings()
		GameSettings.apply()
		b.text = label_of.call())
	v.add_child(b)

func _slider_row(v: VBoxContainer, key: String, text: String, lo: int, hi: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := lbl("%s: %d" % [text, GameSettings.data[key]], 20)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 1
	sl.value = GameSettings.data[key]
	sl.custom_minimum_size = Vector2(300, 28)
	sl.value_changed.connect(func(val: float):
		GameSettings.data[key] = int(val)
		GameSettings.save_settings()
		GameSettings.apply()
		l.text = "%s: %d" % [text, int(val)]
		Sfx.play("click", 0.5))
	row.add_child(sl)
	v.add_child(row)

## the settings panel; `on_back` reopens whatever menu we came from
func show_settings(on_back: Callable) -> void:
	var p := panel(640, 560)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(lbl("SETTINGS", 34, C_GOLD))
	_slider_row(v, "volume", "Volume", 0, 10)
	_slider_row(v, "mouse", "Mouse sensitivity", 1, 10)
	_toggle_row(v, "voices", "Letter voices")
	if not OS.has_feature("web"): _toggle_row(v, "fullscreen", "Fullscreen")
	v.add_child(lbl("SCREEN EFFECTS", 22, C_PURPLE))
	for key in ["fx_grain", "fx_vhs", "fx_crt", "fx_pixels"]:
		_toggle_row(v, key, GameSettings.LABELS[key])
	v.add_child(button("Back", func():
		close_panel()
		on_back.call(), 22, C_GOLD))
	_show(p)
