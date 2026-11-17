-- Frostline: Last Train to Haven
-- Bad Ideas Works · Games of the Week · Week 1

function love.conf(t)
  t.identity = "frostline"
  t.version = "11.4"
  t.window.title = "Frostline - Last Train to Haven"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.vsync = 1
  t.window.msaa = 4
  t.modules.joystick = true
  t.modules.physics = false
  t.modules.video = false
end
