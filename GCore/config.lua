-- ============================================================================
-- config.lua — Tactical Overhaul configuration definition for GMenu
-- ============================================================================

local config = {
  name = "GCore",
  options = {
    {
      id = "safe_destination",
      label = "Safer Destinations",
      type = "checkbox",
      default = 1,
      description = "Avoids sending soldiers to locations where they can't actually go",
      get = function()
        return (modSettings and modSettings.safeDestinationEnabled) or (player and player.option_safeDestinationEnabled) or 1
      end,
      set = function(val)
        local numVal = (val == true or val == 1) and 1 or 0
        if modSettings then modSettings.safeDestinationEnabled = numVal end
        if player then player.option_safeDestinationEnabled = numVal end
        if saveModSettings then saveModSettings() end
      end
    },
    {
      id = "pathfinding",
      label = "Real Pathfinding",
      type = "checkbox",
      default = 1,
      description = "A* hazard & obstacle avoidance pathfinding for infantry and vehicles (Shift+F9 in-game overlay)",
      get = function()
        return (modSettings and modSettings.pathfindingEnabled) or (player and player.option_pathfindingEnabled) or 1
      end,
      set = function(val)
        local numVal = (val == true or val == 1) and 1 or 0
        if modSettings then modSettings.pathfindingEnabled = numVal end
        if player then player.option_pathfindingEnabled = numVal end
        if saveModSettings then saveModSettings() end
      end
    }
  }
}

return config
