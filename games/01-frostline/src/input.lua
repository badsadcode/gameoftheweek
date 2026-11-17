-- input.lua : one place that knows about keyboards and gamepads.
-- Game code asks for actions ("left", "jump", "interact"...) instead of raw keys.
--   Input.down(action)        held? (movement)
--   Input.fromKey(key)        -> list of actions for a key press
--   Input.fromButton(button)  -> list of actions for a gamepad button press
--   Input.label(action)       -> "E" or "B" etc, matching the device used last
local Input = {}
Input.device = "keyboard"

local HELD_KEYS = {
  left = { "a", "left" }, right = { "d", "right" }, up = { "w", "up" }, down = { "s", "down" },
}

local PRESS_KEYS = {
  jump = { "space" }, attack = { "j", "k", "f" }, interact = { "e" }, pause = { "escape", "p" },
  roster = { "tab" },
  confirm = { "return", "kpenter", "space", "e" }, back = { "escape", "backspace" },
  menu_up = { "w", "up" }, menu_down = { "s", "down" }, menu_left = { "a", "left" }, menu_right = { "d", "right" },
}

local PRESS_BUTTONS = {
  jump = { "a" }, attack = { "x", "rightshoulder" }, interact = { "b", "leftshoulder" }, pause = { "start" },
  roster = { "back" },
  confirm = { "a" }, back = { "b", "start" },
  menu_up = { "dpup" }, menu_down = { "dpdown" }, menu_left = { "dpleft" }, menu_right = { "dpright" },
}

local LABELS = {
  keyboard = { interact = "E", attack = "J", jump = "Space", down = "S", up = "W", pause = "Esc", confirm = "Enter", roster = "Tab" },
  gamepad = { interact = "B", attack = "X", jump = "A", down = "Down", up = "Up", pause = "Start", confirm = "A", roster = "Back" },
}

local DEAD = 0.4

local function pads()
  local list = {}
  if not love.joystick then return list end
  for _, js in ipairs(love.joystick.getJoysticks()) do
    if js:isGamepad() then list[#list + 1] = js end
  end
  return list
end

local function padHeld(action)
  for _, js in ipairs(pads()) do
    local x, y = js:getGamepadAxis("leftx"), js:getGamepadAxis("lefty")
    if action == "left" and (x < -DEAD or js:isGamepadDown("dpleft")) then return true end
    if action == "right" and (x > DEAD or js:isGamepadDown("dpright")) then return true end
    if action == "up" and (y < -DEAD or js:isGamepadDown("dpup")) then return true end
    if action == "down" and (y > DEAD or js:isGamepadDown("dpdown")) then return true end
  end
  return false
end

function Input.down(action)
  for _, k in ipairs(HELD_KEYS[action] or {}) do
    if love.keyboard.isDown(k) then return true end
  end
  return padHeld(action)
end

local function lookup(map, key)
  local out = {}
  for action, list in pairs(map) do
    for _, k in ipairs(list) do
      if k == key then out[#out + 1] = action end
    end
  end
  return out
end

function Input.fromKey(key)
  Input.device = "keyboard"
  return lookup(PRESS_KEYS, key)
end

function Input.fromButton(button)
  Input.device = "gamepad"
  return lookup(PRESS_BUTTONS, button)
end

-- left stick flicks act like d-pad presses in menus
local stickState = { x = 0, y = 0 }
function Input.fromAxis(axis, value)
  local out = {}
  if axis == "leftx" or axis == "lefty" then
    local key = axis == "leftx" and "x" or "y"
    local dir = value > 0.6 and 1 or (value < -0.6 and -1 or 0)
    if dir ~= stickState[key] then
      stickState[key] = dir
      if dir ~= 0 then
        Input.device = "gamepad"
        if key == "y" then out[1] = dir < 0 and "menu_up" or "menu_down"
        else out[1] = dir < 0 and "menu_left" or "menu_right" end
      end
    end
  end
  return out
end

function Input.label(action)
  return LABELS[Input.device][action] or action
end

function Input.has(list, action)
  for _, a in ipairs(list) do if a == action then return true end end
  return false
end

return Input
