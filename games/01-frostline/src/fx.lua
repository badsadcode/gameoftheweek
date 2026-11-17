-- fx.lua : game feel. Hit-stop, floating text, camera punch, white flash.
--   FX.hitstop(G, seconds)   freeze the simulation for a moment on impacts
--   FX.float(G, x, y, text, color)   "+2 coal" style text that rises in train space
--   FX.punch(G, amount)      quick camera zoom-in that springs back
--   FX.whiteout(G, amount)   white screen flash (boss destroyed, etc.)
local FX = {}
local lg = love.graphics

function FX.init(G)
  G.floats = {}
  G.hitstop = 0
  G.punch = 0
  G.whiteout = 0
end

function FX.hitstop(G, t) G.hitstop = math.max(G.hitstop or 0, t) end
function FX.punch(G, a) G.punch = math.max(G.punch or 0, a) end
function FX.whiteout(G, a) G.whiteout = math.max(G.whiteout or 0, a) end

function FX.float(G, x, y, text, color)
  -- nudge up if another float is already right there, so they stack instead of overlapping
  for _, f in ipairs(G.floats) do
    if math.abs(f.x - x) < 40 and math.abs(f.y - y) < 18 and f.t < 0.3 then y = y - 20 end
  end
  G.floats[#G.floats + 1] = { x = x, y = y, text = text, color = color or { 1, 1, 1 }, t = 0, life = 1.3 }
end

function FX.update(G, dt)
  for i = #G.floats, 1, -1 do
    local f = G.floats[i]
    f.t = f.t + dt
    f.y = f.y - 38 * dt
    if f.t >= f.life then table.remove(G.floats, i) end
  end
  G.punch = math.max(0, G.punch - dt * 0.35)
  G.whiteout = math.max(0, G.whiteout - dt * 1.4)
end

-- train space (call under the camera transform)
function FX.drawFloats(G, font)
  lg.setFont(font)
  for _, f in ipairs(G.floats) do
    local a = math.min(1, (f.life - f.t) / 0.4)
    local pop = 1 + math.max(0, 0.35 - f.t) * 1.4 -- pops in big, settles
    local w = font:getWidth(f.text)
    lg.push()
    lg.translate(f.x, f.y)
    lg.scale(pop, pop)
    lg.setColor(0, 0, 0, 0.6 * a)
    lg.print(f.text, -w / 2 + 2, 2)
    lg.setColor(f.color[1], f.color[2], f.color[3], a)
    lg.print(f.text, -w / 2, 0)
    lg.pop()
  end
end

return FX
