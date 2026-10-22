-- ============================================================================
-- special_events_core.lua — GSpecialEvents Core Engine & Modular Dispatcher
-- Provides selective runtime event loading, GMenu synchronization, and hooks.
-- ============================================================================

local core = {}
core.VERSION = "1.0.0"

-- Global access
_G.SpecialEvents = core

-- Active state
core.selectedEvent = "Auto"    -- "Auto", specific event name, or "None"
core.activeEvent = ""          -- Evaluated runtime event name (e.g. "Halloween")
core.activeModule = nil        -- Currently loaded event module table
core.registeredModules = {}    -- Cached modules: name -> moduleTable

-- Default configuration settings
core.settings = {
  selectedEvent = "Auto",
  halloween = {
    zombiesAttackGermans = 1,
    germansAttackZombies = 1,
    corpseReanimation = 1,
    reanimationTarget = "Zombie Kills Only", -- "Zombie Kills Only" or "All Casualties"
    reanimationDelay = 2.5,
    zombieHealth = 500,
    zombieSpeedMult = 1.0,
    spawnDistribution = "Distributed",      -- "Distributed", "Tombs Only", "Everywhere"
    waveSpawnChance = 25,
    zombieClawsDamage = 25,
    soundDeath = 1
  }
}

-- Safe sound trigger helper
local function playSfx(sfx, volume)
  if sfx and type(sfx.clone) == "function" then
    local ok, c = pcall(sfx.clone, sfx)
    if ok and c and type(c.play) == "function" then
      if volume and type(c.setVolume) == "function" then
        pcall(c.setVolume, c, volume)
      end
      pcall(c.play, c)
    end
  end
end

-- ============================================================================
-- PERSISTENCE (saveSpecialEvents.lua)
-- ============================================================================

function core.loadSettings()
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo("saveSpecialEvents.lua") then
    local ok, chunk = pcall(love.filesystem.load, "saveSpecialEvents.lua")
    if ok and type(chunk) == "function" then
      local ok2, data = pcall(chunk)
      if ok2 and type(data) == "table" then
        if data.selectedEvent ~= nil then
          core.settings.selectedEvent = data.selectedEvent
          core.selectedEvent = data.selectedEvent
        end
        if type(data.halloween) == "table" then
          for k, v in pairs(data.halloween) do
            core.settings.halloween[k] = v
          end
        end
        print("[GSpecialEvents] Loaded saved settings from saveSpecialEvents.lua")
        return
      end
    end
  end
end

function core.saveSettings()
  if love and love.filesystem then
    local ser = nil
    pcall(function() ser = require "includes/ser" end)
    local content = nil
    if ser then
      local ok, str = pcall(ser, core.settings)
      if ok and str then content = "return " .. str end
    end
    if not content then
      -- Simple serializer fallback
      local h = core.settings.halloween
      content = string.format([[return {
  selectedEvent = %q,
  halloween = {
    zombiesAttackGermans = %d,
    germansAttackZombies = %d,
    corpseReanimation = %d,
    reanimationTarget = %q,
    reanimationDelay = %s,
    zombieHealth = %d,
    zombieSpeedMult = %s,
    spawnDistribution = %q,
    waveSpawnChance = %d,
    zombieClawsDamage = %d,
    soundDeath = %d
  }
}]],
        core.settings.selectedEvent or "Auto",
        h.zombiesAttackGermans or 1,
        h.germansAttackZombies or 1,
        h.corpseReanimation or 1,
        h.reanimationTarget or "Zombie Kills Only",
        tostring(h.reanimationDelay or 2.5),
        h.zombieHealth or 500,
        tostring(h.zombieSpeedMult or 1.0),
        h.spawnDistribution or "Distributed",
        h.waveSpawnChance or 25,
        h.zombieClawsDamage or 25,
        h.soundDeath or 1
      )
    end
    love.filesystem.write("saveSpecialEvents.lua", content)
  end
end

-- ============================================================================
-- SELECTIVE MODULE LOADER & EVENT RESOLUTION
-- ============================================================================

--- Determine effective event name based on setting and system calendar
function core.resolveActiveEventName()
  local sel = core.settings.selectedEvent or "Auto"
  if sel == "None" then
    return ""
  elseif sel == "Auto" then
    if type(_G.specialEventForDate) == "function" and _G.SPECIAL_EVENTS then
      -- Call original underlying calendar function if available
      local ok, ev = pcall(_G.specialEventForDate, _G.SPECIAL_EVENTS)
      if ok and ev then return ev end
    end
    return "Halloween" -- fallback default if calendar check unavailable
  else
    return sel
  end
end

--- Selectively load the module corresponding to the active event
function core.loadEventModule(eventName)
  -- 1. Unload previous module cleanly
  if core.activeModule and core.activeModule.onUnload then
    pcall(core.activeModule.onUnload, core)
  end
  core.activeModule = nil
  core.activeEvent = eventName or ""

  if not eventName or eventName == "" then
    print("[GSpecialEvents] Special events disabled (None).")
    return
  end

  -- 2. Check cached modules or dynamically require module file
  local mod = core.registeredModules[eventName]
  if not mod then
    local candidates = {
      "events/" .. string.lower(eventName),
      "events/" .. eventName,
      "Mods/GSpecialEvents/events/" .. string.lower(eventName),
      "Mods/GSpecialEvents/events/" .. eventName
    }
    for _, modPath in ipairs(candidates) do
      local ok, res = pcall(require, modPath)
      if ok and type(res) == "table" then
        mod = res
        core.registeredModules[eventName] = mod
        break
      end
    end
  end

  -- 3. Initialize module if found
  if mod then
    core.activeModule = mod
    if mod.onLoad then
      pcall(mod.onLoad, core)
    end
    print(string.format("[GSpecialEvents] Selectively loaded event module: [%s]", eventName))
  else
    print(string.format("[GSpecialEvents] Active event: [%s] (Vanilla logic, no custom module)", eventName))
  end
end

--- Change selected event from UI / GMenu
function core.setSelectedEvent(eventName)
  core.settings.selectedEvent = eventName
  core.selectedEvent = eventName

  local resolved = core.resolveActiveEventName()
  _G.specialEvent = resolved
  core.loadEventModule(resolved)
  core.saveSettings()

  print(string.format("[GSpecialEvents] Selected event changed to: '%s' (Resolved: '%s')", eventName, resolved))
end

function core.getSelectedEvent()
  return core.settings.selectedEvent or "Auto"
end

function core.getActiveEvent()
  return core.activeEvent or core.resolveActiveEventName() or ""
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function core.init()
  core.loadSettings()
  local resolved = core.resolveActiveEventName()
  _G.specialEvent = resolved
  core.loadEventModule(resolved)
  print(string.format("[GSpecialEvents] Initialized v%s — Selected: '%s', Active: '%s'", core.VERSION, core.settings.selectedEvent, resolved))
end

-- ============================================================================
-- DISPATCHER HOOKS (CALLED BY GAME ENGINE)
-- ============================================================================

--- Hostility check for 3-way combat: is 'target' an enemy to 'dude'?
-- Returns boolean. If no custom module or event active, falls back to faction inequality.
function core.isHostile(dude, target)
  if not dude or not target then return false end
  if dude.id == target.id then return false end

  if core.activeModule and core.activeModule.isHostile then
    local ok, res = pcall(core.activeModule.isHostile, dude, target, core)
    if ok and res ~= nil then return res end
  end

  -- Standard vanilla fallback
  return dude.faction ~= target.faction
end

-- Register global hostility checker
function _G.isHostileTo(dude, target)
  return core.isHostile(dude, target)
end

--- Custom zombie spawning hook: returns true if handled by module
function core.onSpawnZombies(amount)
  if core.activeModule and core.activeModule.spawnZombies then
    local ok, res = pcall(core.activeModule.spawnZombies, amount, core)
    if ok and res == true then return true end
  end
  return false
end

--- Soldier death notification hook (corpse reanimation and zombie sound)
function core.onDeath(dude)
  if not dude then return end

  -- Zombie death sound Death
  if dude.tag == "zombie" and core.settings.halloween.soundDeath == 1 then
    playSfx(_G.zombieDeadSound, 0.8)
  end

  if core.activeModule and core.activeModule.onDeath then
    pcall(core.activeModule.onDeath, dude, core)
  end
end

--- Main per-frame update hook (called during runTime0)
function core.onUpdate(dt)
  if core.activeModule and core.activeModule.onUpdate then
    pcall(core.activeModule.onUpdate, dt, core)
  end
end

--- Zombie speed scale hook
function core.getZombieSpeed(soldier)
  if not soldier then return 50 end
  if core.activeModule and core.activeModule.getZombieSpeed then
    local ok, spd = pcall(core.activeModule.getZombieSpeed, soldier, core)
    if ok and spd then return spd end
  end
  return soldier.speed or 50
end

--- Zombie idle pathfinding / target hunting hook
-- Returns true if soldier.targetx / targety was updated by the module
function core.onZombieIdle(soldier)
  if core.activeModule and core.activeModule.onZombieIdle then
    local ok, res = pcall(core.activeModule.onZombieIdle, soldier, core)
    if ok and res == true then return true end
  end
  return false
end

--- Halloween wave spawn chance hook
function core.getWaveSpawnChance()
  if core.activeEvent == "Halloween" and core.settings.halloween.waveSpawnChance then
    return core.settings.halloween.waveSpawnChance
  end
  return 10 -- Vanilla 10%
end

--- CQC hit hook: tracks lethal blow from zombie to flag corpse for reanimation
function core.onCqcHit(attacker, defender, damage)
  if not attacker or not defender then return end
  if attacker.tag == "zombie" and (defender.health - damage) <= 0 then
    defender._killedByZombie = true
  end
  if core.activeModule and core.activeModule.onCqcHit then
    pcall(core.activeModule.onCqcHit, attacker, defender, damage, core)
  end
end

return core
