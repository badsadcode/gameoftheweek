-- devtools.lua : headless smoke test. Run:  love game --autotest [--shots]
-- A simple bot plays the game at 4x speed, logs progress, takes screenshots, then quits.
local T = require("train")

local Dev = {}
local Game
local held = {}
local realIsDown
local simTime, shotT, logT = 0, 0, 0
local shots = false
local runs, maxRuns = 0, 2
local SUB = 10

function Dev.start(g)
  Game = g
  realIsDown = love.keyboard.isDown
  love.keyboard.isDown = function(...)
    for i = 1, select("#", ...) do if held[(select(i, ...))] then return true end end
    return false
  end
  for _, a in ipairs(arg or {}) do if a == "--shots" then shots = true end end
  print("[autotest] started")
end

local function press(k) Game.keypressed(k) end

local function bot(G)
  held = {}
  local P = G.player
  if P.y <= T.ROOF_Y + 2 or P.climbing then held.s = true; return end
  -- fight anyone close on our level
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and math.abs(r.y - P.y) < 44 and math.abs(r.x - P.x) < 260 then
      local dx = r.x - P.x
      if math.abs(dx) < 55 then
        P.facing = dx > 0 and 1 or -1
        press("j")
      else
        held[dx > 0 and "d" or "a"] = true
      end
      return
    end
  end
  local dest, wantE
  local atDepot = (G.depot ~= nil) and G.coal < G.maxCoal - 5
  if atDepot ~= G.brake then
    dest = T.LEVER_X
  elseif P.carrying then
    dest = (G.stove < 40 and G.fuel > 25) and T.STOVE_X or T.FURNACE_X
  elseif G.fuel < 85 or G.stove < 40 then
    dest = T.COAL_X
  else
    dest = T.FURNACE_X - 20
  end
  local dx = dest - P.x
  if math.abs(dx) > 18 then
    held[dx > 0 and "d" or "a"] = true
  else
    local it = Game.currentInteraction()
    if it and it.fn then it.fn() end
  end
end

function Dev.update(dt)
  local G = Game.state()
  if G.state == "title" then press("return"); return end
  if G.state == "paused" then G.state = "play" end
  local step = 1 / 60
  for _ = 1, SUB do
    G = Game.state()
    if G.state == "play" then bot(G) end
    Game.update(step)
    simTime = simTime + step
  end
  G = Game.state()
  logT = logT + SUB * step
  if logT >= 15 then
    logT = 0
    print(string.format("[autotest] t=%5.0fs dist=%5.1f speed=%3.0f fuel=%3.0f coal=%2d stove=%3.0f temp=%3.0f pass=%d hp=%3.0f warm=%3.0f raiders=%d kills=%d",
      G.time, G.dist, G.speed, G.fuel, G.coal, G.stove, G.carTemp, G.passengers, G.player.health, G.player.warmth, #G.raiders, G.stats.kills))
  end
  if shots then
    shotT = shotT + SUB * step
    if shotT >= 45 then
      shotT = 0
      love.graphics.captureScreenshot(string.format("shot_%04d.png", math.floor(simTime)))
    end
  end
  if G.state == "over" or G.state == "win" then
    runs = runs + 1
    print(string.format("[autotest] RUN %d ENDED: %s at %.1f km after %.0fs - %s", runs, G.state, G.dist, G.time, G.overReason or ""))
    if shots then love.graphics.captureScreenshot(string.format("shot_end_%d.png", runs)) end
    if runs >= maxRuns then
      love.event.quit()
    else
      Game.newRun("play")
    end
  end
end

function Dev.draw() end

return Dev
