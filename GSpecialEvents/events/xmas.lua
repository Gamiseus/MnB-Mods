-- ============================================================================
-- events/xmas.lua — Christmas Bastogne Special Event Module
-- ============================================================================

local xmas = {}

function xmas.onLoad(core)
  print("[GSpecialEvents] Christmas Bastogne event module loaded.")
  if anounceStuff then
    anounceStuff("Bastogne Christmas Offensive active! Watch out for Santa.")
  end
end

function xmas.onUnload(core)
  print("[GSpecialEvents] Christmas Bastogne event module unloaded.")
end

function xmas.isHostile(dude, target, core)
  -- Standard vanilla hostility
  return dude.faction ~= target.faction
end

return xmas
