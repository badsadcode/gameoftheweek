-- passengers.lua : eight named passengers, each with a perk that only works while they're alive.
local Audio = require("audio")

local Passengers = {}

Passengers.ROSTER = {
  { id = "ivo",      name = "Ivo",          role = "Mechanic",    perk = "Engine burns coal 15% slower",              lost = "The engine will miss his tuning.",  color = { 0.35, 0.45, 0.70 } },
  { id = "olga",     name = "Gran Olga",    role = "Cook",        perk = "Hot soup at the stove every minute",        lost = "No more soup.",                     color = { 0.70, 0.35, 0.45 } },
  { id = "amara",    name = "Doc Amara",    role = "Doctor",      perk = "Fevers last twice as long, bandages heal more", lost = "Who treats fevers now?",        color = { 0.85, 0.85, 0.88 } },
  { id = "pip",      name = "Pip",          role = "Kid",         perk = "Shouts where raiders land",                 lost = "The train is very quiet now.",      color = { 0.95, 0.75, 0.25 }, small = true },
  { id = "sergei",   name = "Sergei",       role = "Old Soldier", perk = "Snatchers and wolves take twice as long",   lost = "The passenger car lost its guard.", color = { 0.40, 0.50, 0.32 } },
  { id = "lena",     name = "Lena",         role = "Lookout",     perk = "Earlier hazard warnings, spots sleds on the map", lost = "Nobody is watching the horizon.", color = { 0.30, 0.55, 0.60 } },
  { id = "bruno",    name = "Bruno",        role = "Stoker",      perk = "Passenger stove burns 25% slower",          lost = "The stove feels colder already.",   color = { 0.70, 0.50, 0.30 } },
  { id = "whiskers", name = "Mr. Whiskers", role = "Cat",         perk = "Raiders drop extra scrap. Unimpressed.",    lost = "Mr. Whiskers has left the building.", color = { 0.95, 0.60, 0.20 }, cat = true },
}

function Passengers.new()
  local list = {}
  for i, def in ipairs(Passengers.ROSTER) do
    list[i] = { def = def, id = def.id, name = def.name, seat = i, alive = true, sick = false, sickT = 0, fate = nil }
  end
  return list
end

function Passengers.find(G, id)
  for _, p in ipairs(G.passengerList) do
    if p.id == id then return p end
  end
end

-- is this passenger alive (and their perk active)?
function Passengers.has(G, id)
  local p = Passengers.find(G, id)
  return p ~= nil and p.alive
end

function Passengers.count(G)
  local n = 0
  for _, p in ipairs(G.passengerList) do if p.alive then n = n + 1 end end
  return n
end

-- random living passenger; filter(p) optional
function Passengers.randomAlive(G, filter)
  local pool = {}
  for _, p in ipairs(G.passengerList) do
    if p.alive and (not filter or filter(p)) then pool[#pool + 1] = p end
  end
  if #pool == 0 then return nil end
  return pool[love.math.random(#pool)]
end

-- verbs: "froze", "taken", "burned", "mauled", "fever", "derail"
local VERBS = {
  froze = "%s froze to death.",
  taken = "%s was snatched by raiders!",
  burned = "%s was lost in the fire.",
  mauled = "Wolves got %s.",
  fever = "%s was lost to the fever.",
  derail = "%s was thrown about in the derailment and didn't make it.",
}

function Passengers.lose(G, p, fate)
  if not p or not p.alive then return end
  p.alive = false
  p.sick = false
  p.fate = fate
  G.passengers = Passengers.count(G)
  local msg = string.format(VERBS[fate] or "%s is gone.", p.name)
  G.toast(msg .. " " .. p.def.lost, { 1, 0.55, 0.45 }, 6)
  Audio.play("lose", 0.25, 1.5)
  if G.onPassengerLost then G.onPassengerLost(p) end
end

-- convenience: lose a random passenger
function Passengers.loseRandom(G, fate, filter)
  local p = Passengers.randomAlive(G, filter)
  if p then Passengers.lose(G, p, fate) end
  return p
end

return Passengers
