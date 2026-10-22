-- ============================================================================
-- events/remembrance.lua — Remembrance Day Tribute Event Module
-- ============================================================================

local remembrance = {}

function remembrance.onLoad(core)
  print("[GSpecialEvents] Remembrance Day tribute event module loaded.")
  if anounceStuff then
    anounceStuff("Remembrance Day: A tribute to the fallen of every front.")
  end
end

function remembrance.onUnload(core)
  print("[GSpecialEvents] Remembrance Day tribute event module unloaded.")
end

function remembrance.isHostile(dude, target, core)
  -- Standard vanilla hostility
  return dude.faction ~= target.faction
end

return remembrance
