-- music.lua : a procedural, adaptive soundtrack.
-- Five layers of identical length loop in sync; their volumes follow the action:
--   pad + arp  : always (the lonely frozen night)
--   bass + drums: fade in with danger (raiders aboard, fires, low fuel)
--   boss       : the Iron Jaw finale
-- Chords: Am - F - Dm - E, one bar each at 92 BPM.
local Music = {}
Music.volume = 0.5

local SR = 22050
local TAU = math.pi * 2
local BPM = 92
local BEAT = 60 / BPM
local BAR = BEAT * 4
local BARS = 4
local LEN = BAR * BARS

local CHORDS = {
  { 110.00, 130.81, 164.81 }, -- Am
  { 87.31, 110.00, 130.81 },  -- F
  { 146.83, 174.61, 220.00 }, -- Dm
  { 82.41, 103.83, 123.47 },  -- E
}

local layers = {}
local current = { pad = 0, arp = 0, bass = 0, drums = 0, boss = 0 }
local target = { pad = 1, arp = 0.7, bass = 0, drums = 0, boss = 0 }
local MIX = { pad = 0.55, arp = 0.45, bass = 0.6, drums = 0.6, boss = 0.75 }

local function render(fn)
  local n = math.floor(LEN * SR)
  local sd = love.sound.newSoundData(n, SR, 16, 1)
  for i = 0, n - 1 do
    local t = i / SR
    local bar = math.floor(t / BAR)
    local v = fn(t, bar % BARS + 1, t - bar * BAR)
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i, v)
  end
  return sd
end

local function noise() return love.math.random() * 2 - 1 end

local function build()
  local d = {}
  -- soft detuned pad, crossfaded per bar
  d.pad = render(function(t, c, tb)
    local env = math.min(1, tb / 0.4) * math.min(1, (BAR - tb) / 0.25 + 0.15)
    local v = 0
    for _, f in ipairs(CHORDS[c]) do
      v = v + math.sin(TAU * f * 2 * t) + 0.6 * math.sin(TAU * f * 2.006 * t) + 0.3 * math.sin(TAU * f * 4 * t)
    end
    return v * 0.045 * env
  end)
  -- plucked arpeggio, 8th notes
  local pattern = { 1, 2, 3, 2, 4, 3, 2, 3 }
  d.arp = render(function(t, c, tb)
    local step = math.floor(tb / (BEAT / 2))
    local ts = tb - step * (BEAT / 2)
    local idx = pattern[step % 8 + 1]
    local ch = CHORDS[c]
    local f = (idx == 4 and ch[1] * 2 or ch[idx]) * 4
    return (math.sin(TAU * f * t) + 0.35 * math.sin(TAU * f * 2 * t)) * math.exp(-ts * 7) * 0.16
  end)
  -- pulsing bass, quarter notes
  d.bass = render(function(t, c, tb)
    local beat = math.floor(tb / BEAT)
    local ts = tb - beat * BEAT
    local f = CHORDS[c][1] / (CHORDS[c][1] > 100 and 2 or 1)
    local s = math.sin(TAU * f * t)
    local sq = math.max(-1, math.min(1, s * 3))
    return sq * math.exp(-ts * 3.5) * 0.3
  end)
  -- kick / snare / hats
  do
    d.drums = render(function(t, c, tb)
      local beat = math.floor(tb / BEAT)
      local tbeat = tb - beat * BEAT
      local v = 0
      if beat == 0 or beat == 2 or (beat == 3 and tbeat > BEAT / 2) then
        local tk = beat == 3 and (tbeat - BEAT / 2) or tbeat
        v = v + math.sin(TAU * (45 + 90 * math.exp(-tk * 25)) * tk) * math.exp(-tk * 9) * 0.7
      end
      if beat == 1 or beat == 3 then
        v = v + noise() * math.exp(-tbeat * 18) * 0.35
      end
      local t8 = tb % (BEAT / 2)
      v = v + noise() * math.exp(-t8 * 55) * 0.12 -- hats: raw noise is bright enough
      return v
    end)
  end
  -- boss: driving 16th-note bass + clap + a stabbing high fifth
  d.boss = render(function(t, c, tb)
    local s16 = BEAT / 4
    local step = math.floor(tb / s16)
    local ts = tb - step * s16
    local f = CHORDS[c][1] / 2
    if step % 4 == 3 then f = f * 2 end
    local saw = ((f * t) % 1) * 2 - 1
    local v = saw * math.exp(-ts * 14) * 0.28
    local beat = math.floor(tb / BEAT)
    local tbeat = tb - beat * BEAT
    if beat % 2 == 1 then v = v + noise() * math.exp(-tbeat * 25) * 0.3 end
    if step % 8 == 0 then
      local hf = CHORDS[c][1] * 6
      v = v + (math.sin(TAU * hf * t) + math.sin(TAU * hf * 1.5 * t)) * math.exp(-ts * 4) * 0.08
    end
    return v
  end)
  return d
end

function Music.load()
  for name, sd in pairs(build()) do
    local src = love.audio.newSource(sd, "static")
    src:setLooping(true)
    src:setVolume(0)
    layers[name] = src
  end
  -- start every layer on the same frame so they stay in sync
  for _, src in pairs(layers) do src:play() end
end

-- mood = { danger = 0..1, boss = 0..1, calm = 0..1 }
function Music.setMood(mood)
  local calm = mood.calm or 1
  target.pad = calm
  target.arp = calm * (0.55 + 0.45 * (1 - (mood.danger or 0)))
  target.bass = math.max(mood.danger or 0, (mood.boss or 0) * 0.6)
  target.drums = mood.danger or 0
  target.boss = mood.boss or 0
end

function Music.update(dt)
  for name, src in pairs(layers) do
    current[name] = current[name] + (target[name] - current[name]) * math.min(1, dt * 1.2)
    src:setVolume(current[name] * MIX[name] * Music.volume)
  end
end

return Music
