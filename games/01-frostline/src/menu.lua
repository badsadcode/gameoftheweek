-- menu.lua : small list menus (title, pause, settings, trader).
-- item = { label = string|function, action = fn, adjust = fn(dir), disabled = fn, hint = string|function }
local Audio = require("audio")
local lg = love.graphics

local Menu = {}
Menu.__index = Menu

function Menu.new(title, items, opts)
  return setmetatable({ title = title, items = items, index = 1, opts = opts or {} }, Menu)
end

local function text(v) if type(v) == "function" then return v() end return v end
local function isDisabled(item) return item.disabled and item.disabled() end

function Menu:move(d)
  local n = #self.items
  for _ = 1, n do
    self.index = (self.index - 1 + d) % n + 1
    if not isDisabled(self.items[self.index]) then break end
  end
  Audio.play("clack", 0.4, 1.6)
end

function Menu:activate()
  local item = self.items[self.index]
  if not item or isDisabled(item) then Audio.play("hurt", 0.2, 1.8); return end
  if item.action then Audio.play("pickup", 0.4, 1.2); item.action() end
end

function Menu:adjust(d)
  local item = self.items[self.index]
  if item and item.adjust and not isDisabled(item) then item.adjust(d); Audio.play("clack", 0.4, 1.3) end
end

-- returns true when the menu consumed the action
function Menu:handle(action)
  if action == "menu_up" then self:move(-1)
  elseif action == "menu_down" then self:move(1)
  elseif action == "menu_left" then self:adjust(-1)
  elseif action == "menu_right" then self:adjust(1)
  elseif action == "confirm" then self:activate()
  else return false end
  return true
end

function Menu:draw(fonts, cx, y, width)
  width = width or 460
  local x = cx - width / 2
  local rowH = self.opts.rowH or 44
  local hasHints = false
  for _, it in ipairs(self.items) do if it.hint then hasHints = true end end
  local head = self.opts.noTitle and 14 or 62
  local h = head + 8 + #self.items * rowH + (hasHints and 30 or 10)
  lg.setColor(0.03, 0.04, 0.08, 0.86)
  lg.rectangle("fill", x, y, width, h, 10, 10)
  lg.setColor(0.6, 0.75, 1, 0.25)
  lg.rectangle("line", x + 0.5, y + 0.5, width - 1, h - 1, 10, 10)
  if not self.opts.noTitle then
    lg.setFont(fonts.med)
    lg.setColor(1, 0.75, 0.4)
    lg.printf(text(self.title), x, y + 18, width, "center")
  end
  local t = love.timer.getTime()
  for i, item in ipairs(self.items) do
    local ry = y + head + (i - 1) * rowH
    local sel = i == self.index
    if sel then
      lg.setColor(1, 0.6, 0.2, 0.18 + 0.06 * math.sin(t * 6))
      lg.rectangle("fill", x + 14, ry, width - 28, rowH - 6, 6, 6)
    end
    lg.setFont(fonts.small)
    if isDisabled(item) then lg.setColor(0.5, 0.52, 0.58)
    elseif sel then lg.setColor(1, 0.92, 0.7)
    else lg.setColor(0.85, 0.9, 1) end
    local label = text(item.label)
    if item.adjust then label = "<  " .. label .. "  >" end
    lg.printf(label, x + 20, ry + 10, width - 40, self.opts.align or "center")
    if sel and item.hint then
      lg.setFont(fonts.tiny)
      lg.setColor(0.7, 0.75, 0.85)
      lg.printf(text(item.hint), x, y + h - 26, width, "center")
    end
  end
  return h
end

return Menu
