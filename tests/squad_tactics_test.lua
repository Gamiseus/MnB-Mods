-- Tests for SquadTactics against a stub of the game.
--   python tests/run_luajit.py tests/squad_tactics_test.lua     (from the MnB-Mods folder)

for _, m in ipairs({ "smart_move", "combat_reaction", "squad_tactics" }) do
  package.preload["includes/" .. m] = function() return dofile("SquadTactics/" .. m .. ".lua") end
end

local passed = 0
local function check(cond, msg)
  if not cond then error("FAILED: " .. msg, 2) end
  passed = passed + 1
end

-- ---- stub game -------------------------------------------------------------
local sightChecks, texts = 0, {}
function distanceCheck(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
function distanceCheck2(a, b) return distanceCheck(a.x, a.y, b.x, b.y) end
function los2(a, b) sightChecks = sightChecks + 1 return true end
function hasBuffByTag() return false end
function underCover() return false end
function fireNearby() return false end
function floatyText(d, t) texts[#texts + 1] = t end
function randNbr(n) return n end -- the top of every roll: never "stand and fight" by chance
function stepScale() return 1 end
function addParticle(p, typez, x, y) p.typez, p.x, p.y = typez, x, y end
spamTimer = 1
altMove = 0
love = { keyboard = { isDown = function() return false end } }

local function soldier(id, faction, x, y)
  return { id = id, faction = faction, x = x, y = y, health = 100, dead = 0, onFire = 0,
    targetx = x, targety = y, kills = 0, xp = 0, temporaryStop = 0, selected = false }
end

player = { deployedTroops = {}, deployedVehicles = {}, groundType = {}, forest = {}, particles = {}, landed = 1 }
local ally = soldier(1, "allied", 100, 300)
player.deployedTroops[1] = ally
for i = 1, 50 do
  player.deployedTroops[#player.deployedTroops + 1] = soldier(100 + i, "axis", 300 + i * 4, 300)
end

local ST = require "includes/squad_tactics"
local R = ST.Reaction

-- A soldier standing still costs nothing.
for _ = 1, 60 do ST.updateSoldier(ally, 1 / 60) end
check(sightChecks == 0, "a soldier standing still makes no sight checks")

-- A soldier on a move order looks a few times a second, at the nearest enemies only.
ally.targetx = 900
for _ = 1, 60 do ST.updateSoldier(ally, 1 / 60) end
check(sightChecks > 0 and sightChecks <= 6 * R.SIGHT_CHECKS,
  "one second of moving among 50 enemies costs at most " .. 6 * R.SIGHT_CHECKS .. " sight checks, not 3000 (" .. sightChecks .. ")")
check(R.isActive(ally), "meeting the enemy interrupts the order")
check(ally.targetx == ally.x and ally.temporaryStop > 0, "the soldier stops to fight")
check(ally.targetPointer == 101 and ally.aim == 1, "and takes on the nearest visible enemy")
check(#texts >= 1, "with a callout")

-- The enemy gone: after a quiet spell the soldier resumes the order.
for i = #player.deployedTroops, 2, -1 do table.remove(player.deployedTroops, i) end
for _ = 1, 60 * 6 do ST.updateSoldier(ally, 1 / 60) end
check(not R.isActive(ally) and ally.targetx == 900, "with the area clear the order is resumed")

-- Halt forgets the order.
player.deployedTroops[2] = soldier(201, "axis", 300, 300)
ally.targetx = 900
for _ = 1, 30 do ST.updateSoldier(ally, 1 / 60) end
check(R.isActive(ally), "a second contact interrupts again")
ally.targetx, ally.targety = ally.x, ally.y
ST.onHalt(ally)
table.remove(player.deployedTroops, 2)
for _ = 1, 60 * 6 do ST.updateSoldier(ally, 1 / 60) end
check(ally.targetx == ally.x, "after Halt the soldier does not go back to the old order")

-- A veteran fires first.
local vet = soldier(2, "allied", 100, 400); vet.kills = 3; vet.targetx = 900
player.deployedTroops[2] = vet
player.deployedTroops[3] = soldier(301, "axis", 300, 400)
for _ = 1, 30 do ST.updateSoldier(vet, 1 / 60) end
check(R.isActive(vet) and R._states[vet].retaliating, "a veteran returns fire before deciding")

-- Reactions off.
QM = { settings = { squad_tactics = { combat_reactions = false } } }
local rookie = soldier(3, "allied", 100, 500); rookie.targetx = 900
before = sightChecks
for _ = 1, 60 do ST.updateSoldier(rookie, 1 / 60) end
check(sightChecks == before and not R.isActive(rookie), "with reactions off nothing is checked")
rookie.temporaryStop = 0.5
for _ = 1, 60 do ST.updateSoldier(rookie, 1 / 60) end
check(rookie.temporaryStop == 0, "temporaryStop still counts down")

-- Squad limit.
QM.settings.squad_tactics.squad_limit = nil
check(ST.squadLimit() == 6, "the limit defaults to the game's 6")
QM.settings.squad_tactics.squad_limit = 12
check(ST.squadLimit() == 12 and ST.sizeWarning(12):find("12", 1, true), "a number is the limit")
QM.settings.squad_tactics.squad_limit = "OFF"
check(ST.squadLimit() == math.huge and not (8 > ST.squadLimit()), "OFF is no limit, and still compares as a number")
check(ST.sizeWarning(6) == nil, "the game's own text is used at 6")

-- Move orders: only soldiers the game really sent to the click are spread out.
QM.settings.squad_tactics.combat_reactions = true
player.deployedTroops = {}
local a, b, c = soldier(11, "allied", 0, 0), soldier(12, "allied", 20, 0), soldier(13, "allied", 40, 0)
a.selected, b.selected, c.selected = true, true, false
player.deployedTroops = { a, b, c }
local batch = ST.captureSelection()
check(#batch == 2, "the selected soldiers are noted")
local planned
ST.Move.assignSquadMoveOrder = function(list, x, y)
  planned = list
  for i, s in ipairs(list) do s.targetx, s.targety = x + i * 50, y end
end
ST.afterMoveOrder(batch, 500, 300)
check(planned == nil, "nothing is planned when the game did not send them")
a.targetx, a.targety, b.targetx, b.targety = 500, 300, 560, 250
player.particles = { { faction = 11, typez = "moveDot" }, { faction = 99 } }
ST.afterMoveOrder(batch, 500, 300)
check(planned and #planned == 2, "the group is planned once the game sent it")
check(#player.particles == 3 and player.particles[1].faction == 99, "old markers of the group are removed, others kept")
check(player.particles[2].x == a.targetx and player.particles[3].faction == 12, "each soldier gets a marker at its own spot")

print(string.format("squad_tactics_test: %d checks passed", passed))
