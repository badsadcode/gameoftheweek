-- render.lua : procedural drawing of the train, people, sleds, bridges, depots and lights.
-- Everything here draws in train space (the caller applies the camera transform).
local T = require("train")
local U = require("util")
local Raiders = require("raiders")
local Boss = require("boss")
local lg = love.graphics

local R = {}
local glowImg

function R.load()
  local size = 128
  local id = love.image.newImageData(size, size)
  id:mapPixel(function(x, y)
    local dx, dy = (x - size / 2) / (size / 2), (y - size / 2) / (size / 2)
    local a = math.max(0, 1 - math.sqrt(dx * dx + dy * dy))
    return 1, 1, 1, a * a
  end)
  glowImg = lg.newImage(id)
end

function R.glow(x, y, radius, c, a)
  lg.setColor(c[1], c[2], c[3], a or 1)
  lg.draw(glowImg, x, y, 0, radius / 64, radius / 64, 64, 64)
end

---------------------------------------------------------------------------
-- People
---------------------------------------------------------------------------
local PLAYER_LOOK = {
  coat = { 0.88, 0.46, 0.16 }, pants = { 0.20, 0.22, 0.30 }, hat = { 0.42, 0.26, 0.16 },
  scarf = { 0.85, 0.15, 0.15 }, skin = { 0.96, 0.80, 0.66 }, style = "cap",
}
R.PLAYER_LOOK = PLAYER_LOOK

local function col(c, flash)
  if flash then lg.setColor(1, 1, 1) else lg.setColor(c) end
end

-- feet at (x, y). o: look fields + facing, anim, moving, duck, attackT, windup, carry, scale, rot, flash, time
function R.person(x, y, o)
  local s = o.scale or 1
  local f = o.facing or 1
  local fl = o.flash
  lg.push()
  lg.translate(x, y)
  if o.rot and o.rot ~= 0 then
    lg.translate(0, -28 * s); lg.rotate(o.rot); lg.translate(0, 28 * s)
  end
  lg.scale(f * s, (o.duck and 0.62 or 1) * s)

  local swing = o.moving and math.sin(o.anim * 1.6) * 6 or 0
  local t = o.time or 0
  -- scarf tail, blown toward the rear of the train (world -x == local -f)
  col(o.scarf, fl)
  local tailDir = -f
  local flap = math.sin(t * 14 + x * 0.01) * 3
  lg.polygon("fill", -2, -43, 4, -40, 4 + tailDir * 22, -38 + flap, tailDir * 20, -43 + flap)
  -- legs
  col(o.pants, fl)
  lg.rectangle("fill", -8 + swing * 0.6, -21, 7, 21)
  lg.rectangle("fill", 1 - swing * 0.6, -21, 7, 21)
  lg.setColor(0.10, 0.08, 0.07)
  lg.rectangle("fill", -9 + swing * 0.6, -4, 9, 4)
  lg.rectangle("fill", 0 - swing * 0.6, -4, 9, 4)
  -- torso
  col(o.coat, fl)
  lg.rectangle("fill", -10, -44, 20, 27, 5, 5)
  lg.setColor(0, 0, 0, 0.18)
  lg.rectangle("fill", -10, -24, 20, 3)
  -- scarf wrap
  col(o.scarf, fl)
  lg.rectangle("fill", -8, -45, 16, 5, 2, 2)
  -- head
  col(o.skin, fl)
  lg.circle("fill", 1, -51, 8)
  if o.style == "hood" then
    col(o.hat, fl)
    lg.arc("fill", 0, -51, 10, math.pi * 0.95, math.pi * 2.05)
    lg.rectangle("fill", -10, -52, 6, 10)
    -- glowing goggles
    lg.setColor(1, 0.25 + 0.15 * math.sin(t * 8), 0.2)
    lg.rectangle("fill", 1, -54, 8, 4, 1, 1)
  else
    col(o.hat, fl)
    lg.rectangle("fill", -8, -61, 18, 7, 3, 3)
    lg.rectangle("fill", -9, -56, 5, 8, 2, 2)
    lg.setColor(0.1, 0.1, 0.12)
    lg.circle("fill", 5, -51, 1.5)
  end

  -- arm + weapon
  local ang
  if o.attackT and o.attackT > 0 then
    local k = 1 - o.attackT / 0.2
    ang = U.lerp(-2.3, 0.9, k)
  elseif o.windup and o.windup > 0 then
    ang = -2.4 + math.sin(t * 30) * 0.1
  elseif o.carry then
    ang = 0.2
  else
    ang = 0.5 + math.sin(o.anim * 1.6) * 0.25 * (o.moving and 1 or 0)
  end
  lg.push()
  lg.translate(3, -39)
  lg.rotate(ang)
  col(o.coat, fl)
  lg.rectangle("fill", -3, -3, 16, 7, 3, 3)
  if not o.carry then
    lg.setColor(0.62, 0.64, 0.68)
    lg.rectangle("fill", 12, -2, 18, 4)
    lg.rectangle("fill", 27, -6, 6, 12, 2, 2)
  end
  lg.pop()
  if o.carry == "medicine" then
    lg.setColor(0.95, 0.95, 0.92); lg.rectangle("fill", 8, -42, 16, 14, 2, 2)
    lg.setColor(0.85, 0.12, 0.12); lg.rectangle("fill", 14, -40, 4, 10); lg.rectangle("fill", 11, -37, 10, 4)
  elseif o.carry == "dynamite" then
    lg.setColor(0.8, 0.15, 0.12)
    for k = 0, 2 do lg.rectangle("fill", 8 + k * 6, -44, 5, 18, 2, 2) end
    lg.setColor(0.3, 0.25, 0.2); lg.line(17, -44, 20, -52)
    lg.setColor(1, 0.85, 0.3, 0.6 + 0.4 * math.sin(t * 40)); lg.circle("fill", 20, -53, 2.5)
  elseif o.carry then
    lg.setColor(0.07, 0.07, 0.08)
    lg.circle("fill", 15, -34, 8)
    lg.circle("fill", 21, -36, 6)
    lg.setColor(0.5, 0.5, 0.6)
    lg.circle("fill", 13, -37, 1.6)
  end
  lg.pop()
end

R.SEATS = { 40, 72, 104, 136, 244, 276, 308, 340 }

local function seatedCat(x, y, t)
  local tail = math.sin(t * 3) * 4
  lg.setColor(0.95, 0.6, 0.2)
  lg.ellipse("fill", x, y - 8, 9, 7)
  lg.circle("fill", x + 6, y - 17, 6)
  lg.polygon("fill", x + 2, y - 21, x + 4, y - 28, x + 7, y - 22)
  lg.polygon("fill", x + 7, y - 22, x + 10, y - 28, x + 11, y - 20)
  lg.setLineWidth(3)
  lg.line(x - 8, y - 6, x - 15, y - 14 + tail)
  lg.setLineWidth(1)
  lg.setColor(0.1, 0.1, 0.1)
  lg.circle("fill", x + 8, y - 18, 1.2)
end

local function seatedPassenger(x, y, p, cold, t)
  if p.def.cat then return seatedCat(x, y, t) end
  local c = p.def.color
  local i = p.seat
  local shiver = cold > 0 and math.sin(t * 45 + i) * 1.4 * cold or 0
  if p.sick then shiver = shiver + math.sin(t * 30 + i) * 0.8 end
  local blue = cold * 0.5
  x = x + shiver
  local small = p.def.small and 0.75 or 1
  lg.setColor(U.lerp(c[1], 0.5, blue), U.lerp(c[2], 0.65, blue), U.lerp(c[3], 0.95, blue))
  lg.rectangle("fill", x - 9 * small, y - 26 * small, 18 * small, 26 * small, 5, 5)
  if p.sick then lg.setColor(0.75, 0.92, 0.6) else lg.setColor(U.lerp(0.95, 0.7, blue), U.lerp(0.78, 0.8, blue), U.lerp(0.65, 0.95, blue)) end
  lg.circle("fill", x, y - 33 * small, 7 * small)
  lg.setColor(0.2 + (i % 3) * 0.15, 0.15, 0.1)
  lg.arc("fill", x, y - 34 * small, 7.5 * small, math.pi, math.pi * 2)
  if p.id == "amara" then lg.setColor(0.85, 0.15, 0.15); lg.rectangle("fill", x - 2, y - 22, 4, 10); lg.rectangle("fill", x - 5, y - 19, 10, 4) end
  if p.id == "sergei" then lg.setColor(0.3, 0.35, 0.25); lg.rectangle("fill", x - 8, y - 43, 16, 5, 2, 2) end
  if p.id == "olga" then lg.setColor(0.9, 0.9, 0.9); lg.arc("fill", x, y - 36, 8, math.pi, math.pi * 2) end
  if p.sick then
    lg.setColor(0.4, 1, 0.4, 0.6 + 0.4 * math.sin(t * 6))
    lg.circle("fill", x, y - 52 * small, 3)
  end
  if cold > 0.4 then -- breath puff
    lg.setColor(1, 1, 1, 0.3 * math.max(0, math.sin(t * 2 + i)))
    lg.circle("fill", x + 10, y - 34 * small, 3)
  end
end

---------------------------------------------------------------------------
-- Train
---------------------------------------------------------------------------
local STYLE = {
  caboose   = { wall = { 0.36, 0.16, 0.14 }, trim = { 0.58, 0.24, 0.17 }, roof = { 0.22, 0.10, 0.09 } },
  passenger = { wall = { 0.42, 0.28, 0.17 }, trim = { 0.62, 0.43, 0.25 }, roof = { 0.20, 0.14, 0.10 } },
  cargo     = { wall = { 0.30, 0.29, 0.27 }, trim = { 0.44, 0.42, 0.37 }, roof = { 0.17, 0.17, 0.17 } },
  tender    = { wall = { 0.17, 0.17, 0.19 }, trim = { 0.32, 0.32, 0.35 }, roof = { 0.12, 0.12, 0.13 } },
  engine    = { wall = { 0.14, 0.13, 0.14 }, trim = { 0.62, 0.16, 0.12 }, roof = { 0.10, 0.10, 0.11 } },
}

local function wheels(x, ang)
  local y = T.RAIL_Y - 16
  lg.setColor(0.10, 0.10, 0.11)
  lg.rectangle("fill", x - 40, y - 10, 80, 10)
  for k = -1, 1, 2 do
    local wx = x + k * 22
    lg.setColor(0.07, 0.07, 0.08)
    lg.circle("fill", wx, y, 16)
    lg.setColor(0.35, 0.35, 0.38)
    lg.circle("line", wx, y, 13)
    for s = 0, 3 do
      local a = ang + s * math.pi / 4
      lg.line(wx - math.cos(a) * 13, y - math.sin(a) * 13, wx + math.cos(a) * 13, y + math.sin(a) * 13)
    end
  end
end

local function roof(x, w, st)
  lg.setColor(st.roof)
  lg.rectangle("fill", x - 6, T.ROOF_Y, w + 12, T.CEIL_Y - T.ROOF_Y)
  lg.setColor(st.trim)
  lg.rectangle("fill", x - 6, T.CEIL_Y - 4, w + 12, 4)
  lg.setColor(0.88, 0.92, 1.0)
  lg.rectangle("fill", x - 6, T.ROOF_Y - 3, w + 12, 5, 2, 2)
end

local function window(x, y, w, h, G)
  local sky = G.windowColor
  lg.setColor(sky[1] * 0.6, sky[2] * 0.6, sky[3] * 0.7)
  lg.rectangle("fill", x, y, w, h, 3, 3)
  -- streaks of passing snow
  lg.setColor(1, 1, 1, 0.25)
  for k = 0, 2 do
    local sx = x + ((-G.scroll * 0.5 + k * 37 + y) % w)
    lg.rectangle("fill", sx, y + 8 + k * 14, math.min(10, x + w - sx), 1.5)
  end
  lg.setColor(0.92, 0.96, 1, 0.45)
  lg.polygon("fill", x, y + h, x, y + h - 12, x + 12, y + h)
  lg.polygon("fill", x + w, y, x + w - 10, y, x + w, y + 10)
  lg.setColor(0.1, 0.07, 0.05)
  lg.setLineWidth(3)
  lg.rectangle("line", x, y, w, h, 3, 3)
  lg.line(x + w / 2, y, x + w / 2, y + h)
  lg.setLineWidth(1)
end

local function crate(x, y, w, h)
  lg.setColor(0.45, 0.33, 0.20)
  lg.rectangle("fill", x, y, w, h)
  lg.setColor(0.30, 0.21, 0.12)
  lg.setLineWidth(2)
  lg.rectangle("line", x, y, w, h)
  lg.line(x, y, x + w, y + h)
  lg.line(x + w, y, x, y + h)
  lg.setLineWidth(1)
end

local function interior(G, c, x)
  local w, floor, ceil = c.w, T.FLOOR_Y, T.CEIL_Y
  local k = c.kind
  if k == "caboose" then
    window(x + 150, ceil + 30, 50, 50, G)
    window(x + 260, ceil + 30, 50, 50, G)
    -- bunk
    lg.setColor(0.30, 0.20, 0.12); lg.rectangle("fill", x + 230, floor - 40, 130, 12)
    lg.setColor(0.55, 0.20, 0.20); lg.rectangle("fill", x + 236, floor - 50, 118, 10, 4, 4)
    lg.setColor(0.30, 0.20, 0.12); lg.rectangle("fill", x + 234, floor - 28, 6, 28); lg.rectangle("fill", x + 350, floor - 28, 6, 28)
    -- medkit cabinet
    local mx = c.x + (T.MEDKIT_X - c.x) + (x - c.x)
    lg.setColor(0.85, 0.85, 0.82); lg.rectangle("fill", mx - 20, floor - 92, 40, 36, 3, 3)
    if G.bandages > 0 then lg.setColor(0.85, 0.12, 0.12) else lg.setColor(0.45, 0.45, 0.45) end
    lg.rectangle("fill", mx - 4, floor - 86, 8, 24); lg.rectangle("fill", mx - 12, floor - 78, 24, 8)
    -- desk + lantern
    lg.setColor(0.32, 0.22, 0.14); lg.rectangle("fill", x + 120, floor - 36, 70, 8); lg.rectangle("fill", x + 126, floor - 28, 6, 28)
    lg.setColor(0.25, 0.25, 0.25); lg.line(x + 210, ceil, x + 210, ceil + 24)
    lg.setColor(1, 0.8, 0.4); lg.rectangle("fill", x + 204, ceil + 24, 12, 14, 3, 3)
  elseif k == "passenger" then
    for i = 0, 3 do
      if i ~= 2 and i ~= 1 then window(x + 30 + i * 90, ceil + 26, 54, 48, G) end
    end
    window(x + 120, ceil + 26, 40, 48, G); window(x + 225, ceil + 26, 40, 48, G)
    -- benches
    lg.setColor(0.35, 0.18, 0.12)
    lg.rectangle("fill", x + 20, floor - 26, 140, 8, 3, 3); lg.rectangle("fill", x + 220, floor - 26, 140, 8, 3, 3)
    lg.rectangle("fill", x + 20, floor - 56, 8, 38); lg.rectangle("fill", x + 352, floor - 56, 8, 38)
    -- passengers
    local cold = U.clamp((5 - G.carTemp) / 20, 0, 1)
    for _, p in ipairs(G.passengerList) do
      if p.alive then seatedPassenger(x + R.SEATS[p.seat], floor - 18, p, cold, G.time) end
    end
    -- stove
    local sx = x + w / 2
    lg.setColor(0.12, 0.12, 0.13)
    lg.rectangle("fill", sx - 22, floor - 52, 44, 52, 4, 4)
    lg.rectangle("fill", sx - 6, ceil, 12, floor - 52 - ceil)
    local heat = U.clamp(G.stove / 40, 0, 1)
    lg.setColor(0.2 + heat * 0.8, 0.1 + heat * 0.45, 0.05 + heat * 0.1)
    lg.rectangle("fill", sx - 12, floor - 38, 24, 18, 3, 3)
    -- lamps
    for _, lx in ipairs({ x + 90, x + 290 }) do
      lg.setColor(0.25, 0.25, 0.25); lg.line(lx, ceil, lx, ceil + 18)
      lg.setColor(1, 0.85, 0.5); lg.circle("fill", lx, ceil + 22, 5)
    end
  elseif k == "cargo" then
    lg.setColor(0, 0, 0, 0.18)
    for i = 0, 5 do lg.rectangle("fill", x + 30 + i * 58, ceil + 30, 30, 6) end
    crate(x + 18, floor - 60, 60, 60); crate(x + 26, floor - 104, 46, 44)
    lg.setColor(0.75, 0.12, 0.1); lg.rectangle("fill", x + 26, floor - 42, 44, 16)
    lg.setColor(1, 0.9, 0.8); lg.print("TNT", x + 35, floor - 41)
    crate(x + 290, floor - 56, 70, 56); crate(x + 230, floor - 40, 50, 40)
    lg.setColor(0.30, 0.32, 0.36)
    lg.rectangle("fill", x + 120, floor - 54, 34, 54, 6, 6); lg.rectangle("fill", x + 160, floor - 54, 34, 54, 6, 6)
    lg.setColor(0.2, 0.2, 0.22)
    lg.rectangle("fill", x + 120, floor - 40, 34, 4); lg.rectangle("fill", x + 160, floor - 40, 34, 4)
    lg.setColor(0.25, 0.25, 0.25); lg.line(x + w / 2, ceil, x + w / 2, ceil + 16)
    lg.setColor(1, 0.8, 0.45, 0.8); lg.circle("fill", x + w / 2, ceil + 20, 4)
  elseif k == "tender" then
    -- coal pile, size tracks stock
    local frac = U.clamp(G.coal / G.maxCoal, 0, 1)
    local h = 8 + 100 * frac
    local x0, x1 = x + 30, x + w - 30
    local pts = {}
    for i = 0, 16 do
      local u = i / 16
      pts[#pts + 1] = U.lerp(x0, x1, u)
      pts[#pts + 1] = floor - h * (math.sin(math.pi * u) ^ 0.7)
    end
    pts[#pts + 1] = x1; pts[#pts + 1] = floor
    pts[#pts + 1] = x0; pts[#pts + 1] = floor
    lg.setColor(0.07, 0.07, 0.08)
    lg.polygon("fill", pts)
    lg.setColor(0.35, 0.37, 0.45)
    for i = 1, 14 do
      local u = (i * 0.618) % 1
      local px = U.lerp(x0 + 20, x1 - 20, u)
      local top = floor - h * (math.sin(math.pi * (px - x0) / (x1 - x0)) ^ 0.7)
      lg.circle("fill", px, U.lerp(top + 6, floor - 4, (i * 0.37) % 1), 1.6)
    end
    -- shovel
    lg.setColor(0.45, 0.32, 0.2); lg.setLineWidth(3)
    lg.line(x + w / 2 + 40, floor - h * 0.6, x + w / 2 + 70, floor - h * 0.6 - 50)
    lg.setLineWidth(1)
    lg.setColor(0.55, 0.57, 0.6)
    lg.rectangle("fill", x + w / 2 + 30, floor - h * 0.6 - 4, 16, 12)
  end
end

local function drawEngine(G, c, x)
  local w, top, ceil, floor = c.w, T.ROOF_Y, T.CEIL_Y, T.FLOOR_Y
  local st = STYLE.engine
  -- cab
  lg.setColor(st.wall)
  lg.rectangle("fill", x, ceil, 190, floor - ceil)
  window(x + 70, ceil + 26, 46, 44, G)
  -- gauges
  for i, gx in ipairs({ x + 30, x + 150 }) do
    lg.setColor(0.8, 0.75, 0.6); lg.circle("fill", gx, ceil + 46, 12)
    lg.setColor(0.2, 0.15, 0.1); lg.circle("line", gx, ceil + 46, 12)
    local v = i == 1 and G.speed / 110 or G.fuel / 100
    local a = math.pi * (0.75 + v * 1.5)
    lg.setColor(0.8, 0.1, 0.1)
    lg.line(gx, ceil + 46, gx + math.cos(a) * 10, ceil + 46 + math.sin(a) * 10)
  end
  -- brake lever
  local lx = T.LEVER_X - c.x + x
  lg.setColor(0.25, 0.25, 0.27); lg.rectangle("fill", lx - 10, floor - 14, 20, 14)
  local la = G.brake and 0.5 or -0.5
  lg.setColor(0.6, 0.6, 0.62); lg.setLineWidth(4)
  lg.line(lx, floor - 10, lx + math.sin(la) * 46, floor - 10 - math.cos(la) * 46)
  lg.setLineWidth(1)
  lg.setColor(G.brake and { 1, 0.3, 0.2 } or { 0.85, 0.75, 0.3 })
  lg.circle("fill", lx + math.sin(la) * 46, floor - 10 - math.cos(la) * 46, 5)
  -- firebox
  local fx = T.FURNACE_X - c.x + x
  lg.setColor(0.10, 0.10, 0.10); lg.rectangle("fill", fx - 28, floor - 74, 56, 74, 4, 4)
  local heat = U.clamp(G.fuel / 50, 0, 1)
  local flick = 0.85 + 0.15 * math.sin(G.time * 23) * math.sin(G.time * 7)
  lg.setColor((0.25 + heat * 0.75) * flick, (0.08 + heat * 0.45) * flick, 0.03)
  lg.rectangle("fill", fx - 18, floor - 60, 36, 26, 4, 4)
  lg.setColor(0.3, 0.3, 0.3); lg.rectangle("fill", fx - 20, floor - 62, 40, 4)
  -- boiler
  lg.setColor(0.13, 0.13, 0.15)
  lg.rectangle("fill", x + 190, top + 6, w - 190, floor - top - 6, 18, 18)
  lg.setColor(0.22, 0.22, 0.25)
  lg.rectangle("fill", x + 190, top + 14, w - 190, 10, 5, 5)
  lg.setColor(st.trim)
  for bx = x + 230, x + w - 40, 50 do lg.rectangle("fill", bx, top + 6, 6, floor - top - 6) end
  lg.setColor(0.09, 0.09, 0.1)
  lg.rectangle("fill", x + w - 46, top + 2, 46, floor - top + 4, 10, 10)
  -- cab front wall
  lg.setColor(0.08, 0.08, 0.09)
  lg.rectangle("fill", x + 186, ceil, 8, floor - ceil)
  -- smokestack + dome + bell
  lg.setColor(0.10, 0.10, 0.11)
  lg.polygon("fill", x + w - 82, top - 52, x + w - 46, top - 52, x + w - 54, top, x + w - 74, top)
  lg.rectangle("fill", x + w - 86, top - 60, 44, 10, 3, 3)
  lg.arc("fill", x + w - 150, top + 2, 22, math.pi, math.pi * 2)
  lg.setColor(0.75, 0.6, 0.25)
  lg.arc("fill", x + w - 210, top - 4, 10, math.pi, math.pi * 2)
  -- headlight
  lg.setColor(0.25, 0.25, 0.25); lg.rectangle("fill", x + w - 8, top + 22, 18, 22, 3, 3)
  lg.setColor(1, 0.95, 0.7); lg.circle("fill", x + w + 8, top + 33, 7)
  -- cowcatcher
  lg.setColor(st.trim)
  lg.polygon("fill", x + w, floor + 12, x + w + 44, T.RAIL_Y - 2, x + w, T.RAIL_Y - 2)
  -- floor + cab roof (boiler top is walkable at ROOF_Y too)
  lg.setColor(0.16, 0.12, 0.10); lg.rectangle("fill", x - 2, floor, 196, 14)
  lg.setColor(0.10, 0.10, 0.11); lg.rectangle("fill", x + 190, floor, w - 190, 14)
  lg.setColor(0.08, 0.08, 0.09); lg.rectangle("fill", x, ceil, 7, floor - ceil)
  roof(x, 194, st)
  lg.setColor(0.88, 0.92, 1.0)
  lg.rectangle("fill", x + 194, top - 3, w - 194, 5, 2, 2)
end

local function drawCar(G, c, ox)
  local x, w = c.x + ox, c.w
  local st = STYLE[c.kind]
  local ceil, floor = T.CEIL_Y, T.FLOOR_Y
  local ang = -G.scroll / 16
  lg.setColor(0.08, 0.08, 0.09)
  lg.rectangle("fill", x + 14, floor + 14, w - 28, 14)
  wheels(x + 70, ang)
  wheels(x + w - 70, ang)
  if c.kind == "engine" then drawEngine(G, c, x); return end

  lg.setColor(st.wall)
  lg.rectangle("fill", x, ceil, w, floor - ceil)
  lg.setColor(0, 0, 0, 0.12)
  for py = ceil + 18, floor - 6, 18 do lg.line(x, py, x + w, py) end
  lg.setColor(st.trim)
  lg.rectangle("fill", x, floor - 46, w, 5)
  interior(G, c, x)
  lg.setColor(0.16, 0.12, 0.10)
  lg.rectangle("fill", x - 2, floor, w + 4, 14)
  lg.setColor(st.trim)
  lg.rectangle("fill", x - 2, floor, w + 4, 3)
  lg.setColor(st.roof)
  lg.rectangle("fill", x, ceil, 7, floor - ceil)
  lg.rectangle("fill", x + w - 7, ceil, 7, floor - ceil)
  roof(x, w, st)
end

local function drawGap(G, g, ox)
  local a = T.cars[g].x + T.CAR_W + ox
  local gx = a + T.GAP / 2
  lg.setColor(0.22, 0.17, 0.12)
  lg.rectangle("fill", a - 2, T.FLOOR_Y, T.GAP + 4, 8)
  lg.setColor(0.24, 0.24, 0.26)
  lg.rectangle("fill", a - 4, T.FLOOR_Y + 20, T.GAP + 8, 7)
  lg.setColor(0.35, 0.35, 0.38)
  lg.circle("fill", gx, T.FLOOR_Y + 23, 6)
  lg.setColor(0.50, 0.46, 0.40)
  lg.setLineWidth(3)
  lg.line(gx - 11, T.ROOF_Y + 2, gx - 11, T.FLOOR_Y)
  lg.line(gx + 11, T.ROOF_Y + 2, gx + 11, T.FLOOR_Y)
  lg.setLineWidth(2)
  for y = T.ROOF_Y + 12, T.FLOOR_Y - 6, 16 do lg.line(gx - 11, y, gx + 11, y) end
  lg.setLineWidth(1)
end

function R.offsetFor(G, carIndex)
  local d = G.detached
  if d and carIndex <= d.upto then return d.offset end
  return 0
end

function R.train(G)
  for i, c in ipairs(T.cars) do drawCar(G, c, R.offsetFor(G, i)) end
  for g = 1, #T.cars - 1 do
    if not (G.detached and g == G.detached.upto) then drawGap(G, g, R.offsetFor(G, g)) end
  end
end

---------------------------------------------------------------------------
-- Raiders, sleds, items
---------------------------------------------------------------------------
local RAIDER_LOOK = { coat = { 0.30, 0.31, 0.35 }, pants = { 0.15, 0.15, 0.17 }, hat = { 0.20, 0.20, 0.23 },
  skin = { 0.75, 0.68, 0.62 }, style = "hood" }

function R.raider(G, r, ox)
  local def = Raiders.TYPES[r.kind]
  if r.kind == "wolf" then
    R.wolf(r.x + ox, r.y, r.facing, r.anim + (r.state == "jump" and G.time * 6 or 0), r.hurtT > 0, r.rot, r.windup > 0)
    if r.state == "board" and r.work > 0 then
      local bx, by = r.x + ox - 22, r.y - 52
      lg.setColor(0, 0, 0, 0.6); lg.rectangle("fill", bx, by, 44, 6, 2, 2)
      lg.setColor(0.85, 0.85, 0.95); lg.rectangle("fill", bx, by, 44 * math.min(1, r.work / Raiders.workNeed(G, r)), 6, 2, 2)
    end
    return
  end
  local o = {
    coat = RAIDER_LOOK.coat, pants = RAIDER_LOOK.pants, hat = RAIDER_LOOK.hat, skin = RAIDER_LOOK.skin,
    style = "hood", scarf = def.scarf, facing = r.facing, anim = r.anim, moving = math.abs(r.vx) > 5 and r.onGround,
    scale = r.scale, rot = r.rot, flash = r.hurtT > 0, time = G.time, windup = r.windup,
  }
  if r.kind == "brute" then o.coat = { 0.26, 0.22, 0.30 } end
  R.person(r.x + ox, r.y, o)
  if r.loot and r.loot > 0 and r.state ~= "dead" then
    lg.setColor(0.4, 0.3, 0.2); lg.circle("fill", r.x + ox - r.facing * 12, r.y - 34, 8)
  end
  if r.hasPassenger then
    lg.setColor(0.4, 0.5, 0.75); lg.rectangle("fill", r.x + ox - r.facing * 18, r.y - 46, 14, 20, 4, 4)
  end
  if r.state == "board" and r.work > 0 and (r.kind == "saboteur" or r.kind == "snatcher") then
    local need = Raiders.workNeed(G, r)
    local bx, by = r.x + ox - 22, r.y - 78 * r.scale
    lg.setColor(0, 0, 0, 0.6); lg.rectangle("fill", bx, by, 44, 6, 2, 2)
    lg.setColor(def.scarf); lg.rectangle("fill", bx, by, 44 * math.min(1, r.work / need), 6, 2, 2)
    if math.sin(G.time * 10) > 0 then
      lg.setColor(1, 0.3, 0.2); lg.print("!", r.x + ox - 3, by - 20)
    end
  end
end

function R.sled(G, s)
  if s.kind == "wolf" then
    if not s.empty then R.wolf(s.x, Raiders.SLED_Y + 6, 1, s.bob * 1.3, false, 0, false) end
    return
  end
  local x, y = s.x, Raiders.SLED_Y + math.sin(s.bob) * 2
  lg.setColor(0.18, 0.18, 0.2)
  lg.polygon("fill", x - 40, y, x + 30, y, x + 46, y - 12, x - 34, y - 16)
  lg.setColor(0.55, 0.2, 0.15)
  lg.polygon("fill", x + 4, y - 16, x + 40, y - 12, x + 30, y - 28)
  lg.setColor(0.5, 0.5, 0.55)
  lg.setLineWidth(3)
  lg.line(x - 46, y + 8, x + 40, y + 8)
  lg.line(x + 40, y + 8, x + 52, y - 2)
  lg.setLineWidth(1)
  if not s.empty then
    local def = Raiders.TYPES[s.kind]
    local sc = def.scale * 0.9
    lg.setColor(RAIDER_LOOK.coat); lg.rectangle("fill", x - 14 * sc, y - 40 * sc, 20 * sc, 26 * sc, 5, 5)
    lg.setColor(def.scarf); lg.rectangle("fill", x - 14 * sc, y - 42 * sc, 18 * sc, 5, 2, 2)
    lg.setColor(RAIDER_LOOK.hat); lg.circle("fill", x - 3 * sc, y - 48 * sc, 9 * sc)
    lg.setColor(1, 0.3, 0.2); lg.rectangle("fill", x, y - 51 * sc, 7 * sc, 4 * sc)
  end
end

function R.items(G)
  for _, it in ipairs(G.items) do
    local by = it.y - 8 + math.sin(it.t * 4) * 3
    if it.kind == "scrap" then
      lg.push(); lg.translate(it.x, by - 2); lg.rotate(it.t * 1.5)
      lg.setColor(0.62, 0.64, 0.7)
      for k = 0, 5 do lg.rectangle("fill", -2.5, -10, 5, 6, 1, 1); lg.rotate(math.pi / 3) end
      lg.circle("fill", 0, 0, 7)
      lg.setColor(0.25, 0.27, 0.3); lg.circle("fill", 0, 0, 2.5)
      lg.pop()
    else
      lg.setColor(0.45, 0.33, 0.2)
      lg.ellipse("fill", it.x, by, 12, 9)
      lg.setColor(0.07, 0.07, 0.08)
      lg.circle("fill", it.x - 4, by - 6, 4); lg.circle("fill", it.x + 4, by - 7, 3)
    end
  end
end

---------------------------------------------------------------------------
-- Overheads (bridges / tunnels) and depots
---------------------------------------------------------------------------
function R.overheadBack(G)
  for _, o in ipairs(G.overheads) do
    if o.kind == "tunnel" then
      lg.setColor(0.10, 0.09, 0.10)
      lg.rectangle("fill", o.x, 0, o.len, T.RAIL_Y)
    else
      lg.setColor(0.32, 0.32, 0.36)
      lg.rectangle("fill", o.x + 10, T.ROOF_Y - T.OVERHEAD_CLEARANCE, 50, T.RAIL_Y - T.ROOF_Y + T.OVERHEAD_CLEARANCE)
    end
  end
end

function R.overheadFront(G)
  local bottom = T.ROOF_Y - T.OVERHEAD_CLEARANCE
  for _, o in ipairs(G.overheads) do
    if o.kind == "tunnel" then
      -- rock above, darkness over the train inside
      lg.setColor(0.24, 0.22, 0.24)
      lg.rectangle("fill", o.x, 0, o.len, bottom)
      lg.setColor(0.32, 0.30, 0.32)
      for k = 0, math.floor(o.len / 60) do
        local rx = o.x + k * 60
        lg.rectangle("fill", rx + 4, bottom - 20 - (k * 37 + o.seed) % 30, 50, 16, 4, 4)
      end
      lg.setColor(0.85, 0.9, 1)
      lg.rectangle("fill", o.x - 20, 0, o.len + 40, 10)
      lg.setColor(0.45, 0.42, 0.40)
      lg.rectangle("fill", o.x - 24, 0, 24, bottom + 10)
      lg.rectangle("fill", o.x + o.len, 0, 24, bottom + 10)
      lg.setColor(0, 0, 0.02, 0.55)
      lg.rectangle("fill", o.x, bottom, o.len, 720 - bottom)
    else
      lg.setColor(0.42, 0.42, 0.46)
      lg.rectangle("fill", o.x - 10, bottom - 30, o.len + 20, 30)
      lg.setColor(0.30, 0.30, 0.34)
      lg.rectangle("fill", o.x - 10, bottom - 8, o.len + 20, 8)
      lg.setColor(0.85, 0.9, 1)
      lg.rectangle("fill", o.x - 10, bottom - 36, o.len + 20, 6)
      lg.setColor(0.25, 0.25, 0.28)
      lg.rectangle("fill", o.x - 6, bottom - 54, 4, 20); lg.rectangle("fill", o.x + o.len + 2, bottom - 54, 4, 20)
      lg.rectangle("fill", o.x - 8, bottom - 56, o.len + 16, 4)
      lg.setColor(0.36, 0.36, 0.40, 0.92)
      lg.rectangle("fill", o.x + 18, T.RAIL_Y + 20, 34, 100)
      -- hazard stripes
      lg.setColor(0.95, 0.75, 0.15)
      for k = 0, math.floor((o.len + 20) / 20) do
        if k % 2 == 0 then lg.rectangle("fill", o.x - 10 + k * 20, bottom - 8, 10, 8) end
      end
    end
  end
end

function R.depotBack(G)
  local d = G.depot
  if not d then return end
  for tx = d.x + 200, d.x + d.len - 200, 650 do
    lg.setColor(0.22, 0.18, 0.15)
    lg.rectangle("fill", tx - 40, 260, 6, T.RAIL_Y - 260)
    lg.rectangle("fill", tx + 34, 260, 6, T.RAIL_Y - 260)
    lg.setLineWidth(3)
    lg.line(tx - 37, 300, tx + 37, 400); lg.line(tx + 37, 300, tx - 37, 400)
    lg.setLineWidth(1)
    lg.setColor(0.30, 0.22, 0.16)
    lg.polygon("fill", tx - 56, 200, tx + 56, 200, tx + 40, 268, tx - 40, 268)
    lg.setColor(0.85, 0.9, 1)
    lg.rectangle("fill", tx - 58, 194, 116, 8, 3, 3)
    lg.setColor(0.18, 0.15, 0.13)
    lg.polygon("fill", tx + 10, 262, tx + 26, 262, tx + 60, 330, tx + 44, 334)
    lg.setColor(1, 0.85, 0.3)
    lg.print("COAL", tx - 18, 222)
  end
  lg.setColor(0.25, 0.20, 0.16)
  lg.rectangle("fill", d.x, T.FLOOR_Y + 30, d.len, 12)
end

---------------------------------------------------------------------------
-- Additive lights (drawn after the night overlay so they punch through)
---------------------------------------------------------------------------
function R.lights(G)
  lg.setBlendMode("add")
  local warm = { 1, 0.7, 0.35 }
  for i, c in ipairs(T.cars) do
    local x = c.x + R.offsetFor(G, i)
    local ceil = T.CEIL_Y
    if c.kind == "caboose" then
      R.glow(x + 210, ceil + 32, 120, warm, 0.35)
    elseif c.kind == "passenger" then
      R.glow(x + 90, ceil + 22, 110, warm, 0.3)
      R.glow(x + 290, ceil + 22, 110, warm, 0.3)
      local heat = U.clamp(G.stove / 40, 0, 1)
      R.glow(x + c.w / 2, T.FLOOR_Y - 30, 150, { 1, 0.5, 0.2 }, 0.5 * heat)
    elseif c.kind == "cargo" then
      R.glow(x + c.w / 2, ceil + 20, 90, warm, 0.2)
    elseif c.kind == "engine" then
      local heat = U.clamp(G.fuel / 50, 0, 1)
      local flick = 0.85 + 0.15 * math.sin(G.time * 23)
      R.glow(T.FURNACE_X, T.FLOOR_Y - 46, 170, { 1, 0.45, 0.15 }, 0.6 * heat * flick)
      local hx, hy = x + c.w + 8, T.ROOF_Y + 33
      lg.setColor(1, 0.95, 0.7, 0.12)
      lg.polygon("fill", hx, hy - 6, hx + 700, hy - 120, hx + 700, hy + 160, hx, hy + 6)
      R.glow(hx, hy, 60, { 1, 0.95, 0.7 }, 0.8)
    end
  end
  if G.depot then
    for tx = G.depot.x + 200, G.depot.x + G.depot.len - 200, 650 do
      R.glow(tx, 196, 90, { 1, 0.8, 0.4 }, 0.5)
    end
  end
  if G.fire then
    local k = G.fire.intensity / 100
    R.glow(G.fire.x, T.FLOOR_Y - 30, 120 + 120 * k, { 1, 0.45, 0.1 }, 0.4 + 0.4 * k * (0.85 + 0.15 * math.sin(G.time * 19)))
  end
  if G.boss then
    R.glow(G.boss.x + 292, 640, 60, { 1, 0.2, 0.1 }, 0.8)
    R.glow(G.boss.x + 130, 632, 40, { 1, 0.2, 0.1 }, 0.6 + 0.3 * math.sin(G.time * 5))
  end
  if G.haven then
    local hx = G.haven.x
    for k = 0, 9 do R.glow(hx + 150 + k * 260, 300, 110, { 1, 0.75, 0.4 }, 0.45) end
    R.glow(hx + 1300, 150, 260, { 1, 0.8, 0.4 }, 0.6)
  end
  lg.setBlendMode("alpha")
end

---------------------------------------------------------------------------
-- Wolves
---------------------------------------------------------------------------
function R.wolf(x, y, facing, anim, flash, rot, snarl)
  lg.push()
  lg.translate(x, y)
  if rot and rot ~= 0 then lg.translate(0, -18); lg.rotate(rot); lg.translate(0, 18) end
  lg.scale(facing or 1, 1)
  local fur = flash and { 1, 1, 1 } or { 0.55, 0.57, 0.63 }
  local dark = flash and { 1, 1, 1 } or { 0.38, 0.40, 0.46 }
  local a = math.sin(anim * 2)
  lg.setColor(dark)
  lg.rectangle("fill", -15 + a * 4, -15, 5, 15, 2, 2)
  lg.rectangle("fill", 9 - a * 4, -15, 5, 15, 2, 2)
  lg.setColor(fur)
  lg.rectangle("fill", -10 - a * 4, -15, 5, 15, 2, 2)
  lg.rectangle("fill", 14 + a * 4, -15, 5, 15, 2, 2)
  lg.ellipse("fill", 0, -20, 21, 9)
  lg.polygon("fill", -18, -24, -36, -30 + a * 3, -32, -19)
  lg.ellipse("fill", 21, -27, 9, 7)
  lg.polygon("fill", 25, -30, 38, -25, 26, -21)
  lg.polygon("fill", 15, -31, 18, -40, 22, -31)
  lg.setColor(1, 0.85, 0.2)
  lg.circle("fill", 24, -29, 1.6)
  if snarl then lg.setColor(1, 1, 1); lg.polygon("fill", 30, -24, 33, -21, 35, -24) end
  lg.pop()
end

---------------------------------------------------------------------------
-- Hazards
---------------------------------------------------------------------------
function R.hazards(G)
  -- snow drift burying a gap
  if G.snow then
    local g = G.snow.gap
    local a = T.cars[g].x + T.CAR_W - 8
    local w = T.GAP + 16
    local k = 0.45 + 0.55 * G.snow.hp / 100
    local top = T.FLOOR_Y - (T.FLOOR_Y - T.ROOF_Y + 20) * k
    lg.setColor(0.9, 0.94, 1)
    lg.rectangle("fill", a, top + 14, w, T.FLOOR_Y + 8 - top - 14, 6, 6)
    lg.ellipse("fill", a + w * 0.3, top + 16, w * 0.4, 16)
    lg.ellipse("fill", a + w * 0.7, top + 10, w * 0.45, 18)
    lg.setColor(0.75, 0.82, 0.95)
    lg.rectangle("fill", a + 6, T.FLOOR_Y - 10, w - 12, 6, 3, 3)
  end
  -- scorch under a fire
  if G.fire then
    lg.setColor(0.05, 0.03, 0.02, 0.6)
    lg.ellipse("fill", G.fire.x, T.FLOOR_Y + 2, 30 + G.fire.intensity * 0.3, 6)
  end
end

function R.trackDamage(G)
  local tr = G.track
  if not tr then return end
  local x = tr.x
  lg.setColor(0.12, 0.1, 0.1)
  lg.rectangle("fill", x - 30, T.RAIL_Y - 4, 60, 10)
  lg.setColor(0.55, 0.55, 0.6)
  lg.polygon("fill", x - 30, T.RAIL_Y - 2, x - 6, T.RAIL_Y - 2, x - 10, T.RAIL_Y - 12)
  lg.polygon("fill", x + 30, T.RAIL_Y - 2, x + 8, T.RAIL_Y - 2, x + 14, T.RAIL_Y + 6)
  for _, fx in ipairs({ x - 70, x + 60 }) do
    lg.setColor(0.35, 0.3, 0.25); lg.rectangle("fill", fx, T.RAIL_Y - 60, 4, 60)
    lg.setColor(0.95, 0.2, 0.15)
    local wave = math.sin(G.time * 8 + fx) * 3
    lg.polygon("fill", fx + 4, T.RAIL_Y - 60, fx + 26, T.RAIL_Y - 54 + wave, fx + 4, T.RAIL_Y - 46)
  end
end

---------------------------------------------------------------------------
-- The Iron Jaw (boss), its chains and projectiles
---------------------------------------------------------------------------
function R.boss(G)
  local b = G.boss
  if not b then return end
  local x = b.x
  local fl = b.flash > 0
  local function c(r, g, bl) if fl then lg.setColor(1, 0.9, 0.85) else lg.setColor(r, g, bl) end end
  -- smokestacks
  c(0.12, 0.11, 0.12)
  lg.rectangle("fill", x - 200, 548, 24, 50); lg.rectangle("fill", x - 158, 556, 22, 42)
  -- treads
  c(0.07, 0.07, 0.08)
  lg.rectangle("fill", x - Boss.HALF, 686, Boss.HALF * 2, 32, 14, 14)
  c(0.22, 0.22, 0.24)
  local off = (G.time * 160) % 30
  for k = 0, math.floor(Boss.HALF * 2 / 30) do
    local cx = x - Boss.HALF + 6 + ((k * 30 - off) % (Boss.HALF * 2 - 12))
    lg.rectangle("fill", cx, 688, 6, 4)
    lg.rectangle("fill", cx, 712, 6, 4)
  end
  for k = 0, 8 do
    c(0.16, 0.16, 0.18)
    lg.circle("fill", x - Boss.HALF + 30 + k * ((Boss.HALF * 2 - 60) / 8), 702, 11)
  end
  -- hull
  c(0.21, 0.20, 0.22)
  lg.polygon("fill", x - 292, 688, x - 300, 626, x - 250, 594, x + 220, 594, x + 300, 640, x + 300, 688)
  c(0.15, 0.14, 0.16)
  for px = x - 250, x + 200, 75 do lg.rectangle("fill", px, 600, 3, 86) end
  c(0.38, 0.36, 0.38)
  for px = x - 280, x + 280, 26 do lg.circle("fill", px, 672, 2) end
  -- ram spikes
  c(0.55, 0.55, 0.58)
  for k = 0, 2 do
    local sy = 646 + k * 14
    lg.polygon("fill", x + 298, sy - 6, x + 336, sy, x + 298, sy + 6)
  end
  -- the jaw emblem
  c(0.75, 0.15, 0.12)
  lg.polygon("fill", x + 90, 612, x + 170, 612, x + 180, 640, x + 160, 668, x + 100, 668, x + 80, 640)
  c(0.95, 0.92, 0.85)
  for k = 0, 4 do
    local tx = x + 100 + k * 14
    lg.polygon("fill", tx, 648, tx + 12, 648, tx + 6, 660)
  end
  c(0.08, 0.06, 0.06)
  lg.circle("fill", x + 112, 628, 7); lg.circle("fill", x + 150, 628, 7)
  -- turret + harpoon gun
  c(0.17, 0.16, 0.18)
  lg.arc("fill", x - 40, 596, 34, math.pi, math.pi * 2)
  lg.push(); lg.translate(x - 40, 580); lg.rotate(b.aim or -0.5)
  c(0.3, 0.3, 0.33); lg.rectangle("fill", 0, -6, 58, 12, 3, 3)
  lg.pop()
  -- name plate
  c(0.85, 0.75, 0.3)
  lg.rectangle("fill", x - 120, 640, 120, 22, 3, 3)
  lg.setColor(0.15, 0.1, 0.05)
  lg.print("IRON  JAW", x - 108, 643)
end


function R.chains(G)
  local b = G.boss
  if not b then return end
  local ax, ay = b.x - 40, 586
  for _, h in ipairs(G.hooks) do
    local hx, hy = h.x, T.FLOOR_Y + 14
    local dx, dy = hx - ax, hy - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local n = math.floor(len / 14)
    lg.setColor(0.45, 0.45, 0.5)
    lg.setLineWidth(2)
    for k = 0, n do
      local u = k / math.max(1, n)
      local sag = math.sin(u * math.pi) * 18
      lg.ellipse("line", ax + dx * u, ay + dy * u + sag, 5, 3)
    end
    lg.setLineWidth(1)
    lg.setColor(0.6, 0.6, 0.65)
    lg.polygon("fill", hx - 10, hy - 6, hx + 10, hy - 6, hx, hy + 8)
    lg.setColor(0.9, 0.2, 0.15, 0.6 + 0.4 * math.sin(G.time * 8))
    lg.circle("fill", hx, hy - 10, 3)
  end
end

function R.projectiles(G)
  for _, p in ipairs(G.projectiles) do
    if p.kind == "harpoon" then
      local cx, cy = U.lerp(p.x0, p.x1, p.t), U.lerp(p.y0, p.y1, p.t)
      lg.setColor(0.5, 0.5, 0.55)
      lg.line(p.x0, p.y0, cx, cy)
      lg.setColor(0.75, 0.75, 0.8)
      lg.circle("fill", cx, cy, 5)
    else
      lg.push(); lg.translate(p.x, p.y); lg.rotate(p.rot)
      lg.setColor(0.8, 0.15, 0.12)
      lg.rectangle("fill", -9, -4, 18, 8, 2, 2)
      lg.setColor(1, 0.85, 0.3); lg.circle("fill", 10, -2, 2.5)
      lg.pop()
    end
  end
end

---------------------------------------------------------------------------
-- Haven station (win sequence)
---------------------------------------------------------------------------
function R.havenBack(G)
  local h = G.haven
  if not h then return end
  local x = h.x
  -- city wall + towers
  lg.setColor(0.22, 0.2, 0.24)
  lg.rectangle("fill", x, 230, 2700, T.RAIL_Y - 230)
  for k = 0, 9 do
    local tx = x + 60 + k * 270
    lg.setColor(0.26, 0.24, 0.28)
    lg.rectangle("fill", tx, 170, 90, 120)
    lg.setColor(0.88, 0.92, 1)
    lg.rectangle("fill", tx - 4, 164, 98, 8, 3, 3)
    lg.setColor(1, 0.8, 0.45)
    lg.rectangle("fill", tx + 30, 200, 14, 22, 3, 3)
    lg.rectangle("fill", tx + 52, 200, 14, 22, 3, 3)
  end
  -- the gate sign
  lg.setColor(0.35, 0.22, 0.14)
  lg.rectangle("fill", x + 1150, 110, 300, 70, 8, 8)
  lg.setColor(1, 0.85, 0.5)
  lg.setFont(R.fonts and R.fonts.big or lg.getFont())
  lg.printf("HAVEN", x + 1150, 122, 300, "center")
  lg.setFont(R.fonts and R.fonts.small or lg.getFont())
end

function R.havenFront(G)
  local h = G.haven
  if not h then return end
  for k = 0, 22 do
    local px = h.x + 120 + k * 115
    local wave = math.sin(G.time * 6 + k) * 0.6
    local col = k % 3 == 0 and { 0.75, 0.35, 0.3 } or (k % 3 == 1 and { 0.3, 0.45, 0.7 } or { 0.45, 0.6, 0.35 })
    lg.setColor(col)
    lg.rectangle("fill", px - 7, 668, 14, 24, 4, 4)
    lg.setColor(0.95, 0.8, 0.65)
    lg.circle("fill", px, 662, 6)
    lg.setColor(col)
    lg.push(); lg.translate(px + 5, 672); lg.rotate(-1.9 + wave)
    lg.rectangle("fill", 0, -2, 14, 4, 2, 2)
    lg.pop()
  end
end

return R
