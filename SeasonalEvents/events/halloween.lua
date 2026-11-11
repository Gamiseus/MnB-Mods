-- events/halloween.lua
-- Halloween as a three-way fight: zombies attack everyone, Germans may fight back, and the
-- dead may rise again. Every part has a switch in Mod Settings.

local halloween = {}

local queue = {}                                        -- corpses waiting to rise
local killedByZombie = setmetatable({}, { __mode = "k" }) -- soldiers whose last blow came from a zombie

local function play(sound, volume)
  if not sound then return end
  local c = sound:clone()
  if volume then c:setVolume(volume) end
  c:play()
end

function halloween.onLoad(core)
  queue = {}
end

function halloween.onUnload(core)
  queue = {}
end

-- ---------------------------------------------------------------------------
-- Who fights whom
-- ---------------------------------------------------------------------------

function halloween.isHostile(dude, target, core)
  local dz, tz = dude.tag == "zombie", target.tag == "zombie"
  if dz and tz then return false end
  local h = core.settings.halloween
  if dz then
    if target.faction == "allied" then return true end
    return target.faction == "axis" and h.zombiesAttackGermans
  end
  if tz then
    if dude.faction == "allied" then return true end
    return dude.faction == "axis" and h.germansAttackZombies
  end
  return dude.faction ~= target.faction
end

-- ---------------------------------------------------------------------------
-- Zombies
-- ---------------------------------------------------------------------------

local function dust(x, y, count)
  for _ = 1, count do
    local p = {}
    addParticle(p, "dustCloud", x + randNbr(30) - 15, y + randNbr(30) - 15, randNbr(360))
    player.particles[#player.particles + 1] = p
  end
end

-- Spawns a zombie at a point and returns it.
local function raise(x, y, core, dustCount)
  local h = core.settings.halloween
  spawnAxisTroops(x, y)
  local z = player.deployedTroops[#player.deployedTroops]
  if not z then return nil end
  z.tag = "zombie"
  z.maxHealth = h.zombieHealth
  z.health = h.zombieHealth
  z.morale = 100
  z.hthDamage = h.zombieClawsDamage
  z.skill = 45
  z.speed = 50 -- the speed option is applied in getZombieSpeed, so it can change mid-battle
  dust(z.x, z.y, dustCount)
  return z
end

local function graves()
  local list = {}
  local function add(items, isGrave)
    if not items then return end
    for i = 1, #items do
      local it = items[i]
      if it.x and it.y and isGrave(it.name) then list[#list + 1] = it end
    end
  end
  add(player.placeables, function(n) return n == "tomb1" or n == "tomb2" or n == "tomb3" or n == "tomb4" end)
  add(player.deco, function(n) return n == "tomb5" end)
  add(player.buildings, function(n) return n == "mausoleum" end)
  return list
end

local function corpses(list)
  local deco = player.deco
  for i = 1, #deco do
    local d = deco[i]
    if type(d.name) == "string" and d.name:find("_dead", 1, true) and d.x and d.y then
      list[#list + 1] = d
    end
  end
  return list
end

function halloween.spawnZombies(amount, core)
  amount = amount or 1
  anounceStuff("Moon Grave Rising! Undead detected across the battlefield.")

  local mode = core.settings.halloween.spawnDistribution
  local spots = graves()
  if mode ~= "Tombs Only" then corpses(spots) end

  local allied = alliedFrontLine()
  local axis = type(axisFrontLine) == "function" and axisFrontLine() or allied + 900
  if axis < allied then axis = allied + 900 end
  local gap = axis - allied

  for _ = 1, amount do
    local x, y
    local roll = randNbr(100)
    if #spots > 0 and (mode == "Tombs Only" or (mode == "Distributed" and roll <= 50)) then
      local s = spots[randNbr(#spots)]
      x, y = s.x + randNbr(60) - 30, s.y + randNbr(60) - 30
    elseif mode == "Everywhere" or mode == "Tombs Only" then
      x, y = allied - 150 + randNbr(math.max(300, gap + 800)), randNbr(620) + 50
    elseif roll <= 80 then
      -- Between the lines.
      x, y = allied + randNbr(math.max(100, gap)), randNbr(560) + 80
    else
      -- On a flank.
      x = allied + randNbr(math.max(200, gap + 300))
      y = randNbr(100) <= 50 and randNbr(80) + 40 or randNbr(80) + 600
    end
    raise(x, y, core, 4)
  end
  return true
end

function halloween.getZombieSpeed(soldier, core)
  return soldier.speed * core.settings.halloween.zombieSpeedMult
end

function halloween.waveSpawnChance(core)
  return core.settings.halloween.waveSpawnChance
end

-- An idle zombie walks at the nearest enemy, German or Allied.
function halloween.onZombieIdle(soldier, core)
  local best, bestDist = nil, math.huge
  local troops = player.deployedTroops
  for i = 1, #troops do
    local t = troops[i]
    if t.health > 10 and core.isHostile(soldier, t) then
      local d = distanceCheck2(soldier, t)
      if d < bestDist then best, bestDist = t, d end
    end
  end
  if not best then return false end
  soldier.targetx, soldier.targety = best.x, best.y
  return true
end

-- ---------------------------------------------------------------------------
-- The dead rise
-- ---------------------------------------------------------------------------

function halloween.onCqcHit(attacker, defender, damage, core)
  if attacker.tag == "zombie" and defender.health - damage <= 0 then
    killedByZombie[defender] = true
  end
end

function halloween.onDeath(dude, core)
  local h = core.settings.halloween
  if dude.tag == "zombie" then
    if h.soundDeath then play(zombieDeadSound, 0.8) end
    return -- zombies do not rise twice
  end
  if not h.corpseReanimation then return end
  if h.reanimationTarget == "All Casualties" or killedByZombie[dude] then
    queue[#queue + 1] = { x = dude.x, y = dude.y, timer = h.reanimationDelay }
  end
end

function halloween.onUpdate(dt, core)
  for i = #queue, 1, -1 do
    local item = queue[i]
    item.timer = item.timer - dt
    if item.timer <= 0 then
      table.remove(queue, i)
      -- The body on the ground is replaced by the zombie.
      local deco = player.deco
      for n = #deco, 1, -1 do
        local d = deco[n]
        if type(d.name) == "string" and d.name:find("_dead", 1, true)
          and math.abs(d.x - item.x) + math.abs(d.y - item.y) < 45 then
          table.remove(deco, n)
          break
        end
      end
      -- spawnAxisTroops reads these two; a battle started without them would stop here.
      player.gainz = player.gainz or 1
      player.dayz = player.dayz or 1
      local z = raise(item.x, item.y, core, 6)
      if z then floatyText(z, "Reanimated!") end
    end
  end
end

halloween._queue = function() return queue end -- for tests

return halloween
