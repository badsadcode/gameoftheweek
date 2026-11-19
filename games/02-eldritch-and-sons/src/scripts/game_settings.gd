## game_settings.gd : player options, saved to user://settings.cfg.
## Screen effects are layered in post.gdshader; each one can be switched off in the menu.
class_name GameSettings

const PATH := "user://settings.cfg"

static var data := {
	"volume": 8,          # 0..10
	"voices": true,       # read letters aloud
	"mouse": 5,           # 1..10
	"fullscreen": false,
	"hq": true,           # Forward+ extras: shadows, volumetric fog, SSAO (off = lighter on the GPU)
	"fx_grain": true,     # gentle film noise (on by default: keeps the creepy)
	"fx_vhs": false,      # wobbly old tape
	"fx_crt": false,      # scanlines + rounded vignette
	"fx_pixels": false,   # chunky low-res render
	"stream": false,      # stream mode: "CHAT DECIDES" banners at big decisions
}

const LABELS := {
	"fx_grain": "Film grain",
	"fx_vhs": "VHS tape",
	"fx_crt": "CRT scanlines",
	"fx_pixels": "Retro pixels",
}

static func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK: return
	for k in data:
		var v = cf.get_value("settings", k, data[k])
		if typeof(v) == typeof(data[k]): data[k] = v

static func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in data: cf.set_value("settings", k, data[k])
	cf.save(PATH)

static func apply() -> void:
	Sfx.volume = data["volume"] / 10.0
	var fs: bool = data["fullscreen"]
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not OS.has_feature("web"):
		DisplayServer.window_set_mode(want)

static func mouse_sensitivity() -> float:
	return 0.0025 * (data["mouse"] / 5.0)
