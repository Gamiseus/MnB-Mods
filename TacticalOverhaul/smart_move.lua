-- ============================================================================
-- includes/smart_move.lua
-- Tactical Squad Formation, Role Assignment & Veterancy Weighting
-- ============================================================================
-- Automatically distributes squad move orders into intelligent tactical
-- formation slots based on:
--   1. Combat Veterancy Weight W_vet(s) (Skill, Rank, XP, Survival, Kills).
--   2. Tactical Role Profiles (Point Assault, Line, Heavy MG/AT, Recon, Medic).
--   3. Tactical Terrain Cover, Trench Depth, Concealment, and LOS Sightlines.
--   4. Anti-Grenade Spacing & Medic Proximity Triage.
-- ============================================================================

local smart_move = {}

smart_move.MIN_SPACING = 44 -- Minimum pixel spacing between assigned squadmates

smart_move.lastAssignment = {
  clickX = 0,
  clickY = 0,
  threatUx = 1,
  threatUy = 0,
  timestamp = -999,
  slots = {}
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- ----------------------------------------------------------------------------
-- 1. Compute Veterancy & Tactical Weight W_vet(s) in [0, 100]
-- ----------------------------------------------------------------------------
function smart_move.computeVeterancyWeight(dude)
  if not dude then
    return 0, { skill = 0, rank = 0, xp = 0, survival = 0, kills = 0 }
  end

  local skillScore = clamp(dude.skill or 30, 0, 100)
  local rankScore = clamp((dude.rank or 0) * 9 + ((dude.level or 1) - 1) * 3, 0, 100)
  local xpScore = clamp(dude.xp or 0, 0, 100)

  local patrols = math.max(0, dude.patrols or dude.missions or 0)
  local combatTime = math.max(0, dude.combatTime or 0)
  local survivalScore = clamp(
    20.0 * math.log(1 + patrols) + 5.0 * math.log(1 + (combatTime / 60.0)),
    0, 100
  )

  local kills = math.max(0, dude.kills or 0)
  local hthKills = math.max(0, dude.hthKills or 0)
  local sgKills = math.max(0, dude.sgKills or 0)
  local killsScore = clamp(
    22.0 * math.log(1 + kills + 0.5 * hthKills + 0.25 * sgKills),
    0, 100
  )

  local awardBonus = (dude.awards and #dude.awards or 0) * 1.5
  local perkBonus = (dude.perks and #dude.perks or 0) * 2.0

  local totalWeight = clamp(
    0.30 * skillScore +
    0.20 * rankScore +
    0.20 * xpScore +
    0.15 * survivalScore +
    0.15 * killsScore +
    awardBonus + perkBonus,
    0, 100
  )

  return totalWeight, {
    skill = skillScore,
    rank = rankScore,
    xp = xpScore,
    survival = survivalScore,
    kills = killsScore
  }
end

-- ----------------------------------------------------------------------------
-- 2. Classify Soldier into Tactical Role Profile
-- ----------------------------------------------------------------------------
function smart_move.classifyRole(dude)
  if not dude then return "rifle_line" end
  local spec = dude.spec or ""
  local w = dude.weapon or {}
  local wtag = w.tag or ""
  local wclass = w.class or ""
  local waction = w.action or ""
  local wrange = w.range or 300

  -- 1. Medic (triage priority)
  if spec == "medic" or (dude.doc or 0) > 0 or (dude.medicBag or 0) > 0 or (dude.medic or 0) > 0 then
    return "medic"
  end

  -- 2. Sniper / Long-Range Recon (rear overwatch, concealment, sightlines)
  if spec == "sniper" or (dude.masterSniper or 0) > 0
     or wtag == "scopedSpringfield" or wtag == "scopedGarand" or wtag == "scopedEnfield" or wtag == "scopedK98" or wtag == "g98"
     or wrange >= 430 or spec == "scout" or spec == "intel" then
    return "sniper_recon"
  end

  -- 3. Command / Support (rear sheltered cover)
  if spec == "officer" or spec == "sarge" or spec == "comms"
     or (dude.officerHat or 0) > 0 or (dude.mortar or 0) > 0 or (dude.radio or 0) > 0 then
    return "command_support"
  end

  -- 4. Heavy Gunner / Anti-Tank (hard cover, clear forward sightlines)
  if spec == "gunner"
     or (dude.bazooka or 0) > 0 or (dude.shrek or 0) > 0
     or (dude.boysRifle or 0) > 0 or (dude.pz39 or 0) > 0
     or wclass == "lmg" or wclass == "mg" or wclass == "atRifle"
     or wtag == "bar" or wtag == "m1919" or wtag == "mg42" or wtag == "mg34" or wtag == "bren" or wtag == "vicker" or wtag == "johnson" or wtag == "zb26"
     or (waction == "auto" and wrange >= 260) then
    return "heavy_gunner_at"
  end

  -- 5. Point / Assault (forward hard cover)
  if spec == "commando" or spec == "sapper" or spec == "engy" or spec == "pointMan"
     or (dude.flamer or 0) > 0
     or wclass == "smg" or wclass == "shotgun"
     or wtag == "tommy" or wtag == "m3" or wtag == "sten" or wtag == "stenMKVI" or wtag == "mp40" or wtag == "shotgun"
     or waction == "pump" or wrange <= 230 then
    return "point_assault"
  end

  return "rifle_line"
end

-- ----------------------------------------------------------------------------
-- 3. Threat Vector Estimation (ux, uy)
-- ----------------------------------------------------------------------------
function smart_move.determineThreatVector(clickX, clickY)
  local sumX, sumY, totalW = 0, 0, 0

  if player and player.deployedTroops then
    for i = 1, #player.deployedTroops do
      local t = player.deployedTroops[i]
      if t and t.faction == "axis" and (t.health or 0) > 10 and (t.dead or 0) == 0 then
        local dx = t.x - clickX
        local dy = t.y - clickY
        local dist = math.sqrt(dx * dx + dy * dy)
        if (t.flagged or 0) > 0 or (t.spotCalled or 0) == 1 or dist < 950 then
          local w = 1.0 / math.max(80, dist)
          if (t.flagged or 0) > 0 then w = w * 2.5 end
          sumX = sumX + t.x * w
          sumY = sumY + t.y * w
          totalW = totalW + w
        end
      end
    end
  end

  if player and player.deployedVehicles then
    for i = 1, #player.deployedVehicles do
      local v = player.deployedVehicles[i]
      if v and v.faction == "axis" and (v.health or 0) > 0 and (v.dead or 0) == 0 then
        local dx = v.x - clickX
        local dy = v.y - clickY
        local dist = math.sqrt(dx * dx + dy * dy)
        if (v.flagged or 0) > 0 or dist < 1100 then
          local w = 2.0 / math.max(100, dist)
          sumX = sumX + v.x * w
          sumY = sumY + v.y * w
          totalW = totalW + w
        end
      end
    end
  end

  if totalW > 0 then
    local vx = (sumX / totalW) - clickX
    local vy = (sumY / totalW) - clickY
    local len = math.sqrt(vx * vx + vy * vy)
    if len > 1 then
      return vx / len, vy / len
    end
  end

  return 1.0, 0.0
end

-- ----------------------------------------------------------------------------
-- 4. Evaluate Terrain Quality at Point
-- ----------------------------------------------------------------------------
local function evaluatePointTerrain(wx, wy, ux, uy)
  -- Delegate walkability, wire, fire, mine, and obstacle safety to GCore
  if pathfinding and pathfinding.isWalkableWorld then
    local walkable, cellCost = pathfinding.isWalkableWorld(wx, wy)
    if not walkable or (cellCost and cellCost >= 5.0) then
      return nil
    end
  end

  local coverVal = 0
  local concealmentVal = 0
  local isSlow = false

  -- GroundType Cover
  if player and player.groundType then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and g.x and g.y then
        local inside = false
        if (g.radius or 0) > 0 then
          if (wx - g.x)^2 + (wy - g.y)^2 <= (g.radius * g.radius) then
            inside = true
          end
        elseif (g.width or 0) > 0 and (g.length or 0) > 0 then
          if wx >= g.x and wx <= (g.x + g.width) and wy >= g.y and wy <= (g.y + g.length) then
            inside = true
          end
        end

        if inside then
          if g.slowy == "yes" or g.name == "mud" or g.name == "water" then
            isSlow = true
          end
          local c = g.cover or 0
          if c > 0 then
            local goodSide = true
            if (g.midpoint or 0) ~= 0 then
              if ux >= 0 and wx > g.midpoint then goodSide = false
              elseif ux < 0 and wx < g.midpoint then goodSide = false end
            end
            if goodSide and c > coverVal then
              coverVal = c
            end
          end
        end
      end
    end
  end

  -- Forest & Rock Concealment
  if player and player.forest then
    for i = 1, #player.forest do
      local f = player.forest[i]
      if f and f.x and f.y and (wx - f.x)^2 + (wy - f.y)^2 <= ((f.radius or 55)^2) then
        concealmentVal = math.max(concealmentVal, 24)
      end
    end
  end

  if player and player.rocks then
    for i = 1, #player.rocks do
      local r = player.rocks[i]
      if r and r.x and r.y and (wx - r.x)^2 + (wy - r.y)^2 <= (((r.radius or 40) + 18)^2) then
        concealmentVal = math.max(concealmentVal, 28)
      end
    end
  end

  -- Building Cover
  local insideBuilding = false
  if player and player.buildings then
    for b = 1, #player.buildings do
      local bld = player.buildings[b]
      if bld and (bld.destroyed or 0) < 1 then
        local bx = bld.x or 0
        local by = bld.y or 0
        local bw = bld.width or 0
        local bl = bld.length or bld.height or 0
        if bw > 0 and bl > 0 then
          local minX = (bld.centered == false) and bx or (bx - bw * 0.5)
          local minY = (bld.centered == false) and by or (by - bl * 0.5)
          if wx >= minX and wx <= minX + bw and wy >= minY and wy <= minY + bl then
            insideBuilding = true
            break
          end
        end
      end
    end
  end

  if insideBuilding then
    coverVal = math.max(coverVal, 48)
  end

  -- Sightline evaluation via GCore Box2D Physics LOS
  local sightlineVal = 20
  if los_physics and los_physics.castRay then
    local hitAny, _, _, bestFrac = los_physics.castRay(wx + ux * 18, wy + uy * 18, wx + ux * 280, wy + uy * 280)
    if not hitAny then
      sightlineVal = 30
    else
      sightlineVal = math.max(4, math.floor(30 * (bestFrac or 0.3)))
    end
  end

  if insideBuilding then
    sightlineVal = math.max(sightlineVal, 24)
  end

  return {
    x = wx,
    y = wy,
    cover = coverVal,
    concealment = concealmentVal,
    sightline = sightlineVal,
    slow = isSlow
  }
end

-- ----------------------------------------------------------------------------
-- 5. Candidate Tactical Slots
-- ----------------------------------------------------------------------------
function smart_move.generateCandidateSlots(clickX, clickY, squadCount, ux, uy)
  local candidates = {}
  local searchRadius = math.min(280, 150 + (squadCount or 4) * 16)
  local lx, ly = -uy, ux

  local function tryAddCandidate(wx, wy, tag)
    local info = evaluatePointTerrain(wx, wy, ux, uy)
    if info then
      local dx = wx - clickX
      local dy = wy - clickY
      info.distFromClick = math.sqrt(dx * dx + dy * dy)
      info.forwardDepth = dx * ux + dy * uy
      info.lateralOffset = dx * lx + dy * ly
      info.tag = tag or "formation"
      candidates[#candidates + 1] = info
    end
  end

  -- 1. Sample hard cover zones (groundType)
  if player and player.groundType then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and (g.cover or 0) > 0 and g.x and g.y then
        if (g.width or 0) > 0 and (g.length or 0) > 0 then
          local cx = g.x + g.width * 0.5
          local cy = g.y + g.length * 0.5
          if (cx - clickX)^2 + (cy - clickY)^2 <= (searchRadius + 60)^2 then
            local stepX = math.max(36, math.min(52, g.width / 3))
            local stepY = math.max(36, math.min(52, g.length / 3))
            for sx = g.x + 14, g.x + g.width - 14, stepX do
              for sy = g.y + 14, g.y + g.length - 14, stepY do
                tryAddCandidate(sx, sy, "cover")
              end
            end
          end
        end
      end
    end
  end

  -- 2. Sample building interiors
  if player and player.buildings then
    for b = 1, #player.buildings do
      local bld = player.buildings[b]
      if bld and (bld.destroyed or 0) < 1 and (bld.impassable or 0) == 0 then
        local bx = bld.x or 0
        local by = bld.y or 0
        local bw = bld.width or 0
        local bl = bld.length or bld.height or 0
        if (bx - clickX)^2 + (by - clickY)^2 <= (searchRadius + 120)^2 then
          if bw > 0 and bl > 0 then
            local minX = (bld.centered == false) and bx or (bx - bw * 0.5)
            local minY = (bld.centered == false) and by or (by - bl * 0.5)
            for sx = minX + 16, minX + bw - 16, 32 do
              for sy = minY + 16, minY + bl - 16, 32 do
                tryAddCandidate(sx, sy, "building_cover")
              end
            end
          end
        end
      end
    end
  end

  -- 3. Sample rocks & trees
  if player and player.rocks then
    for i = 1, #player.rocks do
      local r = player.rocks[i]
      if r and r.x and r.y and (r.x - clickX)^2 + (r.y - clickY)^2 <= searchRadius^2 then
        local offset = (r.radius or 35) + 16
        tryAddCandidate(r.x - ux * offset, r.y - uy * offset, "rock_cover")
        tryAddCandidate(r.x - ux * offset + lx * 24, r.y - uy * offset + ly * 24, "rock_cover")
        tryAddCandidate(r.x - ux * offset - lx * 24, r.y - uy * offset - ly * 24, "rock_cover")
      end
    end
  end

  if player and player.forest then
    for i = 1, #player.forest do
      local f = player.forest[i]
      if f and f.x and f.y and (f.x - clickX)^2 + (f.y - clickY)^2 <= searchRadius^2 then
        tryAddCandidate(f.x - ux * 18, f.y - uy * 18, "forest_conceal")
        tryAddCandidate(f.x + lx * 32, f.y + ly * 32, "forest_conceal")
        tryAddCandidate(f.x - lx * 32, f.y - ly * 32, "forest_conceal")
      end
    end
  end

  -- 4. Formation Chevrons & Depth Tiers
  local depthTiers = { 42, 16, 0, -24, -56, -96, -144 }
  local maxCols = math.max(5, math.ceil((squadCount or 4) * 0.85) + 2)
  local latSpacing = 48

  for _, depth in ipairs(depthTiers) do
    for col = -maxCols, maxCols do
      local stagger = (math.abs(col) % 2 == 1) and -10 or 0
      local wx = clickX + ux * (depth + stagger) + lx * (col * latSpacing)
      local wy = clickY + uy * (depth + stagger) + ly * (col * latSpacing)
      tryAddCandidate(wx, wy, depth < -45 and "overwatch" or "formation")
    end
  end

  return candidates
end

-- ----------------------------------------------------------------------------
-- 6. Role & Veterancy Slot Scoring
-- ----------------------------------------------------------------------------
local function scoreSlotForSoldier(slot, role, vetWeight)
  local baseCover = (slot.cover or 0) > 0 and (35.0 + slot.cover * 2.0) or 0
  local coverScore = baseCover + (slot.cover or 0) * (vetWeight / 100.0) * 1.5
  local concealScore = (slot.concealment or 0) * (0.9 + (vetWeight / 100.0) * 0.5)
  local sightScore = slot.sightline or 20
  local depth = slot.forwardDepth or 0

  local distRate = (slot.cover and slot.cover > 0) and 0.08 or 0.22
  local distPenalty = (slot.distFromClick or 0) * distRate
  local slowPenalty = slot.slow and 25 or 0

  local roleScore = 0
  if role == "point_assault" then
    roleScore = coverScore * 1.65 + concealScore * 0.7 + sightScore * 0.7 - math.abs(depth - 32) * 0.45
  elseif role == "heavy_gunner_at" then
    roleScore = coverScore * 1.75 + concealScore * 0.8 + sightScore * 1.85 - math.abs(depth - 8) * 0.40
  elseif role == "sniper_recon" then
    roleScore = coverScore * 1.35 + concealScore * 1.75 + sightScore * 1.65 - math.abs(depth - (-105)) * 0.55
    if depth <= -50 then roleScore = roleScore + 35 end
  elseif role == "command_support" then
    roleScore = coverScore * 1.60 + concealScore * 1.25 + sightScore * 0.50 - math.abs(depth - (-75)) * 0.50
    if depth <= -35 then roleScore = roleScore + 25 end
  else
    roleScore = coverScore * 1.65 + concealScore * 1.0 + sightScore * 1.0 - math.abs(depth - 5) * 0.40
  end

  return roleScore - distPenalty - slowPenalty
end

local function isSlotSpaced(wx, wy, claimedSlots, minSpacing)
  local minD2 = minSpacing * minSpacing
  for i = 1, #claimedSlots do
    local c = claimedSlots[i]
    if (wx - c.x)^2 + (wy - c.y)^2 < minD2 then
      return false
    end
  end
  return true
end

-- ----------------------------------------------------------------------------
-- 7. Main Squad Assignment Engine
-- ----------------------------------------------------------------------------
function smart_move.assignSquadMoveOrder(selectedSoldiers, clickX, clickY)
  if not selectedSoldiers or #selectedSoldiers == 0 then
    return {}
  end

  local ux, uy = smart_move.determineThreatVector(clickX, clickY)
  local candidates = smart_move.generateCandidateSlots(clickX, clickY, #selectedSoldiers, ux, uy)

  local combatEntries = {}
  local medicEntries = {}

  for i = 1, #selectedSoldiers do
    local s = selectedSoldiers[i]
    local wVet, breakdown = smart_move.computeVeterancyWeight(s)
    local role = smart_move.classifyRole(s)
    local entry = { soldier = s, weight = wVet, breakdown = breakdown, role = role }
    if role == "medic" then
      medicEntries[#medicEntries + 1] = entry
    else
      combatEntries[#combatEntries + 1] = entry
    end
  end

  -- Sort combat troops by veterancy: experienced veterans take prime cover first
  table.sort(combatEntries, function(a, b)
    if math.abs(a.weight - b.weight) > 0.01 then
      return a.weight > b.weight
    end
    return (a.soldier.id or 0) < (b.soldier.id or 0)
  end)

  table.sort(medicEntries, function(a, b)
    return a.weight > b.weight
  end)

  local claimedSlots = {}
  local assignments = {}

  -- Avoid displacing stationary unselected allies already at destination
  if player and player.deployedTroops then
    local selectedSet = {}
    for i = 1, #selectedSoldiers do selectedSet[selectedSoldiers[i]] = true end
    for i = 1, #player.deployedTroops do
      local t = player.deployedTroops[i]
      if t and t.faction == "allied" and (t.health or 0) > 10 and (t.dead or 0) == 0 and not selectedSet[t] then
        local tx = t.targetx or t.x
        local ty = t.targety or t.y
        if (tx - clickX)^2 + (ty - clickY)^2 < (260 * 260) then
          claimedSlots[#claimedSlots + 1] = { x = tx, y = ty, stationary = true }
        end
      end
    end
  end

  -- Assign combat soldiers
  for i = 1, #combatEntries do
    local entry = combatEntries[i]
    local bestSlot = nil
    local bestScore = -math.huge

    -- Strict spacing (44px)
    for c = 1, #candidates do
      local slot = candidates[c]
      if isSlotSpaced(slot.x, slot.y, claimedSlots, smart_move.MIN_SPACING) then
        local sc = scoreSlotForSoldier(slot, entry.role, entry.weight)
        if sc > bestScore then
          bestScore = sc
          bestSlot = slot
        end
      end
    end

    -- Relaxed spacing (28px) if congested
    if not bestSlot then
      for c = 1, #candidates do
        local slot = candidates[c]
        if isSlotSpaced(slot.x, slot.y, claimedSlots, 28) then
          local sc = scoreSlotForSoldier(slot, entry.role, entry.weight)
          if sc > bestScore then
            bestScore = sc
            bestSlot = slot
          end
        end
      end
    end

    local finalX, finalY
    if bestSlot then
      finalX, finalY = bestSlot.x, bestSlot.y
    else
      local angle = (i - 1) * 2.39996
      local rad = 32 * math.sqrt(i)
      finalX = clickX + math.cos(angle) * rad
      finalY = clickY + math.sin(angle) * rad
    end

    -- Nudge destination via GCore to guarantee it is 100% walkable and clear of hazards
    if pathfinding and pathfinding.findSafeDestination then
      finalX, finalY = pathfinding.findSafeDestination(finalX, finalY, entry.soldier)
    end

    claimedSlots[#claimedSlots + 1] = { x = finalX, y = finalY, soldier = entry.soldier }
    entry.x = finalX
    entry.y = finalY
    entry.cover = bestSlot and bestSlot.cover or 0
    assignments[#assignments + 1] = entry
  end

  -- Assign Medics (sheltered behind squad or near wounded squadmates)
  if #medicEntries > 0 then
    local woundedTargets = {}
    for i = 1, #assignments do
      local a = assignments[i]
      local s = a.soldier
      local maxH = s.maxHealth or 100
      if (s.health or 100) < maxH * 0.85 or (s.health or 100) <= 45 then
        woundedTargets[#woundedTargets + 1] = {
          x = a.x, y = a.y,
          severity = (maxH - (s.health or 100)) / math.max(1, maxH)
        }
      end
    end

    table.sort(woundedTargets, function(a, b) return a.severity > b.severity end)

    for m = 1, #medicEntries do
      local mEntry = medicEntries[m]
      local targetPatient = woundedTargets[m] or woundedTargets[1]
      local bestSlot = nil
      local bestScore = -math.huge

      if targetPatient then
        for c = 1, #candidates do
          local slot = candidates[c]
          if isSlotSpaced(slot.x, slot.y, claimedSlots, 32) then
            local dist = math.sqrt((slot.x - targetPatient.x)^2 + (slot.y - targetPatient.y)^2)
            if dist >= 28 and dist <= 95 then
              local sc = (100 - dist) * 1.8 + slot.cover * 1.6 + slot.concealment * 1.1
              if sc > bestScore then
                bestScore = sc
                bestSlot = slot
              end
            end
          end
        end
      end

      if not bestSlot then
        for c = 1, #candidates do
          local slot = candidates[c]
          if isSlotSpaced(slot.x, slot.y, claimedSlots, smart_move.MIN_SPACING) then
            local sc = scoreSlotForSoldier(slot, "command_support", mEntry.weight)
            if sc > bestScore then
              bestScore = sc
              bestSlot = slot
            end
          end
        end
      end

      local finalX, finalY
      if bestSlot then
        finalX, finalY = bestSlot.x, bestSlot.y
      elseif targetPatient then
        finalX = targetPatient.x - ux * 42
        finalY = targetPatient.y - uy * 42
      else
        finalX = clickX - ux * 60
        finalY = clickY - uy * 60
      end

      if pathfinding and pathfinding.findSafeDestination then
        finalX, finalY = pathfinding.findSafeDestination(finalX, finalY, mEntry.soldier)
      end

      claimedSlots[#claimedSlots + 1] = { x = finalX, y = finalY, soldier = mEntry.soldier }
      mEntry.x = finalX
      mEntry.y = finalY
      mEntry.cover = bestSlot and bestSlot.cover or 0
      assignments[#assignments + 1] = mEntry
    end
  end

  -- Apply assignments directly to soldiers
  for i = 1, #assignments do
    local a = assignments[i]
    a.soldier.targetx = a.x
    a.soldier.targety = a.y
    a.soldier._pfGoalX = nil -- Trigger GCore immediate path recalculation
    a.soldier.combatHaltTimer = 0
    a.soldier._savedOrderX = nil
    a.soldier._savedOrderY = nil
    a.soldier._inCombatReaction = nil
    a.soldier._combatThreatClearTimer = nil
    a.soldier._sprintingToCover = nil
    a.soldier._combatRetaliating = nil
    a.soldier._retaliationDone = nil
    a.soldier.temporaryStop = 0
  end

  smart_move.lastAssignment = {
    clickX = clickX,
    clickY = clickY,
    threatUx = ux,
    threatUy = uy,
    timestamp = (player and player.missionTime) or 0,
    slots = assignments
  }

  return assignments
end

return smart_move