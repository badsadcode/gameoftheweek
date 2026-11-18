## save_game.gd : a morning save. Written when a new day starts, so a crash on Thursday doesn't
## send you back to Monday. "Continue" on the title screen loads it. Ending the week deletes it.
## Everything that changes during a week lives in a handful of plain values on main.gd, so the
## save is just those values; the world (mystery house, Agnes's boards) is rebuilt from `day`.
class_name SaveGame

const PATH := "user://save.cfg"
const VERSION := 1

static func exists() -> bool:
	if not FileAccess.file_exists(PATH): return false
	var cf := ConfigFile.new()
	return cf.load(PATH) == OK and cf.get_value("save", "version", 0) == VERSION

static func day_saved() -> int:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK: return 0
	return int(cf.get_value("save", "day", 0))

static func clear() -> void:
	if FileAccess.file_exists(PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

static func save(g) -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "version", VERSION)
	cf.set_value("save", "day", g.day)
	cf.set_value("save", "money", g.money)
	cf.set_value("save", "rep", g.rep)
	cf.set_value("save", "sanity", g.sanity)
	cf.set_value("save", "rules", g.rules)
	cf.set_value("save", "flags", g.flags)
	cf.set_value("save", "deliveries", g.deliveries)
	cf.set_value("save", "crate_slot", g.crate_slot)
	cf.set_value("save", "tips", g.tip_jar.tips)
	var shelves := []
	for s in g.world.shelves: shelves.append([s.product, s.count])
	cf.set_value("save", "shelves", shelves)
	var crates := []
	for c in g.guide.crates(): crates.append([c.product, c.units, c.global_position.x, c.global_position.z])
	if g.player.held: crates.append([g.player.held.product, g.player.held.units, World.DELIVERY.x, World.DELIVERY.z + 1.2])
	cf.set_value("save", "crates", crates)
	cf.save(PATH)

## call on a freshly built week (main._new_week already ran)
static func load_into(g) -> bool:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK: return false
	for c in g.guide.crates(): c.queue_free()
	g.day = int(cf.get_value("save", "day", 1))
	g.money = int(cf.get_value("save", "money", 60))
	g.rep = float(cf.get_value("save", "rep", 3.0))
	g.sanity = float(cf.get_value("save", "sanity", 100.0))
	g.rules = cf.get_value("save", "rules", [])
	g.flags = cf.get_value("save", "flags", {})
	g.deliveries = cf.get_value("save", "deliveries", [])
	g.crate_slot = int(cf.get_value("save", "crate_slot", 0))
	g.tip_jar.tips = int(cf.get_value("save", "tips", 0))
	g.tip_jar._refresh()
	var shelves: Array = cf.get_value("save", "shelves", [])
	for i in mini(shelves.size(), g.world.shelves.size()):
		g.world.shelves[i].product = shelves[i][0]
		g.world.shelves[i].count = int(shelves[i][1])
		g.world.shelves[i].refresh()
	for c in cf.get_value("save", "crates", []):
		g.spawn_crate(c[0], int(c[1]), Vector3(c[2], 0, c[3]))
	g.minute = 7 * 60
	g._new_day_counters()
	if g.day >= 3: g.world.show_mystery_house()
	if g.day >= 4: g.world.board_up_agnes()
	return true
