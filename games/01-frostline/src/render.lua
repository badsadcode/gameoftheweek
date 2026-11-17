-- render.lua : procedural drawing of the train, people, sleds, bridges, depots and lights.
-- Everything here draws in train space (the caller applies the camera transform).
local T = require("train")
local U = require("util")
local Raiders = require("raiders")
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
  if o.carry then
    lg.setColor(0.07, 0.07, 0.08)
    lg.circle("fill", 15, -34, 8)
    lg.circle("fill", 21, -36, 6)
    lg.setColor(0.5, 0.5, 0.6)
    lg.circle("fill", 13, -37, 1.6)
  end
  lg.pop()
end

local function seatedPassenger(x, y, i, cold, t)
  local looks = {
    { 0.35, 0.45, 0.70 }, { 0.70, 0.35, 0.45 }, { 0.40, 0.60, 0.40 }, { 0.60, 0.55, 0.35 },
    { 0.55, 0.40, 0.65 }, { 0.30, 0.55, 0.60 }, { 0.70, 0.50, 0.30 }, { 0.45, 0.45, 0.50 },
  }
  local c = looks[i]
  local shiver = cold > 0 and math.sin(t * 45 + i) * 1.4 * cold or 0
  local blue = cold * 0.5
  x = x + shiver
  local small = (i % 4 == 3) and 0.75 or 1
  lg.setColor(U.lerp(c[1], 0.5, blue), U.lerp(c[2], 0.65, blue), U.lerp(c[3], 0.95, blue))
  lg.rectangle("fill", x - 9 * small, y - 26 * small, 18 * small, 26 * small, 5, 5)
  lg.setColor(U.lerp(0.95, 0.7, blue), U.lerp(0.78, 0.8, blue), U.lerp(0.65, 0.95, blue))
  lg.circle("fill", x, y - 33 * small, 7 * small)
  lg.setColor(0.2 + (i % 3) * 0.15, 0.15, 0.1)
  lg.arc("fill", x, y - 34 * small, 7.5 * small, math.pi, math.pi * 2)
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
    local seats = { 40, 72, 104, 136, 244, 276, 308, 340 }
    for i = 1, G.passengers do seatedPassenger(x + seats[i], floor - 18, i, cold, G.time) end
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
    local need = r.kind == "saboteur" and 9 or 6.5
    local bx, by = r.x + ox - 22, r.y - 78 * r.scale
    lg.setColor(0, 0, 0, 0.6); lg.rectangle("fill", bx, by, 44, 6, 2, 2)
    lg.setColor(def.scarf); lg.rectangle("fill", bx, by, 44 * math.min(1, r.work / need), 6, 2, 2)
    if math.sin(G.time * 10) > 0 then
      lg.setColor(1, 0.3, 0.2); lg.print("!", r.x + ox - 3, by - 20)
    end
  end
end

function R.sled(G, s)
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
    lg.setColor(0.45, 0.33, 0.2)
    lg.ellipse("fill", it.x, by, 12, 9)
    lg.setColor(0.07, 0.07, 0.08)
    lg.circle("fill", it.x - 4, by - 6, 4); lg.circle("fill", it.x + 4, by - 7, 3)
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
  lg.setBlendMode("alpha")
end

return R
