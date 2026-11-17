-- boss.lua : THE IRON JAW, an armoured raider war-wagon that attacks near the end of the line.
--   * fires harpoons into the cars; every chain drags the train slower (cut them with the wrench)
--   * keeps sending raiders aboard
--   * only dynamite hurts it: grab it from the crate in the cargo car, throw it with [attack]
local T = require("train")
local U = require("util")
local Audio = require("audio")
local Particles = require("particles")

local B = {}
B.START_KM = 87
B.HP = 6
B.HALF = 290          -- half length of the war-wagon body
B.DECK_Y = 600        -- where harpoons and raiders launch from
B.GROUND_Y = 672      -- dynamite explodes when it reaches this height
B.DRAG_PER_HOOK = 9   -- km/h lost per attached chain
B.MAX_HOOKS = 3

function B.init(G)
  G.boss, G.bossDone = nil, false
  G.hooks, G.projectiles = {}, {}
end

local function spawn(G)
  G.boss = { x = T.minX() - 900, targetX = 1000, hp = B.HP, state = "approach", t = 0,
             hookT = 4, deployT = 3, flash = 0, dieT = 0, aim = 0 }
  G.toast("THE IRON JAW is coming! Grab DYNAMITE from the cargo car and throw it [" .. G.label("attack") .. "]!", { 1, 0.4, 0.3 }, 7)
  Audio.play("alarm", 0.7, 0.5)
  Audio.play("howl", 0.4, 0.5)
end

function B.drag(G) return #G.hooks * B.DRAG_PER_HOOK end

local function fireHarpoon(G, b)
  local c = T.cars[love.math.random(T.firstAttached, #T.cars)]
  local tx = c.x + 40 + love.math.random() * (c.w - 80)
  local turretX = b.x - 40
  G.projectiles[#G.projectiles + 1] = { kind = "harpoon", x0 = turretX, y0 = B.DECK_Y - 20, x1 = tx, y1 = T.FLOOR_Y + 10, t = 0 }
  b.aim = math.atan2(T.FLOOR_Y + 10 - (B.DECK_Y - 20), tx - turretX)
  Audio.play("harpoon", 0.7)
end

local function die(G, b)
  b.state, b.dieT = "dying", 2.8
  G.hooks = {}
  G.stats.boss = true
  G.scrap = G.scrap + 10
  G.toast("THE IRON JAW IS DOWN! +10 scrap. Chains snapped!", { 1, 0.85, 0.3 }, 6)
  if G.onBossDown then G.onBossDown() end
  Audio.play("boom", 1, 0.6)
  Audio.play("uncouple", 0.8, 1.3)
end

local function explode(G, x, y)
  Audio.play("boom", 0.9, U.rand(0.9, 1.1))
  G.addShake(12)
  Particles.burst(G, x, y, 30, { speed = 380, color = { 1, 0.65, 0.2 }, life = 0.7, add = true, g = 200, layer = "sled" })
  Particles.burst(G, x, y, 16, { speed = 160, color = { 0.25, 0.22, 0.22 }, life = 1.2, g = -40, size = 7, layer = "sled" })
  local b = G.boss
  if b and b.state == "fight" and math.abs(x - b.x) < B.HALF then
    b.hp = b.hp - 1
    b.flash = 0.35
    if G.onBossHit then G.onBossHit() end
    if b.hp <= 0 then die(G, b)
    else G.toast("BOOM! The Iron Jaw is cracking: " .. b.hp .. " more!", { 1, 0.75, 0.3 }, 3) end
  elseif b and b.state ~= "dying" then
    G.toast("Missed! Throw it where the war-wagon is.", { 1, 0.8, 0.5 }, 2.5)
  end
end

function B.throwDynamite(G, P)
  P.carrying = nil
  G.projectiles[#G.projectiles + 1] = { kind = "dynamite", x = P.x + P.facing * 12, y = P.y - 40, vx = P.facing * 230, vy = -380, rot = 0 }
  Audio.play("swing", 0.6, 0.8)
end

-- wrench swing near a chain anchor; returns true if something was hit
function B.hitHooks(G, P, dmg)
  if T.levelOf(P) ~= "floor" then return false end
  local hit = false
  for i = #G.hooks, 1, -1 do
    local h = G.hooks[i]
    if math.abs(h.x - (P.x + P.facing * 30)) < 55 then
      h.hp = h.hp - dmg
      hit = true
      Particles.burst(G, h.x, T.FLOOR_Y + 6, 8, { speed = 200, color = { 1, 0.85, 0.5 }, life = 0.3, add = true })
      if h.hp <= 0 then
        table.remove(G.hooks, i)
        G.stats.chains = G.stats.chains + 1
        Audio.play("uncouple", 0.6, 1.5)
        G.toast("Chain cut!", { 0.6, 1, 0.6 }, 2)
      end
    end
  end
  return hit
end

function B.update(G, dt)
  if not G.boss and not G.bossDone and G.dist >= B.START_KM and G.state == "play" then spawn(G) end

  -- projectiles
  for i = #G.projectiles, 1, -1 do
    local p = G.projectiles[i]
    if p.kind == "harpoon" then
      p.t = p.t + dt / 0.45
      if p.t >= 1 then
        table.remove(G.projectiles, i)
        if G.boss and G.boss.state == "fight" and p.x1 >= T.minX() then
          G.hooks[#G.hooks + 1] = { x = p.x1, hp = 2 }
          G.addShake(5)
          Audio.play("hit", 0.6, 0.6)
        end
      end
    else -- dynamite
      p.vy = p.vy + 1500 * dt
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      p.rot = p.rot + dt * 10
      if love.math.random() < dt * 40 then
        Particles.add(G, { x = p.x, y = p.y - 8, vx = U.rand(-40, 40), vy = U.rand(-60, 0), life = 0.25, size = 2, color = { 1, 0.9, 0.4 }, add = true, layer = "sled" })
      end
      if p.y >= B.GROUND_Y then
        table.remove(G.projectiles, i)
        explode(G, p.x, p.y)
      end
    end
  end

  -- chains on detached cars fall away
  for i = #G.hooks, 1, -1 do
    if G.hooks[i].x < T.minX() then table.remove(G.hooks, i) end
  end

  local b = G.boss
  if not b then return end
  b.t = b.t + dt
  b.flash = math.max(0, b.flash - dt)
  if love.math.random() < dt * 14 then
    Particles.add(G, { x = b.x - 190 + love.math.random() * 50, y = 545, vx = -G.speed * 6, vy = -60, life = 1.6, size = 7,
      grow = 14, color = { 0.15, 0.13, 0.13 }, alpha = 0.6, layer = "smoke" })
  end

  if b.state == "approach" then
    b.targetX = U.clamp(G.player.x, T.minX() + 150, T.LENGTH - 150)
    b.x = b.x + 320 * dt
    if b.x >= b.targetX then b.state = "fight" end
  elseif b.state == "fight" then
    -- shadow the player (so it's always on screen) while weaving back and forth
    b.targetX = U.clamp(G.player.x + math.sin(b.t * 0.35) * 260, T.minX() + 150, T.LENGTH - 150)
    b.x = U.lerp(b.x, b.targetX, math.min(1, dt * 0.6))
    b.hookT = b.hookT - dt
    if b.hookT <= 0 then
      if #G.hooks < B.MAX_HOOKS then fireHarpoon(G, b) end
      b.hookT = 5 + b.hp * 0.6
    end
    b.deployT = b.deployT - dt
    if b.deployT <= 0 then
      b.deployT = 8
      local aboard = 0
      for _, r in ipairs(G.raiders) do if r.state == "board" or r.state == "jump" then aboard = aboard + 1 end end
      if aboard < 5 then G.deployFromBoss(b.x + U.rand(-120, 120)) end
    end
  elseif b.state == "dying" then
    b.dieT = b.dieT - dt
    b.x = b.x - 160 * dt
    if love.math.random() < dt * 10 then
      local ex = b.x + U.rand(-B.HALF, B.HALF)
      Particles.burst(G, ex, U.rand(600, 690), 14, { speed = 260, color = { 1, 0.6, 0.2 }, life = 0.6, add = true, layer = "sled" })
      if love.math.random() < 0.4 then Audio.play("boom", 0.5, U.rand(0.8, 1.2)) end
    end
    if b.dieT <= 0 then
      G.boss = nil
      G.bossDone = true
    end
  end
end

return B
