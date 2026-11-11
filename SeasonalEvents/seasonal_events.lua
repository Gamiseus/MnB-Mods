-- seasonal_events.lua
-- Seasonal Events: choose which of the game's special events is active, and let an event
-- be a module that changes how the game plays while it is on.
--
-- The patches in qm.toml call the functions at the bottom of this file. Each hands the call
-- to the active event's module when it defines that function, and otherwise does what the
-- game does.
--
-- For other mods (global SpecialEvents):
--   SpecialEvents.register("Name", module)    add or replace an event module
--   SpecialEvents.getActiveEvent()            "" when no event is on
--   SpecialEvents.setSelectedEvent("Name")    "Auto", "None" or an event name
--   SpecialEvents.isHostile(a, b)             also the global isHostileTo(a, b)
--
-- An event module is a table with any of:
--   onLoad(core), onUnload(core)
--   isHostile(dude, target, core)             who fights whom
--   onDeath(dude, core), onUpdate(dt, core), onCqcHit(attacker, defender, damage, core)
--   spawnZombies(amount, core)                return true when it did the spawning
--   getZombieSpeed(soldier, core), onZombieIdle(soldier, core)
--   waveSpawnChance(core)                     percent chance of a zombie rising per wave

local core = {}
_G.SpecialEvents = core
_G.SeasonalEvents = core

local MOD_ID = "seasonal_events"

core.activeEvent = ""
core.activeModule = nil
core.registeredModules = {}

-- The Halloween options, read from Mod Settings. Event modules read this table.
core.settings = {
  selectedEvent = "Auto",
  halloween = {
    zombiesAttackGermans = true,
    germansAttackZombies = true,
    corpseReanimation = true,
    reanimationTarget = "Zombie Kills Only",
    reanimationDelay = 5,
    zombieHealth = 500,
    zombieSpeedMult = 1,
    spawnDistribution = "Distributed",
    waveSpawnChance = 25,
    zombieClawsDamage = 25,
    soundDeath = true,
  },
}

local function flag(v, default)
  if v == nil then return default end
  return v == true or v == 1
end

--- Copies Mod Settings into core.settings. Cheap; called a few times a second.
function core.readSettings()
  local q = QM and QM.settings and QM.settings[MOD_ID]
  if not q then return end
  local s, h = core.settings, core.settings.halloween
  s.selectedEvent = q.event_select or s.selectedEvent
  h.zombiesAttackGermans = flag(q.halloween_3way_zombies, h.zombiesAttackGermans)
  h.germansAttackZombies = flag(q.halloween_3way_germans, h.germansAttackZombies)
  h.corpseReanimation = flag(q.halloween_reanimation, h.corpseReanimation)
  h.soundDeath = flag(q.halloween_sound_death, h.soundDeath)
  h.reanimationTarget = q.halloween_reanim_target or h.reanimationTarget
  h.spawnDistribution = q.halloween_spawns or h.spawnDistribution
  h.reanimationDelay = tonumber(q.halloween_reanim_delay) or h.reanimationDelay
  h.zombieHealth = tonumber(q.halloween_zombie_hp) or h.zombieHealth
  h.zombieSpeedMult = tonumber(q.halloween_zombie_speed) or h.zombieSpeedMult
  h.waveSpawnChance = tonumber(q.halloween_wave_freq) or h.waveSpawnChance
  h.zombieClawsDamage = tonumber(q.halloween_zombie_dmg) or h.zombieClawsDamage
end

-- ---------------------------------------------------------------------------
-- Which event is on
-- ---------------------------------------------------------------------------

--- Adds or replaces an event module. `name` is the event's name as the game writes it
--- ("Halloween", "Xmas", "Remembrance") or a new one.
function core.register(name, module)
  assert(type(name) == "string" and type(module) == "table", "SpecialEvents.register(name, module)")
  core.registeredModules[name] = module
  if core.activeEvent == name then core.activate(name) end
end

local function findModule(name)
  local m = core.registeredModules[name]
  if m then return m end
  -- A module patch named events/<name> also counts.
  local ok, res = pcall(require, "events/" .. name:lower())
  if ok and type(res) == "table" then
    core.registeredModules[name] = res
    return res
  end
  return nil
end

local function vanillaHostile(dude, target)
  return dude.faction ~= target.faction
end

local hostile = vanillaHostile

--- Makes `name` the running event ("" for none) and loads its module, if it has one.
function core.activate(name)
  name = name or ""
  local old = core.activeModule
  if old and old.onUnload then old.onUnload(core) end
  core.activeEvent = name
  core.activeModule = name ~= "" and findModule(name) or nil
  local m = core.activeModule
  hostile = m and m.isHostile or vanillaHostile
  _G.specialEvent = name
  if m and m.onLoad then m.onLoad(core) end
  print(string.format("[SeasonalEvents] Active event: %s%s", name ~= "" and name or "none",
    m and "" or (name ~= "" and " (the game's own behaviour)" or "")))
end

--- The player's choice: "Auto" (by the calendar), "None", or an event name.
function core.getSelectedEvent()
  return core.settings.selectedEvent or "Auto"
end

--- The event that is running, "" for none.
function core.getActiveEvent()
  return core.activeEvent
end

-- The event the choice stands for today.
local function resolve()
  local sel = core.getSelectedEvent()
  if sel == "None" then return "" end
  if sel ~= "Auto" then return sel end
  -- The game's calendar. Patched to return the choice when it is not "Auto", so here it
  -- runs its own date check.
  if type(specialEventForDate) == "function" and SPECIAL_EVENTS then
    return specialEventForDate(SPECIAL_EVENTS) or ""
  end
  return ""
end

--- Sets the choice and switches to it at once.
function core.setSelectedEvent(name)
  core.settings.selectedEvent = name
  local q = QM and QM.settings and QM.settings[MOD_ID]
  if q then q.event_select = name end
  core.activate(resolve())
end

--- Called by the game's calendar function: the event to use, or nil to let the calendar
--- decide.
function core.override()
  local sel = core.getSelectedEvent()
  if sel == "Auto" then return nil end
  return sel == "None" and "" or sel
end

--- Once, after the game picked its event at start-up.
function core.init()
  core.readSettings()
  core.activate(resolve())
end

-- ---------------------------------------------------------------------------
-- Hooks the patches call
-- ---------------------------------------------------------------------------

--- Whether `target` is an enemy of `dude`. Called for every pair the AI considers, so it
--- does as little as possible.
function core.isHostile(dude, target)
  if dude.id == target.id then return false end
  return hostile(dude, target, core)
end

local isHostile = core.isHostile
function _G.isHostileTo(dude, target)
  return isHostile(dude, target)
end

local settingsTimer = 0

function core.onUpdate(dt)
  -- Pick up changes made in Mod Settings while playing.
  settingsTimer = settingsTimer - dt
  if settingsTimer <= 0 then
    settingsTimer = 0.5
    local before = core.settings.selectedEvent
    core.readSettings()
    if core.settings.selectedEvent ~= before then core.activate(resolve()) end
  end
  local m = core.activeModule
  if m and m.onUpdate then m.onUpdate(dt, core) end
end

function core.onDeath(dude)
  local m = core.activeModule
  if m and m.onDeath then m.onDeath(dude, core) end
end

function core.onCqcHit(attacker, defender, damage)
  local m = core.activeModule
  if m and m.onCqcHit then m.onCqcHit(attacker, defender, damage, core) end
end

--- True when the event's module spawned the zombies itself.
function core.onSpawnZombies(amount)
  local m = core.activeModule
  return m ~= nil and m.spawnZombies ~= nil and m.spawnZombies(amount, core) == true
end

function core.getZombieSpeed(soldier)
  local m = core.activeModule
  if m and m.getZombieSpeed then return m.getZombieSpeed(soldier, core) end
  return soldier.speed
end

--- True when the event's module gave the idle zombie somewhere to go.
function core.onZombieIdle(soldier)
  local m = core.activeModule
  return m ~= nil and m.onZombieIdle ~= nil and m.onZombieIdle(soldier, core) == true
end

--- Percent chance of zombies rising on a wave. The game's own value is 10.
function core.getWaveSpawnChance()
  local m = core.activeModule
  if m and m.waveSpawnChance then return m.waveSpawnChance(core) end
  return 10
end

return core
