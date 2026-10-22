-- ============================================================================
-- includes/smart_move.lua
-- Section 1.2: Smart Weighted Player Squad Movement & Formation Assignment
-- ============================================================================
-- Replaces the vanilla random scatter (+100 - randNbr(200)) when mass-selecting
-- soldiers with a tactical slot matcher driven by:
--   1. Veterancy & Tactical Weight W_vet(s) from combat skill, rank, XP,
--      missions survived (patrols + combatTime), and kills.
--   2. Class & Weapon Role Profiles (Point/Assault, Rifle Line, Heavy Gunner/AT,
--      Sniper/Recon Overwatch, Command/Comms/Mortar Support, and Medic Triage).
--   3. Real Cover, Concealment, Box2D Sightline Scoring, and Anti-Grenade Spacing.
-- ============================================================================

local smart_move = {}

smart_move.MIN_SPACING = 44 -- Minimum pixel spacing between assigned squadmates

-- Store last assignment metadata for optional debug visualization
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

  -- Combat skill (typically 25..100+)
  local skillRaw = dude.skill or 30
  local skillScore = clamp(skillRaw, 0, 100)

  -- Military rank (0..11+) and level
  local rankRaw = dude.rank or 0
  local levelRaw = dude.level or 1
  local rankScore = clamp(rankRaw * 9 + (levelRaw - 1) * 3, 0, 100)

  -- Direct experience (0..100+)
  local xpRaw = dude.xp or 0
  local xpScore = clamp(xpRaw, 0, 100)

  -- Missions survived (patrols) & combat time survived (seconds)
  local patrols = math.max(0, dude.patrols or dude.missions or 0)
  local combatTime = math.max(0, dude.combatTime or 0)
  local survivalScore = clamp(
    20.0 * math.log(1 + patrols) + 5.0 * math.log(1 + (combatTime / 60.0)),
    0, 100
  )

  -- Kills (total kills + bonus for close-quarters / shotgun kills)
  local kills = math.max(0, dude.kills or 0)
  local hthKills = math.max(0, dude.hthKills or 0)
  local sgKills = math.max(0, dude.sgKills or 0)
  local killsScore = clamp(
    22.0 * math.log(1 + kills + 0.5 * hthKills + 0.25 * sgKills),
    0, 100
  )

  -- Weighted combination + small bonus for earned awards/perks
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

  -- 1. Medic (prioritizes wounded triage or sheltered rear cover)
  if spec == "medic" or (dude.doc or 0) > 0 or (dude.medicBag or 0) > 0 or (dude.medic or 0) > 0 then
    return "medic"
  end

  -- 2. Sniper / Long-Range Recon (prioritizes rear overwatch + concealment + sightlines)
  if spec == "sniper" or (dude.masterSniper or 0) > 0
     or wtag == "scopedSpringfield" or wtag == "scopedGarand" or wtag == "scopedEnfield" or wtag == "scopedK98" or wtag == "g98"
     or wrange >= 430 then
    return "sniper_recon"
  end

  -- 3. Command / Radio / Mortar Support (prioritizes sheltered rear cover)
  if spec == "officer" or spec == "sarge" or spec == "comms"
     or (dude.officerHat or 0) > 0 or (dude.mortar or 0) > 0 or (dude.radio or 0) > 0 then
    return "command_support"
  end

  -- 4. Heavy Gunner / Anti-Tank Overwatch (prioritizes hard cover + clear forward LOS)
  if spec == "gunner"
     or (dude.bazooka or 0) > 0 or (dude.shrek or 0) > 0
     or (dude.boysRifle or 0) > 0 or (dude.pz39 or 0) > 0
     or wclass == "lmg" or wclass == "mg" or wclass == "atRifle"
     or wtag == "bar" or wtag == "m1919" or wtag == "mg42" or wtag == "mg34" or wtag == "bren" or wtag == "vicker" or wtag == "johnson" or wtag == "zb26"
     or (waction == "auto" and wrange >= 260) then
    return "heavy_gunner_at"
  end

  -- 5. Point / Close-Quarters Assault (prioritizes forward hard cover)
  if spec == "commando" or spec == "sapper" or spec == "engy" or spec == "pointMan"
     or (dude.flamer or 0) > 0
     or wclass == "smg" or wclass == "shotgun"
     or wtag == "tommy" or wtag == "m3" or wtag == "sten" or wtag == "stenMKVI" or wtag == "mp40" or wtag == "shotgun"
     or waction == "pump" or wrange <= 230 then
    return "point_assault"
  end

  -- 6. Scout with medium-range rifle -> slight overwatch/flank preference
  if spec == "scout" or spec == "intel" then
    return "sniper_recon"
  end

  return "rifle_line"
end

-- ----------------------------------------------------------------------------
-- 3. Determine Threat Direction Unit Vector (ux, uy) from (clickX, clickY)
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
    local tx = sumX / totalW
    local ty = sumY / totalW
    local vx = tx - clickX
    local vy = ty - clickY
    local len = math.sqrt(vx * vx + vy * vy)
    if len > 1 then
      return vx / len, vy / len
    end
  end

  -- Default directional fallback by game mode
  if player and player.gameType == 1 and player.mnb2SubGame ~= 8 then
    -- Classic Defense mode: Germans advance from North (top) to South (bottom), or East in some modes
    return 1.0, 0.0
  end
  -- Campaign & Trench mode: Germans are to the East (+X)
  return 1.0, 0.0
end

-- ----------------------------------------------------------------------------
-- Helper: Evaluate terrain & cover quality at a world point (wx, wy)
-- ----------------------------------------------------------------------------
local function evaluatePointTerrain(wx, wy, ux, uy, allowBuildingClick)
  local maxX = (player and player.endLine) and (player.endLine + 200) or 2000
  local maxY = (player and player.mapHeight) or 720
  if wx < 16 or wx > maxX or wy < 18 or wy > (maxY - 18) then
    return nil
  end

  -- Reject active fires
  if player and player.fire then
    for i = 1, #player.fire do
      local f = player.fire[i]
      if f and f.x and f.y then
        local dx = wx - f.x
        local dy = wy - f.y
        local rad = math.max(36, (f.size or 0.5) * 45 + 24)
        if (dx * dx + dy * dy) < (rad * rad) then
          return nil
        end
      end
    end
  end

  -- Check pathfinding walkability (pass nil for allowBuildingId to permit valid building destinations)
  if pathfinding and pathfinding.isWalkableWorld then
    local walkable, cellCost = pathfinding.isWalkableWorld(wx, wy, nil, nil)
    if not walkable or (cellCost and cellCost >= 5.0) then
      return nil
    end
  end

  local coverVal = 0
  local concealmentVal = 0
  local isSlow = false

  -- Check groundType cover / hazards
  if player and player.groundType then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and g.x and g.y then
        local inside = false
        if (g.radius or 0) > 0 then
          local dx = wx - g.x
          local dy = wy - g.y
          if (dx * dx + dy * dy) <= (g.radius * g.radius) then
            inside = true
          end
        elseif (g.width or 0) > 0 and (g.length or 0) > 0 then
          if wx >= g.x and wx <= (g.x + g.width) and wy >= g.y and wy <= (g.y + g.length) then
            inside = true
          end
        end

        if inside then
          local gname = g.name or ""
          if gname == "wire" or gname == "entanglement" then
            return nil -- Never intentionally place soldiers onto barbed wire
          end
          if g.slowy == "yes" or gname == "mud" or gname == "water" then
            isSlow = true
          end
          local c = g.cover or 0
          if c > 0 then
            -- If directional cover (midpoint ~= 0), verify friendly side
            local goodSide = true
            if (g.midpoint or 0) ~= 0 then
              if ux >= 0 and wx > g.midpoint then
                goodSide = false
              elseif ux < 0 and wx < g.midpoint then
                goodSide = false
              end
            end
            if goodSide and c > coverVal then
              coverVal = c
            end
          end
        end
      end
    end
  end

  -- Check forest & rock concealment
  if player and player.forest then
    for i = 1, #player.forest do
      local f = player.forest[i]
      if f and f.x and f.y then
        local dx = wx - f.x
        local dy = wy - f.y
        local rad = f.radius or 55
        if (dx * dx + dy * dy) <= (rad * rad) then
          concealmentVal = math.max(concealmentVal, 24)
        end
      end
    end
  end

  if player and player.rocks then
    for i = 1, #player.rocks do
      local r = player.rocks[i]
      if r and r.x and r.y then
        local dx = wx - r.x
        local dy = wy - r.y
        local rad = (r.radius or 40) + 18
        if (dx * dx + dy * dy) <= (rad * rad) then
          concealmentVal = math.max(concealmentVal, 28)
        end
      end
    end
  end

  -- Check building interior shelter & cover
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
          local maxX = minX + bw
          local maxY = minY + bl
          if wx >= minX and wx <= maxX and wy >= minY and wy <= maxY then
            insideBuilding = true
            break
          end
        else
          local rad = (bld.radius or 90) * 0.45
          if ((wx - bx)^2 + (wy - by)^2) <= (rad * rad) then
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

  -- Sightline score using Box2D raycast along threat vector (ux, uy)
  local sightlineVal = 20
  if los_physics and los_physics.castRay then
    local probeDist = 280
    local hitAny, _, _, bestFrac = los_physics.castRay(wx + ux * 18, wy + uy * 18, wx + ux * probeDist, wy + uy * probeDist)
    if not hitAny then
      sightlineVal = 30
    else
      sightlineVal = math.max(4, math.floor(30 * (bestFrac or 0.3)))
    end
  end

  -- Soldiers in buildings shoot through windows/doors; don't penalize sightline for building walls
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
-- 4. Generate Candidate Tactical Slots around (clickX, clickY)
-- ----------------------------------------------------------------------------
function smart_move.generateCandidateSlots(clickX, clickY, squadCount, ux, uy)
  local candidates = {}
  local searchRadius = math.min(280, 150 + (squadCount or 4) * 16)

  -- Perpendicular lateral vector (lx, ly)
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

  -- A. Sample nearby hard cover zones (player.groundType with cover > 0)
  if player and player.groundType then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and (g.cover or 0) > 0 and g.x and g.y then
        if (g.radius or 0) > 0 then
          local dx = g.x - clickX
          local dy = g.y - clickY
          if (dx * dx + dy * dy) <= (searchRadius + g.radius) * (searchRadius + g.radius) then
            tryAddCandidate(g.x, g.y, "cover")
            local rStep = math.min(g.radius * 0.6, 36)
            if rStep >= 18 then
              for a = 0, 5 do
                local ang = a * (math.pi / 3)
                tryAddCandidate(g.x + math.cos(ang) * rStep, g.y + math.sin(ang) * rStep, "cover")
              end
            end
          end
        elseif (g.width or 0) > 0 and (g.length or 0) > 0 then
          local cx = g.x + g.width * 0.5
          local cy = g.y + g.length * 0.5
          local dx = cx - clickX
          local dy = cy - clickY
          local maxDim = math.max(g.width, g.length) * 0.5
          if (dx * dx + dy * dy) <= (searchRadius + maxDim) * (searchRadius + maxDim) then
            local stepX = math.max(36, math.min(52, g.width / 3))
            local stepY = math.max(36, math.min(52, g.length / 3))
            local padX = math.min(14, g.width * 0.25)
            local padY = math.min(14, g.length * 0.25)
            if g.width <= 36 then
              padX = g.width * 0.5
            end
            if g.length <= 36 then
              padY = g.length * 0.5
            end
            for sx = g.x + padX, g.x + g.width - padX + 1, stepX do
              for sy = g.y + padY, g.y + g.length - padY + 1, stepY do
                if (sx - clickX) * (sx - clickX) + (sy - clickY) * (sy - clickY) <= (searchRadius + 40) * (searchRadius + 40) then
                  tryAddCandidate(sx, sy, "cover")
                end
              end
            end
          end
        end
      end
    end
  end

  -- B. Sample interior positions of nearby intact buildings / bunkers
  if player and player.buildings then
    for b = 1, #player.buildings do
      local bld = player.buildings[b]
      if bld and (bld.destroyed or 0) < 1 and (bld.impassable or 0) == 0 and (bld.noGoZone or 0) == 0 then
        local bx = bld.x or 0
        local by = bld.y or 0
        local bw = bld.width or 0
        local bl = bld.length or bld.height or 0
        local dist2 = (bx - clickX)^2 + (by - clickY)^2
        if dist2 <= (searchRadius + 140)^2 then
          if bw > 0 and bl > 0 then
            local minX = (bld.centered == false) and bx or (bx - bw * 0.5)
            local minY = (bld.centered == false) and by or (by - bl * 0.5)
            local maxX = minX + bw
            local maxY = minY + bl
            local pad = 16
            local step = 32
            for sx = minX + pad, maxX - pad, step do
              for sy = minY + pad, maxY - pad, step do
                tryAddCandidate(sx, sy, "building_cover")
              end
            end
          else
            local rad = (bld.radius or 90) * 0.4
            tryAddCandidate(bx, by, "building_cover")
            if rad >= 20 then
              for a = 0, 3 do
                local ang = a * (math.pi / 2)
                tryAddCandidate(bx + math.cos(ang) * (rad * 0.6), by + math.sin(ang) * (rad * 0.6), "building_cover")
              end
            end
          end
        end
      end
    end
  end

  -- B. Sample sheltered spots behind rocks & trees (player.rocks / player.forest)
  if player and player.rocks then
    for i = 1, #player.rocks do
      local r = player.rocks[i]
      if r and r.x and r.y then
        local dx = r.x - clickX
        local dy = r.y - clickY
        if (dx * dx + dy * dy) <= searchRadius * searchRadius then
          local offset = (r.radius or 35) + 16
          -- Sheltered side opposite threat vector (ux, uy)
          tryAddCandidate(r.x - ux * offset, r.y - uy * offset, "rock_cover")
          tryAddCandidate(r.x - ux * offset + lx * 24, r.y - uy * offset + ly * 24, "rock_cover")
          tryAddCandidate(r.x - ux * offset - lx * 24, r.y - uy * offset - ly * 24, "rock_cover")
        end
      end
    end
  end

  if player and player.forest then
    for i = 1, #player.forest do
      local f = player.forest[i]
      if f and f.x and f.y then
        local dx = f.x - clickX
        local dy = f.y - clickY
        if (dx * dx + dy * dy) <= searchRadius * searchRadius then
          tryAddCandidate(f.x - ux * 18, f.y - uy * 18, "forest_conceal")
          tryAddCandidate(f.x + lx * 32, f.y + ly * 32, "forest_conceal")
          tryAddCandidate(f.x - lx * 32, f.y - ly * 32, "forest_conceal")
        end
      end
    end
  end

  -- C. Tactical Formation Slots (Forward Line, Main Line, Rear Support, Sniper Overwatch)
  local depthTiers = { 42, 16, 0, -24, -56, -96, -144 }
  local maxCols = math.max(5, math.ceil((squadCount or 4) * 0.85) + 2)
  local latSpacing = 48

  for _, depth in ipairs(depthTiers) do
    for col = -maxCols, maxCols do
      -- Slight chevron/stagger so soldiers aren't in a rigid robotic line
      local stagger = (math.abs(col) % 2 == 1) and -10 or 0
      local wx = clickX + ux * (depth + stagger) + lx * (col * latSpacing)
      local wy = clickY + uy * (depth + stagger) + ly * (col * latSpacing)
      tryAddCandidate(wx, wy, depth < -45 and "overwatch" or "formation")
    end
  end

  return candidates
end

-- ----------------------------------------------------------------------------
-- Score a Candidate Slot for a Specific Soldier Role & Veterancy Weight
-- ----------------------------------------------------------------------------
local function scoreSlotForSoldier(slot, role, vetWeight)
  -- Baseline cover encouragement: even a rookie with 0 XP gets a strong base incentive for cover (+35 flat, 2.0x cover)
  local baseCover = 0
  if (slot.cover or 0) > 0 then
    baseCover = 35.0 + (slot.cover * 2.0)
  end
  local vetCoverBonus = (slot.cover or 0) * (vetWeight / 100.0) * 1.5
  local coverScore = baseCover + vetCoverBonus

  local concealScore = (slot.concealment or 0) * (0.9 + (vetWeight / 100.0) * 0.5)
  local sightScore = slot.sightline or 20
  local depth = slot.forwardDepth or 0

  -- For cover slots, reduce distance penalty so troops readily take nearby cover
  local distRate = (slot.cover and slot.cover > 0) and 0.08 or 0.22
  local distPenalty = (slot.distFromClick or 0) * distRate
  local slowPenalty = slot.slow and 25 or 0

  local roleScore = 0
  if role == "point_assault" then
    roleScore = coverScore * 1.65 + concealScore * 0.7 + sightScore * 0.7
    local idealDepth = 32
    roleScore = roleScore - math.abs(depth - idealDepth) * 0.45
  elseif role == "heavy_gunner_at" then
    roleScore = coverScore * 1.75 + concealScore * 0.8 + sightScore * 1.85
    local idealDepth = 8
    roleScore = roleScore - math.abs(depth - idealDepth) * 0.40
  elseif role == "sniper_recon" then
    roleScore = coverScore * 1.35 + concealScore * 1.75 + sightScore * 1.65
    local idealDepth = -105
    roleScore = roleScore - math.abs(depth - idealDepth) * 0.55
    if depth <= -50 then
      roleScore = roleScore + 35
    end
  elseif role == "command_support" then
    roleScore = coverScore * 1.60 + concealScore * 1.25 + sightScore * 0.50
    local idealDepth = -75
    roleScore = roleScore - math.abs(depth - idealDepth) * 0.50
    if depth <= -35 then
      roleScore = roleScore + 25
    end
  else
    -- "rifle_line": strong baseline appreciation for cover + sightlines
    roleScore = coverScore * 1.65 + concealScore * 1.0 + sightScore * 1.0
    local idealDepth = 5
    roleScore = roleScore - math.abs(depth - idealDepth) * 0.40
  end

  return roleScore - distPenalty - slowPenalty
end

-- ----------------------------------------------------------------------------
-- Check if (x, y) respects anti-grenade spacing against claimed slots
-- ----------------------------------------------------------------------------
local function isSlotSpaced(wx, wy, claimedSlots, minSpacing)
  local minD2 = minSpacing * minSpacing
  for i = 1, #claimedSlots do
    local c = claimedSlots[i]
    local dx = wx - c.x
    local dy = wy - c.y
    if (dx * dx + dy * dy) < minD2 then
      return false
    end
  end
  return true
end

-- ----------------------------------------------------------------------------
-- 5. Assign Tactical Destinations to a Selected Group of Player Soldiers
-- Returns: assignments array { { soldier = s, x = ..., y = ..., role = ..., weight = ... }, ... }
-- ----------------------------------------------------------------------------
function smart_move.assignSquadMoveOrder(selectedSoldiers, clickX, clickY)
  if not selectedSoldiers or #selectedSoldiers == 0 then
    return {}
  end

  local ux, uy = smart_move.determineThreatVector(clickX, clickY)
  local candidates = smart_move.generateCandidateSlots(clickX, clickY, #selectedSoldiers, ux, uy)

  -- Separate medics from combat/support troops so medics can position relative
  -- to wounded squadmates' assigned slots (or behind squad center of mass)
  local combatEntries = {}
  local medicEntries = {}

  for i = 1, #selectedSoldiers do
    local s = selectedSoldiers[i]
    local wVet, breakdown = smart_move.computeVeterancyWeight(s)
    local role = smart_move.classifyRole(s)
    local entry = {
      soldier = s,
      weight = wVet,
      breakdown = breakdown,
      role = role
    }
    if role == "medic" then
      medicEntries[#medicEntries + 1] = entry
    else
      combatEntries[#combatEntries + 1] = entry
    end
  end

  -- Sort combat entries in descending order of Veterancy Weight W_vet
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

  -- Pre-populate claimedSlots with stationary unselected living allies already at destination
  if player and player.deployedTroops then
    local selectedSet = {}
    for i = 1, #selectedSoldiers do
      selectedSet[selectedSoldiers[i]] = true
    end
    for i = 1, #player.deployedTroops do
      local t = player.deployedTroops[i]
      if t and t.faction == "allied" and (t.health or 0) > 10 and (t.dead or 0) == 0 and not selectedSet[t] then
        local tx = t.targetx or t.x
        local ty = t.targety or t.y
        if (tx - clickX) * (tx - clickX) + (ty - clickY) * (ty - clickY) < (260 * 260) then
          claimedSlots[#claimedSlots + 1] = { x = tx, y = ty, stationary = true }
        end
      end
    end
  end

  -- Assign combat/support soldiers in descending veterancy order
  for i = 1, #combatEntries do
    local entry = combatEntries[i]
    local bestSlot = nil
    local bestScore = -math.huge

    -- Pass 1: strict anti-grenade spacing (44 px)
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

    -- Pass 2: relaxed spacing (28 px) if area is tight
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
      -- Fallback spiral slot
      local angle = (i - 1) * 2.39996
      local rad = 32 * math.sqrt(i)
      finalX = clamp(clickX + math.cos(angle) * rad, 20, ((player and player.endLine) or 1280) + 180)
      finalY = clamp(clickY + math.sin(angle) * rad, 20, 700)
    end

    claimedSlots[#claimedSlots + 1] = { x = finalX, y = finalY, soldier = entry.soldier }
    entry.x = finalX
    entry.y = finalY
    entry.cover = bestSlot and bestSlot.cover or 0
    assignments[#assignments + 1] = entry
  end

  -- Step 4: Assign Medics near wounded/bleeding allies or sheltered behind squad
  if #medicEntries > 0 then
    -- Identify wounded allies (either in the moving squad or already deployed near clickX, clickY)
    local woundedTargets = {}

    for i = 1, #assignments do
      local a = assignments[i]
      local s = a.soldier
      local maxH = s.maxHealth or 100
      if (s.health or 100) < maxH * 0.85 or (s.health or 100) <= 45 then
        woundedTargets[#woundedTargets + 1] = {
          x = a.x,
          y = a.y,
          severity = (maxH - (s.health or 100)) / math.max(1, maxH)
        }
      end
    end

    if player and player.deployedTroops then
      for i = 1, #player.deployedTroops do
        local t = player.deployedTroops[i]
        if t and t.faction == "allied" and (t.dead or 0) == 0 and (t.health or 0) > 0 then
          local maxH = t.maxHealth or 100
          if t.health < maxH * 0.85 or t.health <= 45 then
            local dx = t.x - clickX
            local dy = t.y - clickY
            if (dx * dx + dy * dy) <= (340 * 340) then
              woundedTargets[#woundedTargets + 1] = {
                x = t.targetx or t.x,
                y = t.targety or t.y,
                severity = ((maxH - t.health) / math.max(1, maxH)) + (t.health <= 10 and 2.0 or 0)
              }
            end
          end
        end
      end
    end

    table.sort(woundedTargets, function(a, b)
      return a.severity > b.severity
    end)

    for m = 1, #medicEntries do
      local mEntry = medicEntries[m]
      local targetPatient = woundedTargets[m] or woundedTargets[1]
      local bestSlot = nil
      local bestScore = -math.huge

      if targetPatient then
        -- Generate extra triage candidate slots right next to the patient (36..58 px away, sheltered behind patient)
        local lx, ly = -uy, ux
        local triageOffsets = {
          { -ux * 44, -uy * 44 },
          { -ux * 38 + lx * 26, -uy * 38 + ly * 26 },
          { -ux * 38 - lx * 26, -uy * 38 - ly * 26 },
          { lx * 44, ly * 44 },
          { -lx * 44, -ly * 44 },
          { ux * 40, uy * 40 }
        }
        for _, off in ipairs(triageOffsets) do
          local twx = targetPatient.x + off[1]
          local twy = targetPatient.y + off[2]
          local info = evaluatePointTerrain(twx, twy, ux, uy, false)
          if info then
            info.forwardDepth = (twx - clickX) * ux + (twy - clickY) * uy
            info.distFromClick = math.sqrt((twx - clickX) * (twx - clickX) + (twy - clickY) * (twy - clickY))
            candidates[#candidates + 1] = info
          end
        end

        for c = 1, #candidates do
          local slot = candidates[c]
          if isSlotSpaced(slot.x, slot.y, claimedSlots, 32) then
            local dx = slot.x - targetPatient.x
            local dy = slot.y - targetPatient.y
            local distToPatient = math.sqrt(dx * dx + dy * dy)
            if distToPatient >= 28 and distToPatient <= 95 then
              -- Score closeness to patient + cover + sheltered side behind patient
              local shelterDot = -((dx * ux + dy * uy) / math.max(1, distToPatient))
              local sc = (100 - distToPatient) * 1.8 + slot.cover * 1.6 + slot.concealment * 1.1 + shelterDot * 22
              if sc > bestScore then
                bestScore = sc
                bestSlot = slot
              end
            end
          end
        end
      end

      -- If no wounded patient nearby (or no close slot), place medic in sheltered rear cover behind squad
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
        finalX = clamp(targetPatient.x - ux * 42, 20, ((player and player.endLine) or 1280) + 180)
        finalY = clamp(targetPatient.y - uy * 42, 20, 700)
      else
        finalX = clamp(clickX - ux * 60, 20, ((player and player.endLine) or 1280) + 180)
        finalY = clamp(clickY - uy * 60, 20, 700)
      end

      claimedSlots[#claimedSlots + 1] = { x = finalX, y = finalY, soldier = mEntry.soldier }
      mEntry.x = finalX
      mEntry.y = finalY
      mEntry.cover = bestSlot and bestSlot.cover or 0
      assignments[#assignments + 1] = mEntry
    end
  end

  -- Apply assignments to soldiers
  for i = 1, #assignments do
    local a = assignments[i]
    a.soldier.targetx = a.x
    a.soldier.targety = a.y
    a.soldier._pfGoalX = nil -- Trigger immediate pathfinding check
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
