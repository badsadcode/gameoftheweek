-- audio.lua : every sound is synthesized at startup. No asset files needed.
local A = {}
A.master = 0.8

local SR = 22050
local TAU = math.pi * 2
local sources = {}

local function noise() return love.math.random() * 2 - 1 end

-- one-pole low-pass that keeps its own state
local function lowpass(k)
  local y = 0
  return function(x) y = y + k * (x - y); return y end
end

local function render(dur, fn)
  local n = math.floor(dur * SR)
  local sd = love.sound.newSoundData(n, SR, 16, 1)
  for i = 0, n - 1 do
    local v = fn(i / SR, i / n)
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i, v)
  end
  return sd
end

-- phase accumulator oscillator (so frequency sweeps sound right)
local function osc()
  local ph = 0
  return function(freq) ph = ph + freq / SR; return math.sin(ph * TAU) end
end

local function build()
  local d = {}

  do local lp = lowpass(0.07)
    d.chug = render(0.24, function(t) return lp(noise()) * math.exp(-t * 14) * 3.4 end) end

  d.clack = render(0.09, function(t)
    return (math.sin(TAU * 1180 * t) * 0.5 + math.sin(TAU * 2350 * t) * 0.25 + noise() * 0.2) * math.exp(-t * 60)
  end)

  do local lp, lp2 = lowpass(0.025), lowpass(0.2)
    d.wind = render(4.0, function(t, u)
      local edge = math.min(1, u * 20, (1 - u) * 20)
      local m = 0.65 + 0.35 * math.sin(TAU * t * 0.5)
      return (lp(noise()) * 5 + lp2(noise()) * 0.15) * m * edge
    end) end

  do local lp = lowpass(0.25)
    d.swing = render(0.17, function(t, u) return lp(noise()) * math.sin(math.pi * u) * 0.9 end) end

  do local o = osc()
    d.hit = render(0.22, function(t)
      return (o(140 - 300 * t) * 0.9 + noise() * 0.5 * math.exp(-t * 40)) * math.exp(-t * 14)
    end) end

  do local lp = lowpass(0.18)
    d.shovel = render(0.32, function(t)
      local grain = (math.sin(t * 160) > 0.2) and 1 or 0.35
      return lp(noise()) * grain * math.exp(-t * 7) * 1.8
    end) end

  do local lp = lowpass(0.05)
    d.whoosh = render(0.6, function(t) return lp(noise()) * math.min(1, t * 12) * math.exp(-t * 5) * 3.5 end) end

  d.bell = render(1.5, function(t)
    local v = math.sin(TAU * 880 * t) + 0.5 * math.sin(TAU * 2215 * t) + 0.35 * math.sin(TAU * 1320 * t)
    local strike = (t % 0.5)
    return v * math.exp(-strike * 5) * 0.3
  end)

  d.alarm = render(0.5, function(t)
    local f = ((t * 6) % 1 < 0.5) and 660 or 880
    local sq = (math.sin(TAU * f * t) > 0) and 1 or -1
    return sq * 0.18 * math.min(1, (0.5 - t) * 20)
  end)

  d.pickup = render(0.25, function(t)
    local f = t < 0.08 and 660 or 990
    return math.sin(TAU * f * t) * math.exp(-t * 9) * 0.5
  end)

  do local o = osc()
    d.hurt = render(0.28, function(t) return (o(420 - 900 * t) * 0.6 + noise() * 0.2) * math.exp(-t * 9) end) end

  do local o1, o2, o3 = osc(), osc(), osc()
    local lp = lowpass(0.3)
    d.whistle = render(1.9, function(t)
      local env = math.min(1, t * 8) * math.min(1, (1.9 - t) * 3)
      local wob = 1 + 0.004 * math.sin(TAU * 5 * t)
      return (o1(440 * wob) + o2(554 * wob) * 0.8 + o3(659 * wob) * 0.6 + lp(noise()) * 0.6) * env * 0.22
    end) end

  do local o = osc()
    d.grunt = render(0.25, function(t, u)
      local s = o(110 + 40 * math.sin(t * 50))
      return (s > 0 and 0.5 or -0.5) * math.sin(math.pi * u) * 0.5
    end) end

  do local o = osc()
    d.jump = render(0.15, function(t) return o(300 + 900 * t) * math.exp(-t * 18) * 0.35 end) end

  d.uncouple = render(0.7, function(t)
    return (math.sin(TAU * 310 * t) * 0.5 + math.sin(TAU * 470 * t) * 0.3 + noise() * 0.4 * math.exp(-t * 20)) * math.exp(-t * 5)
  end)

  d.lose = render(1.8, function(t)
    local notes = { 392, 349, 311, 262 }
    local i = math.min(4, math.floor(t / 0.42) + 1)
    local lt = t - (i - 1) * 0.42
    return (math.sin(TAU * notes[i] * t) + 0.3 * math.sin(TAU * notes[i] * 2 * t)) * math.exp(-lt * 3) * 0.3
  end)

  d.win = render(2.0, function(t)
    local notes = { 523, 659, 784, 1047 }
    local i = math.min(4, math.floor(t / 0.25) + 1)
    local lt = t - (i - 1) * 0.25
    return (math.sin(TAU * notes[i] * t) + 0.3 * math.sin(TAU * notes[i] * 3 * t)) * math.exp(-lt * (i == 4 and 1.5 or 4)) * 0.3
  end)

  do local lp = lowpass(0.4)
    d.brake = render(0.9, function(t)
      return (math.sin(TAU * 2600 * t + math.sin(t * 40)) * 0.15 + lp(noise()) * 0.3) * math.min(1, t * 10) * math.exp(-t * 3)
    end) end

  return d
end

function A.load()
  for name, sd in pairs(build()) do
    sources[name] = love.audio.newSource(sd, "static")
  end
end

function A.play(name, vol, pitch)
  local base = sources[name]
  if not base then return end
  local s = base:clone()
  s:setVolume((vol or 1) * A.master)
  s:setPitch(pitch or 1)
  s:play()
  return s
end

function A.loop(name, vol)
  local base = sources[name]
  if not base then return end
  local s = base:clone()
  s:setLooping(true)
  s:setVolume((vol or 1) * A.master)
  s:play()
  return s
end

return A
