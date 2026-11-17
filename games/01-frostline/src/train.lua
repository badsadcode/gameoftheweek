-- train.lua : geometry of the train + the shared body physics.
-- Coordinates are "train space": x = 0 at the rear of the caboose, increasing toward the engine.
-- y grows downward (LÖVE default). Bodies store their FEET position.
local T = {}

T.CAR_W    = 380
T.GAP      = 56
T.ROOF_Y   = 384   -- feet height when standing on a roof
T.CEIL_Y   = 404   -- underside of the roof (inside ceiling)
T.FLOOR_Y  = 560   -- feet height inside cars / on platforms between cars
T.RAIL_Y   = 632
T.PERSON_H = 56
T.GRAVITY  = 1800
T.OVERHEAD_CLEARANCE = 44 -- bridges/tunnels hang this far above the roof

T.KINDS = { "caboose", "passenger", "cargo", "tender", "engine" }
T.cars = {}
for i, kind in ipairs(T.KINDS) do
  T.cars[i] = { index = i, kind = kind, x = (i - 1) * (T.CAR_W + T.GAP), w = T.CAR_W }
end
T.LENGTH = T.cars[#T.cars].x + T.CAR_W

-- points of interest
local eng = T.cars[5]
T.CAB_END   = eng.x + 190               -- inside the engine you can only walk the cab
T.LEVER_X   = eng.x + 42
T.FURNACE_X = eng.x + 140
T.COAL_X    = T.cars[4].x + T.CAR_W / 2
T.STOVE_X   = T.cars[2].x + T.CAR_W / 2
T.MEDKIT_X  = T.cars[1].x + 70
T.DYNAMITE_X = T.cars[3].x + 60         -- crate in the cargo car (boss fight)
T.TRADER_X  = T.cars[3].x + T.CAR_W / 2 + 60

-- index of the rear-most car still attached (raiders can uncouple cars)
T.firstAttached = 1
-- gap index buried by an avalanche (blocks walking between those two cars), or nil
T.blockedGap = nil

function T.reset() T.firstAttached = 1; T.blockedGap = nil end
function T.minX() return T.cars[T.firstAttached].x end

function T.carAt(x)
  for i = T.firstAttached, #T.cars do
    local c = T.cars[i]
    if x >= c.x and x <= c.x + c.w then return c end
  end
end

-- gap g sits between car g and car g+1
function T.gapAt(x)
  for g = T.firstAttached, #T.cars - 1 do
    local a = T.cars[g].x + T.CAR_W
    if x > a and x < a + T.GAP then return g end
  end
end

function T.gapCenter(g) return T.cars[g].x + T.CAR_W + T.GAP / 2 end

function T.nearestGap(x)
  local best, bd
  for g = T.firstAttached, #T.cars - 1 do
    local d = math.abs(T.gapCenter(g) - x)
    if not bd or d < bd then best, bd = g, d end
  end
  return best
end

function T.levelOf(b)
  if b.climbing then return "ladder" end
  if b.y <= T.ROOF_Y + 2 then return "roof" end
  return "floor"
end

-- Integrates a body {x, y, vx, vy, onGround}: roofs, floor, ceilings, train ends.
function T.stepBody(b, dt)
  b.vy = b.vy + T.GRAVITY * dt
  local nx = b.x + b.vx * dt
  local lo = T.minX() + 12
  local hi = (b.y > T.ROOF_Y + 10) and (T.CAB_END - 12) or (T.LENGTH - 12)
  if nx < lo then nx = lo; b.vx = 0 elseif nx > hi then nx = hi; b.vx = 0 end
  -- a snow-buried gap is a wall at floor level
  local bg = T.blockedGap
  if bg and bg >= T.firstAttached and b.y > T.ROOF_Y + 10 then
    local a = T.cars[bg].x + T.CAR_W - 6
    local z = T.cars[bg + 1].x + 6
    if b.x <= a and nx > a then nx = a; b.vx = 0
    elseif b.x >= z and nx < z then nx = z; b.vx = 0 end
  end
  b.x = nx

  local ny = b.y + b.vy * dt
  local car = T.carAt(b.x)
  b.onGround = false
  if car and b.y <= T.ROOF_Y + 0.5 and ny >= T.ROOF_Y and b.vy >= 0 then
    ny = T.ROOF_Y; b.vy = 0; b.onGround = true
  elseif ny >= T.FLOOR_Y then
    ny = T.FLOOR_Y; b.vy = 0; b.onGround = true
  end
  -- bump your head on the ceiling when inside a car
  if car and b.y > T.ROOF_Y + 1 and ny - T.PERSON_H < T.CEIL_Y then
    ny = T.CEIL_Y + T.PERSON_H
    if b.vy < 0 then b.vy = 0 end
  end
  b.y = ny
end

return T
