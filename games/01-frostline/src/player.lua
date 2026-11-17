-- player.lua : the lone crew member. Movement, ladders, ducking, getting hurt.
local T = require("train")
local U = require("util")
local Audio = require("audio")
local Input = require("input")
local Particles = require("particles")

local Player = {}
Player.__index = Player

function Player.new()
  local p = setmetatable({}, Player)
  p.x, p.y = T.COAL_X + 60, T.FLOOR_Y
  p.vx, p.vy = 0, 0
  p.facing = 1
  p.onGround = true
  p.climbing = false
  p.gap = nil
  p.ducking = false
  p.health, p.warmth = 100, 100
  p.carrying = nil -- nil | "coal" | "medicine" | "dynamite"
  p.attackT, p.attackCD = 0, 0
  p.stun, p.hurtT, p.lastHurt = 0, 0, 99
  p.overheadCD = 0
  p.anim = 0
  p.squash = 0      -- >0 squashed (landing), <0 stretched (jumping)
  p.stepT, p.breathT = 0, 1
  return p
end

-- gap index if standing on a roof right next to a ladder
function Player:roofLadder()
  if not self.onGround or T.levelOf(self) ~= "roof" then return nil end
  for g = T.firstAttached, #T.cars - 1 do
    if math.abs(self.x - T.gapCenter(g)) < T.GAP / 2 + 24 then return g end
  end
end

function Player:canClimbUp()
  if self.onGround and T.levelOf(self) == "floor" then return T.gapAt(self.x) end
end

-- safe from low bridges / tunnel ceilings?
function Player:isLow()
  if self.climbing then return self.y > T.ROOF_Y + 30 end
  return self.ducking or self.stun > 0 or self.y > T.ROOF_Y + 2
end

function Player:hurt(G, amount, dir)
  if G.state ~= "play" then return end
  self.health = math.max(0, self.health - amount)
  self.hurtT = 0.25
  self.lastHurt = 0
  if not self.climbing then
    self.vx = (dir or 0) * 260
    if self.onGround then self.vy = -180 end
  end
  Audio.play("hurt", 0.7, U.rand(0.9, 1.1))
  G.addShake(7)
  G.flash = 0.25
end

function Player:jump()
  if self.stun > 0 then return end
  if self.climbing then
    self.climbing = false
    self.vy = -260
    self.vx = self.facing * 120
    return
  end
  if self.onGround and not self.ducking then
    self.vy = -640
    self.onGround = false
    self.squash = -0.2
    Audio.play("jump", 0.3)
  end
end

function Player:update(G, dt)
  self.attackCD = math.max(0, self.attackCD - dt)
  self.attackT = math.max(0, self.attackT - dt)
  self.hurtT = math.max(0, self.hurtT - dt)
  self.overheadCD = math.max(0, self.overheadCD - dt)
  self.lastHurt = self.lastHurt + dt

  local L, R = Input.down("left"), Input.down("right")
  local Up, Dn = Input.down("up"), Input.down("down")
  if self.stun > 0 then
    self.stun = self.stun - dt
    L, R, Up, Dn = false, false, false, false
  end
  local dir = (R and 1 or 0) - (L and 1 or 0)

  if self.climbing then
    if self.gap < T.firstAttached then self.climbing = false; return end
    if dir ~= 0 then self.facing = dir end
    local v = (Dn and 1 or 0) - (Up and 1 or 0)
    self.y = self.y + v * 220 * dt
    self.anim = self.anim + math.abs(v) * dt * 8
    if self.y <= T.ROOF_Y then
      -- top of the ladder: step onto the roof you're facing
      self.climbing = false
      local g = self.gap
      if self.facing > 0 then self.x = T.cars[g + 1].x + 16 else self.x = T.cars[g].x + T.CAR_W - 16 end
      self.y, self.vy, self.onGround = T.ROOF_Y, 0, true
    elseif self.y >= T.FLOOR_Y then
      self.climbing = false
      self.y, self.vy, self.onGround = T.FLOOR_Y, 0, true
    end
    return
  end

  -- grab a ladder
  if Up then
    local g = self:canClimbUp()
    if g then
      self.climbing, self.gap = true, g
      self.x, self.vx, self.vy = T.gapCenter(g), 0, 0
      self.ducking = false
      return
    end
  end
  if Dn then
    local g = self:roofLadder()
    if g then
      self.climbing, self.gap = true, g
      self.x, self.y, self.vx, self.vy = T.gapCenter(g), T.ROOF_Y + 6, 0, 0
      self.ducking = false
      return
    end
  end

  self.ducking = Dn and self.onGround and T.levelOf(self) == "roof"

  local maxSpeed = self.carrying and 225 or 260
  local target = self.ducking and 0 or dir * maxSpeed
  local accel = self.onGround and 2600 or 1400
  self.vx = U.approach(self.vx, target, accel * dt)
  if dir ~= 0 then self.facing = dir end

  local wasGround, preVy = self.onGround, self.vy
  T.stepBody(self, dt)
  if self.onGround and math.abs(self.vx) > 10 then
    self.anim = self.anim + dt * math.abs(self.vx) * 0.055
  end

  -- juice: landing squash + dust, snowy footsteps on roofs, frosty breath
  self.squash = U.approach(self.squash, 0, dt * 1.6)
  if not wasGround and self.onGround and preVy > 350 then
    self.squash = math.min(0.28, preVy / 2200)
    Particles.burst(G, self.x, self.y, 8, { speed = 110, vy = -60, color = { 0.92, 0.95, 1 }, life = 0.45, g = 300, size = 2.5 })
    Audio.play("clack", 0.25, 0.6)
  end
  local onRoof = self.y <= T.ROOF_Y + 2
  self.stepT = self.stepT - dt
  if onRoof and self.onGround and math.abs(self.vx) > 60 and self.stepT <= 0 then
    self.stepT = 0.16
    Particles.add(G, { x = self.x - self.facing * 6, y = self.y - 2, vx = -self.vx * 0.2 + U.rand(-20, 20), vy = U.rand(-60, -20),
      life = 0.4, size = U.rand(2, 3.5), g = 200, color = { 0.95, 0.97, 1 }, alpha = 0.8 })
  end
  self.breathT = self.breathT - dt
  if self.breathT <= 0 then
    self.breathT = U.rand(1.1, 1.7)
    if onRoof or self.warmth < 60 or self.climbing then
      local hy = self.y - (self.ducking and 32 or 51)
      for k = 1, 3 do
        Particles.add(G, { x = self.x + self.facing * 10, y = hy, vx = self.facing * U.rand(20, 40) - 30, vy = U.rand(-12, 4),
          life = 0.9, size = 2 + k, grow = 5, color = { 1, 1, 1 }, alpha = 0.3, drag = 1 })
      end
    end
  end
end

return Player
