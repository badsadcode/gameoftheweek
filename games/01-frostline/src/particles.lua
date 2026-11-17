-- particles.lua : smoke, sparks, coal bits, snow spray (all in train space)
local Particles = {}
local lg = love.graphics

-- p = {x, y, vx, vy, life, size, grow, drag, g, color, alpha, add, layer, square}
function Particles.add(G, p)
  p.life = p.life or 1
  p.max = p.life
  p.size = p.size or 3
  p.grow = p.grow or 0
  p.drag = p.drag or 0
  p.g = p.g or 0
  p.alpha = p.alpha or 1
  p.layer = p.layer or "front"
  p.color = p.color or { 1, 1, 1 }
  local ps = G.particles
  ps[#ps + 1] = p
end

function Particles.burst(G, x, y, n, opts)
  for _ = 1, n do
    local a = love.math.random() * math.pi * 2
    local s = (opts.speed or 150) * (0.4 + love.math.random() * 0.6)
    Particles.add(G, {
      x = x, y = y, vx = math.cos(a) * s + (opts.vx or 0), vy = math.sin(a) * s + (opts.vy or 0),
      life = (opts.life or 0.5) * (0.6 + love.math.random() * 0.6), size = opts.size or 2.5,
      g = opts.g or 600, drag = opts.drag or 1, color = opts.color, add = opts.add, square = opts.square,
      layer = opts.layer,
    })
  end
end

function Particles.update(G, dt)
  local ps = G.particles
  local i = 1
  while i <= #ps do
    local p = ps[i]
    p.life = p.life - dt
    if p.life <= 0 then
      ps[i] = ps[#ps]; ps[#ps] = nil
    else
      p.vy = p.vy + p.g * dt
      local k = math.max(0, 1 - p.drag * dt)
      p.vx, p.vy = p.vx * k, p.vy * k
      p.x = p.x + p.vx * dt
      p.y = p.y + p.vy * dt
      p.size = p.size + p.grow * dt
      i = i + 1
    end
  end
end

function Particles.draw(G, layer, additive)
  for _, p in ipairs(G.particles) do
    if p.layer == layer and (p.add or false) == additive then
      local c = p.color
      local a = p.alpha * (p.life / p.max)
      lg.setColor(c[1], c[2], c[3], a)
      if p.square then
        lg.rectangle("fill", p.x - p.size / 2, p.y - p.size / 2, p.size, p.size)
      else
        lg.circle("fill", p.x, p.y, p.size)
      end
    end
  end
end

return Particles
