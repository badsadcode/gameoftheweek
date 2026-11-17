-- raiders.lua : sled-riding raiders who chase the train, leap aboard and cause trouble.
--   thief    -> steals coal from the tender
--   snatcher -> kidnaps passengers
--   saboteur -> uncouples cars (lose the passenger car = game over)
--   brute    -> hunts YOU
--   wolf     -> (hazard) runs alongside, leaps onto the platforms and goes for the passengers
local T = require("train")
local U = require("util")
local Audio = require("audio")
local Particles = require("particles")
local Passengers = require("passengers")
local Upgrades = require("upgrades")

local Raiders = {}
Raiders.SLED_Y = 690

Raiders.TYPES = {
  thief    = { hp = 2, speed = 140, dmg = 8,  windup = 0.45, cooldown = 1.0, scale = 1.0, scarf = { 0.95, 0.80, 0.20 }, label = "Coal Thief" },
  snatcher = { hp = 2, speed = 150, dmg = 8,  windup = 0.45, cooldown = 1.0, scale = 1.0, scarf = { 0.30, 0.90, 0.55 }, label = "Snatcher" },
  saboteur = { hp = 3, speed = 130, dmg = 10, windup = 0.45, cooldown = 1.0, scale = 1.0, scarf = { 0.95, 0.25, 0.20 }, label = "Saboteur" },
  brute    = { hp = 5, speed = 165, dmg = 16, windup = 0.6,  cooldown = 1.2, scale = 1.3, scarf = { 0.70, 0.40, 0.95 }, label = "Brute" },
  wolf     = { hp = 1, speed = 230, dmg = 6,  windup = 0.3,  cooldown = 0.8, scale = 1.0, scarf = { 0.6, 0.6, 0.65 },  label = "Wolf" },
}

-- scrap each kind drops when thrown off
local SCRAP = { thief = 1, snatcher = 1, saboteur = 2, brute = 4, wolf = 1 }

-- seconds a raider must work to finish its job (perks and upgrades change these)
function Raiders.workNeed(G, r)
  if r.kind == "saboteur" then return Upgrades.has(G, "couplings") and 24 or 12 end
  if r.kind == "snatcher" then return Passengers.has(G, "sergei") and 13 or 6.5 end
  if r.kind == "wolf" then return Passengers.has(G, "sergei") and 14 or 7 end
  return 1.7
end

function Raiders.init(G)
  G.sleds, G.raiders = {}, {}
  G.spawnT = 24
end

local function pickType(p)
  return U.pick({
    { "thief", 3 },
    { "snatcher", 1.5 + p * 2 },
    { "saboteur", p > 0.1 and (0.8 + p * 3) or 0 },
    { "brute", p > 0.22 and (0.8 + p * 3.2) or 0 },
  })
end

local function roofSpotNear(x)
  x = U.clamp(x, T.minX() + 30, T.LENGTH - 30)
  if not T.carAt(x) then x = x + T.GAP end
  return x
end

-- where a raider of this kind wants to land; fills s.landX, s.landY, s.gap
function Raiders.planLanding(G, s)
  local kind = s.kind
  local function floorGap(g)
    g = math.max(g, T.firstAttached)
    if T.blockedGap == g then -- buried in snow: land on the roof next to it instead
      s.landX, s.landY = T.cars[g].x + T.CAR_W - 30, T.ROOF_Y
    else
      s.landX, s.landY = T.gapCenter(g), T.FLOOR_Y
    end
  end
  if kind == "thief" then
    floorGap(3)
  elseif kind == "snatcher" or kind == "wolf" then
    floorGap((T.firstAttached == 1 and love.math.random() < 0.5) and 1 or 2)
  elseif kind == "saboteur" then
    s.gap = love.math.random(T.firstAttached, 3)
    floorGap(s.gap)
  else
    s.offset = s.offset or U.rand(-180, 180)
    s.landY = T.ROOF_Y
    s.landX = roofSpotNear(G.player.x + s.offset)
  end
end

function Raiders.spawnSled(G, i, kind)
  kind = kind or pickType(G.progress)
  local s = {
    kind = kind, x = T.minX() - 280 - (i - 1) * 170, bob = love.math.random() * 6,
    speed = 58 + G.progress * 42 + U.rand(-6, 12), empty = false,
  }
  if kind == "wolf" then s.speed = 92 + G.progress * 20 + U.rand(-5, 10); s.x = T.minX() - 240 - (i - 1) * 90 end
  Raiders.planLanding(G, s)
  G.sleds[#G.sleds + 1] = s
end

function Raiders.spawnWolves(G, n)
  for i = 1, n do Raiders.spawnSled(G, i, "wolf") end
end

-- the Iron Jaw launches raiders straight from its deck
function Raiders.deployFromBoss(G, x)
  local s = { kind = U.pick({ { "thief", 2 }, { "saboteur", 2 }, { "brute", 2 } }), x = x, empty = false }
  Raiders.planLanding(G, s)
  Raiders.board(G, s, 600)
end

function Raiders.board(G, s, fromY)
  local def = Raiders.TYPES[s.kind]
  fromY = fromY or (Raiders.SLED_Y - 30)
  G.raiders[#G.raiders + 1] = {
    kind = s.kind, state = "jump", jt = 0,
    fromX = s.x, fromY = fromY, toX = s.landX, toY = s.landY,
    x = s.x, y = fromY, vx = 0, vy = 0, onGround = false, climbing = false, facing = 1,
    hp = def.hp, scale = def.scale, stun = 0, windup = 0, atkCD = 0.6, work = 0, loot = 0, anim = 0,
    gap = s.gap, offset = U.rand(-40, 40), hurtT = 0, rot = 0, provoked = 0,
  }
  if s.kind == "wolf" then Audio.play("grunt", 0.4, 1.6) else Audio.play("jump", 0.4, 0.8) end
end

function Raiders.leave(G, r, msg, color)
  r.state = "leave"
  r.climbing = false
  r.vx, r.vy = -260, -420
  if msg then G.toast(msg, color or { 1, 0.45, 0.35 }) end
end

function Raiders.kill(G, r, dir)
  r.state = "dead"
  r.climbing = false
  r.vx, r.vy = dir * 260, -460
  G.stats.kills = G.stats.kills + 1
  local y = r.onGround and r.y or T.FLOOR_Y
  if r.kind ~= "wolf" and (r.loot > 0 or love.math.random() < 0.45) then
    G.items[#G.items + 1] = { kind = "coal", x = r.x, y = y, amount = r.loot > 0 and r.loot + 1 or 2, t = 0 }
  end
  if r.kind == "brute" and G.toyWanted and not G.hasToy then
    G.toyWanted = false
    G.items[#G.items + 1] = { kind = "toy", x = r.x - 18 * dir, y = y, amount = 1, t = 0 }
  end
  if G.onRaiderKilled then G.onRaiderKilled(r) end
  local scrap = (SCRAP[r.kind] or 1) + (Passengers.has(G, "whiskers") and 1 or 0)
  G.items[#G.items + 1] = { kind = "scrap", x = r.x + 18 * dir, y = y, amount = scrap, t = 0.5 }
end

function Raiders.damage(G, r, dmg, dir)
  r.hp = r.hp - dmg
  r.hurtT = 0.15
  r.provoked = 4
  r.climbing = false
  if r.kind == "brute" then
    r.stun, r.vx = 0.12, dir * 120
  else
    r.windup, r.stun, r.vx = 0, 0.35, dir * 280
  end
  Particles.burst(G, r.x, r.y - 30 * r.scale, 8, { speed = 220, color = { 1, 0.9, 0.6 }, life = 0.3, add = true, g = 300 })
  if r.hp <= 0 then Raiders.kill(G, r, dir) end
end

-- clotheslined by a bridge or tunnel
function Raiders.knockOff(G, r)
  r.state = "dead"
  r.climbing = false
  r.vx, r.vy = -540, -140
  G.stats.kills = G.stats.kills + 1
  G.stats.knocked = G.stats.knocked + 1
  Audio.play("hit", 0.6, 0.7)
  if G.stats.knocked == 1 then G.toast("Clotheslined! Bridges hit raiders too.", { 0.6, 1, 0.6 }) end
end

-- Walk/climb toward (tx, tlevel). Returns true once arrived.
local function navigate(G, r, tx, tlevel, speed, dt)
  if r.climbing then
    r.y = r.y + r.climbDir * 170 * dt
    if r.y <= T.ROOF_Y then
      r.climbing = false
      r.y, r.vy, r.onGround = T.ROOF_Y, 0, true
      local g = r.gap
      if tx > r.x then r.x = T.cars[g + 1].x + 16 else r.x = T.cars[g].x + T.CAR_W - 16 end
    elseif r.y >= T.FLOOR_Y then
      r.climbing = false
      r.y, r.onGround = T.FLOOR_Y, true
    end
    return false
  end
  if not r.onGround then return false end

  local lvl = T.levelOf(r)
  if lvl ~= tlevel then
    local g = T.nearestGap(r.x)
    if not g then return false end
    local gx = T.gapCenter(g)
    if lvl == "roof" then
      -- just walk off the edge into the gap; gravity does the rest
      r.vx = U.sign(gx - r.x) * speed
      if r.vx == 0 then r.vx = speed end
    elseif math.abs(gx - r.x) < 6 then
      r.climbing, r.gap, r.climbDir = true, g, -1
      r.x, r.vx = gx, 0
    else
      r.vx = U.sign(gx - r.x) * speed
    end
    if r.vx ~= 0 then r.facing = U.sign(r.vx) end
    return false
  end

  local d = tx - r.x
  if math.abs(d) < 8 then r.vx = 0; return true end
  r.vx = U.sign(d) * speed
  r.facing = U.sign(d)
  if lvl == "roof" and T.carAt(r.x) and not T.carAt(r.x + r.facing * 20) then
    r.vy = -480
    r.vx = r.facing * (speed + 40)
  end
  return false
end

function Raiders.think(G, r, dt)
  local P = G.player
  local def = Raiders.TYPES[r.kind]
  r.atkCD = math.max(0, r.atkCD - dt)
  r.provoked = math.max(0, r.provoked - dt)

  if r.stun > 0 then
    r.stun = r.stun - dt
    r.vx = U.approach(r.vx, 0, 900 * dt)
    return
  end

  local dx = P.x - r.x
  if r.windup > 0 then
    r.vx = 0
    r.windup = r.windup - dt
    if r.windup <= 0 then
      if math.abs(dx) < 66 * r.scale and math.abs(P.y - r.y) < 44 and not P.climbing then
        P:hurt(G, def.dmg, U.sign(dx))
      end
      r.atkCD = def.cooldown
      Audio.play("swing", 0.35, 0.7)
    end
    return
  end

  local sameLevel = math.abs(P.y - r.y) < 44 and not P.climbing
  local aggro = r.kind == "brute" or r.provoked > 0 or (sameLevel and math.abs(dx) < (r.kind == "wolf" and 200 or 120))
  if r.kind == "wolf" and not sameLevel then aggro = false end -- wolves can't climb
  local spd = def.speed

  if aggro and P.health > 0 then
    if sameLevel and math.abs(dx) < 54 * r.scale then
      r.vx = 0
      if dx ~= 0 then r.facing = U.sign(dx) end
      if r.atkCD <= 0 then
        r.windup = def.windup
        Audio.play("grunt", 0.45, (r.kind == "brute" and 0.7 or 1) * U.rand(0.9, 1.1))
      end
      return
    end
    local tl = T.levelOf(P)
    if tl == "ladder" then tl = "floor" end
    navigate(G, r, P.x, tl, spd * 1.05, dt)
    return
  end

  if r.kind == "thief" then
    if navigate(G, r, T.COAL_X + r.offset, "floor", spd, dt) then
      r.work = r.work + dt
      if r.work >= 1.7 then
        r.work = 0
        if G.coal > 0 then
          G.coal = G.coal - 1
          r.loot = r.loot + 1
          Audio.play("shovel", 0.3, 1.3)
        end
        if r.loot >= 5 or G.coal <= 0 then Raiders.leave(G, r, "A thief got away with " .. r.loot .. " coal!") end
      end
    end
  elseif r.kind == "snatcher" or r.kind == "wolf" then
    if T.firstAttached > 2 then Raiders.leave(G, r); return end
    if navigate(G, r, T.STOVE_X + (r.offset > 0 and 90 or -90) + r.offset * 0.5, "floor", spd, dt) then
      r.work = r.work + dt
      if r.kind == "wolf" and love.math.random() < dt * 2 then Audio.play("grunt", 0.3, 1.7) end
      if r.work >= Raiders.workNeed(G, r) then
        if r.kind == "wolf" then
          Passengers.loseRandom(G, "mauled")
          Raiders.leave(G, r)
        else
          local p = Passengers.loseRandom(G, "taken")
          if p then G.stats.taken = G.stats.taken + 1; r.hasPassenger = true end
          Raiders.leave(G, r)
        end
      end
    end
  elseif r.kind == "saboteur" then
    if r.gap < T.firstAttached then r.gap = T.firstAttached; r.work = 0 end
    if navigate(G, r, T.gapCenter(r.gap), "floor", spd, dt) then
      if r.work == 0 then Audio.play("alarm", 0.6, 1.2) end
      r.work = r.work + dt
      if love.math.random() < dt * 12 then
        Particles.burst(G, r.x + 8, T.FLOOR_Y + 22, 2, { speed = 120, color = { 1, 0.7, 0.3 }, life = 0.35, add = true })
      end
      if r.work >= Raiders.workNeed(G, r) then
        G.uncouple(r.gap)
        Raiders.leave(G, r)
      end
    end
  end
end

function Raiders.update(G, dt)
  -- spawning
  G.spawnT = G.spawnT - dt
  if G.spawnT <= 0 then
    local p = G.progress
    G.spawnT = U.lerp(17, 7, p) + love.math.random() * 5
    if G.boss then G.spawnT = G.spawnT * 2.2 end -- the Iron Jaw brings its own raiders
    local n = 1
    if love.math.random() < p * 0.8 then n = n + 1 end
    if love.math.random() < p * 0.4 then n = n + 1 end
    for i = 1, n do Raiders.spawnSled(G, i) end
  end

  -- sleds
  for i = #G.sleds, 1, -1 do
    local s = G.sleds[i]
    s.bob = s.bob + dt * 9
    s.x = s.x + (s.speed - G.speed) * 7 * dt - (s.empty and 220 or 0) * dt
    if s.kind == "brute" and not s.empty then s.landX = roofSpotNear(G.player.x + s.offset) end
    if not s.empty and s.x >= s.landX - 40 then
      Raiders.board(G, s)
      s.empty = true
    end
    if s.kind ~= "wolf" and love.math.random() < dt * 30 then
      Particles.add(G, { x = s.x - 30, y = Raiders.SLED_Y + 8, vx = -G.speed * 6 - 60, vy = U.rand(-60, -10),
        life = 0.6, size = U.rand(2, 5), grow = 6, g = 100, color = { 0.9, 0.95, 1 }, alpha = 0.7, layer = "sled" })
    end
    if s.x < T.minX() - 1100 then
      if not s.empty and s.kind ~= "wolf" then
        G.stats.outrun = G.stats.outrun + 1
        if G.stats.outrun == 1 or G.stats.outrun % 5 == 0 then
          G.toast("Outran a raider sled! Speed keeps them off.", { 0.6, 0.9, 1 })
        end
      end
      table.remove(G.sleds, i)
    end
  end

  -- raiders
  for i = #G.raiders, 1, -1 do
    local r = G.raiders[i]
    r.hurtT = math.max(0, r.hurtT - dt)
    if r.state == "jump" then
      r.jt = r.jt + dt / 0.8
      local t = math.min(1, r.jt)
      r.x = U.lerp(r.fromX, r.toX, t)
      r.y = U.lerp(r.fromY, r.toY, t) - math.sin(math.pi * t) * 170
      r.facing = 1
      if t >= 1 then
        if r.toX < T.minX() then
          r.state, r.vx, r.vy = "leave", -200, 0
        else
          -- landing spot got buried by an avalanche meanwhile? hop onto the roof instead
          local bg = T.blockedGap
          if bg and r.toY == T.FLOOR_Y and math.abs(r.x - T.gapCenter(bg)) < T.GAP then
            r.x, r.toY = T.cars[bg].x + T.CAR_W - 30, T.ROOF_Y
          end
          r.state, r.y, r.vy, r.onGround = "board", r.toY, 0, true
          Particles.burst(G, r.x, r.y, 6, { speed = 90, color = { 0.9, 0.95, 1 }, life = 0.4, g = 200 })
          if G.onRaiderLanded then G.onRaiderLanded(r) end
          if r.toY == T.ROOF_Y and Upgrades.has(G, "spikes") and r.kind ~= "wolf" then
            Raiders.damage(G, r, 1, 1)
            if r.state == "board" then r.stun = 0.8 end
          end
        end
      end
    elseif r.state == "board" then
      Raiders.think(G, r, dt)
      if not r.climbing then T.stepBody(r, dt) end
      if r.onGround and math.abs(r.vx) > 5 then r.anim = r.anim + dt * math.abs(r.vx) * 0.055 end
    elseif r.state == "dead" or r.state == "leave" then
      r.vy = r.vy + T.GRAVITY * dt
      r.x = r.x + r.vx * dt
      r.y = r.y + r.vy * dt
      if r.state == "dead" then r.rot = r.rot + dt * 9 * U.sign(r.vx) end
      if r.y > 900 then table.remove(G.raiders, i) end
    elseif r.state == "detached" then
      if not G.detached or G.detached.offset < -2500 then table.remove(G.raiders, i) end
    end
  end
end

return Raiders
