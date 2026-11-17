-- hud.lua : bars, route, minimap, warnings, toasts, title/pause/end screens.
local T = require("train")
local U = require("util")
local Events = require("events")
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

local function panel(x, y, w, h)
  lg.setColor(0.03, 0.04, 0.08, 0.72)
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

function HUD.play(G, interaction)
  local P = G.player

  -- left: you
  panel(14, 14, 270, 116)
  bar(30, 44, 238, 12, P.health / 100, { 0.9, 0.25, 0.25 }, "HEALTH", math.ceil(P.health) .. "", P.health < 30)
  bar(30, 80, 238, 12, P.warmth / 100, { 0.35, 0.8, 1.0 }, "WARMTH", math.ceil(P.warmth) .. "", P.warmth < 25)
  lg.setFont(F.small)
  lg.setColor(0.85, 0.9, 1)
  lg.print(P.carrying and "Hands: COAL" or "Hands: empty", 30, 102)
  lg.setColor(T.firstAttached == 1 and { 1, 0.5, 0.5 } or { 0.5, 0.5, 0.5 })
  lg.printf("Bandages: " .. G.bandages, 30, 102, 238, "right")

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

  -- right: the train
  panel(VW - 284, 14, 270, 170)
  local bx = VW - 268
  bar(bx, 44, 238, 12, G.coal / G.maxCoal, { 0.55, 0.55, 0.62 }, "COAL IN TENDER", G.coal .. " / " .. G.maxCoal, G.coal <= 5)
  bar(bx, 80, 238, 12, G.fuel / 100, { 1.0, 0.55, 0.15 }, "FIREBOX (speed)", math.ceil(G.fuel) .. "%", G.fuel < 20)
  bar(bx, 116, 238, 12, G.stove / 100, { 1.0, 0.82, 0.3 }, "PASSENGER STOVE", math.ceil(G.stove) .. "%", G.stove < 15)
  lg.setFont(F.tiny)
  local tc = G.carTemp < 0 and { 0.5, 0.75, 1 } or { 1, 0.85, 0.6 }
  lg.setColor(tc)
  lg.print(string.format("Car %d°C", math.floor(G.carTemp + 0.5)), bx, 136)
  lg.setColor(0.6, 0.7, 0.85)
  lg.printf(string.format("Outside %d°C", math.floor(G.ambient + 0.5)), bx, 136, 238, "right")
  for i = 1, 8 do
    local px = bx + (i - 1) * 30 + 10
    if i <= G.passengers then
      lg.setColor(G.carTemp < 0 and { 0.6, 0.8, 1 } or { 1, 0.85, 0.65 })
      lg.circle("fill", px, 160, 5)
      lg.rectangle("fill", px - 6, 166, 12, 10, 3, 3)
    else
      lg.setColor(0.4, 0.4, 0.45, 0.6)
      lg.line(px - 5, 158, px + 5, 172); lg.line(px + 5, 158, px - 5, 172)
    end
  end

  -- minimap
  local mx, mw, my = 340, 600, 664
  panel(mx - 14, my - 10, mw + 28, 44)
  local s = mw / T.LENGTH
  for i, c in ipairs(T.cars) do
    local att = i >= T.firstAttached
    lg.setColor(att and { 0.45, 0.5, 0.6, 0.9 } or { 0.3, 0.3, 0.3, 0.3 })
    lg.rectangle("fill", mx + c.x * s, my + 6, c.w * s, 14, 3, 3)
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" or r.state == "jump" then
      local ry = r.y <= T.ROOF_Y + 2 and my + 2 or my + 13
      lg.setColor(1, 0.25, 0.2)
      lg.circle("fill", mx + U.clamp(r.x, 0, T.LENGTH) * s, ry, 4)
    end
  end
  for _, sl in ipairs(G.sleds) do
    if not sl.empty and sl.x > -300 then
      lg.setColor(1, 0.5, 0.3, 0.7)
      lg.circle("line", mx + math.max(-10, sl.x) * s, my + 28, 3)
    end
  end
  local py = P.y <= T.ROOF_Y + 2 and my + 2 or my + 13
  lg.setColor(1, 0.65, 0.2)
  lg.circle("fill", mx + P.x * s, py, 5)
  lg.setColor(1, 1, 1)
  lg.circle("line", mx + P.x * s, py, 5)

  -- warnings
  local warns = {}
  local o = Events.incoming(G)
  if o then
    local onRoof = P.y <= T.ROOF_Y + 2 or (P.climbing and P.y < T.ROOF_Y + 30)
    warns[#warns + 1] = { (o.kind == "tunnel" and "TUNNEL" or "LOW BRIDGE") .. (onRoof and "! GET DOWN or hold [S] to duck" or " ahead"), onRoof and { 1, 0.3, 0.2 } or { 1, 0.85, 0.3 } }
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and r.kind == "saboteur" and r.work > 0 then
      warns[#warns + 1] = { "SABOTEUR AT A COUPLING!", { 1, 0.3, 0.2 } }; break
    end
  end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and r.kind == "snatcher" and r.work > 0 then
      warns[#warns + 1] = { "SNATCHER IN THE PASSENGER CAR!", { 0.4, 1, 0.6 } }; break
    end
  end
  if G.depotLoading then warns[#warns + 1] = { "LOADING COAL...", { 0.6, 1, 0.6 } } end
  if G.depotTooFast then warns[#warns + 1] = { "AT DEPOT - TOO FAST TO LOAD! Pull the brake", { 1, 0.85, 0.3 } } end
  if G.fuel <= 0 then warns[#warns + 1] = { "FIREBOX OUT - THE TRAIN IS STOPPING!", { 1, 0.3, 0.2 } }
  elseif G.fuel < 20 then warns[#warns + 1] = { "Firebox low", { 1, 0.6, 0.3 } } end
  if G.carTemp < 0 then warns[#warns + 1] = { "Passengers are freezing!", { 0.5, 0.8, 1 } } end
  if P.warmth < 20 then warns[#warns + 1] = { "You're freezing - get near a fire", { 0.5, 0.8, 1 } } end
  local wy = 128
  for i = 1, math.min(3, #warns) do
    local w = warns[i]
    local c = w[2]
    shadowText(w[1], 0, wy, VW, "center", { c[1], c[2], c[3], 0.65 + 0.35 * pulse(7) }, F.med)
    wy = wy + 28
  end

  -- toasts
  local ty = 214
  for i = #G.toasts, math.max(1, #G.toasts - 2), -1 do
    local t = G.toasts[i]
    local a = math.min(1, t.t / 0.5, (t.max - t.t) / 0.25 + 0.0001)
    lg.setFont(F.small)
    local w = F.small:getWidth(t.msg) + 30
    lg.setColor(0.02, 0.03, 0.06, 0.7 * a)
    lg.rectangle("fill", VW / 2 - w / 2, ty, w, 28, 6, 6)
    lg.setColor(t.color[1], t.color[2], t.color[3], a)
    lg.printf(t.msg, 0, ty + 5, VW, "center")
    ty = ty + 34
  end
end

-- prompt above the player (train space, called under camera)
function HUD.prompt(G, interaction)
  if not interaction then return end
  local P = G.player
  lg.setFont(F.small)
  local text = interaction.disabled and interaction.label or ("[E] " .. interaction.label)
  local w = F.small:getWidth(text) + 16
  local x, y = P.x - w / 2, P.y - 92
  lg.setColor(0, 0, 0, 0.65)
  lg.rectangle("fill", x, y, w, 24, 5, 5)
  lg.setColor(interaction.disabled and { 0.7, 0.7, 0.7 } or { 1, 0.9, 0.5 })
  lg.print(text, x + 8, y + 3)
end

local CONTROLS = {
  { "A / D  or  Arrows", "Move" },
  { "W / S  at a gap", "Climb ladders" },
  { "Space", "Jump" },
  { "S  on a roof", "Duck under bridges" },
  { "E", "Shovel / feed / brake / bandage" },
  { "J  or  Left click", "Swing wrench" },
  { "P / Esc", "Pause      F11  Fullscreen" },
}

function HUD.title(G)
  lg.setColor(0, 0, 0.03, 0.45)
  lg.rectangle("fill", 0, 0, VW, VH)
  shadowText("FROSTLINE", 0, 70, VW, "center", { 0.85, 0.95, 1 }, F.huge)
  shadowText("Last Train to Haven", 0, 160, VW, "center", { 1, 0.7, 0.4 }, F.med)

  panel(150, 220, 470, 300)
  lg.setFont(F.small)
  lg.setColor(0.9, 0.93, 1)
  lg.printf("You are the last crew on the last train. 100 km of frozen wasteland lie between eight passengers and Haven.\n\n"
    .. "Shovel coal into the FURNACE to keep speed up. Fast trains outrun raider sleds.\n\n"
    .. "Feed the passenger car's STOVE or they freeze.\n\n"
    .. "Coal is scarce: brake at DEPOTS to reload.\n\n"
    .. "Throw raiders off before they steal coal, snatch passengers or uncouple the cars.",
    170, 236, 430, "left")

  panel(660, 220, 470, 300)
  lg.setFont(F.med)
  lg.setColor(1, 0.75, 0.4)
  lg.print("Controls", 680, 232)
  lg.setFont(F.small)
  for i, c in ipairs(CONTROLS) do
    local y = 232 + i * 36
    lg.setColor(1, 0.9, 0.6)
    lg.print(c[1], 680, y)
    lg.setColor(0.85, 0.9, 1)
    lg.print(c[2], 870, y)
  end

  shadowText("Press ENTER to depart", 0, 560, VW, "center", { 1, 1, 1, 0.55 + 0.45 * pulse(4) }, F.big)
  shadowText("Bad Ideas Works  ·  Game of the Week #1", 0, 680, VW, "center", { 0.6, 0.7, 0.85 }, F.tiny)
end

function HUD.paused()
  lg.setColor(0, 0, 0.03, 0.6)
  lg.rectangle("fill", 0, 0, VW, VH)
  shadowText("PAUSED", 0, 250, VW, "center", { 1, 1, 1 }, F.huge)
  shadowText("P / Esc to resume      Q to quit to title", 0, 370, VW, "center", { 0.8, 0.85, 1 }, F.med)
end

function HUD.ending(G, won)
  local a = math.min(1, G.endT / 1.2)
  lg.setColor(0, 0, 0.03, 0.65 * a)
  lg.rectangle("fill", 0, 0, VW, VH)
  if G.endT < 0.6 then return end
  local title = won and "YOU REACHED HAVEN" or "THE LINE GOES COLD"
  shadowText(title, 0, 120, VW, "center", won and { 1, 0.85, 0.5 } or { 0.7, 0.85, 1 }, F.huge)
  shadowText(G.overReason or "", 0, 220, VW, "center", { 0.9, 0.9, 0.95 }, F.med)
  local s = G.stats
  local score = math.floor(G.dist * 10) + s.kills * 50 + (won and G.passengers * 500 or 0)
  local lines = {
    { "Distance", string.format("%.1f km", G.dist) },
    { "Passengers saved", won and (G.passengers .. " / 8") or "0 / 8" },
    { "Raiders thrown off", s.kills .. (s.knocked > 0 and ("  (" .. s.knocked .. " by bridges)") or "") },
    { "Sleds outrun", s.outrun .. "" },
    { "Coal shovelled", s.shoveled .. "" },
    { "Frozen / snatched", s.frozen .. " / " .. s.taken },
    { "SCORE", score .. "" },
  }
  panel(400, 280, 480, 280)
  lg.setFont(F.small)
  for i, l in ipairs(lines) do
    local y = 270 + i * 36
    lg.setColor(i == #lines and { 1, 0.8, 0.4 } or { 0.75, 0.8, 0.9 })
    lg.print(l[1], 430, y)
    lg.printf(l[2], 430, y, 420, "right")
  end
  shadowText("ENTER to ride again      Esc for title", 0, 600, VW, "center", { 1, 1, 1, 0.6 + 0.4 * pulse(4) }, F.med)
end

return HUD
