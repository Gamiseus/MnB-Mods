-- truesight.lua
-- Keybind actions for TrueSight.

local M = {}

local function cue(text)
  print("[TrueSight] " .. text)
  if player and player.textCue then
    player.textCue[#player.textCue + 1] = { name = text, x = (player.screenx or 0) + 600, y = 300, alpha = 255 }
  end
end

--- Shows or hides the line-of-sight overlay.
function M.toggleOverlay()
  los_physics.debugOverlay = not los_physics.debugOverlay
  cue(los_physics.debugOverlay and "Line of sight overlay ON" or "Line of sight overlay OFF")
end

return M
