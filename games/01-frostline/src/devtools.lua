-- devtools.lua : headless smoke test. Run:  love src --autotest [--shots]
-- A simple bot plays full runs at 10x speed (shoveling, fighting, fires, fevers, snow, trader, boss),
-- logs progress, takes screenshots, then quits.
local T = require("train")
local Upgrades = require("upgrades")
local Hazards = require("hazards")

local Dev = {}
local Game
local held = {}
local simTime, shotT, logT = 0, 0, 0
local shots = false
local runs, maxRuns = 0, 2
local SUB = 10
local SHOT_EVERY = 40
local results = {}
local startKm, god = nil, false

function Dev.start(g)
  io.stdout:setvbuf("no")
  Game = g
  Game.skipIntro = true
  love.keyboard.isDown = function(...)
    for i = 1, select("#", ...) do if held[(select(i, ...))] then return true end end
    return false
  end
  for _, a in ipairs(arg or {}) do
    if a == "--shots" then shots = true end
    local n = a:match("^%-%-runs=(%d+)$")
    if n then maxRuns = tonumber(n) end
    local k = a:match("^%-%-start=(%d+)$")
    if k then startKm = tonumber(k) end
    if a == "--god" then god = true end
    local e = a:match("^%-%-shotevery=(%d+)$")
    if e then SHOT_EVERY = tonumber(e) end
  end
  print("[autotest] started")
end

local function press(k) Game.keypressed(k) end
local function interact()
  local it = Game.currentInteraction()
  if it and it.fn then it.fn(); return true end
  return false
end

local function goTo(P, x, tolerance)
  local dx = x - P.x
  if math.abs(dx) > (tolerance or 18) then held[dx > 0 and "d" or "a"] = true; return false end
  return true
end

local function wrapToast(G)
  if G.__wrapped then return end
  G.__wrapped = true
  local orig = G.toast
  G.toast = function(msg, ...)
    print(string.format("[toast %5.1fkm] %s", G.dist, msg))
    return orig(msg, ...)
  end
end

local function cheats(G)
  wrapToast(G)
  if startKm and G.time < 0.05 and G.dist < startKm then
    G.dist = startKm
    G.depotIdx = 1
    while require("events").DEPOT_KMS[G.depotIdx] and require("events").DEPOT_KMS[G.depotIdx] < startKm do G.depotIdx = G.depotIdx + 1 end
    G.depotAnnounced = G.depotIdx - 1
    G.nextHazardKm = startKm + 1
    G.nextOverheadKm = startKm + 2
    G.nextBlizzardKm = startKm + 3
  end
  if god then
    G.player.health = math.max(G.player.health, 60)
    for _, r in ipairs(G.raiders) do if r.kind == "saboteur" then r.work = 0 end end
  end
end

local function bot(G)
  held = {}
  local P = G.player
  if G.menu then
    -- trader: buy the cheapest thing we can afford, then leave
    local u = Upgrades.cheapestAffordable(G)
    if u then Upgrades.buy(G, u) end
    Game.closeMenu()
    return
  end
  if P.y <= T.ROOF_Y + 2 or P.climbing then held.s = true; return end

  -- fight anyone close on our level
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and math.abs(r.y - P.y) < 44 and math.abs(r.x - P.x) < 260 then
      local dx = r.x - P.x
      if math.abs(dx) < 55 then P.facing = dx > 0 and 1 or -1; press("j")
      else held[dx > 0 and "d" or "a"] = true end
      return
    end
  end
  -- hunt raiders that are busy sabotaging / snatching (an attentive player watches the minimap)
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and r.work > 0 and (r.kind == "saboteur" or r.kind == "snatcher" or r.kind == "wolf") then
      if math.abs(r.y - P.y) < 44 then
        local dx = r.x - P.x
        if math.abs(dx) < 55 then P.facing = dx > 0 and 1 or -1; press("j")
        else held[dx > 0 and "d" or "a"] = true end
        return
      end
    end
  end
  -- keep the fire going even mid-fight
  if G.boss and (G.fuel < 30 or G.stove < 15) and (not P.carrying or P.carrying == "coal") then
    if P.carrying == "coal" then
      if goTo(P, (G.stove < 15 and G.fuel >= 30) and T.STOVE_X or T.FURNACE_X) then interact() end
    elseif goTo(P, T.COAL_X) then interact() end
    return
  end
  -- chains first, then dynamite
  if #G.hooks > 0 then
    local h = G.hooks[1]
    if P.carrying == "dynamite" then press("j"); return end
    local stand = h.x - 30
    if goTo(P, stand, 10) then P.facing = 1; press("j") end
    return
  end
  if G.boss and G.boss.state == "fight" then
    if P.carrying == "dynamite" then
      local dir = G.boss.x > P.x and 1 or -1
      if goTo(P, G.boss.x - dir * 180, 60) then P.facing = dir; press("j") end
      return
    elseif not P.carrying then
      if goTo(P, T.DYNAMITE_X) then interact() end
      return
    end
  end
  -- heal up like a sensible human
  if P.health < 45 and not P.carrying then
    if require("passengers").has(G, "olga") and G.soupT <= 0 and T.firstAttached <= 2 then
      if goTo(P, T.STOVE_X) then interact() end
      return
    elseif G.bandages > 0 and T.firstAttached == 1 then
      if goTo(P, T.MEDKIT_X) then interact() end
      return
    end
  end
  -- emergencies
  if G.fire then
    if goTo(P, G.fire.x, 30) then interact() end
    return
  end
  local sick = Hazards.firstSick(G)
  if sick and T.firstAttached == 1 then
    if P.carrying == "medicine" then
      if goTo(P, T.STOVE_X - 100) then interact() end
      return
    elseif not P.carrying then
      if goTo(P, T.MEDKIT_X) then interact() end
      return
    end
  end
  -- passenger favours (listen, then deliver when possible)
  do
    local St = require("story")
    local rq, st, rp = St.activeRequest(G)
    if rq and rp and rp.alive and (st == "asking" or (rq.can(G) and (rq.id ~= "olga" or P.carrying == "coal"))) then
      local sx = T.cars[2].x + require("render").SEATS[rp.seat]
      if goTo(P, sx, 8) then interact() end
      return
    end
  end
  -- brake for depots and damaged track
  local wantBrake = ((G.depot ~= nil) and G.coal < G.maxCoal - 5) or (G.track ~= nil and not G.track.passed)
  if G.avalanche then wantBrake = false end
  local dest
  if wantBrake ~= G.brake then
    dest = T.LEVER_X
  elseif G.depotLoading and Upgrades.cheapestAffordable(G) and not P.carrying then
    dest = T.TRADER_X
  elseif P.carrying == "coal" or P.carrying == "wood" then
    dest = (G.stove < 40 and G.fuel > 25) and T.STOVE_X or T.FURNACE_X
  elseif G.coal == 0 and G.crates > 0 and (G.fuel < 50 or G.stove < 30) then
    dest = T.CRATES_X
  elseif P.carrying then
    dest = T.FURNACE_X -- holding something odd; just wander to the cab
  elseif G.fuel < 85 or G.stove < 40 then
    dest = T.COAL_X
  else
    dest = T.FURNACE_X - 20
  end
  -- snow in the way?
  if G.snow then
    local gx = T.gapCenter(G.snow.gap)
    if (P.x < gx) ~= (dest < gx) then
      if Hazards.canDig(G, P.x) then interact(); return end
      goTo(P, gx + (P.x < gx and -40 or 40), 6)
      return
    end
  end
  if goTo(P, dest) then interact() end
end

function Dev.update(dt)
  local G = Game.state()
  if G.state == "title" then Game.newRun("play"); return end
  local step = 1 / 60
  for _ = 1, SUB do
    G = Game.state()
    if G.state == "play" then cheats(G); bot(G) end
    Game.update(step)
    simTime = simTime + step
  end
  G = Game.state()
  logT = logT + SUB * step
  if logT >= 20 then
    logT = 0
    print(string.format("[autotest] t=%4.0fs km=%5.1f spd=%3.0f fuel=%3.0f coal=%2d/%2d stove=%3.0f pass=%d hp=%3.0f scrap=%2d upg=%d raiders=%d kills=%d fire=%s snow=%s boss=%s hooks=%d",
      G.time, G.dist, G.speed, G.fuel, G.coal, G.maxCoal, G.stove, G.passengers, G.player.health, G.scrap, G.stats.upgrades,
      #G.raiders, G.stats.kills, G.fire and "Y" or "-", G.snow and "Y" or "-", G.boss and (G.boss.state .. ":" .. G.boss.hp) or "-", #G.hooks))
  end
  if shots then
    shotT = shotT + SUB * step
    if shotT >= SHOT_EVERY then
      shotT = 0
      love.graphics.captureScreenshot(string.format("shot_%04d.png", math.floor(simTime)))
    end
  end
  if (G.state == "over" or G.state == "win") and G.endT > 6 then
    runs = runs + 1
    local line = string.format("RUN %d: %s at %.1f km after %.0fs, %d passengers, score %d, boss %s - %s",
      runs, G.state, G.dist, G.time, G.passengers, G.score or 0, tostring(G.stats.boss), G.overReason or "")
    print("[autotest] " .. line)
    results[#results + 1] = line
    if shots then love.graphics.captureScreenshot(string.format("shot_end_%d.png", runs)) end
    if runs >= maxRuns then
      print("[autotest] DONE")
      love.event.quit()
    else
      Game.newRun("play")
    end
  end
end

-- love src --scenes : stage specific situations and screenshot them (menus, hazards, boss)
local scenes, sceneIdx, sceneT = nil, 0, 0
local function setupScenes()
  local Hz = require("hazards")
  local Up = require("upgrades")
  local function play(km) Game.newRun("play"); local G = Game.state(); G.dist = km or 30; G.time = 60; G.hintIdx = 99; return G end
  scenes = {
    { "title", function() Game.newRun("title") end },
    { "settings", function() Game.newRun("title"); Game.openMenu(Game.settingsMenu()) end },
    { "pause", function() local G = play(40); G.passengerList[3].alive = false; G.passengerList[3].fate = "froze"; G.passengers = 7; Game.openMenu(Game.pauseMenu()) end },
    { "trader", function() local G = play(31); G.scrap = 15; G.upgrades.coat = 1; local m = Up.menu(G, Game.closeMenu); m.kind = "trader"; Game.openMenu(m) end },
    { "fire", function() local G = play(30); G.player.x = 1000; Hz.trigger(G, "fire"); G.fire.car = 3; G.fire.x = 1000; G.fire.intensity = 80 end },
    { "snow", function() local G = play(45); G.player.x = 1200; Hz.trigger(G, "avalanche"); G.avalanche.t = 0.01; G.speed = 40 end },
    { "wolves", function() local G = play(50); G.player.x = 560; G.player.y = 560; Hz.trigger(G, "wolves"); G.speed = 30 end },
    { "sick", function() local G = play(55); G.player.x = 640; Hz.trigger(G, "sick") end },
    { "track", function() local G = play(35); G.player.x = 1900; Hz.trigger(G, "track") end },
    { "boss", function()
        local G = play(88.5); G.player.x = 1250; G.player.facing = 1; G.player.carrying = "dynamite"
        G.boss = { x = 1350, targetX = 1350, hp = 4, state = "fight", t = 0, hookT = 1.2, deployT = 99, flash = 0, dieT = 0, aim = -0.6 }
        G.hooks = { { x = 760, hp = 2 } }
      end },
    { "intro", function() local G = play(0); G.intro = require("story").newIntro(); G.intro.t = 9.5 end },
    { "chatter", function()
        local St = require("story")
        local G = play(21); G.player.x = 720; G.player.facing = -1
        G.requests.ivo = "asking"
        G.radioIdx = 3; G.nextHazardKm = 999; G.nextOverheadKm = 999
        St.bark(G, "olga", "Eat something. You look like a broom.", true)
        G.radio = { text = "Marisol here. Coal depot coming up. Slow down or they can't load you. Trust me, I've watched trains try.", t = 7 }
      end },
    { "win", function()
        local G = play(99.95); G.stats.boss = true; G.stats.kills = 31
        require("passengers").find(G, "bruno").alive = false; require("passengers").find(G, "bruno").fate = "froze"; G.passengers = 7
      end },
    { "lose", function() local G = play(41); G.player.health = 0; G.player.warmth = 0 end },
    { "crates", function() local G = play(25); G.coal = 2; G.player.x = 1150; G.player.facing = 1; G.crates = 4; G.radioIdx = 99; G.nextHazardKm = 999; G.nextOverheadKm = 999 end },
    { "passengers", function() local G = play(20); G.player.x = 690; G.player.facing = -1; G.player.carrying = "coal" end },
  }
end

function Dev.startScenes(g)
  Game = g
  Game.skipIntro = true
  love.keyboard.isDown = function() return false end
  setupScenes()
end

local captured = false
function Dev.updateScenes(dt)
  sceneT = sceneT - dt
  if sceneT <= 0 and sceneIdx > 0 and not captured then
    love.graphics.captureScreenshot("scene_" .. scenes[sceneIdx][1] .. ".png")
    captured = true -- the capture happens at the end of this frame; switch scenes next frame
    Game.update(1 / 60)
    return
  end
  if sceneT <= 0 then
    captured = false
    sceneIdx = sceneIdx + 1
    if sceneIdx > #scenes then love.event.quit(); return end
    scenes[sceneIdx][2]()
    local slow = { wolves = 3.5, track = 3.5, boss = 2.5, win = 9, lose = 3, chatter = 1 }
    sceneT = slow[scenes[sceneIdx][1]] or 1.5
  end
  Game.update(1 / 60)
  local name = scenes[sceneIdx] and scenes[sceneIdx][1]
  if name == "boss" or name == "passengers" or name == "chatter" or name == "crates" then
    local G = Game.state(); G.toasts = {}; G.overheads = {}
  end
end

function Dev.draw() end

return Dev
