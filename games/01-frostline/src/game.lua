-- game.lua : the run state (G), the simulation loop, actions, menus and the draw order.
--
-- States: "title" -> "play" -> "over" | "win"
-- A menu (pause, settings, depot trader) can sit on top of any state; while one is open the world is frozen.
local U = require("util")
local T = require("train")
local Audio = require("audio")
local Music = require("music")
local Input = require("input")
local Settings = require("settings")
local Menu = require("menu")
local BG = require("background")
local Player = require("player")
local Raiders = require("raiders")
local Events = require("events")
local Hazards = require("hazards")
local Boss = require("boss")
local Passengers = require("passengers")
local Upgrades = require("upgrades")
local Render = require("render")
local HUD = require("hud")
local Particles = require("particles")
local Story = require("story")
local FX = require("fx")
local lg = love.graphics

local Game = {}
local G
local VW, VH = 1280, 720
local GOAL_KM = 100

-- {seconds, function returning the hint text} (functions so the key labels match the device)
local HINTS = {
  { 1.5, function() return "Grab coal in the TENDER [" .. Input.label("interact") .. "], then feed the FURNACE in the engine cab." end },
  { 10, function() return "The passengers' STOVE needs coal too. It's two cars back. Meet the passengers while you're there!" end },
  { 20, function() return "Raiders chase on sleds. Swing your wrench with [" .. Input.label("attack") .. "]. They drop scrap." end },
  { 30, function() return "Ladders sit between cars: [" .. Input.label("up") .. "] up, [" .. Input.label("down") .. "] down. Watch for low bridges up top!" end },
  { 42, function() return "Brake at coal depots to reload coal and spend scrap at the trader in the cargo car." end },
}

local menuStack = {}
local fade = { a = 0, phase = nil, fn = nil } -- screen transitions

-- fade to black, run fn, fade back in
function Game.transition(fn)
  if fade.phase then return end
  fade.phase, fade.fn = "out", fn
end

function Game.state() return G end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local function applySettings()
  Audio.master = Settings.sfxVolume()
  Music.volume = Settings.musicVolume()
  if love.window.getFullscreen() ~= Settings.data.fullscreen then
    love.window.setFullscreen(Settings.data.fullscreen, "desktop")
  end
end
Game.applySettings = applySettings

function Game.load()
  Settings.load()
  HUD.load()
  Render.fonts = HUD.fonts
  Audio.load()
  Music.load()
  BG.load()
  Render.load()
  applySettings()
  Game.wind = Audio.loop("wind", 0.2)
  Game.newRun("title")
end

function Game.newRun(state)
  T.reset()
  menuStack = {}
  G = {
    state = state or "play", time = 0, dist = 0, progress = 0, speed = 58, fuel = 75, coal = 30, maxCoal = 50, crates = T.CRATES, coalHint = false,
    stove = 70, carTemp = 14, ambient = -22, freeze = 0, bandages = 3, brake = false,
    scrap = 2, upgrades = {}, soupT = 25, pipT = 0,
    scroll = 0, camX = 0, shake = 0, flash = 0, toasts = {}, particles = {}, items = {},
    stats = { kills = 0, taken = 0, shoveled = 0, outrun = 0, knocked = 0, fires = 0, cured = 0, chains = 0, upgrades = 0, boss = false, favours = 0 },
    stallT = 0, detached = nil, loadAcc = 0, chugT = 0, clackT = 0, smokeT = 0, hintIdx = 1, endT = 0,
    windowColor = { 0.1, 0.1, 0.2 }, menu = nil,
  }
  G.passengerList = Passengers.new()
  G.passengers = Passengers.count(G)
  G.player = Player.new()
  G.label = Input.label
  G.toast = function(msg, color, dur)
    G.toasts[#G.toasts + 1] = { msg = msg, color = color or { 1, 1, 1 }, t = dur or 4.5, max = dur or 4.5 }
  end
  G.addShake = function(a) if Settings.data.shake then G.shake = math.max(G.shake, a) end end
  G.uncouple = Game.uncouple
  G.spawnWolves = function(n) Raiders.spawnWolves(G, n) end
  G.deployFromBoss = function(x) Raiders.deployFromBoss(G, x) end
  G.onRaiderLanded = Game.onRaiderLanded
  G.onPassengerLost = function(p) Story.onPassengerLost(G, p) end
  G.onRaiderKilled = function() FX.hitstop(G, 0.08); FX.punch(G, 0.02) end
  G.onBossHit = function() FX.hitstop(G, 0.14); FX.punch(G, 0.05) end
  G.onBossDown = function() FX.whiteout(G, 0.9); FX.punch(G, 0.1); Story.react(G, "victory", true) end
  G.onBigImpact = function(a) FX.punch(G, a) end
  FX.init(G)
  Story.initRadio(G)
  Story.initBarks(G)
  Story.initRequests(G)
  if G.state == "play" and not Game.skipIntro then G.intro = Story.newIntro() end
  Raiders.init(G)
  Events.init(G)
  Hazards.init(G)
  Boss.init(G)
  if G.state == "title" then
    G.camX = T.LENGTH - VW + 100
    G.progress = 0.45
    Game.openMenu(Game.titleMenu())
  else
    G.camX = U.clamp(G.player.x - VW / 2, -150, T.LENGTH - VW + 220)
  end
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
function Game.openMenu(m)
  menuStack[#menuStack + 1] = m
  G.menu = m
end

function Game.closeMenu()
  menuStack[#menuStack] = nil
  G.menu = menuStack[#menuStack]
end

local function onOff(v) return v and "On" or "Off" end

function Game.settingsMenu()
  local d = Settings.data
  local function vol(key, name)
    return {
      label = function() return name .. ":  " .. d[key] end,
      adjust = function(dir) d[key] = U.clamp(d[key] + dir, 0, 10); Settings.save(); applySettings() end,
      action = function() d[key] = (d[key] + 1) % 11; Settings.save(); applySettings() end,
    }
  end
  local m = Menu.new("Settings", {
    vol("master", "Master volume"),
    vol("music", "Music"),
    vol("sfx", "Sound effects"),
    { label = function() return "Screen shake:  " .. onOff(d.shake) end,
      adjust = function() d.shake = not d.shake; Settings.save() end,
      action = function() d.shake = not d.shake; Settings.save() end },
    { label = function() return "Fullscreen:  " .. onOff(d.fullscreen) end,
      adjust = function() d.fullscreen = not d.fullscreen; Settings.save(); applySettings() end,
      action = function() d.fullscreen = not d.fullscreen; Settings.save(); applySettings() end },
    { label = "Back", action = Game.closeMenu },
  })
  m.kind = "settings"
  return m
end

function Game.titleMenu()
  local m = Menu.new("", {
    { label = "Depart for Haven", action = function() Game.transition(function() Game.newRun("play"); Audio.play("whistle", 0.6) end) end },
    { label = "Settings", action = function() Game.openMenu(Game.settingsMenu()) end },
    { label = "Quit", action = function() love.event.quit() end },
  }, { rowH = 40, noTitle = true })
  m.kind = "title"
  return m
end

function Game.pauseMenu()
  local m = Menu.new("Paused", {
    { label = "Resume", action = Game.closeMenu },
    { label = "Settings", action = function() Game.openMenu(Game.settingsMenu()) end },
    { label = "Quit to title", action = function() Game.transition(function() Game.newRun("title") end) end },
  })
  m.kind = "pause"
  return m
end

---------------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------------
local CAR_NAMES = Hazards.CAR_NAMES

function Game.onRaiderLanded(r)
  if not Passengers.has(G, "pip") or G.pipT > 0 or G.state ~= "play" then return end
  G.pipT = 5
  local car = T.carAt(r.x)
  local where
  if car then where = (r.y <= T.ROOF_Y + 2 and "on the " .. CAR_NAMES[car.index] .. " roof" or "in the " .. CAR_NAMES[car.index])
  else local g = T.gapAt(r.x); where = g and ("between the " .. CAR_NAMES[g] .. " and the " .. CAR_NAMES[g + 1]) or "somewhere" end
  local what = r.kind == "wolf" and "A WOLF" or (r.kind == "brute" and "A BIG ONE" or "A raider")
  G.toast("Pip: \"" .. what .. " landed " .. where .. "!\"", { 1, 0.85, 0.4 }, 3)
end

function Game.uncouple(g)
  if G.state ~= "play" or g < T.firstAttached then return end
  local cut = T.cars[g + 1].x
  T.firstAttached = g + 1
  if T.blockedGap and T.blockedGap <= g then T.blockedGap = nil; G.snow = nil end
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
  if P.x < cut and P.x > T.cars[g].x + T.CAR_W then
    -- standing on the coupling itself: leap onto the train side
    P.climbing = false
    P.x, P.y, P.vy = cut + 14, T.FLOOR_Y, -300
    G.toast("You leapt across as the coupling broke!", { 1, 0.85, 0.4 }, 3)
  end
  if P.x < cut then
    G.pendingLoss = { t = 1.6, reason = "You were left behind on the uncoupled cars." }
  elseif g >= 2 then
    for _, p in ipairs(G.passengerList) do if p.alive then p.alive = false; p.fate = "uncoupled" end end
    G.passengers = 0
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
    target = math.max(G.brake and 22 or 8, target - Boss.drag(G))
  end
  local rate = (target < G.speed) and (G.brake and 0.9 or 0.35) or 0.22
  G.speed = math.max(0, G.speed + (target - G.speed) * math.min(1, rate * dt))
  local burn = (0.8 + G.speed / 100 * 1.3) * (Passengers.has(G, "ivo") and 0.85 or 1) * (G.perkTuned and 0.85 or 1)
  G.fuel = math.max(0, G.fuel - burn * dt)
  G.dist = G.dist + G.speed * dt / 400
  G.progress = U.clamp(G.dist / GOAL_KM, 0, 1)
  G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
  G.stallT = (G.speed < 3) and (G.stallT + dt) or 0
  if G.brake and G.speed > 25 and love.math.random() < dt * 30 then
    local c = T.cars[love.math.random(T.firstAttached, #T.cars)]
    Particles.burst(G, c.x + 48 + love.math.random() * (c.w - 96), T.RAIL_Y - 2, 2,
      { speed = 160, vx = -200, vy = -80, color = { 1, 0.7, 0.3 }, life = 0.3, add = true, g = 500 })
  end
end

local function updateDetached(dt)
  if G.detached then
    G.detached.vel = G.detached.vel + 70 * dt
    G.detached.offset = G.detached.offset - G.detached.vel * dt
  end
end

local function updateHeat(dt)
  local P = G.player
  G.ambient = -22 - G.blizzard * 14
  local stoveBurn = (0.75 + G.blizzard * 0.5)
  if Passengers.has(G, "bruno") then stoveBurn = stoveBurn * 0.75 end
  if Upgrades.has(G, "insulation") then stoveBurn = stoveBurn * 0.7 end
  G.stove = math.max(0, G.stove - stoveBurn * dt)
  if G.stove > 0 then
    G.carTemp = U.approach(G.carTemp, 20, 1.6 * dt)
  else
    G.carTemp = U.approach(G.carTemp, G.ambient, (0.45 + G.blizzard * 0.3) * dt)
  end
  if G.carTemp < 0 then
    G.freeze = G.freeze + (-G.carTemp) / 20 * dt
    if G.freeze >= 20 then
      G.freeze = 0
      Passengers.loseRandom(G, "froze")
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
  if rate < 0 then
    rate = rate * (1 + G.blizzard * 0.9)
    if Upgrades.has(G, "coat") then rate = rate * 0.6 end
    if G.perkScarf then rate = rate * 0.75 end
  end
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
    if it.t > 0.3 and math.abs(it.x - P.x) < 34 and math.abs(it.y - P.y) < 50 then
      if it.kind == "toy" then
        G.hasToy = true
        FX.float(G, it.x, it.y - 60, "Pip's toy train!", { 1, 0.85, 0.4 })
        G.toast("You found Pip's toy train! Bring it to Pip.", { 1, 0.85, 0.4 }, 4)
      elseif it.kind == "scrap" then
        G.scrap = G.scrap + it.amount
        FX.float(G, it.x, it.y - 50, "+" .. it.amount .. " scrap", { 0.8, 0.85, 0.95 })
      else
        G.coal = math.min(G.maxCoal, G.coal + it.amount)
        FX.float(G, it.x, it.y - 50, "+" .. it.amount .. " coal", { 0.75, 0.75, 0.85 })
      end
      Audio.play("pickup", 0.6, it.kind == "scrap" and 1.3 or 1)
      table.remove(G.items, i)
    elseif it.x < T.minX() then
      table.remove(G.items, i)
    end
  end
end

-- engine smoke, stove-pipe smoke, chugs and rail clacks, music mood: running in every state
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

  -- music follows the danger level
  local mood = { calm = 1, danger = 0, boss = 0 }
  if G.state == "play" then
    local aboard = 0
    for _, r in ipairs(G.raiders) do if r.state == "board" then aboard = aboard + 1 end end
    local d = aboard * 0.35 + (G.fire and 0.4 or 0) + (G.fuel < 15 and 0.3 or 0) + (G.carTemp < 0 and 0.2 or 0)
      + (G.avalanche and 0.6 or 0)
    mood.danger = U.clamp(d, 0, 1)
    if G.boss and G.boss.state ~= "dying" then mood.boss = 1; mood.danger = math.max(mood.danger, 0.6) end
  elseif G.state == "over" then
    mood.calm = 0.5
  end
  Music.setMood(mood)
  Music.update(dt)
end

local function updateCamera(dt)
  local P = G.player
  local target = P.x - VW / 2 + P.facing * 90
  if G.state == "win" then target = T.LENGTH / 2 - VW / 2 + 300 end
  G.camX = U.lerp(G.camX, target, math.min(1, dt * (G.state == "win" and 1.2 or 5)))
  G.camX = U.clamp(G.camX, T.minX() - 150, T.LENGTH - VW + 220)
end

---------------------------------------------------------------------------
-- Endings
---------------------------------------------------------------------------
local function computeScore(won)
  local s = G.stats
  local parts = {
    { "Distance", math.floor(G.dist * 10) },
    { "Raiders thrown off", s.kills * 50 },
    { "Passengers saved", won and Passengers.count(G) * 500 or 0 },
    { "Iron Jaw destroyed", s.boss and 2000 or 0 },
  }
  local total = 0
  for _, p in ipairs(parts) do total = total + p[2] end
  G.scoreParts, G.score = parts, total
  G.newBest = Settings.recordRun(total, G.dist, Passengers.count(G), won, s.boss)
end

local function lose(reason)
  if G.state ~= "play" then return end
  G.state = "over"
  G.overReason = reason
  G.endT = 0
  G.brake = false
  Audio.play("lose", 0.6)
  computeScore(false)
end

local function win()
  G.state = "win"
  G.endT = 0
  G.haven = { x = T.LENGTH + 300 }
  local n = Passengers.count(G)
  G.overReason = n .. " passenger" .. (n == 1 and "" or "s") .. " stepped off into the warm lights of Haven."
  for _, r in ipairs(G.raiders) do
    if r.state == "board" or r.state == "jump" then r.state = "leave"; r.vx, r.vy = -260, -420 end
  end
  G.sleds = {}
  G.hooks = {}
  if G.boss and G.boss.state ~= "dying" then
    G.toast("Haven's guns open fire! The Iron Jaw flees into the snow.", { 1, 0.85, 0.4 }, 5)
    G.boss = nil
  end
  G.fire, G.avalanche = nil, nil
  Audio.play("whistle", 0.8)
  Audio.play("win", 0.6)
  Story.react(G, "haven", true)
  computeScore(true)
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
  elseif Passengers.count(G) <= 0 then
    lose("No passengers left. There's no one left to save.")
  elseif G.stallT > 10 then
    lose(#G.hooks > 0 and "The Iron Jaw's chains dragged the train to a stop." or "The train stalled in the wastes. The raiders closed in.")
  elseif G.dist >= GOAL_KM then
    win()
  end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function Game.update(dt)
  G.dt = dt
  if fade.phase == "out" then
    fade.a = math.min(1, fade.a + dt / 0.35)
    if fade.a >= 1 then
      local fn = fade.fn
      fade.phase, fade.fn = "in", nil
      if fn then fn() end
    end
  elseif fade.phase == "in" then
    fade.a = math.max(0, fade.a - dt / 0.45)
    if fade.a <= 0 then fade.phase = nil end
  end
  FX.update(G, dt)
  for i = #G.toasts, 1, -1 do
    G.toasts[i].t = G.toasts[i].t - dt
    if G.toasts[i].t <= 0 then table.remove(G.toasts, i) end
  end
  if G.menu and G.state ~= "title" then
    Music.update(dt)
    return -- world frozen while a menu is open
  end
  if G.hitstop > 0 and G.state == "play" then
    G.hitstop = G.hitstop - dt
    return -- impact freeze-frame
  end
  if G.intro and not G.intro.done and G.state == "play" then
    Story.updateIntro(G, dt)
    G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
    G.windowColor = BG.skyColor(G.progress)
    ambient(dt)
    Particles.update(G, dt)
    return
  end
  G.time = G.time + dt
  G.windowColor = BG.skyColor(G.progress)
  G.shake = math.max(0, G.shake - dt * 30)
  G.flash = math.max(0, G.flash - dt)

  if G.state == "title" then
    G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
    -- slow cinematic pan along the train
    local lo, hi = -150, T.LENGTH - VW + 220
    G.camX = (lo + hi) / 2 + math.sin(G.time * 0.07) * (hi - lo) / 2
    ambient(dt)
    Particles.update(G, dt)
    return
  end

  if G.state == "over" or G.state == "win" then
    G.endT = G.endT + dt
    if G.state == "win" then
      -- glide into the station
      G.speed = math.max(0, G.speed - dt * math.max(4, G.speed * 0.45))
      if G.haven then G.haven.x = G.haven.x - G.speed * Events.PX_PER_KMH * dt end
    else
      G.speed = math.max(0, G.speed - dt * 6)
    end
    G.scroll = G.scroll + G.speed * Events.PX_PER_KMH * dt
    updateDetached(dt)
    Raiders.update(G, dt)
    Boss.update(G, dt)
    ambient(dt)
    Particles.update(G, dt)
    updateCamera(dt)
    return
  end

  -- play
  local hint = HINTS[G.hintIdx]
  if hint and G.time >= hint[1] then
    G.toast(hint[2](), { 1, 0.9, 0.6 }, 7)
    G.hintIdx = G.hintIdx + 1
  end
  G.soupT = math.max(0, G.soupT - dt)
  G.pipT = math.max(0, G.pipT - dt)
  Story.updateRadio(G, dt)
  Story.updateBarks(G, dt)
  Story.updateRequests(G, dt)
  if not G.coalHint and G.coal <= 4 and G.crates > 0 then
    G.coalHint = true
    G.radio = { text = "Marisol here. Running low on coal? Burn the cargo! Those crates in your cargo car make decent firewood.", t = 0 }
    Audio.play("radio", 0.55)
  end
  updateTrain(dt)
  updateDetached(dt)
  G.player:update(G, dt)
  Raiders.update(G, dt)
  Events.update(G, dt)
  Hazards.update(G, dt)
  Boss.update(G, dt)
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
local function handsFull(P, what)
  return { label = "Hands full (" .. P.carrying .. ")", disabled = true, what = what }
end

function Game.currentInteraction()
  local P = G.player
  if G.state ~= "play" or G.menu or P.climbing or T.levelOf(P) ~= "floor" or not P.onGround then return nil end
  local x = P.x
  local car = T.carAt(x)

  -- emergencies first
  if G.fire and car and car.index == G.fire.car and math.abs(x - G.fire.x) < 75 then
    return { label = "Stomp out the fire!", fn = function() Hazards.stomp(G) end }
  end
  if Hazards.canDig(G, x) then
    return { label = "Dig through the snow", fn = function() Hazards.dig(G) end }
  end

  if math.abs(x - T.FURNACE_X) < 40 then
    if P.carrying == "coal" or P.carrying == "wood" then
      return { label = "Feed the furnace", fn = function()
        local add = (Upgrades.has(G, "bellows") and 17 or 12) - (P.carrying == "wood" and 2 or 0)
        G.fuel = math.min(100, G.fuel + add)
        FX.float(G, T.FURNACE_X, T.FLOOR_Y - 100, "+" .. add .. " fuel", { 1, 0.65, 0.25 })
        P.carrying = nil
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
  if G.boss and G.boss.state ~= "dying" and math.abs(x - T.DYNAMITE_X) < 45 then
    if P.carrying then return handsFull(P) end
    return { label = "Grab dynamite", fn = function() P.carrying = "dynamite"; Audio.play("pickup", 0.5, 0.7) end }
  end
  if G.depotLoading and math.abs(x - T.TRADER_X) < 60 then
    return { label = "Trade scrap at the depot (" .. G.scrap .. ")", fn = function()
      local m = Upgrades.menu(G, Game.closeMenu)
      m.kind = "trader"
      Game.openMenu(m)
    end }
  end
  if math.abs(x - T.CRATES_X) < 70 and car and car.kind == "cargo" then
    if G.crates <= 0 then return { label = "Nothing left to burn here", disabled = true } end
    if P.carrying then return handsFull(P) end
    return { label = "Smash a crate for firewood (" .. G.crates .. " left)", fn = function()
      G.crates = G.crates - 1
      P.carrying = "wood"
      G.stats.crates = (G.stats.crates or 0) + 1
      Audio.play("hit", 0.7, 1.3)
      FX.hitstop(G, 0.05)
      Particles.burst(G, T.CRATES_X, T.FLOOR_Y - 30, 14, { speed = 220, vy = -120, color = { 0.55, 0.4, 0.25 }, life = 0.6, square = true, size = 4 })
    end }
  end
  if math.abs(x - T.COAL_X) < 125 then
    if P.carrying then return handsFull(P) end
    if G.coal <= 0 then return { label = "The tender is empty!", disabled = true } end
    return { label = "Shovel coal", fn = function()
      G.coal = G.coal - 1
      P.carrying = "coal"
      Audio.play("shovel", 0.7)
      Particles.burst(G, P.x + P.facing * 14, P.y - 30, 6, { speed = 100, color = { 0.1, 0.1, 0.12 }, life = 0.4, square = true })
    end }
  end
  if T.firstAttached <= 2 and car and car.kind == "passenger" then
    local favour = Story.interaction(G, P)
    if favour and not (favour.disabled and P.carrying == "coal" and math.abs(x - T.STOVE_X) < 50) then return favour end
    local sick = Hazards.firstSick(G)
    if P.carrying == "medicine" and sick then
      return { label = "Give medicine to " .. sick.name, fn = function()
        sick.sick = false
        P.carrying = nil
        G.stats.cured = G.stats.cured + 1
        G.toast(sick.name .. " is going to be fine. Phew.", { 0.6, 1, 0.6 }, 4)
        Audio.play("pickup", 0.6, 1.1)
      end }
    end
    if math.abs(x - T.STOVE_X) < 50 then
      if P.carrying == "coal" or P.carrying == "wood" then
        return { label = "Feed the stove", fn = function()
          local heat = P.carrying == "wood" and 25 or 30
          G.stove = math.min(100, G.stove + heat)
          FX.float(G, T.STOVE_X, T.FLOOR_Y - 90, "+" .. heat .. " heat", { 1, 0.82, 0.35 })
          if love.math.random() < 0.35 then Story.react(G, "stoked") end
          P.carrying = nil
          G.stats.shoveled = G.stats.shoveled + 1
          Audio.play("whoosh", 0.6, 1.2)
          Particles.burst(G, T.STOVE_X, T.FLOOR_Y - 30, 10, { speed = 150, color = { 1, 0.6, 0.2 }, life = 0.4, add = true, g = -100 })
        end }
      end
      if Passengers.has(G, "olga") and not P.carrying then
        if G.soupT <= 0 then
          return { label = "Take Gran Olga's soup", fn = function()
            P.warmth = 100
            P.health = math.min(100, P.health + 25)
            G.soupT = G.perkSoup and 30 or 60
            G.toast("Gran Olga: \"Eat! You're all bones.\" (+warmth, +health)", { 1, 0.85, 0.6 }, 4)
            Audio.play("pickup", 0.6, 0.9)
          end }
        end
        return { label = string.format("Soup's cooking (%ds)", math.ceil(G.soupT)), disabled = true }
      end
      if not P.carrying then return { label = "Stove: bring coal from the tender", disabled = true } end
    end
  end
  if T.firstAttached == 1 and math.abs(x - T.MEDKIT_X) < 40 then
    local sick = Hazards.firstSick(G)
    if sick and not P.carrying then
      return { label = "Take medicine for " .. sick.name, fn = function() P.carrying = "medicine"; Audio.play("pickup", 0.5) end }
    end
    if G.bandages <= 0 then return { label = "Medkit is empty", disabled = true } end
    if P.health >= 100 then return { label = "Medkit (" .. G.bandages .. " bandages)", disabled = true } end
    return { label = "Use bandage (" .. G.bandages .. " left)", fn = function()
      G.bandages = G.bandages - 1
      P.health = math.min(100, P.health + (Passengers.has(G, "amara") and 65 or 45))
      Audio.play("pickup", 0.6, 0.8)
    end }
  end
end

local function playerAttack()
  local P = G.player
  if P.attackCD > 0 or P.climbing or P.stun > 0 then return end
  if P.carrying == "dynamite" then
    P.attackCD = 0.4
    Boss.throwDynamite(G, P)
    return
  end
  P.attackCD, P.attackT = 0.36, 0.2
  Audio.play("swing", 0.5, U.rand(0.9, 1.1))
  local dmg = Upgrades.has(G, "wrench") and 2 or 1
  local hit = false
  for _, r in ipairs(G.raiders) do
    if r.state == "board" then
      local dx = (r.x - P.x) * P.facing
      if dx > -14 and dx < 76 * r.scale and math.abs(r.y - P.y) < 46 then
        Raiders.damage(G, r, dmg, P.facing)
        hit = true
      end
    end
  end
  if Boss.hitHooks(G, P, dmg) then hit = true end
  if hit then
    Audio.play("hit", 0.8, U.rand(0.9, 1.1))
    G.addShake(4)
    FX.hitstop(G, 0.05)
  end
end

-- every key / button press ends up here as an action name
function Game.action(a)
  if G.menu then
    if a == "back" or (a == "pause" and G.state ~= "title") then
      if G.state == "title" and #menuStack <= 1 then return end
      Game.closeMenu()
      Audio.play("clack", 0.4, 1.0)
      return
    end
    G.menu:handle(a)
    return
  end
  local s = G.state
  if s == "play" and G.intro and not G.intro.done then
    Story.skipIntro(G)
    return
  end
  if s == "play" then
    if a == "pause" or a == "roster" then Game.openMenu(Game.pauseMenu())
    elseif a == "jump" then G.player:jump()
    elseif a == "attack" then playerAttack()
    elseif a == "interact" then
      local it = Game.currentInteraction()
      if it and it.fn then it.fn() end
    end
  elseif s == "over" or s == "win" then
    local ready = s == "over" and G.endT > 1 or (G.endT > 5)
    if ready then
      if a == "confirm" then Game.transition(function() Game.newRun("play"); Audio.play("whistle", 0.6) end)
      elseif a == "back" then Game.transition(function() Game.newRun("title") end) end
    end
  end
end

-- one key can mean several actions (Space = jump & confirm, Esc = pause & back): context decides
local function dispatch(actions)
  if fade.phase then return end
  if G.state == "play" and G.intro and not G.intro.done and not G.menu then
    if #actions > 0 then Story.skipIntro(G) end
    return
  end
  local inMenu = G.menu or G.state ~= "play"
  if inMenu then
    if Input.has(actions, "back") then Game.action("back"); return end
    for _, a in ipairs(actions) do
      if a == "confirm" or a == "pause" or a:sub(1, 5) == "menu_" then Game.action(a); return end
    end
  else
    for _, a in ipairs(actions) do
      if not (a == "confirm" or a == "back" or a:sub(1, 5) == "menu_") then Game.action(a) end
    end
  end
end

function Game.keypressed(k) dispatch(Input.fromKey(k)) end
function Game.gamepadpressed(button) dispatch(Input.fromButton(button)) end

function Game.gamepadaxis(axis, value)
  if not (G.menu or G.state ~= "play") then return end
  for _, a in ipairs(Input.fromAxis(axis, value)) do Game.action(a) end
end

function Game.mousepressed(b)
  if G.state == "play" and not G.menu and b == 1 then playerAttack() end
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
  local rock = math.sin(G.time * 9) * math.min(1.5, G.speed / 60)

  -- camera punch: zoom in a touch around the screen centre
  lg.push()
  if G.punch > 0 then
    local z = 1 + G.punch
    lg.translate(VW / 2, VH / 2)
    lg.scale(z, z)
    lg.translate(-VW / 2, -VH / 2)
  end

  BG.drawBack(G)

  lg.push()
  lg.translate(math.floor(-G.camX + sx), math.floor(sy))
  Render.havenBack(G)
  BG.drawTrack(G)
  Render.trackDamage(G)
  Render.depotBack(G)
  Render.overheadBack(G)
  lg.push()
  lg.translate(0, rock)
  Render.train(G)
  Render.hazards(G)
  Render.items(G)
  for _, r in ipairs(G.raiders) do
    if r.state == "detached" then
      Render.raider(G, r, G.detached and G.detached.offset or 0)
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
      squash = P.squash, lean = P.onGround and not P.ducking and (P.vx / 260) * 0.09 or 0,
    })
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "jump" then Render.raider(G, r, 0) end
  end
  Particles.draw(G, "front", false)
  lg.pop()
  Particles.draw(G, "smoke", false)
  Render.overheadFront(G)
  Render.chains(G)
  Render.boss(G)
  for _, s in ipairs(G.sleds) do Render.sled(G, s) end
  Render.projectiles(G)
  Particles.draw(G, "sled", false)
  Render.havenFront(G)
  lg.pop()

  BG.drawFront(G)

  -- night overlay, then lights punch through
  local night = BG.night(G.progress)
  if G.state == "win" then night = night * math.max(0, 1 - G.endT / 6) end
  lg.setColor(0.02, 0.03, 0.10, night * 0.75)
  lg.rectangle("fill", 0, 0, VW, VH)
  lg.push()
  lg.translate(math.floor(-G.camX + sx), math.floor(sy + rock))
  Render.lights(G)
  Particles.draw(G, "front", true)
  Particles.draw(G, "sled", true)
  Story.drawWorld(G, HUD.fonts)
  FX.drawFloats(G, HUD.fonts.float)
  if G.state == "play" and not G.menu and not (G.intro and not G.intro.done) then
    HUD.nameTags(G)
    HUD.prompt(G, Game.currentInteraction())
  end
  lg.pop()

  BG.drawSnow(G)
  HUD.avalanche(G)

  if G.flash > 0 then
    lg.setColor(1, 0.1, 0.05, G.flash * 0.6)
    lg.rectangle("fill", 0, 0, VW, VH)
  end
  if G.state == "play" and P.warmth < 35 then
    local a = (35 - P.warmth) / 35
    lg.setColor(0.8, 0.9, 1, a * 0.35)
    lg.rectangle("fill", 0, 0, VW, 40); lg.rectangle("fill", 0, VH - 40, VW, 40)
    lg.rectangle("fill", 0, 0, 40, VH); lg.rectangle("fill", VW - 40, 0, 40, VH)
  end

  lg.pop() -- camera punch

  if G.whiteout > 0 then
    lg.setColor(1, 1, 1, G.whiteout * 0.8)
    lg.rectangle("fill", 0, 0, VW, VH)
  end

  if G.state == "title" then
    HUD.title(G)
  elseif G.state == "over" or G.state == "win" then
    HUD.ending(G, G.state == "win")
  elseif G.intro and not G.intro.done then
    Story.drawIntro(G, HUD.fonts, VW, VH)
  else
    HUD.play(G)
  end
  if G.menu then HUD.menu(G, G.menu, #menuStack) end

  if fade.a > 0 then
    lg.setColor(0, 0, 0, fade.a)
    lg.rectangle("fill", 0, 0, VW, VH)
  end
end

return Game
