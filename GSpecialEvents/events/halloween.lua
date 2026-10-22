-- ============================================================================
-- events/halloween.lua — Halloween MoonGrave 3-Way Zombie Overhaul
-- Implements 3-way combat, distributed spawns, corpse reanimation, and custom stats.
-- ============================================================================

local halloween = {}
halloween.reanimationQueue = {}

-- Safe sound trigger helper
local function playSfx(sfx, volume, pitch)
  if sfx and type(sfx.clone) == "function" then
    local ok, c = pcall(sfx.clone, sfx)
    if ok and c and type(c.play) == "function" then
      if volume and type(c.setVolume) == "function" then pcall(c.setVolume, c, volume) end
      if pitch and type(c.setPitch) == "function" then pcall(c.setPitch, c, pitch) end
      pcall(c.play, c)
    end
  end
end

-- ============================================================================
-- LIFECYCLE HOOKS
-- ============================================================================

function halloween.onLoad(core)
  halloween.reanimationQueue = {}
  print("[GSpecialEvents] Halloween MoonGrave module activated.")
end

function halloween.onUnload(core)
  halloween.reanimationQueue = {}
  print("[GSpecialEvents] Halloween MoonGrave module deactivated.")
end

-- ============================================================================
-- 3-WAY TARGETING & HOSTILITY
-- ============================================================================

--- Determine hostility between two combatants
-- Enables Germans and Zombies to engage each other while preserving Allied combat
function halloween.isHostile(dude, target, core)
  if not dude or not target or dude.id == target.id then return false end

  local dIsZ = (dude.tag == "zombie")
  local tIsZ = (target.tag == "zombie")

  -- Undead fraternity: Two zombies never attack each other
  if dIsZ and tIsZ then
    return false
  end

  local zVsGermans = (core.settings.halloween.zombiesAttackGermans == 1)
  local germansVsZ = (core.settings.halloween.germansAttackZombies == 1)

  -- Attacker is Zombie
  if dIsZ then
    if target.faction == "allied" then
      return true
    elseif target.faction == "axis" and not tIsZ then
      return zVsGermans
    end
    return false
  end

  -- Attacker is German (Axis human)
  if dude.faction == "axis" and not dIsZ then
    if tIsZ then
      return germansVsZ
    elseif target.faction == "allied" then
      return true
    end
    return false
  end

  -- Attacker is Allied soldier
  if dude.faction == "allied" then
    if tIsZ or target.faction == "axis" then
      return true
    end
    return false
  end

  -- Default fallback
  return dude.faction ~= target.faction
end

-- ============================================================================
-- DISTRIBUTED ZOMBIE SPAWNING
-- ============================================================================

function halloween.spawnZombies(amount, core)
  amount = amount or 1

  if anounceStuff then
    anounceStuff("Moon Grave Rising! Undead detected across the battlefield.")
  end

  local spawnLocations = {}
  local mode = core.settings.halloween.spawnDistribution or "Distributed"

  -- 1. Gather cemetery tombs & graves
  if player and player.placeables then
    for i = 1, #player.placeables do
      local p = player.placeables[i]
      if p and (p.name == "tomb1" or p.name == "tomb2" or p.name == "tomb3" or p.name == "tomb4") then
        table.insert(spawnLocations, { x = p.x, y = p.y })
      end
    end
  end

  if player and player.deco then
    for i = 1, #player.deco do
      local d = player.deco[i]
      if d and d.name == "tomb5" then
        table.insert(spawnLocations, { x = d.x, y = d.y })
      end
    end
  end

  if player and player.buildings then
    for i = 1, #player.buildings do
      local b = player.buildings[i]
      if b and b.name == "mausoleum" then
        table.insert(spawnLocations, { x = b.x, y = b.y })
      end
    end
  end

  -- 2. If Distributed or Everywhere, also gather fallen soldier corpses
  if (mode == "Distributed" or mode == "Everywhere") and player and player.deco then
    for i = 1, #player.deco do
      local d = player.deco[i]
      if d and type(d.name) == "string" and d.name:find("_dead") and d.x and d.y then
        table.insert(spawnLocations, { x = d.x, y = d.y })
      end
    end
  end

  -- 3. Calculate dynamic frontline bounds
  local frontAllied = (type(_G.alliedFrontLine) == "function" and _G.alliedFrontLine()) or 300
  local frontAxis = (type(_G.axisFrontLine) == "function" and _G.axisFrontLine()) or 1200
  if frontAxis < frontAllied then frontAxis = frontAllied + 900 end

  local hp = core.settings.halloween.zombieHealth or 500
  local dmg = core.settings.halloween.zombieClawsDamage or 25
  local spdMult = core.settings.halloween.zombieSpeedMult or 1.0

  for i = 1, amount do
    local spawnX, spawnY

    if mode == "Tombs Only" and #spawnLocations > 0 then
      local loc = spawnLocations[randNbr(#spawnLocations)]
      spawnX = loc.x + (randNbr(40) - 20)
      spawnY = loc.y + (randNbr(40) - 20)
    elseif mode == "Distributed" then
      local roll = randNbr(100)
      if roll <= 50 and #spawnLocations > 0 then
        local loc = spawnLocations[randNbr(#spawnLocations)]
        spawnX = loc.x + (randNbr(60) - 30)
        spawnY = loc.y + (randNbr(60) - 30)
      elseif roll <= 80 then
        -- Frontline / no man's land between lines
        spawnX = frontAllied + randNbr(math.max(100, frontAxis - frontAllied))
        spawnY = randNbr(560) + 80
      else
        -- Flank rising
        spawnX = frontAllied + randNbr(math.max(200, frontAxis - frontAllied + 300))
        spawnY = (randNbr(100) <= 50) and (randNbr(80) + 40) or (randNbr(80) + 600)
      end
    else
      -- Everywhere
      spawnX = frontAllied - 150 + randNbr(math.max(300, frontAxis - frontAllied + 800))
      spawnY = randNbr(620) + 50
    end

    -- Spawn soldier entity into player.deployedTroops
    if spawnAxisTroops then
      spawnAxisTroops(spawnX, spawnY)
      local zombie = player.deployedTroops[#player.deployedTroops]
      if zombie then
        zombie.tag = "zombie"
        zombie.maxHealth = hp
        zombie.health = hp
        zombie.morale = 100
        zombie.hthDamage = dmg
        zombie.skill = 45
        zombie.speed = 50 * spdMult
        zombie._zombieSpeedMult = spdMult

        -- Spawn graveyard rising dust particles
        if addParticle and player.particles then
          for p = 1, 4 do
            local newPart = {}
            addParticle(newPart, "dustCloud", zombie.x + randNbr(30) - 15, zombie.y + randNbr(30) - 15, randNbr(360))
            table.insert(player.particles, newPart)
          end
        end
      end
    end
  end

  return true -- custom spawn handled
end

-- ============================================================================
-- CORPSE REANIMATION (INFECTION)
-- ============================================================================

function halloween.onDeath(dude, core)
  if not dude then return end

  -- Zombies do not reanimate a second time
  if dude.tag == "zombie" then
    return
  end

  if core.settings.halloween.corpseReanimation ~= 1 then
    return
  end

  -- Check trigger condition: all casualties or only those killed by zombies
  local reanimTarget = core.settings.halloween.reanimationTarget or "Zombie Kills Only"
  local qualifies = false

  if reanimTarget == "All Casualties" then
    qualifies = true
  elseif dude._killedByZombie == true or dude.killedByZombie == true then
    qualifies = true
  end

  if qualifies then
    local delay = core.settings.halloween.reanimationDelay or 2.5
    table.insert(halloween.reanimationQueue, {
      x = dude.x,
      y = dude.y,
      timer = delay,
      tag = dude.tag or "soldier",
      name = dude.name or "Fallen Soldier"
    })
  end
end

function halloween.onUpdate(dt, core)
  if not halloween.reanimationQueue or #halloween.reanimationQueue == 0 then
    return
  end

  local hp = core.settings.halloween.zombieHealth or 500
  local dmg = core.settings.halloween.zombieClawsDamage or 25
  local spdMult = core.settings.halloween.zombieSpeedMult or 1.0

  for i = #halloween.reanimationQueue, 1, -1 do
    local item = halloween.reanimationQueue[i]
    item.timer = item.timer - dt

    if item.timer <= 0 then
      -- 1. Remove corpse deco matching position so body doesn't linger underneath risen zombie
      if player and player.deco then
        for dIdx = #player.deco, 1, -1 do
          local d = player.deco[dIdx]
          if d and d.x and d.y then
            local dist = math.abs(d.x - item.x) + math.abs(d.y - item.y)
            if dist < 45 and type(d.name) == "string" and d.name:find("_dead") then
              table.remove(player.deco, dIdx)
              break
            end
          end
        end
      end

      -- 2. Spawn newly risen zombie at corpse location
      if spawnAxisTroops and player then
        player.gainz = player.gainz or 1
        player.dayz = player.dayz or 1
        pcall(spawnAxisTroops, item.x, item.y)
        local zombie = player.deployedTroops and player.deployedTroops[#player.deployedTroops]
        if zombie then
          zombie.tag = "zombie"
          zombie.maxHealth = hp
          zombie.health = hp
          zombie.morale = 100
          zombie.hthDamage = dmg
          zombie.skill = 45
          zombie.speed = 50 * spdMult
          zombie._zombieSpeedMult = spdMult

          -- Rising dust and particles
          if addParticle and player.particles then
            for p = 1, 6 do
              local newPart = {}
              addParticle(newPart, "dustCloud", zombie.x + randNbr(30) - 15, zombie.y + randNbr(30) - 15, randNbr(360))
              table.insert(player.particles, newPart)
            end
          end

          if floatyText then
            floatyText(zombie, "Reanimated!")
          end
        end
      end

      table.remove(halloween.reanimationQueue, i)
    end
  end
end

-- ============================================================================
-- ZOMBIE SPEED & INTELLIGENT 3-WAY HUNTING
-- ============================================================================

function halloween.getZombieSpeed(soldier, core)
  if soldier and soldier.tag == "zombie" then
    local mult = core.settings.halloween.zombieSpeedMult or 1.0
    return (soldier.speed or 50) * mult
  end
  return soldier and soldier.speed or 50
end

--- Aggressive 3-way zombie idle hunt
-- Finds the closest living hostile soldier (Allied OR German) across the field
function halloween.onZombieIdle(soldier, core)
  if not soldier or soldier.tag ~= "zombie" then return false end

  local closestTarget = nil
  local closestDist = 999999

  if player and player.deployedTroops then
    for i = 1, #player.deployedTroops do
      local t = player.deployedTroops[i]
      if t and t.health > 10 and t.id ~= soldier.id and _G.isHostileTo(soldier, t) then
        local d = distanceCheck2(soldier, t)
        if d < closestDist then
          closestDist = d
          closestTarget = t
        end
      end
    end
  end

  if closestTarget then
    soldier.targetx = closestTarget.x
    soldier.targety = closestTarget.y
    return true
  end

  return false -- fallback to standard front line
end

return halloween
