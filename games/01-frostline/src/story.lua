-- story.lua : the characters and the story around the run.
--   intro    : a short skippable cinematic when a run starts
--   radio    : Marisol from Haven Control checks in along the route
--   barks    : passengers talk in speech bubbles (idle chatter + reactions)
--   requests : small favours passengers ask, with real rewards
--   epilogue : what became of everyone, depending on who survived
local T = require("train")
local U = require("util")
local Audio = require("audio")
local Passengers = require("passengers")
local lg = love.graphics

local Story = {}

---------------------------------------------------------------------------
-- Intro
---------------------------------------------------------------------------
local INTRO = {
  "Ashford fell to the raiders at dusk.",
  "One train got out. Eight passengers. One crew member: you.",
  "Haven is 100 km north. The radio says they'll keep the gates open.",
  "Keep the fires burning.",
}
local LINE_TIME = 2.6

function Story.newIntro() return { t = 0, done = false } end

function Story.updateIntro(G, dt)
  local i = G.intro
  i.t = i.t + dt
  if i.t > #INTRO * LINE_TIME + 1.2 then i.done = true end
end

function Story.skipIntro(G)
  if G.intro and not G.intro.done and G.intro.t > 0.4 then G.intro.done = true end
end

function Story.drawIntro(G, F, VW, VH)
  local i = G.intro
  local barH = 90 * math.min(1, i.t * 2)
  lg.setColor(0, 0, 0, 0.95)
  lg.rectangle("fill", 0, 0, VW, barH)
  lg.rectangle("fill", 0, VH - barH, VW, barH)
  lg.setColor(0, 0, 0.02, 0.35)
  lg.rectangle("fill", 0, 0, VW, VH)
  for n, line in ipairs(INTRO) do
    local start = (n - 1) * LINE_TIME + 0.4
    local k = U.clamp((i.t - start) / 0.8, 0, 1)
    if k > 0 then
      local last = n == #INTRO
      local font = last and F.huge or F.big
      lg.setFont(font)
      local y = 150 + (n - 1) * 70 + (last and 20 or 0) + (1 - k) * 12
      lg.setColor(0, 0, 0, 0.6 * k)
      lg.printf(line, 2, y + 2, VW, "center")
      if last then lg.setColor(1, 0.75, 0.4, k) else lg.setColor(0.9, 0.94, 1, k) end
      lg.printf(line, 0, y, VW, "center")
    end
  end
  lg.setFont(F.tiny)
  lg.setColor(0.7, 0.75, 0.85, 0.6 + 0.4 * math.sin(i.t * 3))
  lg.printf("press any button to skip", 0, VH - 50, VW, "center")
end

---------------------------------------------------------------------------
-- Radio: Marisol, Haven Control
---------------------------------------------------------------------------
local RADIO = {
  { 0.3, function() return "Haven Control to the Ashford train, do you read? ...Good. This is Marisol. Keep heading north and keep that engine fed." end },
  { 11.5, function() return "Marisol here. Coal depot coming up. Slow down or they can't load you. Trust me, I've watched trains try." end },
  { 24, function() return "Haven Control. Raider sleds spotted on your line. Lots of them. Go fast. Stay faster." end },
  { 39, function(G)
      if Passengers.count(G) == 8 then return "Marisol again. Half of Haven's kitchen is betting you make it with everyone. The other half is just hungry." end
      return "Marisol again. I heard you lost someone. ...Keep going. Bring the rest home."
    end },
  { 51, function(G)
      if Passengers.has(G, "whiskers") then return "Quick question from the kids here: is it true there's a CAT on that train? They want to know its name." end
      return "The kids here keep asking about the train. I tell them you're the bravest crew on the line."
    end },
  { 62, function() return "Storm front over the pass. Keep your passengers warm, crew. That's an order. I don't actually outrank you." end },
  { 75, function() return "Haven Control. We can see your smoke on the horizon! Barely. It's very far. But it's there." end },
  { 86, function() return "Crew, listen. Something big is moving on the old military road. Raider war-wagon. They call it the Iron Jaw. There's dynamite in your cargo car, right? ...Right?" end },
  { 95, function(G)
      if G.stats.boss then return "Was that explosion you?! Five kilometres left! We're opening the gates. Everyone's out on the platform!" end
      return "Five kilometres! We're opening the gates. Hold on, just a little longer!"
    end },
}

function Story.initRadio(G)
  G.radio = nil
  G.radioIdx = 1
end

function Story.updateRadio(G, dt)
  local nxt = RADIO[G.radioIdx]
  if nxt and G.dist >= nxt[1] then
    G.radioIdx = G.radioIdx + 1
    G.radio = { text = nxt[2](G), t = 0 }
    Audio.play("radio", 0.55)
  end
  if G.radio then
    G.radio.t = G.radio.t + dt
    if G.radio.t > 4 + #G.radio.text / 22 then G.radio = nil end
  end
end

function Story.drawRadio(G, F, x, y, w)
  local r = G.radio
  if not r then return end
  local shown = r.text:sub(1, math.floor(r.t * 45))
  local a = math.min(1, r.t * 4, (4 + #r.text / 22 - r.t) * 2)
  lg.setFont(F.small)
  local _, lines = F.small:getWrap(r.text, w - 28)
  local h = 40 + #lines * F.small:getHeight()
  lg.setColor(0.02, 0.07, 0.05, 0.85 * a)
  lg.rectangle("fill", x, y - h, w, h, 8, 8)
  lg.setColor(0.35, 1, 0.55, 0.5 * a)
  lg.rectangle("line", x + 0.5, y - h + 0.5, w - 1, h - 1, 8, 8)
  lg.setFont(F.tiny)
  lg.setColor(0.45, 1, 0.6, a * (0.6 + 0.4 * math.sin(r.t * 12)))
  lg.circle("fill", x + 16, y - h + 15, 4)
  lg.print("RADIO  ·  HAVEN CONTROL (MARISOL)", x + 26, y - h + 7)
  lg.setFont(F.small)
  lg.setColor(0.75, 1, 0.8, a)
  lg.printf(shown, x + 14, y - h + 28, w - 28, "left")
end

---------------------------------------------------------------------------
-- Barks: passengers talking
---------------------------------------------------------------------------
local IDLE = {
  ivo = { "That engine knocks when it's hungry. Listen.", "I could fix anything with a wrench and a good mood.", "Don't let the pressure drop, crew." },
  olga = { "Eat something. You look like a broom.", "When I was young, trains had dining cars.", "Who wants soup? Everyone wants soup." },
  amara = { "Keep your hands warm. Frostbite is not a fun hobby.", "Everyone drink water. Melted snow counts.", "I've patched up worse. Probably." },
  pip = { "Are we there yet?", "When I grow up I'm gonna drive a train!", "Mr. Whiskers is looking at me again.", "Can I pull the brake? Just once?" },
  sergei = { "In my day, we walked to Haven. Uphill.", "Raiders. Hmph. Amateurs.", "Keep your guard up, young one." },
  lena = { "Clear skies to the north... for now.", "I see smoke on the hills. Probably nothing.", "Bridges ahead, usually. Stay low up there." },
  bruno = { "A good fire is a happy fire.", "Feed the stove, feed the soul.", "Don't let it go out. Please." },
  whiskers = { "Mrrp.", "...", "*judges you silently*", "Mrow." },
}

local REACT = {
  cold = { bruno = "The stove's dying, crew!", pip = "I can't feel my toes...", olga = "Brrr! Some coal, please!", amara = "We need heat in here, now!" },
  stoked = { bruno = "Ahh. Now THAT'S a fire.", olga = "Bless you, dear.", pip = "Warm! Warm warm warm!", whiskers = "*purrs*" },
  raider = { sergei = "Get away from them, you dog!", pip = "HELP! Raider in here!", olga = "Out! Out of my car!", lena = "Crew! They're in the passenger car!" },
  wolf = { pip = "WOLF! WOLF!", sergei = "Back, beast!", whiskers = "HSSSSS!" },
  boss = { pip = "WHAT IS THAT?!", sergei = "Now THAT is a tank.", lena = "War-wagon on the left side!", olga = "Oh, I don't like that one." },
  hurt = { amara = "You're bleeding! The medkit's in the caboose.", olga = "Sit down before you fall down!" },
  welcome = { olga = "Ah, the crew! Sit, sit. ...No? Busy? Fine.", pip = "Hi! Are you the driver? You're the driver!" },
  haven = { pip = "WE MADE IT!", olga = "I'm making soup for the whole town.", sergei = "...Well done, young one." },
  victory = { pip = "YOU BLEW IT UP!!", sergei = "Ha! Magnificent!", lena = "It's burning! It's really burning!" },
}

local LOSS = { "Not %s...", "%s... no.", "We'll remember you, %s.", "Why %s?!" }

function Story.initBarks(G)
  G.barks = {}
  G.barkT = 6
  G.idleT = 14
  G.barkFlags = {}
end

-- shows a speech bubble over a living passenger; returns true if it did
function Story.bark(G, id, text, force)
  local p = Passengers.find(G, id)
  if not p or not p.alive or not text then return false end
  if not force and G.barkT > 0 then return false end
  for i = #G.barks, 1, -1 do if G.barks[i].id == id then table.remove(G.barks, i) end end
  G.barks[#G.barks + 1] = { id = id, seat = p.seat, text = text, t = 0, life = 2.6 + #text / 20 }
  G.barkT = 4
  Audio.play("blip", 0.35, 0.8 + p.seat * 0.06)
  return true
end

-- a reaction from whoever is alive among the listed speakers
function Story.react(G, kind, force)
  local pool = {}
  for id, text in pairs(REACT[kind] or {}) do
    if Passengers.has(G, id) then pool[#pool + 1] = { id, text } end
  end
  if #pool == 0 then return end
  local pick = pool[love.math.random(#pool)]
  Story.bark(G, pick[1], pick[2], force)
end

-- once-per-run reactions
function Story.reactOnce(G, kind, force)
  if G.barkFlags[kind] then return end
  G.barkFlags[kind] = true
  Story.react(G, kind, force)
end

function Story.onPassengerLost(G, lost)
  local other = Passengers.randomAlive(G, function(p) return not p.def.cat end)
  if other then
    Story.bark(G, other.id, string.format(LOSS[love.math.random(#LOSS)], lost.name), true)
  end
end

function Story.updateBarks(G, dt)
  G.barkT = math.max(0, G.barkT - dt)
  for i = #G.barks, 1, -1 do
    local b = G.barks[i]
    b.t = b.t + dt
    local p = G.passengerList[b.seat]
    if b.t >= b.life or not p.alive then table.remove(G.barks, i) end
  end
  -- idle chatter
  G.idleT = G.idleT - dt
  if G.idleT <= 0 then
    G.idleT = U.rand(16, 28)
    local p = Passengers.randomAlive(G)
    if p then
      local lines = IDLE[p.id]
      Story.bark(G, p.id, lines[love.math.random(#lines)])
    end
  end
  -- situational
  if G.carTemp < 4 and love.math.random() < dt * 0.25 then Story.react(G, "cold") end
  for _, r in ipairs(G.raiders) do
    if r.state == "board" and r.work > 0.5 and (r.kind == "snatcher" or r.kind == "wolf") then
      if love.math.random() < dt * 0.5 then Story.react(G, r.kind == "wolf" and "wolf" or "raider", true) end
      break
    end
  end
  if G.player.health < 30 and love.math.random() < dt * 0.15 then Story.react(G, "hurt") end
  local car = T.carAt(G.player.x)
  if car and car.kind == "passenger" and T.levelOf(G.player) == "floor" then Story.reactOnce(G, "welcome", true) end
  if G.boss and G.boss.state == "fight" then Story.reactOnce(G, "boss", true) end
end

---------------------------------------------------------------------------
-- Requests: small favours
---------------------------------------------------------------------------
-- status: nil (not yet) -> "asking" -> "active" -> "done"
local REQUESTS = {
  { id = "ivo", km = 8, ask = "Got 3 scrap, crew? I could tune that engine for you.",
    can = function(G) return G.scrap >= 3 end, need = "3 scrap", label = "Give Ivo 3 scrap",
    give = function(G) G.scrap = G.scrap - 3; G.perkTuned = true end,
    thanks = "Ha! Listen to her purr. She'll burn less coal now.", reward = "Engine tuned: burns 15% less coal" },
  { id = "olga", km = 20, ask = "My soup pot is empty. Bring me a shovel of coal, dear?",
    can = function(G) return G.player.carrying == "coal" end, need = "a shovel of coal", label = "Give Gran Olga the coal",
    give = function(G) G.player.carrying = nil; G.perkSoup = true; G.soupT = 0 end,
    thanks = "There we go. Soup's ready, and I'll cook twice as often now.", reward = "Soup every 30 seconds" },
  { id = "pip", km = 34, ask = "A big raider stole my toy train! The big purple ones! Please get it back?",
    can = function(G) return G.hasToy end, need = "Pip's toy train (a brute has it)", label = "Give Pip the toy train",
    give = function(G) G.hasToy = false; G.perkScarf = true end,
    thanks = "MY TRAIN! You can have my lucky scarf! It's super warm!", reward = "Lucky scarf: warmth drains 25% slower",
    onActive = function(G) G.toyWanted = true end },
  { id = "amara", km = 58, ask = "I'm running out of bandage cloth. Could you spare 2 scrap?",
    can = function(G) return G.scrap >= 2 end, need = "2 scrap", label = "Give Doc Amara 2 scrap",
    give = function(G) G.scrap = G.scrap - 2; G.bandages = G.bandages + 3 end,
    thanks = "Wonderful. Three fresh bandages in the caboose kit.", reward = "+3 bandages" },
}

function Story.initRequests(G)
  G.requests = {}
  G.hasToy, G.toyWanted = false, false
end

local function seatX(p) return T.cars[2].x + require("render").SEATS[p.seat] end

function Story.updateRequests(G, dt)
  for _, rq in ipairs(REQUESTS) do
    local st = G.requests[rq.id]
    if not st and G.dist >= rq.km and Passengers.has(G, rq.id) then
      local busy = false
      for _, s in pairs(G.requests) do if s == "asking" or s == "active" then busy = true end end
      if not busy then
        G.requests[rq.id] = "asking"
        Story.bark(G, rq.id, rq.ask, true)
        G.toast(Passengers.find(G, rq.id).name .. " wants to ask you a favour (passenger car).", { 1, 0.85, 0.6 }, 5)
      end
    end
    if (st == "asking" or st == "active") and not Passengers.has(G, rq.id) then G.requests[rq.id] = "done" end
  end
end

-- interaction for a passenger request, when standing next to that passenger
function Story.interaction(G, P)
  if T.firstAttached > 2 then return nil end
  for _, rq in ipairs(REQUESTS) do
    local st = G.requests[rq.id]
    local p = Passengers.find(G, rq.id)
    if (st == "asking" or st == "active") and p.alive and math.abs(P.x - seatX(p)) < 30 then
      if st == "asking" then
        return { label = "Listen to " .. p.name, fn = function()
          G.requests[rq.id] = "active"
          if rq.onActive then rq.onActive(G) end
          Story.bark(G, rq.id, rq.ask, true)
          G.toast("Favour for " .. p.name .. ": bring " .. rq.need .. ".", { 1, 0.85, 0.6 }, 5)
        end }
      elseif rq.can(G) then
        return { label = rq.label, fn = function()
          rq.give(G)
          G.requests[rq.id] = "done"
          G.stats.favours = G.stats.favours + 1
          Story.bark(G, rq.id, rq.thanks, true)
          G.toast("Favour done! " .. rq.reward, { 0.6, 1, 0.6 }, 5)
          Audio.play("win", 0.35, 1.2)
        end }
      else
        return { label = p.name .. " needs " .. rq.need, disabled = true }
      end
    end
  end
end

-- the active request, for the HUD
function Story.activeRequest(G)
  for _, rq in ipairs(REQUESTS) do
    local st = G.requests[rq.id]
    if st == "asking" or st == "active" then return rq, st, Passengers.find(G, rq.id) end
  end
end

---------------------------------------------------------------------------
-- World drawing: speech bubbles and favour markers (train space)
---------------------------------------------------------------------------
function Story.drawWorld(G, F)
  if T.firstAttached > 2 then return end
  local car = T.cars[2]
  local Render = require("render")
  -- favour markers
  local rq, st, p = Story.activeRequest(G)
  if rq and p and p.alive then
    local x = car.x + Render.SEATS[p.seat]
    local y = T.FLOOR_Y - 70 + math.sin(G.time * 5) * 4
    lg.setFont(F.big)
    local mark = st == "asking" and "!" or (rq.can(G) and "?" or "...")
    lg.setColor(0, 0, 0, 0.5)
    lg.printf(mark, x - 30 + 2, y - 36 + 2, 60, "center")
    lg.setColor(1, 0.85, 0.3)
    lg.printf(mark, x - 30, y - 36, 60, "center")
  end
  -- speech bubbles
  lg.setFont(F.small)
  for _, b in ipairs(G.barks) do
    local x = car.x + Render.SEATS[b.seat]
    local a = math.min(1, b.t * 6, (b.life - b.t) * 3)
    local maxW = 230
    local tw, lines = F.small:getWrap(b.text, maxW - 16)
    local w = math.min(maxW, tw + 18)
    local h = #lines * F.small:getHeight() + 12
    local bx = U.clamp(x - w / 2, car.x - 60, car.x + car.w + 60 - w)
    local by = T.CEIL_Y - h - 10 - (b.seat % 2) * 6
    lg.setColor(1, 0.98, 0.92, 0.95 * a)
    lg.rectangle("fill", bx, by, w, h, 8, 8)
    lg.polygon("fill", x - 6, by + h - 1, x + 6, by + h - 1, x, by + h + 9)
    lg.setColor(0.15, 0.12, 0.18, a)
    lg.printf(b.text, bx + 9, by + 6, w - 18, "left")
  end
end

---------------------------------------------------------------------------
-- Epilogue
---------------------------------------------------------------------------
local EPILOGUE = {
  ivo = "Keeps Haven's generators running. Named one 'Frostline'.",
  olga = "Runs Haven's busiest soup kitchen. Nobody leaves hungry.",
  amara = "Opened a clinic. Keeps a bandage with your name on it.",
  pip = "Tells your story to everyone. It gets bigger every time.",
  sergei = "Joined the wall guard. Finally gets to sit down.",
  lena = "Watches the horizon from Haven's tallest tower.",
  bruno = "Never lets a fire go out. Ever.",
  whiskers = "Elected mayor of Haven. Still unimpressed.",
}

function Story.epilogueLine(p) return EPILOGUE[p.id] end

function Story.endingTitle(G, won)
  if not won then return "THE LINE GOES COLD", { 0.7, 0.85, 1 } end
  local n = Passengers.count(G)
  if n == 8 and G.stats.boss then return "LEGEND OF THE FROSTLINE", { 1, 0.8, 0.3 } end
  if n == 8 then return "EVERYONE MADE IT", { 1, 0.85, 0.5 } end
  if n >= 5 then return "YOU REACHED HAVEN", { 1, 0.85, 0.5 } end
  return "A BITTERSWEET ARRIVAL", { 0.85, 0.8, 0.95 }
end

return Story
