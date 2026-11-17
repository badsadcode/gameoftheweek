-- upgrades.lua : the depot trader. Spend scrap (dropped by raiders) on train and gear upgrades.
local Menu = require("menu")
local Audio = require("audio")
local T = require("train")

local Upgrades = {}

Upgrades.LIST = {
  { id = "tender",     name = "Bigger Tender",     desc = "+15 coal capacity",                        cost = 6 },
  { id = "bellows",    name = "Firebox Bellows",   desc = "Each shovel gives the furnace +5 more",    cost = 7 },
  { id = "insulation", name = "Stove Insulation",  desc = "Passenger stove burns 30% slower",         cost = 6 },
  { id = "coat",       name = "Thermal Coat",      desc = "You lose warmth 40% slower",               cost = 5 },
  { id = "wrench",     name = "Heavy Wrench",      desc = "Your wrench hits twice as hard",           cost = 9 },
  { id = "couplings",  name = "Welded Couplings",  desc = "Saboteurs need twice as long",             cost = 7 },
  { id = "spikes",     name = "Roof Spikes",       desc = "Raiders landing on roofs take a hit",      cost = 8 },
  { id = "medkit",     name = "Medkit Refill",     desc = "+2 bandages in the caboose",               cost = 4, repeatable = true },
}

function Upgrades.has(G, id) return (G.upgrades[id] or 0) > 0 end

local function owned(G, u) return not u.repeatable and Upgrades.has(G, u.id) end

function Upgrades.canBuy(G, u)
  if owned(G, u) or G.scrap < u.cost then return false end
  if u.id == "medkit" and T.firstAttached > 1 then return false end
  return true
end

function Upgrades.buy(G, u)
  if not Upgrades.canBuy(G, u) then return false end
  G.scrap = G.scrap - u.cost
  G.upgrades[u.id] = (G.upgrades[u.id] or 0) + 1
  if u.id == "tender" then G.maxCoal = G.maxCoal + 15 end
  if u.id == "medkit" then G.bandages = G.bandages + 2 end
  G.stats.upgrades = G.stats.upgrades + 1
  Audio.play("pickup", 0.7, 0.9)
  return true
end

-- the cheapest affordable upgrade (used by the test bot)
function Upgrades.cheapestAffordable(G)
  local best
  for _, u in ipairs(Upgrades.LIST) do
    if Upgrades.canBuy(G, u) and (not best or u.cost < best.cost) then best = u end
  end
  return best
end

function Upgrades.menu(G, onClose)
  local items = {}
  for _, u in ipairs(Upgrades.LIST) do
    items[#items + 1] = {
      label = function()
        if owned(G, u) then return u.name .. "  (owned)" end
        return string.format("%s  -  %d scrap", u.name, u.cost)
      end,
      hint = function() return u.desc end,
      disabled = function() return not Upgrades.canBuy(G, u) end,
      action = function() Upgrades.buy(G, u) end,
    }
  end
  items[#items + 1] = { label = "Back to the train", hint = "The train keeps rolling while you shop... just kidding, time is frozen.", action = onClose }
  local m = Menu.new(function() return "Depot Trader  -  you have " .. G.scrap .. " scrap" end, items, { rowH = 38 })
  -- start on the first thing you can afford, else on "Back"
  m.index = #items
  for i, u in ipairs(Upgrades.LIST) do
    if Upgrades.canBuy(G, u) then m.index = i; break end
  end
  return m
end

return Upgrades
