-- events.lua : things the train passes along the line.
--   overheads : low bridges and tunnels (deadly if you stand on a roof)
--   depots    : coal depots (slow below DEPOT_SPEED to load coal)
--   blizzards : everything freezes faster for a while
-- Event objects live in train space and slide left at the train's speed.
local T = require("train")
local U = require("util")
local Audio = require("audio")
local Raiders = require("raiders")
local Particles = require("particles")
local Passengers = require("passengers")

local E = {}
E.DEPOT_SPEED = 35
E.DEPOT_KMS = { 14, 31, 48, 65, 82 }
E.PX_PER_KMH = 8 -- world flow speed in px/s per km/h

function E.init(G)
  G.overheads = {}
  G.depot = nil
  G.depotIdx = 1
  G.depotAnnounced = 0
  G.depotLoading, G.depotTooFast = false, false
  G.nextOverheadKm = 4 + love.math.random() * 2
  G.blizzard, G.blizzardTarget, G.blizzardT = 0, 0, 0
  G.nextBlizzardKm = 20 + love.math.random() * 6
end

function E.flow(G) return G.speed * E.PX_PER_KMH end

-- the next overhead that hasn't fully reached the engine yet (for warnings)
function E.incoming(G)
  for _, o in ipairs(G.overheads) do
    if o.x > T.cars[T.firstAttached].x - 50 and o.x > G.player.x - 40 then return o end
  end
end

local function spawnOverhead(G)
  local tunnel = G.progress > 0.2 and love.math.random() < 0.35
  local flow = E.flow(G)
  local o = {
    kind = tunnel and "tunnel" or "bridge",
    len = tunnel and U.rand(900, 1500) or 70,
    x = T.LENGTH + 150 + math.max(flow * 4.5, 500) * (Passengers.has(G, "lena") and 1.6 or 1),
    seed = love.math.random() * 1000,
  }
  G.overheads[#G.overheads + 1] = o
  Audio.play("bell", 0.6)
  local duck = "DUCK [" .. G.label("down") .. "]"
  local who = Passengers.has(G, "lena") and "Lena: " or ""
  G.toast(who .. (tunnel and "TUNNEL AHEAD! Get off the roof or " or "LOW BRIDGE AHEAD! Get off the roof or ") .. duck .. ".", { 1, 0.85, 0.3 })
end

function E.update(G, dt)
  local flow = E.flow(G)
  local P = G.player

  -- overheads -------------------------------------------------------------
  local depotNear = G.depot ~= nil
  if G.dist >= G.nextOverheadKm then
    if not depotNear then spawnOverhead(G) end
    G.nextOverheadKm = G.dist + U.lerp(7, 4, G.progress) + love.math.random() * 4
  end
  for i = #G.overheads, 1, -1 do
    local o = G.overheads[i]
    o.x = o.x - flow * dt
    local x0, x1 = o.x, o.x + o.len
    -- player
    if P.x > x0 - 8 and P.x < x1 + 8 and not P:isLow() and P.overheadCD <= 0 then
      P:hurt(G, 30, -1)
      P.stun = 1.1
      P.overheadCD = 1.4
      P.vx = -200
      G.addShake(14)
      Audio.play("hit", 0.9, 0.6)
      G.toast("WHAM! Stay low under bridges and tunnels.", { 1, 0.5, 0.4 })
    end
    -- raiders standing on roofs
    for _, r in ipairs(G.raiders) do
      if r.state == "board" and not r.climbing and r.y <= T.ROOF_Y + 2 and r.x > x0 - 8 and r.x < x1 + 8 then
        Raiders.knockOff(G, r)
      end
    end
    if x1 < T.minX() - 600 then table.remove(G.overheads, i) end
  end

  -- depots ----------------------------------------------------------------
  local nextKm = E.DEPOT_KMS[G.depotIdx]
  if nextKm then
    if G.depotAnnounced < G.depotIdx and G.dist >= nextKm - 3 then
      G.depotAnnounced = G.depotIdx
      G.toast("Coal depot in 3 km! Pull the BRAKE (engine lever) to load below " .. E.DEPOT_SPEED .. " km/h.", { 0.7, 1, 0.7 }, 6)
      Audio.play("pickup", 0.5)
    end
    if G.dist >= nextKm and not G.depot then
      G.depot = { x = T.LENGTH + 250 + flow * 3, len = 2400 }
      G.depotIdx = G.depotIdx + 1
    end
  end
  G.depotLoading, G.depotTooFast = false, false
  if G.depot then
    local d = G.depot
    d.x = d.x - flow * dt
    if T.COAL_X > d.x and T.COAL_X < d.x + d.len then
      if G.speed <= E.DEPOT_SPEED then
        G.depotLoading = true
        if G.coal < G.maxCoal then
          G.loadAcc = G.loadAcc + 2.4 * dt
          if G.loadAcc >= 1 then
            G.loadAcc = G.loadAcc - 1
            G.coal = math.min(G.maxCoal, G.coal + 1)
            Audio.play("shovel", 0.25, 0.8)
          end
          if love.math.random() < dt * 40 then
            Particles.add(G, { x = T.COAL_X + U.rand(-60, 60), y = T.CEIL_Y + 6, vx = U.rand(-20, 20), vy = 60,
              g = 900, life = 0.35, size = U.rand(2, 4), color = { 0.08, 0.08, 0.09 }, square = true })
          end
        end
      else
        G.depotTooFast = true
      end
    end
    if d.x + d.len < T.minX() - 700 then G.depot = nil end
  end

  -- blizzards -------------------------------------------------------------
  if G.blizzardTarget == 0 and G.dist >= G.nextBlizzardKm then
    G.blizzardTarget = 1
    G.blizzardT = U.rand(30, 42)
    G.toast("BLIZZARD! Everything freezes faster. Keep the fires going.", { 0.7, 0.85, 1 }, 5)
    Audio.play("alarm", 0.3, 0.6)
  end
  if G.blizzardTarget == 1 then
    G.blizzardT = G.blizzardT - dt
    if G.blizzardT <= 0 then
      G.blizzardTarget = 0
      G.nextBlizzardKm = G.dist + U.rand(18, 26)
    end
  end
  G.blizzard = U.approach(G.blizzard, G.blizzardTarget, dt * 0.25)
end

return E
