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
