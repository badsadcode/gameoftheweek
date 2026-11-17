-- Frostline: Last Train to Haven
-- Bad Ideas Works · Game of the Week #01

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
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
end
