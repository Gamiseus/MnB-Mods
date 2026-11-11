-- wayfinder.lua
-- Keybind actions for Wayfinder.

local M = {}

local function cue(text)
  print("[Wayfinder] " .. text)
  if player and player.textCue then
    player.textCue[#player.textCue + 1] = { name = text, x = (player.screenx or 0) + 600, y = 300, alpha = 255 }
  end
end

--- Shows or hides the navigation grid overlay.
function M.toggleOverlay()
  pathfinding.debugOverlay = not pathfinding.debugOverlay
  cue(pathfinding.debugOverlay and "Navigation grid overlay ON" or "Navigation grid overlay OFF")
end

return M
