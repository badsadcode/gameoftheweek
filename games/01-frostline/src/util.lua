-- util.lua : tiny math helpers used everywhere
local U = {}

function U.clamp(v, a, b)
  if v < a then return a elseif v > b then return b end
  return v
end

function U.lerp(a, b, t) return a + (b - a) * t end

function U.sign(v)
  if v > 0 then return 1 elseif v < 0 then return -1 end
  return 0
end

-- move v toward target by at most step
function U.approach(v, target, step)
  if v < target then return math.min(v + step, target) end
  return math.max(v - step, target)
end

function U.rand(a, b) return a + love.math.random() * (b - a) end

-- weighted pick from a list of {key, weight}
function U.pick(list)
  local total = 0
  for _, e in ipairs(list) do total = total + e[2] end
  local r = love.math.random() * total
  for _, e in ipairs(list) do
    r = r - e[2]
    if r <= 0 and e[2] > 0 then return e[1] end
  end
  return list[1][1]
end

function U.lerpColor(a, b, t)
  return { U.lerp(a[1], b[1], t), U.lerp(a[2], b[2], t), U.lerp(a[3], b[3], t), U.lerp(a[4] or 1, b[4] or 1, t) }
end

-- keys = { {pos, color}, ... } sorted by pos; returns interpolated color at p
function U.gradient(keys, p)
  if p <= keys[1][1] then return keys[1][2] end
  for i = 1, #keys - 1 do
    local a, b = keys[i], keys[i + 1]
    if p <= b[1] then return U.lerpColor(a[2], b[2], (p - a[1]) / (b[1] - a[1])) end
  end
  return keys[#keys][2]
end

return U
