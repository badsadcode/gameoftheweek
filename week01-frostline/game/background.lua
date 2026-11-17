-- background.lua : sky, stars, aurora, mountains, trees, snowfield, rails, poles, falling snow.
local U = require("util")
local T = require("train")
local lg = love.graphics

local BG = {}
local VW, VH = 1280, 720
local W = 2400 -- repeat width for parallax layers

local layers, trees, stars, flakes = {}, {}, {}, {}

-- sum of integer-frequency sines: wraps seamlessly over W
local function ridge(n, base, amp, seed)
  local rng = love.math.newRandomGenerator(seed)
  local waves = {}
  for i = 1, 6 do
    waves[i] = { f = rng:random(1, 3 * i), a = amp / (i * 1.1), ph = rng:random() * math.pi * 2 }
  end
  local pts = {}
  for i = 0, n do
    local u = i / n
    local y = base
    for _, w in ipairs(waves) do y = y - w.a * math.abs(math.sin(u * math.pi * w.f + w.ph)) end
    pts[i] = y
  end
  return pts
end

function BG.load()
  layers.far = { pts = ridge(160, 470, 70, 7), n = 160, f = 0.03 }
  layers.mid = { pts = ridge(120, 515, 30, 21), n = 120, f = 0.12 }
  local rng = love.math.newRandomGenerator(99)
  for i = 1, 70 do
    trees[i] = { x = rng:random() * W, h = 30 + rng:random() * 55, f = 0.4 + rng:random() * 0.3 }
  end
  table.sort(trees, function(a, b) return a.f < b.f end)
  for i = 1, 160 do
    stars[i] = { x = rng:random() * VW, y = rng:random() * 380, s = rng:random() * 1.6 + 0.4, tw = rng:random() * 6 }
  end
  for i = 1, 260 do
    flakes[i] = { x = rng:random() * VW, y = rng:random() * VH, z = 0.3 + rng:random() * 0.7 }
  end
end

-- day/night palette keyed by journey progress (dusk -> night -> dawn at Haven)
local SKY_TOP = {
  { 0.00, { 0.20, 0.12, 0.30 } }, { 0.15, { 0.05, 0.05, 0.15 } }, { 0.50, { 0.01, 0.02, 0.07 } },
  { 0.85, { 0.10, 0.10, 0.25 } }, { 1.00, { 0.30, 0.42, 0.68 } },
}
local SKY_BOT = {
  { 0.00, { 0.90, 0.48, 0.40 } }, { 0.15, { 0.28, 0.20, 0.40 } }, { 0.50, { 0.07, 0.11, 0.22 } },
  { 0.85, { 0.55, 0.33, 0.45 } }, { 1.00, { 1.00, 0.75, 0.50 } },
}
function BG.night(p)
  if p < 0.12 then return U.lerp(0.15, 0.5, p / 0.12) end
  if p < 0.8 then return 0.5 end
  return U.lerp(0.5, 0.0, (p - 0.8) / 0.2)
end
function BG.light(p) return 1 - BG.night(p) * 1.2 end

function BG.skyColor(p) return U.gradient(SKY_BOT, p) end

local function drawSky(p, time)
  local top, bot = U.gradient(SKY_TOP, p), U.gradient(SKY_BOT, p)
  local bands = 28
  for i = 0, bands - 1 do
    local c = U.lerpColor(top, bot, (i / (bands - 1)) ^ 1.4)
    lg.setColor(c)
    lg.rectangle("fill", 0, i * (560 / bands), VW, 560 / bands + 1)
  end
  -- stars
  local starA = U.clamp((BG.night(p) - 0.2) / 0.3, 0, 1)
  if starA > 0 then
    for _, s in ipairs(stars) do
      local a = starA * (0.6 + 0.4 * math.sin(time * 2 + s.tw))
      lg.setColor(1, 1, 1, a)
      lg.circle("fill", s.x, s.y, s.s)
    end
  end
  -- aurora in the deep night
  local aur = U.clamp(1 - math.abs(p - 0.5) / 0.22, 0, 1)
  if aur > 0 then
    lg.setBlendMode("add")
    for band = 1, 2 do
      for i = 0, 70 do
        local x = i * 19
        local y = 90 + band * 40 + math.sin(i * 0.12 + time * 0.3 + band) * 35 + math.sin(i * 0.05 - time * 0.2) * 25
        local a = aur * 0.06 * (0.6 + 0.4 * math.sin(i * 0.3 + time + band))
        local g = band == 1 and { 0.3, 1.0, 0.6 } or { 0.5, 0.4, 1.0 }
        for k = 0, 3 do
          lg.setColor(g[1], g[2], g[3], a * (1 - k * 0.22))
          lg.rectangle("fill", x, y + k * 22, 20, 26)
        end
      end
    end
    lg.setBlendMode("alpha")
  end
  -- moon
  local moonA = U.clamp(BG.night(p) * 2, 0, 1)
  if moonA > 0 then
    lg.setColor(0.95, 0.95, 0.85, 0.08 * moonA)
    lg.circle("fill", 1020, 110, 70)
    lg.setColor(0.95, 0.95, 0.88, moonA)
    lg.circle("fill", 1020, 110, 30)
    lg.setColor(0.8, 0.8, 0.75, moonA * 0.5)
    lg.circle("fill", 1010, 102, 6); lg.circle("fill", 1030, 118, 4)
  end
  -- sunrise glow at the end
  if p > 0.85 then
    local a = (p - 0.85) / 0.15
    lg.setColor(1, 0.85, 0.5, a)
    lg.circle("fill", 900, 520, 60)
  end
end

local function drawRidge(L, off, color, bottom)
  local sw = W / L.n
  lg.setColor(color)
  for copy = 0, 1 do
    local base = copy * W - off
    for i = 0, L.n - 1 do
      local x1 = base + i * sw
      if x1 < VW and x1 + sw > 0 then
        local x2 = x1 + sw
        lg.polygon("fill", x1, L.pts[i], x2, L.pts[i + 1], x2, bottom, x1, bottom)
      end
    end
  end
end

local function tree(x, y, h, c)
  lg.setColor(c)
  lg.rectangle("fill", x - 2, y - h * 0.2, 4, h * 0.2)
  for k = 0, 2 do
    local w = h * (0.42 - k * 0.1)
    local ty = y - h * 0.15 - k * h * 0.27
    lg.polygon("fill", x - w, ty, x + w, ty, x, ty - h * 0.45)
  end
end

-- draws everything behind the train (screen space, uses scroll/camera)
function BG.drawBack(G)
  local p, light = G.progress, BG.light(G.progress)
  local scroll, camX = G.scroll, G.camX
  drawSky(p, G.time)

  local function tint(c, k) local l = U.lerp(light, 1, k or 0); return { c[1] * l, c[2] * l, c[3] * l, c[4] or 1 } end
  drawRidge(layers.far, (scroll * layers.far.f + camX * 0.05) % W, tint({ 0.36, 0.40, 0.58 }, 0.3), 560)
  drawRidge(layers.mid, (scroll * layers.mid.f + camX * 0.15) % W, tint({ 0.55, 0.62, 0.76 }, 0.2), 560)
  -- snowfield
  lg.setColor(tint({ 0.80, 0.86, 0.95 }, 0.15))
  lg.rectangle("fill", 0, 520, VW, VH - 520)
  for _, t in ipairs(trees) do
    local x = (t.x - (scroll * t.f + camX * t.f)) % W - 100
    if x > -100 and x < VW + 100 then
      local dark = U.lerp(0.55, 0.2, t.f)
      tree(x, 548 + t.f * 18, t.h * (0.6 + t.f * 0.6), tint({ 0.10 + dark * 0.2, 0.22 + dark * 0.25, 0.28 + dark * 0.3 }, 0.1))
    end
  end
end

-- poles, ground and rails are in train space (drawn under camera transform)
function BG.drawTrack(G)
  local light = BG.light(G.progress)
  local camX, scroll = G.camX, G.scroll
  local x0, x1 = camX - 200, camX + VW + 200
  -- telegraph poles behind the train
  local spacing = 520
  local off = scroll % spacing
  lg.setColor(0.12 * light + 0.05, 0.10 * light + 0.05, 0.10 * light + 0.06)
  local first = math.floor((x0 + off) / spacing) * spacing - off
  local prev
  for x = first, x1, spacing do
    lg.rectangle("fill", x - 4, 330, 8, 260)
    lg.rectangle("fill", x - 26, 342, 52, 5)
    if prev then
      lg.setLineWidth(1.5)
      local pts = {}
      for k = 0, 10 do
        local u = k / 10
        pts[#pts + 1] = U.lerp(prev, x, u)
        pts[#pts + 1] = 344 + math.sin(u * math.pi) * 26
      end
      lg.line(pts)
      lg.setLineWidth(1)
    end
    prev = x
  end
  -- gravel bed + rails
  lg.setColor(0.25 * light + 0.08, 0.24 * light + 0.08, 0.27 * light + 0.1)
  lg.rectangle("fill", x0, T.RAIL_Y, x1 - x0, 22)
  local tieOff = scroll % 34
  lg.setColor(0.22 * light + 0.06, 0.16 * light + 0.05, 0.12 * light + 0.04)
  for x = math.floor(x0 / 34) * 34 - tieOff, x1, 34 do
    lg.rectangle("fill", x, T.RAIL_Y + 2, 18, 8)
  end
  lg.setColor(0.55 * light + 0.15, 0.55 * light + 0.15, 0.6 * light + 0.18)
  lg.rectangle("fill", x0, T.RAIL_Y - 2, x1 - x0, 4)
end

-- snowbanks in front of everything
function BG.drawFront(G)
  local light = BG.light(G.progress)
  local off = (G.scroll * 1.5 + G.camX * 1.5) % 900
  lg.setColor(0.86 * U.lerp(light, 1, 0.3), 0.9 * U.lerp(light, 1, 0.3), 0.98 * U.lerp(light, 1, 0.3))
  lg.rectangle("fill", 0, 704, VW, 16)
  for k = -1, 2 do
    local bx = k * 900 - off
    lg.ellipse("fill", bx + 200, 712, 180, 22)
    lg.ellipse("fill", bx + 560, 716, 240, 18)
    lg.ellipse("fill", bx + 820, 710, 120, 20)
  end
end

function BG.updateSnow(G, dt)
  local wind = G.speed * 7 + 40 + G.blizzard * 500
  for _, f in ipairs(flakes) do
    f.x = f.x - wind * f.z * dt
    f.y = f.y + (40 + 70 * f.z + G.blizzard * 120) * dt + math.sin(G.time * 2 + f.z * 10) * 10 * dt
    if f.x < -10 then f.x = f.x + VW + 20; f.y = love.math.random() * VH end
    if f.y > VH + 10 then f.y = -10; f.x = love.math.random() * VW end
  end
end

function BG.drawSnow(G)
  local count = math.floor(#flakes * (0.45 + 0.55 * G.blizzard))
  local streak = G.speed * 0.08 + G.blizzard * 18
  for i = 1, count do
    local f = flakes[i]
    lg.setColor(1, 1, 1, 0.35 + 0.5 * f.z)
    local s = f.z * 2.4
    lg.rectangle("fill", f.x, f.y, s + streak * f.z, s)
  end
  if G.blizzard > 0 then
    lg.setColor(0.85, 0.9, 1, G.blizzard * 0.28)
    lg.rectangle("fill", 0, 0, VW, VH)
  end
end

return BG
