-- Frostline: Last Train to Haven
-- Bad Ideas Works · Games of the Week · Week 1
--
-- Map of the code (studio motto #001: keep it understandable):
--   game.lua       run state, simulation loop, input, draw order
--   train.lua      train geometry + shared body physics
--   player.lua     the player: movement, ladders, ducking
--   raiders.lua    sleds + boarding raiders and their AI
--   events.lua     bridges, tunnels, coal depots, blizzards
--   render.lua     procedural drawing of everything in the world
--   background.lua sky, parallax scenery, snow
--   hud.lua        UI, title, pause and end screens
--   hazards.lua    fires, track damage, wolves, fevers, avalanches
--   boss.lua       the Iron Jaw finale
--   passengers.lua the eight named passengers and their perks
--   upgrades.lua   the depot trader
--   input.lua      keyboard + gamepad actions
--   menu.lua       list menus (title, pause, settings, trader)
--   settings.lua   options + high score, saved to disk
--   audio.lua      synthesized sound effects
--   music.lua      procedural adaptive soundtrack
--   devtools.lua   automated smoke test (love . --autotest)

local Game = require("game")

local VW, VH = 1280, 720
local scale, ox, oy = 1, 0, 0
local Dev

local function recompute()
  local w, h = love.graphics.getDimensions()
  scale = math.min(w / VW, h / VH)
  ox, oy = math.floor((w - VW * scale) / 2), math.floor((h - VH * scale) / 2)
end

function love.load(args)
  love.graphics.setDefaultFilter("linear", "linear")
  recompute()
  local t0 = love.timer.getTime()
  Game.load()
  Game.loadSeconds = love.timer.getTime() - t0
  for _, a in ipairs(args or {}) do
    if a == "--autotest" then
      Dev = require("devtools")
      Dev.start(Game)
    elseif a == "--loadtime" then
      print(string.format("[loadtime] %.2f s", Game.loadSeconds))
      love.event.quit()
    elseif a == "--scenes" then
      Dev = require("devtools")
      Dev.startScenes(Game)
      Dev.update = Dev.updateScenes
    end
  end
end

function love.resize() recompute() end

function love.update(dt)
  dt = math.min(dt, 1 / 30)
  if Dev then Dev.update(dt) else Game.update(dt) end
end

function love.draw()
  love.graphics.clear(0, 0, 0)
  love.graphics.setScissor(ox, oy, math.ceil(VW * scale), math.ceil(VH * scale))
  love.graphics.push()
  love.graphics.translate(ox, oy)
  love.graphics.scale(scale)
  Game.draw()
  love.graphics.pop()
  love.graphics.setScissor()
  if Dev then Dev.draw() end
end

function love.keypressed(k)
  if k == "f11" then
    local Settings = require("settings")
    Settings.data.fullscreen = not Settings.data.fullscreen
    Settings.save()
    Game.applySettings()
    recompute()
    return
  end
  Game.keypressed(k)
end

function love.mousepressed(_, _, b) Game.mousepressed(b) end
function love.gamepadpressed(_, button) Game.gamepadpressed(button) end
function love.gamepadaxis(_, axis, value) Game.gamepadaxis(axis, value) end

function love.focus(f)
  if Dev then return end
  if not f then
    local G = Game.state()
    if G and G.state == "play" and not G.menu then Game.openMenu(Game.pauseMenu()) end
  end
end
