-- ============================================================================
-- display_scale.lua — Resolution Independence, Aspect Scaling & Window Manager
-- Part of GCore Mod for Mud and Blood (LÖVE 11.4)
-- ============================================================================

local display_scale = {}

display_scale.VIRTUAL_W = 1280
display_scale.VIRTUAL_H = 720
display_scale.scale = 1.0
display_scale.offsetX = 0
display_scale.offsetY = 0

local origMouseGetPosition = love.mouse.getPosition
local origMouseGetX = love.mouse.getX
local origMouseGetY = love.mouse.getY
local origMouseSetPosition = love.mouse.setPosition

local origSetFullscreen = love.window.setFullscreen
local origSetMode = love.window.setMode

-- Recompute uniform aspect ratio scaling and letterbox/pillarbox offsets
function display_scale.recompute()
  local winW, winH = love.graphics.getDimensions()
  if not winW or not winH or winW <= 0 or winH <= 0 then return end
  local sx = winW / display_scale.VIRTUAL_W
  local sy = winH / display_scale.VIRTUAL_H
  display_scale.scale = math.min(sx, sy)
  display_scale.offsetX = math.floor((winW - display_scale.VIRTUAL_W * display_scale.scale) / 2)
  display_scale.offsetY = math.floor((winH - display_scale.VIRTUAL_H * display_scale.scale) / 2)
end

-- Convert physical window coordinates to virtual 1280x720 coordinates
function display_scale.toVirtual(x, y)
  if not x or not y then return x, y end
  local vx = (x - display_scale.offsetX) / display_scale.scale
  local vy = (y - display_scale.offsetY) / display_scale.scale
  return vx, vy
end

-- Convert virtual 1280x720 coordinates to physical window coordinates
function display_scale.toWindow(vx, vy)
  if not vx or not vy then return vx, vy end
  local x = math.floor(vx * display_scale.scale + display_scale.offsetX)
  local y = math.floor(vy * display_scale.scale + display_scale.offsetY)
  return x, y
end

-- Called at the beginning of love.draw()
function display_scale.beginDraw()
  display_scale.recompute()
  -- Render black bars outside the active 16:9 viewport
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.push()
  love.graphics.translate(display_scale.offsetX, display_scale.offsetY)
  love.graphics.scale(display_scale.scale, display_scale.scale)
  -- Scissor to keep rendering strictly bounded inside the 16:9 virtual display
  love.graphics.setScissor(
    display_scale.offsetX,
    display_scale.offsetY,
    math.floor(display_scale.VIRTUAL_W * display_scale.scale),
    math.floor(display_scale.VIRTUAL_H * display_scale.scale)
  )
end

-- Called at the end of love.draw()
function display_scale.endDraw()
  love.graphics.setScissor()
  love.graphics.pop()
end

-- Toggle fullscreen cleanly using "desktop" mode
function display_scale.toggleFullscreen()
  local cur = love.window.getFullscreen()
  local target = not cur
  love.window.setFullscreen(target, "desktop")
  display_scale.recompute()
  if player then
    player.fullScreen = target and 1 or 0
    if player.textCue then
      player.textCue[#player.textCue + 1] = {}
      player.textCue[#player.textCue].name = target and "Fullscreen Enabled" or "Windowed Mode"
      player.textCue[#player.textCue].x = (player.screenx or 0) + 600
      player.textCue[#player.textCue].y = 300
      player.textCue[#player.textCue].alpha = 255
    end
  end
end

-- Initialize display scaling hooks and overrides
function display_scale.init()
  display_scale.recompute()

  -- Hook mouse coordinate getters so game logic always receives virtual coords
  love.mouse.getPosition = function()
    local wx, wy = origMouseGetPosition()
    return display_scale.toVirtual(wx, wy)
  end

  love.mouse.getX = function()
    local vx, _ = love.mouse.getPosition()
    return vx
  end

  love.mouse.getY = function()
    local _, vy = love.mouse.getPosition()
    return vy
  end

  if origMouseSetPosition then
    love.mouse.setPosition = function(vx, vy)
      local wx, wy = display_scale.toWindow(vx, vy)
      return origMouseSetPosition(wx, wy)
    end
  end

  -- Wrap love.mousepressed and love.mousereleased
  local origMousePressed = love.mousepressed
  love.mousepressed = function(x, y, button, istouch, presses)
    local vx, vy = display_scale.toVirtual(x, y)
    if origMousePressed then
      return origMousePressed(vx, vy, button, istouch, presses)
    end
  end

  local origMouseReleased = love.mousereleased
  love.mousereleased = function(x, y, button, istouch, presses)
    local vx, vy = display_scale.toVirtual(x, y)
    if origMouseReleased then
      return origMouseReleased(vx, vy, button, istouch, presses)
    end
  end

  -- Hook love.resize
  local origResize = love.resize
  love.resize = function(w, h)
    display_scale.recompute()
    if origResize then
      origResize(w, h)
    end
  end

  -- Override love.window.setFullscreen to always use "desktop" borderless fullscreen
  love.window.setFullscreen = function(fs, fstype)
    local ok = origSetFullscreen(fs, "desktop")
    display_scale.recompute()
    if player then
      player.fullScreen = fs and 1 or 0
    end
    return ok
  end

  -- Override love.window.setMode to preserve resizable = true and min dimensions
  love.window.setMode = function(w, h, flags)
    flags = flags or {}
    flags.resizable = true
    flags.minwidth = 1280
    flags.minheight = 720
    local ok = origSetMode(w, h, flags)
    display_scale.recompute()
    return ok
  end
end

return display_scale
