-- ============================================================================
-- events/general.lua — General Fallback / Modular Event Template
-- ============================================================================

local general = {}

function general.onLoad(core)
  print("[GSpecialEvents] Generic event module loaded for: " .. tostring(core.activeEvent))
end

function general.onUnload(core)
  print("[GSpecialEvents] Generic event module unloaded.")
end

function general.isHostile(dude, target, core)
  return dude.faction ~= target.faction
end

return general
