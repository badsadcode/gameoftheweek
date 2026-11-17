-- game.lua : the run state (G), the simulation loop, input and the draw order.
local U = require("util")
local T = require("train")
local Audio = require("audio")
local BG = require("background")
local Player = require("player")
local Raiders = require("raiders")
local Events = require("events")
local Render = require("render")
local HUD = require("hud")
local Particles = require("particles")
local lg = love.graphics

local Game = {}
local G
local VW, VH = 1280, 720
local GOAL_KM = 100

local HINTS = {
  { 1.5, "Grab coal in the TENDER [E], then feed the FURNACE in the engine cab [E]." },
  { 10, "The passengers' STOVE needs coal too. It's two cars back." },
  { 20, "Raiders will chase on sleds. Swing your wrench with [J] or Left Click." },
  { 30, "Ladders sit between cars: [W] up, [S] down. Watch for low bridges up top!" },
  { 42, "The brake lever is in the engine cab. Only brake for depots!" },
}

function Game.state() return G end

function Game.load()
  HUD.load()
  Audio.load()
  BG.load()
  Render.load()
  Game.newRun("title")
  Game.wind = Audio.loop("wind", 0.2)
end

function Game.newRun(state)
  T.reset()
  G = {
    state = state or "play", time = 0, dist = 0, progress = 0, speed = 58, fuel = 75, coal = 24, maxCoal = 50,
    stove = 70, carTemp = 14, ambient = -22, freeze = 0, passengers = 8, bandages = 3, brake = false,
    scroll = 0, camX = 0, shake = 0, flash = 0, toasts = {}, particles = {}, items = {},
    stats = { kills = 0, taken = 0, frozen = 0, shoveled = 0, outrun = 0, knocked = 0 },
    stallT = 0, detached = nil, loadAcc = 0, chugT = 0, clackT = 0, smokeT = 0, hintIdx = 1, endT = 0,
    windowColor = { 0.1, 0.1, 0.2 },
  }
  G.player = Player.new()
  G.toast = function(msg, color, dur)
    G.toasts[#G.toasts + 1] = { msg = msg, color = color or { 1, 1, 1 }, t = dur or 4.5, max = dur or 4.5 }
  end
  G.addShake = function(a) G.shake = math.max(G.shake, a) end
  G.uncouple = Game.uncouple
  Raiders.init(G)
  Events.init(G)
  if G.state == "title" then
    G.camX = T.LENGTH - VW + 100
    G.progress = 0.45
  else
    G.camX = U.clamp(G.player.x - VW / 2, -150, T.LENGTH - VW + 220)
  end
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------
function Game.uncouple(g)
  if G.state ~= "play" or g < T.firstAttached then return end
  local cut = T.cars[g + 1].x
  T.firstAttached = g + 1
  G.detached = { upto = g, offset = 0, vel = 0 }
  Audio.play("uncouple", 0.9)
  G.addShake(12)
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and r.x < cut then r.state = "detached" end
  end
  for i = #G.items, 1, -1 do
    if G.items[i].x < cut then table.remove(G.items, i) end
  end
  local P = G.player
  if P.x < cut then
    G.pendingLoss = { t = 1.6, reason = "You were left behind on the uncoupled cars." }
  elseif g >= 2 then
    G.pendingLoss = { t = 2.2, reason = "Saboteurs uncoupled the passenger car. It vanished into the snow." }
  else
    G.bandages = 0
    G.toast("The CABOOSE was uncoupled! The medkit went with it.", { 1, 0.4, 0.3 }, 5)
  end
end

local function updateTrain(dt)
  local target = 0
  if G.fuel > 0 then
    target = G.brake and 22 or (30 + G.fuel * 0.7)
    if T.firstAttached > 1 then target = target + 5 end -- lighter train
  end
  local rate = (target < G.speed) and (G.brake and 0.9 or 0.35) or 0.22
  G.speed = math.max(0, G.speed + (target - G.speed) * math.min(1, rate * dt))
  G.fuel = math.max(0, G.fuel - (0.8 + G.speed / 100 * 1.3) * dt)
  G.dist = G.dist + G.speed * dt / 400
  G.progress = U.clamp(G.dist / GOAL_KM, 0, 1)
  G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
  G.stallT = (G.speed < 3) and (G.stallT + dt) or 0
  if G.detached then
    G.detached.vel = G.detached.vel + 70 * dt
    G.detached.offset = G.detached.offset - G.detached.vel * dt
  end
  if G.brake and G.speed > 25 and love.math.random() < dt * 30 then
    local c = T.cars[love.math.random(T.firstAttached, #T.cars)]
    Particles.burst(G, c.x + 48 + love.math.random() * (c.w - 96), T.RAIL_Y - 2, 2,
      { speed = 160, vx = -200, vy = -80, color = { 1, 0.7, 0.3 }, life = 0.3, add = true, g = 500 })
  end
end

local function updateHeat(dt)
  local P = G.player
  G.ambient = -22 - G.blizzard * 14
  G.stove = math.max(0, G.stove - (0.75 + G.blizzard * 0.5) * dt)
  if G.stove > 0 then
    G.carTemp = U.approach(G.carTemp, 20, 1.6 * dt)
  else
    G.carTemp = U.approach(G.carTemp, G.ambient, (0.45 + G.blizzard * 0.3) * dt)
  end
  if G.carTemp < 0 then
    G.freeze = G.freeze + (-G.carTemp) / 10 * dt
    if G.freeze >= 18 and G.passengers > 0 then
      G.freeze = 0
      G.passengers = G.passengers - 1
      G.stats.frozen = G.stats.frozen + 1
      G.toast("A passenger froze to death. Feed the stove!", { 0.5, 0.8, 1 }, 5)
      Audio.play("lose", 0.25, 1.5)
    end
  else
    G.freeze = math.max(0, G.freeze - dt)
  end

  local lvl = T.levelOf(P)
  local car = T.carAt(P.x)
  local rate
  if lvl ~= "floor" then rate = -2.6
  elseif car and car.kind == "engine" and G.fuel > 0 then rate = 9
  elseif car and car.kind == "passenger" and G.carTemp > 5 then rate = 7
  elseif car then rate = -0.8
  else rate = -1.6 end
  if rate < 0 then rate = rate * (1 + G.blizzard * 0.9) end
  P.warmth = U.clamp(P.warmth + rate * dt, 0, 100)
  if P.warmth <= 0 then
    P.health = math.max(0, P.health - 4 * dt)
  elseif P.warmth > 55 and P.lastHurt > 4 then
    P.health = math.min(100, P.health + 1.5 * dt)
  end
end

local function updateItems(dt)
  local P = G.player
  for i = #G.items, 1, -1 do
    local it = G.items[i]
    it.t = it.t + dt
    if math.abs(it.x - P.x) < 34 and math.abs(it.y - P.y) < 50 then
      G.coal = math.min(G.maxCoal, G.coal + it.amount)
      G.toast("+" .. it.amount .. " coal", { 0.8, 0.85, 1 }, 2)
      Audio.play("pickup", 0.6)
      table.remove(G.items, i)
    elseif it.x < T.minX() then
      table.remove(G.items, i)
    end
  end
end

-- engine smoke, stove-pipe smoke, chugs and rail clacks: running in every state
local function ambient(dt)
  BG.updateSnow(G, dt)
  local flow = G.speed * Events.PX_PER_KMH
  local eng = T.cars[5]
  G.smokeT = G.smokeT - dt
  if G.smokeT <= 0 and G.speed > 1 then
    G.smokeT = 0.05
    Particles.add(G, { x = eng.x + eng.w - 64, y = T.ROOF_Y - 60, vx = -flow * 0.85 + U.rand(-20, 20), vy = U.rand(-70, -40),
      life = 2.4, size = 8, grow = 16, drag = 0.2, color = { 0.18, 0.18, 0.2 }, alpha = 0.45, layer = "smoke" })
  end
  if G.stove > 0 and T.firstAttached <= 2 and love.math.random() < dt * 8 then
    Particles.add(G, { x = T.STOVE_X, y = T.ROOF_Y - 4, vx = -flow * 0.85, vy = -30,
      life = 1.4, size = 4, grow = 8, color = { 0.6, 0.6, 0.65 }, alpha = 0.3, layer = "smoke" })
  end
  if G.speed > 1 then
    G.chugT = G.chugT - dt
    if G.chugT <= 0 then
      G.chugT = 1 / math.max(0.7, G.speed / 14)
      Audio.play("chug", 0.28, 0.85 + G.speed / 500)
    end
    G.clackT = G.clackT - dt
    if G.clackT <= 0 then
      G.clackT = 1100 / math.max(80, flow)
      Audio.play("clack", 0.18, U.rand(0.95, 1.05))
    end
  end
  if Game.wind then
    local P = G.player
    local up = (G.state == "play" and P.y <= T.ROOF_Y + 2) and 0.3 or 0
    Game.wind:setVolume((0.12 + G.blizzard * 0.45 + up) * Audio.master)
  end
end

local function updateCamera(dt)
  local P = G.player
  local target = P.x - VW / 2 + P.facing * 90
  G.camX = U.lerp(G.camX, target, math.min(1, dt * 5))
  G.camX = U.clamp(G.camX, T.minX() - 150, T.LENGTH - VW + 220)
end

local function lose(reason)
  if G.state ~= "play" then return end
  G.state = "over"
  G.overReason = reason
  G.endT = 0
  Audio.play("lose", 0.6)
end

local function checkEnd()
  local P = G.player
  if G.pendingLoss then
    G.pendingLoss.t = G.pendingLoss.t - G.dt
    if G.pendingLoss.t <= 0 then lose(G.pendingLoss.reason) end
    return
  end
  if P.health <= 0 then
    lose(P.warmth <= 0 and "You froze to death on the line." or "The raiders overwhelmed you.")
  elseif G.passengers <= 0 then
    lose("No passengers left. There's no one left to save.")
  elseif G.stallT > 6 then
    lose("The train stalled in the wastes. The raiders closed in.")
  elseif G.dist >= GOAL_KM then
    G.state = "win"
    G.endT = 0
    G.overReason = G.passengers .. " passenger" .. (G.passengers == 1 and "" or "s") .. " stepped off into the warm lights of Haven."
    Audio.play("whistle", 0.8)
    Audio.play("win", 0.6)
  end
end

function Game.update(dt)
  G.dt = dt
  if G.state == "paused" then return end
  G.time = G.time + dt
  G.windowColor = BG.skyColor(G.progress)
  G.shake = math.max(0, G.shake - dt * 30)
  G.flash = math.max(0, G.flash - dt)
  for i = #G.toasts, 1, -1 do
    G.toasts[i].t = G.toasts[i].t - dt
    if G.toasts[i].t <= 0 then table.remove(G.toasts, i) end
  end

  if G.state == "title" then
    G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
    ambient(dt)
    Particles.update(G, dt)
    return
  end

  if G.state == "over" or G.state == "win" then
    G.endT = G.endT + dt
    G.speed = math.max(0, G.speed - dt * (G.state == "win" and 12 or 6))
    G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
    if G.detached then
      G.detached.vel = G.detached.vel + 70 * dt
      G.detached.offset = G.detached.offset - G.detached.vel * dt
    end
    ambient(dt)
    Particles.update(G, dt)
    return
  end

  -- play
  local hint = HINTS[G.hintIdx]
  if hint and G.time >= hint[1] then
    G.toast(hint[2], { 1, 0.9, 0.6 }, 7)
    G.hintIdx = G.hintIdx + 1
  end
  updateTrain(dt)
  G.player:update(G, dt)
  Raiders.update(G, dt)
  Events.update(G, dt)
  updateHeat(dt)
  updateItems(dt)
  Particles.update(G, dt)
  ambient(dt)
  updateCamera(dt)
  checkEnd()
end

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------
function Game.currentInteraction()
  local P = G.player
  if G.state ~= "play" or P.climbing or T.levelOf(P) ~= "floor" or not P.onGround then return nil end
  local x = P.x
  if math.abs(x - T.FURNACE_X) < 40 then
    if P.carrying then
      return { label = "Feed the furnace", fn = function()
        G.fuel = math.min(100, G.fuel + 12)
        P.carrying = false
        G.stats.shoveled = G.stats.shoveled + 1
        Audio.play("whoosh", 0.7)
        Particles.burst(G, T.FURNACE_X, T.FLOOR_Y - 46, 14, { speed = 200, color = { 1, 0.6, 0.2 }, life = 0.5, add = true, g = -100 })
      end }
    end
    return { label = "Furnace: bring coal from the tender", disabled = true }
  end
  if math.abs(x - T.LEVER_X) < 32 then
    return { label = G.brake and "Release the brake" or "Pull the brake", fn = function()
      G.brake = not G.brake
      Audio.play("brake", G.brake and 0.6 or 0.3, G.brake and 1 or 1.4)
    end }
  end
  if math.abs(x - T.COAL_X) < 125 then
    if P.carrying then return { label = "Carrying coal", disabled = true } end
    if G.coal <= 0 then return { label = "The tender is empty!", disabled = true } end
    return { label = "Shovel coal", fn = function()
      G.coal = G.coal - 1
      P.carrying = true
      Audio.play("shovel", 0.7)
      Particles.burst(G, P.x + P.facing * 14, P.y - 30, 6, { speed = 100, color = { 0.1, 0.1, 0.12 }, life = 0.4, square = true })
    end }
  end
  if T.firstAttached <= 2 and math.abs(x - T.STOVE_X) < 50 then
    if P.carrying then
      return { label = "Feed the stove", fn = function()
        G.stove = math.min(100, G.stove + 30)
        P.carrying = false
        G.stats.shoveled = G.stats.shoveled + 1
        Audio.play("whoosh", 0.6, 1.2)
        Particles.burst(G, T.STOVE_X, T.FLOOR_Y - 30, 10, { speed = 150, color = { 1, 0.6, 0.2 }, life = 0.4, add = true, g = -100 })
      end }
    end
    return { label = "Stove: bring coal from the tender", disabled = true }
  end
  if T.firstAttached == 1 and math.abs(x - T.MEDKIT_X) < 40 then
    if G.bandages <= 0 then return { label = "Medkit is empty", disabled = true } end
    if P.health >= 100 then return { label = "Medkit (" .. G.bandages .. " left)", disabled = true } end
    return { label = "Use bandage (" .. G.bandages .. " left)", fn = function()
      G.bandages = G.bandages - 1
      P.health = math.min(100, P.health + 45)
      Audio.play("pickup", 0.6, 0.8)
    end }
  end
end

local function playerAttack()
  local P = G.player
  if P.attackCD > 0 or P.climbing or P.stun > 0 then return end
  P.attackCD, P.attackT = 0.36, 0.2
  Audio.play("swing", 0.5, U.rand(0.9, 1.1))
  local hit = false
  for _, r in ipairs(G.raiders) do
    if r.state == "board" then
      local dx = (r.x - P.x) * P.facing
      if dx > -14 and dx < 76 * r.scale and math.abs(r.y - P.y) < 46 then
        Raiders.damage(G, r, 1, P.facing)
        hit = true
      end
    end
  end
  if hit then
    Audio.play("hit", 0.8, U.rand(0.9, 1.1))
    G.addShake(4)
  end
end

function Game.keypressed(k)
  local s = G.state
  if s == "title" then
    if k == "return" or k == "kpenter" or k == "space" then
      Game.newRun("play")
      Audio.play("whistle", 0.6)
    elseif k == "escape" then
      love.event.quit()
    end
  elseif s == "play" then
    if k == "escape" or k == "p" then
      G.state = "paused"
    elseif k == "space" then
      G.player:jump()
    elseif k == "j" or k == "k" or k == "f" then
      playerAttack()
    elseif k == "e" then
      local it = Game.currentInteraction()
      if it and it.fn then it.fn() end
    end
  elseif s == "paused" then
    if k == "escape" or k == "p" then G.state = "play"
    elseif k == "q" then Game.newRun("title") end
  elseif s == "over" or s == "win" then
    if G.endT > 0.8 then
      if k == "return" or k == "kpenter" or k == "r" then
        Game.newRun("play")
        Audio.play("whistle", 0.6)
      elseif k == "escape" then
        Game.newRun("title")
      end
    end
  end
end

function Game.mousepressed(b)
  if G.state == "play" and b == 1 then playerAttack() end
end

---------------------------------------------------------------------------
-- Draw
---------------------------------------------------------------------------
function Game.draw()
  local P = G.player
  local sx, sy = 0, 0
  if G.shake > 0 then
    sx, sy = U.rand(-G.shake, G.shake), U.rand(-G.shake, G.shake) * 0.6
  end
  -- gentle rocking of the whole train with speed
  local rock = math.sin(G.time * 9) * math.min(1.5, G.speed / 60)

  BG.drawBack(G)

  lg.push()
  lg.translate(math.floor(-G.camX + sx), math.floor(sy))
  BG.drawTrack(G)
  Render.depotBack(G)
  Render.overheadBack(G)
  lg.push()
  lg.translate(0, rock)
  Render.train(G)
  Render.items(G)
  for _, r in ipairs(G.raiders) do
    if r.state == "detached" then
      local ox = G.detached and G.detached.offset or 0
      Render.raider(G, r, ox)
    elseif r.state ~= "jump" then
      Render.raider(G, r, 0)
    end
  end
  if G.state ~= "title" then
    local ox = (G.pendingLoss and P.x < T.minX()) and (G.detached and G.detached.offset or 0) or 0
    local look = Render.PLAYER_LOOK
    Render.person(P.x + ox, P.y, {
      coat = look.coat, pants = look.pants, hat = look.hat, scarf = look.scarf, skin = look.skin, style = look.style,
      facing = P.facing, anim = P.anim, moving = math.abs(P.vx) > 10 and P.onGround, duck = P.ducking or P.stun > 0,
      attackT = P.attackT, carry = P.carrying, flash = P.hurtT > 0, time = G.time,
    })
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "jump" then Render.raider(G, r, 0) end
  end
  Particles.draw(G, "front", false)
  lg.pop()
  Particles.draw(G, "smoke", false)
  Render.overheadFront(G)
  for _, s in ipairs(G.sleds) do Render.sled(G, s) end
  Particles.draw(G, "sled", false)
  lg.pop()

  BG.drawFront(G)

  -- night overlay, then lights punch through
  local night = BG.night(G.progress)
  lg.setColor(0.02, 0.03, 0.10, night * 0.75)
  lg.rectangle("fill", 0, 0, VW, VH)
  lg.push()
  lg.translate(math.floor(-G.camX + sx), math.floor(sy + rock))
  Render.lights(G)
  Particles.draw(G, "front", true)
  if G.state == "play" then HUD.prompt(G, Game.currentInteraction()) end
  lg.pop()

  BG.drawSnow(G)

  if G.flash > 0 then
    lg.setColor(1, 0.1, 0.05, G.flash * 0.6)
    lg.rectangle("fill", 0, 0, VW, VH)
  end
  -- freezing frost vignette
  if G.state == "play" and P.warmth < 35 then
    local a = (35 - P.warmth) / 35
    lg.setColor(0.8, 0.9, 1, a * 0.35)
    lg.rectangle("fill", 0, 0, VW, 40); lg.rectangle("fill", 0, VH - 40, VW, 40)
    lg.rectangle("fill", 0, 0, 40, VH); lg.rectangle("fill", VW - 40, 0, 40, VH)
  end

  if G.state == "title" then
    HUD.title(G)
  elseif G.state == "over" or G.state == "win" then
    HUD.ending(G, G.state == "win")
  else
    HUD.play(G)
    if G.state == "paused" then HUD.paused() end
  end
end

return Game
