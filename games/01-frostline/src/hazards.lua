-- hazards.lua : random trouble along the line, roughly one every 5-9 km.
--   fire      : a car catches fire, stomp it out [E] before it spreads damage
--   track     : damaged rails ahead, brake below TRACK_SPEED or derail
--   wolves    : a pack chases the train at night and goes for the passengers
--   sick      : a passenger gets a fever, fetch medicine from the caboose
--   avalanche : outrun it (> AVALANCHE_SPEED) or snow buries a gap you must dig through
local T = require("train")
local U = require("util")
local Audio = require("audio")
local Particles = require("particles")
local Passengers = require("passengers")

local H = {}
H.TRACK_SPEED = 40
H.AVALANCHE_SPEED = 65
local PX_PER_KMH = 8

local CAR_NAMES = { "caboose", "passenger car", "cargo car", "tender", "engine" }
H.CAR_NAMES = CAR_NAMES

function H.init(G)
  G.fire, G.track, G.avalanche, G.snow = nil, nil, nil, nil
  G.nextHazardKm = 7 + love.math.random() * 3
  T.blockedGap = nil
end

local function lookoutFactor(G) return Passengers.has(G, "lena") and 1.6 or 1 end

local function anySick(G)
  for _, p in ipairs(G.passengerList) do if p.alive and p.sick then return true end end
  return false
end

local function wolvesAround(G)
  for _, s in ipairs(G.sleds) do if s.kind == "wolf" then return true end end
  for _, r in ipairs(G.raiders) do if r.kind == "wolf" and r.state == "board" then return true end end
  return false
end

local function eligible(G, kind)
  if kind == "fire" then return G.fire == nil end
  if kind == "track" then return G.track == nil end
  if kind == "wolves" then return G.progress > 0.12 and G.progress < 0.85 and not wolvesAround(G) end
  if kind == "sick" then return not anySick(G) and Passengers.randomAlive(G, function(p) return not p.def.cat end) ~= nil end
  if kind == "avalanche" then return G.avalanche == nil and G.snow == nil end
  return false
end

function H.trigger(G, kind)
  local flow = G.speed * PX_PER_KMH
  if kind == "fire" then
    local choices = {}
    for i = T.firstAttached, 4 do
      local w = (i == 2 or i == 3) and 2 or 1
      for _ = 1, w do choices[#choices + 1] = i end
    end
    local idx = choices[love.math.random(#choices)]
    local c = T.cars[idx]
    G.fire = { car = idx, x = c.x + 70 + love.math.random() * (c.w - 140), intensity = 35, dmgT = 0 }
    G.toast("FIRE in the " .. CAR_NAMES[idx] .. "! Stomp it out [" .. G.label("interact") .. "].", { 1, 0.55, 0.2 }, 5)
    Audio.play("alarm", 0.5)
  elseif kind == "track" then
    G.track = { x = T.LENGTH + math.max(flow * 5, 600) * lookoutFactor(G), passed = false }
    G.toast("TRACK DAMAGE AHEAD! Brake below " .. H.TRACK_SPEED .. " km/h or we derail!", { 1, 0.8, 0.3 }, 6)
    Audio.play("bell", 0.6, 0.8)
  elseif kind == "wolves" then
    G.spawnWolves(3 + math.floor(G.progress * 3))
    G.toast("WOLVES! A hungry pack is chasing the train.", { 0.85, 0.85, 0.95 }, 5)
    Audio.play("howl", 0.6)
  elseif kind == "sick" then
    local p = Passengers.randomAlive(G, function(q) return not q.def.cat end)
    p.sick = true
    p.sickT = Passengers.has(G, "amara") and 130 or 65
    local where = T.firstAttached == 1 and "Bring MEDICINE from the caboose." or "...and the caboose medkit is gone."
    G.toast(p.name .. " has a fever! " .. where, { 0.6, 1, 0.6 }, 6)
    Audio.play("hurt", 0.4, 0.7)
  elseif kind == "avalanche" then
    G.avalanche = { t = 4.5 * lookoutFactor(G) }
    G.toast("AVALANCHE! Get above " .. H.AVALANCHE_SPEED .. " km/h to outrun it!", { 0.85, 0.92, 1 }, 5)
    Audio.play("rumble", 0.8)
  end
end

local function derail(G)
  local P = G.player
  G.addShake(24)
  Audio.play("uncouple", 1, 0.6)
  Audio.play("boom", 0.6, 0.7)
  P:hurt(G, 22, -1)
  P.stun = 1.2
  G.speed = 12
  G.coal = math.max(0, G.coal - 5)
  if love.math.random() < 0.5 then Passengers.loseRandom(G, "derail") end
  G.toast("DERAILED! ...well, mostly. We're back on the rails, barely.", { 1, 0.45, 0.35 }, 5)
  for _ = 1, 3 do
    local c = T.cars[love.math.random(T.firstAttached, #T.cars)]
    Particles.burst(G, c.x + c.w / 2, T.RAIL_Y - 10, 20, { speed = 300, color = { 1, 0.7, 0.3 }, life = 0.6, add = true })
  end
end

local function bury(G)
  local options = {}
  for g = T.firstAttached, #T.cars - 1 do options[#options + 1] = g end
  local g = options[love.math.random(#options)]
  T.blockedGap = g
  G.snow = { gap = g, hp = 100 }
  G.speed = math.max(10, G.speed - 20)
  G.addShake(16)
  -- push anyone standing in the gap out of the snow
  local a, z = T.cars[g].x + T.CAR_W - 10, T.cars[g + 1].x + 10
  local function evict(b)
    if b.y > T.ROOF_Y + 10 and b.x > a - 4 and b.x < z + 4 then
      b.climbing = false
      b.x = (b.x < (a + z) / 2) and a or z
      b.y = T.FLOOR_Y
    end
  end
  evict(G.player)
  for _, r in ipairs(G.raiders) do if r.state == "board" then evict(r) end end
  G.toast("Snow buried the gap between the " .. CAR_NAMES[g] .. " and the " .. CAR_NAMES[g + 1] .. "! Dig through [" .. G.label("interact") .. "].", { 0.85, 0.92, 1 }, 6)
end

-- interactions (called from the game's interaction list)
function H.stomp(G)
  local f = G.fire
  if not f then return end
  f.intensity = f.intensity - 20
  Audio.play("whoosh", 0.5, 1.6)
  Particles.burst(G, f.x, T.FLOOR_Y - 20, 12, { speed = 120, vy = -80, color = { 0.85, 0.85, 0.9 }, life = 0.7, g = -60 })
  if f.intensity <= 0 then
    G.fire = nil
    G.stats.fires = G.stats.fires + 1
    G.toast("Fire's out!", { 0.6, 1, 0.6 }, 3)
  end
end

function H.dig(G)
  local s = G.snow
  if not s then return end
  s.hp = s.hp - 20
  Audio.play("shovel", 0.6, 1.4)
  Particles.burst(G, T.gapCenter(s.gap), T.FLOOR_Y - 30, 10, { speed = 160, color = { 0.95, 0.97, 1 }, life = 0.5 })
  if s.hp <= 0 then
    G.snow = nil
    T.blockedGap = nil
    G.toast("Dug through!", { 0.6, 1, 0.6 }, 3)
  end
end

-- near which side of the buried gap is x? returns true if close enough to dig
function H.canDig(G, x)
  local s = G.snow
  if not s then return false end
  local a, z = T.cars[s.gap].x + T.CAR_W - 6, T.cars[s.gap + 1].x + 6
  return math.abs(x - a) < 40 or math.abs(x - z) < 40
end

function H.firstSick(G)
  for _, p in ipairs(G.passengerList) do if p.alive and p.sick then return p end end
end

function H.update(G, dt)
  local flow = G.speed * PX_PER_KMH
  local P = G.player

  -- schedule (no new trouble during the boss fight)
  if not G.boss and G.dist >= G.nextHazardKm and G.dist < 86 then
    local pool = {}
    for _, k in ipairs({ "fire", "track", "wolves", "sick", "avalanche" }) do
      if eligible(G, k) then pool[#pool + 1] = k end
    end
    if #pool > 0 then H.trigger(G, pool[love.math.random(#pool)]) end
    G.nextHazardKm = G.dist + U.lerp(9, 5, G.progress) + love.math.random() * 4
  end

  -- fire
  local f = G.fire
  if f then
    if f.car < T.firstAttached then
      G.fire = nil
    else
      f.intensity = math.min(100, f.intensity + 3.2 * dt)
      if love.math.random() < dt * (10 + f.intensity * 0.4) then
        Particles.add(G, { x = f.x + U.rand(-30, 30) * (f.intensity / 100 + 0.3), y = T.FLOOR_Y - 4, vx = U.rand(-20, 20), vy = U.rand(-140, -60),
          life = U.rand(0.4, 0.8), size = U.rand(4, 9) * (0.5 + f.intensity / 100), grow = -6, color = { 1, U.rand(0.35, 0.7), 0.1 }, add = true, alpha = 0.9 })
      end
      if f.intensity >= 60 then
        f.dmgT = f.dmgT + dt
        if f.dmgT >= 10 then
          f.dmgT = 0
          local kind = T.cars[f.car].kind
          if kind == "passenger" then Passengers.loseRandom(G, "burned")
          elseif kind == "tender" then G.coal = math.max(0, G.coal - 4); G.toast("The fire is eating our coal!", { 1, 0.55, 0.2 })
          elseif kind == "cargo" then G.scrap = math.max(0, G.scrap - 2); G.toast("Scrap is melting in the cargo fire!", { 1, 0.55, 0.2 })
          elseif kind == "caboose" then G.bandages = math.max(0, G.bandages - 1); G.toast("The fire burned a bandage!", { 1, 0.55, 0.2 }) end
        end
      end
      if T.levelOf(P) == "floor" and math.abs(P.x - f.x) < 40 and f.intensity > 40 then
        P.health = math.max(0, P.health - 3 * dt)
        P.lastHurt = 0
      end
    end
  end

  -- damaged track
  local tr = G.track
  if tr then
    tr.x = tr.x - flow * dt
    if not tr.passed and tr.x <= T.LENGTH - 30 then
      tr.passed = true
      if G.speed > H.TRACK_SPEED then derail(G)
      else G.toast("Smooth. The rails held.", { 0.6, 1, 0.6 }, 3) end
    end
    if tr.x < T.minX() - 500 then G.track = nil end
  end

  -- fevers
  for _, p in ipairs(G.passengerList) do
    if p.alive and p.sick then
      p.sickT = p.sickT - dt
      if p.sickT <= 0 then Passengers.lose(G, p, "fever") end
    end
  end

  -- avalanche
  local av = G.avalanche
  if av then
    av.t = av.t - dt
    G.addShake(2 + 3 * (1 - math.max(0, av.t) / 4.5))
    if av.t <= 0 then
      G.avalanche = nil
      if G.speed >= H.AVALANCHE_SPEED then
        G.toast("Outran the avalanche!", { 0.6, 1, 0.6 }, 3)
      else
        Audio.play("rumble", 1, 0.7)
        bury(G)
      end
    end
  end
end

return H
