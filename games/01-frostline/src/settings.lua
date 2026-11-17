-- settings.lua : options + high scores, saved in LÖVE's save folder as settings.txt
local Settings = {}

Settings.data = {
  master = 8, music = 6, sfx = 8, shake = true, fullscreen = false,
  best_score = 0, best_dist = 0, best_passengers = 0, runs = 0, wins = 0, boss_kills = 0,
}

local FILE = "settings.txt"

function Settings.load()
  if not love.filesystem.getInfo(FILE) then return end
  for line in love.filesystem.lines(FILE) do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k and Settings.data[k] ~= nil then
      if v == "true" then v = true elseif v == "false" then v = false else v = tonumber(v) or v end
      if type(v) == type(Settings.data[k]) then Settings.data[k] = v end
    end
  end
end

function Settings.save()
  local keys = {}
  for k in pairs(Settings.data) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(Settings.data[k]) end
  pcall(love.filesystem.write, FILE, table.concat(out, "\n"))
end

-- volume helpers (0..1)
function Settings.sfxVolume() return Settings.data.master / 10 * Settings.data.sfx / 10 end
function Settings.musicVolume() return Settings.data.master / 10 * Settings.data.music / 10 end

-- records a finished run; returns true if it is a new best score
function Settings.recordRun(score, dist, passengers, won, boss)
  local d = Settings.data
  d.runs = d.runs + 1
  if won then d.wins = d.wins + 1 end
  if boss then d.boss_kills = d.boss_kills + 1 end
  local best = score > d.best_score
  if best then d.best_score = score end
  d.best_dist = math.max(d.best_dist, math.floor(dist * 10) / 10)
  if won then d.best_passengers = math.max(d.best_passengers, passengers) end
  Settings.save()
  return best
end

return Settings
