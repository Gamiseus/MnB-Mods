-- ============================================================================
-- config.lua — Tactical Overhaul configuration definition for GMenu
-- ============================================================================

local config = {
  name = "Tactical Overhaul",
  options = {
    {
      id = "squad_limit",
      label = "Squad Size Limit",
      type = "cycle",
      options = { 6, 8, 10, 12, 16, 24, 32, "OFF" },
      labels = { "6", "8", "10", "12", "16", "24", "32", "OFF" },
      default = 6,
      description = "Exposed soldier threshold before German counter-assault waves trigger (Default: 6)",
      get = function()
        local enabled = (modSettings and modSettings.squadLimitEnabled)
        if enabled == 0 then return "OFF" end
        return (modSettings and modSettings.squadLimitThreshold) or (player and player.option_squadLimitThreshold) or 6
      end,
      set = function(val)
        if val == "OFF" then
          if modSettings then modSettings.squadLimitEnabled = 0 end
          if player then player.option_squadLimitEnabled = 0 end
        else
          local numVal = tonumber(val) or 6
          if modSettings then
            modSettings.squadLimitEnabled = 1
            modSettings.squadLimitThreshold = numVal
          end
          if player then
            player.option_squadLimitEnabled = 1
            player.option_squadLimitThreshold = numVal
          end
        end
        if saveModSettings then saveModSettings() end
      end
    },
    {
      id = "smart_move",
      label = "Smart Squad Move",
      type = "checkbox",
      default = 1,
      description = "Weighted cover distribution, overwatch spacing, and medic placement on squad move orders",
      get = function()
        return (modSettings and modSettings.smartMoveEnabled) or (player and player.option_smartMoveEnabled) or 1
      end,
      set = function(val)
        local numVal = (val == true or val == 1) and 1 or 0
        if modSettings then modSettings.smartMoveEnabled = numVal end
        if player then player.option_smartMoveEnabled = numVal end
        if saveModSettings then saveModSettings() end
      end
    }
  }
}

return config
