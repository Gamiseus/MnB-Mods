-- Tests for SeasonalEvents against a stub of the game.
--   python tests/run_luajit.py tests/seasonal_events_test.lua     (from the MnB-Mods folder)

package.preload["includes/seasonal_events"] = function() return dofile("SeasonalEvents/seasonal_events.lua") end
package.preload["events/halloween"] = function() return dofile("SeasonalEvents/events/halloween.lua") end

local passed = 0
local function check(cond, msg)
  if not cond then error("FAILED: " .. msg, 2) end
  passed = passed + 1
end

-- ---- stub game -------------------------------------------------------------
local announced, sounds = {}, 0
function anounceStuff(t) announced[#announced + 1] = t end
function randNbr(n) return math.max(1, math.floor(n / 2)) end
function addParticle(p, typez, x, y) p.typez, p.x, p.y = typez, x, y end
function floatyText() end
function alliedFrontLine() return 1000 end
function distanceCheck2(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) end
zombieDeadSound = { clone = function() return { setVolume = function() end, play = function() sounds = sounds + 1 end } end }
local nextId = 0
local function unit(faction, x, y, tag)
  nextId = nextId + 1
  return { id = nextId, faction = faction, x = x, y = y, health = 100, tag = tag or "soldier", speed = 60 }
end
player = { deployedTroops = {}, particles = {}, deco = {}, placeables = {}, buildings = {} }
function spawnAxisTroops(x, y) player.deployedTroops[#player.deployedTroops + 1] = unit("axis", x, y) end

local calendar = "Xmas"
SPECIAL_EVENTS = {}
function specialEventForDate()
  local chosen = SpecialEvents.override()
  if chosen then specialEvent = chosen return chosen end
  specialEvent = calendar
  return calendar
end

QM = { settings = { seasonal_events = {} } }
local q = QM.settings.seasonal_events
local SE = require "includes/seasonal_events"

-- ---- which event is on -----------------------------------------------------
SE.init()
check(SE.getActiveEvent() == "Xmas" and specialEvent == "Xmas", "Auto follows the game's calendar")
check(SE.activeModule == nil, "an event without a module keeps the game's behaviour")
local us, them = unit("allied", 0, 0), unit("axis", 10, 0)
check(isHostileTo(us, them) and not isHostileTo(us, us) and not isHostileTo(them, unit("axis", 0, 0)),
  "without a module, the other faction is the enemy")

q.event_select = "None"
SE.onUpdate(1)
check(SE.getActiveEvent() == "" and specialEvent == "", "None turns events off, picked up while playing")
check(specialEventForDate() == "", "and the calendar function returns the choice")

q.event_select = "Halloween"
SE.onUpdate(1)
check(SE.getActiveEvent() == "Halloween" and SE.activeModule ~= nil, "choosing Halloween loads its module")

-- ---- Halloween: who fights whom --------------------------------------------
local zombie, zombie2 = unit("axis", 0, 0, "zombie"), unit("axis", 5, 5, "zombie")
check(not isHostileTo(zombie, zombie2), "zombies do not fight each other")
check(isHostileTo(zombie, us) and isHostileTo(us, zombie), "zombies and Allies fight")
check(isHostileTo(zombie, them) and isHostileTo(them, zombie), "zombies and Germans fight by default")
check(isHostileTo(them, us) and not isHostileTo(them, unit("axis", 1, 1)), "Germans still fight Allies only")
q.halloween_3way_zombies = false
q.halloween_3way_germans = 0
SE.onUpdate(1)
check(not isHostileTo(zombie, them) and not isHostileTo(them, zombie), "both three-way switches can be turned off")
q.halloween_3way_zombies, q.halloween_3way_germans = true, true
SE.onUpdate(1)

-- ---- Halloween: zombies ----------------------------------------------------
q.halloween_zombie_hp, q.halloween_zombie_speed, q.halloween_zombie_dmg = 250, 2.0, 40
SE.onUpdate(1)
player.deployedTroops = {}
check(SE.onSpawnZombies(3) == true and #player.deployedTroops == 3, "the event spawns the zombies itself")
local z = player.deployedTroops[1]
check(z.tag == "zombie" and z.health == 250 and z.hthDamage == 40, "with the configured health and damage")
check(SE.getZombieSpeed(z) == 100, "the speed option is applied once, not squared (" .. SE.getZombieSpeed(z) .. ")")
check(#announced == 1 and #player.particles == 12, "with an announcement and dust")
check(SE.getWaveSpawnChance() == 25, "the wave chance comes from the options")

player.deployedTroops = { z, us }
us.x, us.y = 400, 300
check(SE.onZombieIdle(z) and z.targetx == 400, "an idle zombie walks at the nearest enemy")

-- ---- Halloween: the dead rise ----------------------------------------------
q.halloween_reanim_delay = 1.0
SE.onUpdate(1)
local victim = unit("allied", 200, 200)
victim.health = 10
SE.onCqcHit(z, victim, 30)
player.deco = { { name = "allied_dead1", x = 205, y = 198 }, { name = "crater", x = 205, y = 198 } }
SE.onDeath(victim)
local before = #player.deployedTroops
SE.onUpdate(0.5)
check(#player.deployedTroops == before, "the corpse waits for the delay")
SE.onUpdate(0.6)
check(#player.deployedTroops == before + 1 and player.deployedTroops[#player.deployedTroops].tag == "zombie",
  "then rises as a zombie")
check(#player.deco == 1 and player.deco[1].name == "crater", "and its body is removed from the ground")

local bystander = unit("allied", 600, 600)
SE.onDeath(bystander)
SE.onUpdate(2)
check(#player.deployedTroops == before + 1, "a soldier not killed by a zombie stays dead")
q.halloween_reanim_target = "All Casualties"
SE.onUpdate(1)
SE.onDeath(bystander)
SE.onUpdate(2)
check(#player.deployedTroops == before + 2, "unless every casualty rises")

SE.onDeath(z)
check(sounds == 1, "a zombie's death plays its sound and does not queue it again")
SE.onUpdate(2)
check(#player.deployedTroops == before + 2, "zombies do not rise twice")

-- ---- other mods ------------------------------------------------------------
local loaded, unloaded = 0, 0
SE.register("Example", {
  onLoad = function() loaded = loaded + 1 end,
  onUnload = function() unloaded = unloaded + 1 end,
  isHostile = function() return false end,
  waveSpawnChance = function() return 77 end,
})
SE.setSelectedEvent("Example")
check(loaded == 1 and SE.getActiveEvent() == "Example" and q.event_select == "Example", "a registered event can be selected")
check(not isHostileTo(us, them) and SE.getWaveSpawnChance() == 77, "and its functions are used")
check(SE.onSpawnZombies(1) == false and SE.getZombieSpeed(z) == z.speed, "what it leaves out falls back to the game")
SE.setSelectedEvent("Auto")
check(unloaded == 1 and SE.getActiveEvent() == "Xmas", "switching away unloads it")

print(string.format("seasonal_events_test: %d checks passed", passed))
