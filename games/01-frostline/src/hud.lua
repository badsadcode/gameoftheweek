-- hud.lua : bars, route, minimap, warnings, toasts, name tags, title/menu/results screens.
local T = require("train")
local U = require("util")
local Events = require("events")
local Hazards = require("hazards")
local Boss = require("boss")
local Input = require("input")
local Settings = require("settings")
local Passengers = require("passengers")
local Upgrades = require("upgrades")
local lg = love.graphics

local HUD = {}
local F = {}
local VW, VH = 1280, 720

function HUD.load()
  F.huge = lg.newFont(78)
  F.big = lg.newFont(40)
  F.med = lg.newFont(22)
  F.small = lg.newFont(16)
  F.tiny = lg.newFont(13)
  HUD.fonts = F
end

local function panel(x, y, w, h, a)
  lg.setColor(0.03, 0.04, 0.08, a or 0.72)
  lg.rectangle("fill", x, y, w, h, 8, 8)
  lg.setColor(0.6, 0.75, 1, 0.18)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 8, 8)
end

local function pulse(speed) return 0.5 + 0.5 * math.sin(love.timer.getTime() * (speed or 8)) end

local function bar(x, y, w, h, frac, c, label, value, danger)
  lg.setFont(F.tiny)
  lg.setColor(0.8, 0.85, 0.95, 0.9)
  lg.print(label, x, y - 16)
  if value then lg.printf(value, x, y - 16, w, "right") end
  lg.setColor(0, 0, 0, 0.55)
  lg.rectangle("fill", x, y, w, h, 4, 4)
  local k = danger and (0.55 + 0.45 * pulse(10)) or 1
  lg.setColor(c[1] * k, c[2] * k, c[3] * k)
  lg.rectangle("fill", x, y, math.max(0, w * U.clamp(frac, 0, 1)), h, 4, 4)
end

local function shadowText(text, x, y, w, align, c, font)
  lg.setFont(font)
  lg.setColor(0, 0, 0, 0.7)
  lg.printf(text, x + 2, y + 2, w, align)
  lg.setColor(c)
  lg.printf(text, x, y, w, align)
end

local function key(action) return "[" .. Input.label(action) .. "]" end

local function passengerIcon(p, x, y, t)
  if p.alive then
    if p.def.cat then
      lg.setColor(0.95, 0.6, 0.2)
      lg.circle("fill", x, y + 8, 6)
      lg.polygon("fill", x - 5, y + 4, x - 4, y - 3, x - 1, y + 3)
      lg.polygon("fill", x + 1, y + 3, x + 4, y - 3, x + 5, y + 4)
      return
    end
    if p.sick then lg.setColor(0.4, 1, 0.4, 0.55 + 0.45 * math.sin(t * 8)) else lg.setColor(p.def.color) end
    lg.circle("fill", x, y, 5)
    lg.rectangle("fill", x - 6, y + 6, 12, 10, 3, 3)
  else
    lg.setColor(0.4, 0.4, 0.45, 0.6)
    lg.line(x - 5, y - 2, x + 5, y + 14); lg.line(x + 5, y - 2, x - 5, y + 14)
  end
end

---------------------------------------------------------------------------
-- In-game HUD
---------------------------------------------------------------------------
function HUD.play(G)
  local P = G.player
  local t = love.timer.getTime()

  -- left: you
  panel(14, 14, 270, 136)
  bar(30, 44, 238, 12, P.health / 100, { 0.9, 0.25, 0.25 }, "HEALTH", math.ceil(P.health) .. "", P.health < 30)
  bar(30, 80, 238, 12, P.warmth / 100, { 0.35, 0.8, 1.0 }, "WARMTH", math.ceil(P.warmth) .. "", P.warmth < 25)
  lg.setFont(F.small)
  lg.setColor(0.85, 0.9, 1)
  local hands = P.carrying and (P.carrying:sub(1, 1):upper() .. P.carrying:sub(2)) or "empty"
  lg.print("Hands: " .. hands, 30, 100)
  lg.setColor(0.75, 0.8, 0.9)
  lg.printf("Scrap: " .. G.scrap, 30, 100, 238, "right")
  lg.setColor(T.firstAttached == 1 and { 1, 0.5, 0.5 } or { 0.5, 0.5, 0.5 })
  lg.print("Bandages: " .. G.bandages, 30, 122)
  local owned = 0
  for _ in pairs(G.upgrades) do owned = owned + 1 end
  lg.setColor(0.6, 0.65, 0.75)
  lg.printf("Upgrades: " .. owned, 30, 122, 238, "right")

  -- center: route + speed
  panel(410, 14, 460, 100)
  local rx, rw = 440, 400
  lg.setFont(F.tiny)
  lg.setColor(0.7, 0.75, 0.85)
  lg.print("ASHFORD", rx - 10, 24)
  lg.printf("HAVEN", rx, 24, rw + 10, "right")
  lg.setColor(0.25, 0.3, 0.4)
  lg.rectangle("fill", rx, 46, rw, 4, 2, 2)
  for i, km in ipairs(Events.DEPOT_KMS) do
    lg.setColor(i < G.depotIdx and { 0.35, 0.4, 0.35 } or { 0.5, 0.95, 0.5 })
    lg.rectangle("fill", rx + rw * km / 100 - 2, 41, 4, 14)
  end
  lg.setColor(1, 0.35, 0.3)
  lg.rectangle("fill", rx + rw * Boss.START_KM / 100 - 3, 39, 6, 18, 2, 2)
  lg.setColor(0.6, 0.85, 1)
  lg.rectangle("fill", rx, 46, rw * U.clamp(G.progress, 0, 1), 4, 2, 2)
  local tx = rx + rw * U.clamp(G.progress, 0, 1)
  lg.setColor(1, 0.6, 0.2)
  lg.polygon("fill", tx - 7, 40, tx + 7, 40, tx + 10, 48, tx + 7, 56, tx - 7, 56)
  lg.setFont(F.big)
  lg.setColor(1, 1, 1)
  lg.printf(math.floor(G.speed + 0.5) .. "", 410, 60, 230, "right")
  lg.setFont(F.small)
  lg.setColor(0.7, 0.75, 0.85)
  lg.print("km/h", 646, 82)
  lg.printf(string.format("%.1f / 100 km", G.dist), 700, 66, 150, "right")
  if G.brake then
    lg.setColor(1, 0.3, 0.2, 0.6 + 0.4 * pulse(6))
    lg.printf("BRAKE ON", 700, 88, 150, "right")
  end

  -- right: the train + passengers
  panel(VW - 284, 14, 270, 176)
  local bx = VW - 268
  bar(bx, 44, 238, 12, G.coal / G.maxCoal, { 0.55, 0.55, 0.62 }, "COAL IN TENDER", G.coal .. " / " .. G.maxCoal, G.coal <= 5)
  bar(bx, 80, 238, 12, G.fuel / 100, { 1.0, 0.55, 0.15 }, "FIREBOX (speed)", math.ceil(G.fuel) .. "%", G.fuel < 20)
  bar(bx, 116, 238, 12, G.stove / 100, { 1.0, 0.82, 0.3 }, "PASSENGER STOVE", math.ceil(G.stove) .. "%", G.stove < 15)
  lg.setFont(F.tiny)
  lg.setColor(G.carTemp < 0 and { 0.5, 0.75, 1 } or { 1, 0.85, 0.6 })
  lg.print(string.format("Car %d°C", math.floor(G.carTemp + 0.5)), bx, 136)
  lg.setColor(0.6, 0.7, 0.85)
  lg.printf(string.format("Outside %d°C", math.floor(G.ambient + 0.5)), bx, 136, 238, "right")
  for i, p in ipairs(G.passengerList) do
    passengerIcon(p, bx + (i - 1) * 30 + 10, 158, t)
  end

  -- boss health
  local topY = 128
  local b = G.boss
  if b then
    local w = 420
    local x = VW / 2 - w / 2
    panel(x - 10, topY - 6, w + 20, 40, 0.8)
    lg.setFont(F.small)
    lg.setColor(1, 0.45, 0.35)
    lg.printf("THE IRON JAW", x, topY - 2, w, "center")
    lg.setColor(0, 0, 0, 0.6)
    lg.rectangle("fill", x, topY + 18, w, 10, 4, 4)
    lg.setColor(0.9, 0.2, 0.15)
    lg.rectangle("fill", x, topY + 18, w * math.max(0, b.hp) / Boss.HP, 10, 4, 4)
    topY = topY + 46
  end

  -- minimap
  local mx, mw, my = 340, 600, 664
  local ghost = G.boss ~= nil -- don't hide the Iron Jaw's face
  panel(mx - 14, my - 10, mw + 28, 44, ghost and 0.25 or 0.72)
  local fade = ghost and 0.5 or 1
  local s = mw / T.LENGTH
  for i, c in ipairs(T.cars) do
    local att = i >= T.firstAttached
    lg.setColor(att and { 0.45, 0.5, 0.6, 0.9 * fade } or { 0.3, 0.3, 0.3, 0.3 * fade })
    if G.fire and G.fire.car == i then lg.setColor(1, 0.5, 0.2, 0.6 + 0.4 * pulse(8)) end
    lg.rectangle("fill", mx + c.x * s, my + 6, c.w * s, 14, 3, 3)
  end
  if G.snow then
    lg.setColor(0.95, 0.97, 1)
    lg.rectangle("fill", mx + T.gapCenter(G.snow.gap) * s - 4, my + 2, 8, 22, 2, 2)
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" or r.state == "jump" then
      local ry = r.y <= T.ROOF_Y + 2 and my + 2 or my + 13
      lg.setColor(r.kind == "wolf" and { 0.85, 0.85, 0.95 } or { 1, 0.25, 0.2 })
      lg.circle("fill", mx + U.clamp(r.x, 0, T.LENGTH) * s, ry, 4)
    end
  end
  if Passengers.has(G, "lena") then
    for _, sl in ipairs(G.sleds) do
      if not sl.empty and sl.x > -300 then
        lg.setColor(1, 0.5, 0.3, 0.7)
        lg.circle("line", mx + math.max(-10, sl.x) * s, my + 28, 3)
      end
    end
  end
  local py = P.y <= T.ROOF_Y + 2 and my + 2 or my + 13
  lg.setColor(1, 0.65, 0.2)
  lg.circle("fill", mx + P.x * s, py, 5)
  lg.setColor(1, 1, 1)
  lg.circle("line", mx + P.x * s, py, 5)

  -- warnings
  local warns = {}
  local function warn(text, c) warns[#warns + 1] = { text, c } end
  local onRoof = P.y <= T.ROOF_Y + 2 or (P.climbing and P.y < T.ROOF_Y + 30)
  local o = Events.incoming(G)
  if o then
    warn((o.kind == "tunnel" and "TUNNEL" or "LOW BRIDGE") .. (onRoof and ("! GET DOWN or hold " .. key("down") .. " to duck") or " ahead"),
      onRoof and { 1, 0.3, 0.2 } or { 1, 0.85, 0.3 })
  end
  if G.track and not G.track.passed then
    local fast = G.speed > Hazards.TRACK_SPEED
    warn("TRACK DAMAGE AHEAD" .. (fast and (" - BRAKE below " .. Hazards.TRACK_SPEED .. "!") or " - speed OK"), fast and { 1, 0.3, 0.2 } or { 0.6, 1, 0.6 })
  end
  if G.avalanche then
    local ok = G.speed >= Hazards.AVALANCHE_SPEED
    warn(string.format("AVALANCHE in %.0fs - %s", math.max(0, G.avalanche.t), ok and "outrunning it!" or ("go above " .. Hazards.AVALANCHE_SPEED .. " km/h!")),
      ok and { 0.6, 1, 0.6 } or { 0.85, 0.92, 1 })
  end
  if G.fire then warn("FIRE in the " .. Hazards.CAR_NAMES[G.fire.car] .. "!", { 1, 0.5, 0.2 }) end
  if G.boss and #G.hooks > 0 then warn("CHAINS ARE DRAGGING THE TRAIN (" .. #G.hooks .. ") - cut them with your wrench!", { 1, 0.4, 0.3 }) end
  if G.boss and G.boss.state == "fight" and P.carrying ~= "dynamite" and #G.hooks == 0 then
    warn("Grab DYNAMITE (cargo car) and throw it " .. key("attack") .. " at the Iron Jaw", { 1, 0.75, 0.3 })
  end
  local sick = Hazards.firstSick(G)
  if sick then warn(string.format("%s has a fever: medicine in %ds", sick.name, math.ceil(sick.sickT)), { 0.5, 1, 0.5 }) end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and r.kind == "saboteur" and r.work > 0 then warn("SABOTEUR AT A COUPLING!", { 1, 0.3, 0.2 }); break end
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and (r.kind == "snatcher" or r.kind == "wolf") and r.work > 0 then
      warn(r.kind == "wolf" and "WOLF IN THE PASSENGER CAR!" or "SNATCHER IN THE PASSENGER CAR!", { 0.4, 1, 0.6 }); break
    end
  end
  if G.depotLoading then warn("LOADING COAL... (trader open in the cargo car)", { 0.6, 1, 0.6 }) end
  if G.depotTooFast then warn("AT DEPOT - TOO FAST TO LOAD! Pull the brake", { 1, 0.85, 0.3 }) end
  if G.fuel <= 0 then warn("FIREBOX OUT - THE TRAIN IS STOPPING!", { 1, 0.3, 0.2 })
  elseif G.fuel < 20 then warn("Firebox low", { 1, 0.6, 0.3 }) end
  if G.carTemp < 0 then warn("Passengers are freezing!", { 0.5, 0.8, 1 }) end
  if P.warmth < 20 then warn("You're freezing - get near a fire", { 0.5, 0.8, 1 }) end
  local wy = topY
  for i = 1, math.min(3, #warns) do
    local c = warns[i][2]
    shadowText(warns[i][1], 0, wy, VW, "center", { c[1], c[2], c[3], 0.65 + 0.35 * pulse(7) }, F.med)
    wy = wy + 28
  end

  -- toasts
  local ty = math.max(214, wy + 8)
  for i = #G.toasts, math.max(1, #G.toasts - 2), -1 do
    local tt = G.toasts[i]
    local a = math.min(1, tt.t / 0.5, (tt.max - tt.t) / 0.25 + 0.0001)
    lg.setFont(F.small)
    local w = math.min(VW - 40, F.small:getWidth(tt.msg) + 30)
    lg.setColor(0.02, 0.03, 0.06, 0.7 * a)
    lg.rectangle("fill", VW / 2 - w / 2, ty, w, 28, 6, 6)
    lg.setColor(tt.color[1], tt.color[2], tt.color[3], a)
    lg.printf(tt.msg, VW / 2 - w / 2, ty + 5, w, "center")
    ty = ty + 34
  end
end

-- prompt above the player (train space, called under camera)
function HUD.prompt(G, interaction)
  if not interaction then return end
  local P = G.player
  lg.setFont(F.small)
  local text = interaction.disabled and interaction.label or ("[" .. Input.label("interact") .. "] " .. interaction.label)
  local w = F.small:getWidth(text) + 16
  local x, y = P.x - w / 2, P.y - 92
  lg.setColor(0, 0, 0, 0.65)
  lg.rectangle("fill", x, y, w, 24, 5, 5)
  lg.setColor(interaction.disabled and { 0.7, 0.7, 0.7 } or { 1, 0.9, 0.5 })
  lg.print(text, x + 8, y + 3)
end

-- passenger names when you're in their car (train space)
function HUD.nameTags(G)
  local P = G.player
  local car = T.carAt(P.x)
  if not car or car.kind ~= "passenger" or T.levelOf(P) ~= "floor" then return end
  local Render = require("render")
  lg.setFont(F.tiny)
  for i, p in ipairs(G.passengerList) do
    local x = car.x + Render.SEATS[p.seat]
    if p.alive and (p.sick or math.abs(x - P.x) < 70) then
      local y = T.FLOOR_Y - 76 - (i % 2) * 18
      local text = p.name .. (p.sick and string.format(" (fever %ds)", math.ceil(p.sickT)) or "")
      local w = F.tiny:getWidth(text) + 8
      lg.setColor(0, 0, 0, 0.55)
      lg.rectangle("fill", x - w / 2, y, w, 16, 4, 4)
      lg.setColor(p.sick and { 0.5, 1, 0.5 } or { 1, 0.92, 0.75 })
      lg.printf(text, x - w / 2, y + 1, w, "center")
    end
  end
end

-- rolling snow cloud while an avalanche approaches (screen space)
function HUD.avalanche(G)
  local av = G.avalanche
  if not av then return end
  local k = U.clamp(1 - av.t / 6, 0, 1)
  local t = love.timer.getTime()
  for i = 0, 14 do
    local x = VW - 80 * k * 4 + i * 30 + math.sin(t * 3 + i) * 12
    local y = 40 + (i % 5) * 50 + math.cos(t * 2 + i) * 8
    lg.setColor(0.95, 0.97, 1, 0.55 * k)
    lg.circle("fill", x, y, 50 + 40 * k)
  end
end

---------------------------------------------------------------------------
-- Roster (shown in the pause menu and on the results screen)
---------------------------------------------------------------------------
local FATES = {
  froze = "froze", taken = "snatched", burned = "lost in a fire", mauled = "taken by wolves",
  fever = "lost to fever", derail = "lost in a derailment", uncoupled = "left behind",
}

local function roster(G, x, y, w, showPerks)
  panel(x, y, w, 46 + #G.passengerList * (showPerks and 38 or 24))
  lg.setFont(F.med)
  lg.setColor(1, 0.75, 0.4)
  lg.print("Passengers", x + 16, y + 10)
  local t = love.timer.getTime()
  for i, p in ipairs(G.passengerList) do
    local ry = y + 44 + (i - 1) * (showPerks and 38 or 24)
    passengerIcon(p, x + 26, ry + 2, t)
    lg.setFont(F.small)
    lg.setColor(p.alive and { 1, 0.95, 0.85 } or { 0.55, 0.55, 0.6 })
    lg.print(p.name, x + 44, ry)
    lg.setFont(F.tiny)
    local status = p.alive and (p.sick and "FEVER" or p.def.role) or (FATES[p.fate] or "gone")
    lg.setColor(p.alive and (p.sick and { 0.5, 1, 0.5 } or { 0.7, 0.8, 0.95 }) or { 1, 0.5, 0.45, 0.8 })
    lg.printf(status, x, ry + 2, w - 16, "right")
    if showPerks then
      lg.setColor(p.alive and { 0.6, 0.66, 0.78 } or { 0.45, 0.45, 0.5 })
      lg.print(p.def.perk, x + 44, ry + 18)
    end
  end
end

local function upgradesPanel(G, x, y, w)
  local list = {}
  for _, u in ipairs(Upgrades.LIST) do
    if Upgrades.has(G, u.id) then list[#list + 1] = u.name .. (u.repeatable and (" x" .. G.upgrades[u.id]) or "") end
  end
  panel(x, y, w, 50 + math.max(1, #list) * 22)
  lg.setFont(F.med)
  lg.setColor(1, 0.75, 0.4)
  lg.print("Upgrades", x + 16, y + 10)
  lg.setFont(F.small)
  lg.setColor(0.8, 0.85, 0.95)
  if #list == 0 then lg.print("None yet. Spend scrap at depots!", x + 16, y + 44) end
  for i, name in ipairs(list) do lg.print("- " .. name, x + 16, y + 22 + i * 22) end
end

local function controls(x, y, w)
  local rows = {
    { (Input.device == "gamepad") and "Left stick / D-pad" or "A / D  or  Arrows", "Move" },
    { Input.label("up") .. " / " .. Input.label("down") .. "  at a gap", "Climb ladders" },
    { Input.label("jump"), "Jump" },
    { Input.label("down") .. "  on a roof", "Duck under bridges" },
    { Input.label("interact"), "Shovel, feed, brake, dig, trade..." },
    { Input.label("attack") .. ((Input.device == "gamepad") and "" or "  or  Left click"), "Wrench / throw dynamite" },
    { Input.label("pause"), "Pause & passengers" },
  }
  panel(x, y, w, 60 + #rows * 32)
  lg.setFont(F.med)
  lg.setColor(1, 0.75, 0.4)
  lg.print("Controls", x + 18, y + 12)
  lg.setFont(F.small)
  for i, c in ipairs(rows) do
    local ry = y + 18 + i * 32
    lg.setColor(1, 0.9, 0.6)
    lg.print(c[1], x + 18, ry)
    lg.setColor(0.85, 0.9, 1)
    lg.print(c[2], x + w * 0.48, ry)
  end
end

---------------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------------
function HUD.title(G)
  lg.setColor(0, 0, 0.03, 0.45)
  lg.rectangle("fill", 0, 0, VW, VH)
  shadowText("FROSTLINE", 0, 40, VW, "center", { 0.85, 0.95, 1 }, F.huge)
  shadowText("Last Train to Haven", 0, 128, VW, "center", { 1, 0.7, 0.4 }, F.med)

  panel(110, 180, 430, 330)
  lg.setFont(F.small)
  lg.setColor(0.9, 0.93, 1)
  lg.printf("You are the last crew on the last train. 100 km of frozen wasteland lie between eight passengers and Haven.\n\n"
    .. "Shovel coal into the FURNACE for speed, and into the STOVE so nobody freezes.\n\n"
    .. "Brake at DEPOTS to reload and spend scrap on upgrades.\n\n"
    .. "Fight off raiders, wolves, fires and avalanches... and whatever waits near the end of the line.",
    130, 196, 390, "left")
  controls(740, 180, 430)

  local d = Settings.data
  lg.setFont(F.small)
  lg.setColor(0.75, 0.8, 0.9)
  local best = d.runs > 0 and string.format("Best score: %d   ·   Best distance: %.1f km   ·   Wins: %d", d.best_score, d.best_dist, d.wins) or "No runs yet. Good luck out there."
  lg.printf(best, 0, 518, VW, "center")
  shadowText("Bad Ideas Works  ·  Game of the Week #1", 0, 690, VW, "center", { 0.6, 0.7, 0.85 }, F.tiny)
end

function HUD.menu(G, menu, depth)
  if menu.kind == "title" then
    menu:draw(F, VW / 2, 546, 360)
    return
  end
  lg.setColor(0, 0, 0.03, 0.6)
  lg.rectangle("fill", 0, 0, VW, VH)
  if menu.kind == "pause" then
    controls(40, 120, 380)
    menu:draw(F, VW / 2, 200, 340)
    roster(G, VW - 420, 70, 380, true)
  elseif menu.kind == "trader" then
    upgradesPanel(G, 40, 150, 300)
    menu:draw(F, VW / 2 + 60, 110, 560)
  else
    menu:draw(F, VW / 2, 180, 420)
  end
  lg.setFont(F.tiny)
  lg.setColor(0.65, 0.7, 0.8)
  local nav = Input.device == "gamepad" and "D-pad: choose · A: select · B: back" or "Arrows/WASD: choose · Enter: select · Esc: back"
  lg.printf(nav, 0, VH - 34, VW, "center")
end

function HUD.ending(G, won)
  local wait = won and 5 or 0.6
  if won and G.endT < wait then
    if G.endT > 1.5 then shadowText("Arriving at Haven...", 0, 140, VW, "center", { 1, 0.85, 0.5, math.min(1, (G.endT - 1.5)) }, F.big) end
    return
  end
  local a = math.min(1, (G.endT - wait + 0.6) / 1.2)
  lg.setColor(0, 0, 0.03, 0.7 * a)
  lg.rectangle("fill", 0, 0, VW, VH)
  if G.endT < wait + 0.3 then return end
  local title = won and "YOU REACHED HAVEN" or "THE LINE GOES COLD"
  shadowText(title, 0, 34, VW, "center", won and { 1, 0.85, 0.5 } or { 0.7, 0.85, 1 }, F.huge)
  shadowText(G.overReason or "", 0, 124, VW, "center", { 0.9, 0.9, 0.95 }, F.med)

  roster(G, 90, 175, 400, false)

  -- score breakdown
  local x, y, w = 540, 175, 400
  local s = G.stats
  panel(x, y, w, 380)
  lg.setFont(F.med)
  lg.setColor(1, 0.75, 0.4)
  lg.print("The run", x + 16, y + 10)
  local lines = {
    { "Distance", string.format("%.1f km", G.dist) },
    { "Raiders thrown off", s.kills .. (s.knocked > 0 and ("  (" .. s.knocked .. " by bridges)") or "") },
    { "Sleds outrun", s.outrun .. "" },
    { "Coal shovelled", s.shoveled .. "" },
    { "Fires put out", s.fires .. "" },
    { "Fevers cured", s.cured .. "" },
    { "Upgrades bought", s.upgrades .. "" },
    { "The Iron Jaw", s.boss and "DESTROYED" or (G.dist >= Boss.START_KM and "survived it" or "never met it") },
  }
  lg.setFont(F.small)
  for i, l in ipairs(lines) do
    local ly = y + 18 + i * 26
    lg.setColor(0.75, 0.8, 0.9)
    lg.print(l[1], x + 16, ly)
    lg.printf(l[2], x + 16, ly, w - 32, "right")
  end
  local sy = y + 18 + #lines * 26 + 36
  lg.setColor(0.6, 0.65, 0.75, 0.6)
  lg.line(x + 16, sy - 8, x + w - 16, sy - 8)
  lg.setFont(F.med)
  lg.setColor(1, 0.85, 0.4)
  lg.print("SCORE", x + 16, sy)
  lg.printf(tostring(G.score or 0), x + 16, sy, w - 32, "right")
  lg.setFont(F.small)
  if G.newBest then
    lg.setColor(1, 0.9, 0.3, 0.6 + 0.4 * pulse(6))
    lg.printf("NEW HIGH SCORE!", x, sy + 34, w, "center")
  else
    lg.setColor(0.65, 0.7, 0.8)
    lg.printf("Best: " .. Settings.data.best_score, x, sy + 34, w, "center")
  end

  -- score parts
  local px = 990
  panel(px, y, 220, 30 + #(G.scoreParts or {}) * 44)
  lg.setFont(F.tiny)
  for i, part in ipairs(G.scoreParts or {}) do
    local ly = y + 14 + (i - 1) * 44
    lg.setColor(0.7, 0.75, 0.85)
    lg.print(part[1], px + 14, ly)
    lg.setFont(F.small)
    lg.setColor(1, 0.95, 0.8)
    lg.print("+" .. part[2], px + 14, ly + 16)
    lg.setFont(F.tiny)
  end

  local again = "[" .. Input.label("confirm") .. "] ride again      [" .. (Input.device == "gamepad" and "B" or "Esc") .. "] title"
  shadowText(again, 0, 640, VW, "center", { 1, 1, 1, 0.6 + 0.4 * pulse(4) }, F.med)
end

return HUD
