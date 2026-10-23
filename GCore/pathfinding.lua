-- ============================================================================
-- includes/pathfinding.lua
-- Section 1.1: Tactical Nav-Grid, 8-Way A* + LOS String-Pulling & Thread Pool
-- ============================================================================
-- Provides obstacle- and hazard-aware navigation for both AI and player-
-- controlled infantry and vehicles in Mud and Blood (v0.5.3b, LOVE 11.4).
-- ============================================================================

local pathfinding = {}

pathfinding.CELL_SIZE = 32
pathfinding.debugOverlay = false

local SQRT2 = 1.4142135623730951
local DIRS = {
  {  1,  0, 1.0   },
  { -1,  0, 1.0   },
  {  0,  1, 1.0   },
  {  0, -1, 1.0   },
  {  1,  1, SQRT2 },
  { -1,  1, SQRT2 },
  {  1, -1, SQRT2 },
  { -1, -1, SQRT2 }
}

local OVERHEAD_ONLY_BUILDINGS = {
  camNet = true,
  bofor = true,
  tent = true,
  antena = true
}

local BARRIER_PLACEABLES = {
  dragonTooth = 24,
  obstacle = 26,
  palisade = 28,
  barricade = 26,
  hogBale1 = 24,
  fence1 = 16,
  fence2 = 16,
  fence3 = 16,
  achWall = 24
}

-- Cached nav-grid state
local navGrid = {
  originX = -256,
  originY = 0,
  cols = 60,
  rows = 23,
  cellSize = 32,
  baseCosts = {},       -- flat array [1 .. cols*rows], <0 = impassable
  buildingIds = {},     -- flat array [1 .. cols*rows], >0 = building index
  treeIds = {},         -- flat array [1 .. cols*rows], >0 = forest tree index
  treeTrunkIds = {},    -- flat array [1 .. cols*rows], >0 = solid trunk center
  vehicleBlocked = {},  -- flat array [1 .. cols*rows], true = blocked for vehicles
  alliedMineCost = {},  -- flat array [1 .. cols*rows], penalty for detected/allied mines
  axisMineCost = {},    -- flat array [1 .. cols*rows], penalty for detected/axis mines
  lastSyncTime = -999,
  dirty = true
}

-- Background love.thread worker state
local workerThread = nil
local reqChannel = nil
local resChannel = nil
local nextAsyncReqId = 1
local pendingUnitsByReqId = {}

pathfinding.stats = {
  syncCount = 0,
  pathsComputed = 0,
  directPaths = 0,
  asyncJobsSent = 0,
  asyncJobsCompleted = 0,
  lastRebuildMs = 0
}

-- ----------------------------------------------------------------------------
-- Coordinate Conversions
-- ----------------------------------------------------------------------------
function pathfinding.worldToGrid(wx, wy)
  local cs = navGrid.cellSize
  local c = math.floor(((wx or 0) - navGrid.originX) / cs) + 1
  local r = math.floor(((wy or 0) - navGrid.originY) / cs) + 1
  if c < 1 then c = 1 elseif c > navGrid.cols then c = navGrid.cols end
  if r < 1 then r = 1 elseif r > navGrid.rows then r = navGrid.rows end
  return c, r
end

function pathfinding.gridToWorld(c, r)
  local cs = navGrid.cellSize
  return navGrid.originX + (c - 0.5) * cs, navGrid.originY + (r - 0.5) * cs
end

local function cellIndex(c, r)
  return (r - 1) * navGrid.cols + c
end

-- ----------------------------------------------------------------------------
-- Helper: Determine if a soldier can cut barbed wire / entanglements
-- ----------------------------------------------------------------------------
local function canCutWire(unit)
  if not unit then return false end
  if (unit.wireCutter or 0) > 0 or (unit.toolBox or 0) > 0 then
    return true
  end
  if unit.spec == "engy" or unit.spec == "sapper" then
    return true
  end
  return false
end

-- ----------------------------------------------------------------------------
-- Helper: Extract a building's world-space AABB footprint
-- ----------------------------------------------------------------------------
local function getBuildingFootprint(b, bIndex)
  if not b or OVERHEAD_ONLY_BUILDINGS[b.name or ""] then
    return nil
  end
  if (b.destroyed or 0) >= 1 then
    return nil
  end

  -- Check if there is a linked groundType floor by cheeseID
  if player and player.groundType and b.cheeseID then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and g.cheeseID == b.cheeseID then
        if (g.width or 0) > 0 and (g.length or 0) > 0 then
          return g.x, g.y, g.x + g.width, g.y + g.length, (b.impassable == 1 or b.noGoZone == 1)
        elseif (g.radius or 0) > 0 then
          local rad = g.radius * 0.65
          return g.x - rad, g.y - rad, g.x + rad, g.y + rad, (b.impassable == 1 or b.noGoZone == 1)
        end
      end
    end
  end

  -- Explicit width/length or radius on the building record itself
  local bx = b.x or 0
  local by = b.y or 0
  local bw = b.width or 0
  local bl = b.length or b.height or 0
  if bw > 0 and bl > 0 then
    -- Check if (bx, by) is center or top-left
    if b.centered == false then
      return bx, by, bx + bw, by + bl, (b.impassable == 1 or b.noGoZone == 1)
    else
      return bx - bw * 0.5, by - bl * 0.5, bx + bw * 0.5, by + bl * 0.5, (b.impassable == 1 or b.noGoZone == 1)
    end
  end

  local rad = (b.radius or 90) * 0.45
  if rad < 28 then rad = 28 end
  if rad > 140 then rad = 140 end
  return bx - rad, by - rad, bx + rad, by + rad, (b.impassable == 1 or b.noGoZone == 1)
end

-- ----------------------------------------------------------------------------
-- Rebuild the Tactical Nav-Grid from live `player` state
-- ----------------------------------------------------------------------------
function pathfinding.rebuildGrid()
  if not player then return end
  local t0 = love.timer and love.timer.getTime() or 0

  local cs = pathfinding.CELL_SIZE
  local minX = -256
  local maxX = math.max(1600, (player.endLine or 1280) + 640)
  if player.mapWidth and player.mapWidth > maxX then
    maxX = player.mapWidth + 256
  end
  local minY = 0
  local maxY = math.max(720, player.mapHeight or 720)

  local cols = math.max(10, math.ceil((maxX - minX) / cs))
  local rows = math.max(10, math.ceil((maxY - minY) / cs))

  navGrid.originX = minX
  navGrid.originY = minY
  navGrid.cols = cols
  navGrid.rows = rows
  navGrid.cellSize = cs

  local baseCosts = navGrid.baseCosts
  local buildingIds = navGrid.buildingIds
  local treeIds = navGrid.treeIds
  local treeTrunkIds = navGrid.treeTrunkIds
  local vehicleBlocked = navGrid.vehicleBlocked
  local alliedMineCost = navGrid.alliedMineCost
  local axisMineCost = navGrid.axisMineCost
  local totalCells = cols * rows

  for i = 1, totalCells do
    baseCosts[i] = 1.0
    buildingIds[i] = 0
    treeIds[i] = 0
    treeTrunkIds[i] = 0
    vehicleBlocked[i] = false
    alliedMineCost[i] = 0
    axisMineCost[i] = 0
  end

  -- Helper to rasterize an AABB in world coordinates
  local function markRect(x1, y1, x2, y2, fn)
    local c1 = math.max(1, math.floor((x1 - minX) / cs) + 1)
    local c2 = math.min(cols, math.floor((x2 - minX) / cs) + 1)
    local r1 = math.max(1, math.floor((y1 - minY) / cs) + 1)
    local r2 = math.min(rows, math.floor((y2 - minY) / cs) + 1)
    for r = r1, r2 do
      local rowOffset = (r - 1) * cols
      for c = c1, c2 do
        fn(rowOffset + c, c, r)
      end
    end
  end

  -- Helper to rasterize a circle in world coordinates
  local function markCircle(cx, cy, radius, fn)
    if not cx or not cy or not radius or radius <= 0 then return end
    local r2 = radius * radius
    local c1 = math.max(1, math.floor((cx - radius - minX) / cs) + 1)
    local c2 = math.min(cols, math.floor((cx + radius - minX) / cs) + 1)
    local row1 = math.max(1, math.floor((cy - radius - minY) / cs) + 1)
    local row2 = math.min(rows, math.floor((cy + radius - minY) / cs) + 1)
    for r = row1, row2 do
      local wy = minY + (r - 0.5) * cs
      local dy2 = (wy - cy) * (wy - cy)
      local rowOffset = (r - 1) * cols
      for c = c1, c2 do
        local wx = minX + (c - 0.5) * cs
        if (wx - cx) * (wx - cx) + dy2 <= r2 then
          fn(rowOffset + c, c, r)
        end
      end
    end
  end

  -- 1. Roads (player.roads) -> lower cost (0.75)
  if player.roads then
    for i = 1, #player.roads do
      local rd = player.roads[i]
      if rd and rd.x and rd.y then
        local rw = rd.width or rd.radius or 48
        local rl = rd.length or rw
        markRect(rd.x - rw * 0.5, rd.y - rl * 0.5, rd.x + rw * 0.5, rd.y + rl * 0.5, function(idx)
          if baseCosts[idx] > 0.75 then baseCosts[idx] = 0.75 end
        end)
      end
    end
  end

  -- 2. Forest (player.forest): Trunks (high cost/obstacle) & Canopies (moderate brush avoidance)
  if player.forest then
    for i = 1, #player.forest do
      local f = player.forest[i]
      if f and f.x and f.y then
        local canopyRad = (f.radius or 50) * 0.80
        local trunkRad = (f.type == 8 and (f.radius or 50) * 0.25 or (f.radius or 50) * 0.35)
        -- Canopy avoidance
        markCircle(f.x, f.y, canopyRad, function(idx)
          treeIds[idx] = i
          if baseCosts[idx] > 0 and baseCosts[idx] < 2.5 then
            baseCosts[idx] = 2.5
          end
        end)
        -- Trunk center
        markCircle(f.x, f.y, trunkRad, function(idx)
          treeTrunkIds[idx] = i
          vehicleBlocked[idx] = true
          if baseCosts[idx] > 0 and baseCosts[idx] < 4.8 then
            baseCosts[idx] = 4.8
          end
        end)
      end
    end
  end

  -- 3. GroundType zones (cover, mud, water, wire, entanglement, bunkers, buildings)
  if player.groundType then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and g.x and g.y then
        local gname = g.name or ""
        local gcov = g.cover or 0
        local gslow = (g.slowy == "yes") or ((g.incline or 0) ~= 0)
        local gimpassable = (g.impassable == 1 or g.noGoZone == 1 or g.deep == 1)

        local applyCell = function(idx)
          if gimpassable then
            baseCosts[idx] = -1
            vehicleBlocked[idx] = true
            return
          end
          if baseCosts[idx] < 0 then return end

          if gname == "wire" or gname == "entanglement" then
            if baseCosts[idx] < 6.5 then baseCosts[idx] = 6.5 end
          elseif gname == "killZone" then
            if baseCosts[idx] < 3.5 then baseCosts[idx] = 3.5 end
          elseif gname == "water" then
            -- Water slows infantry and blocks non-amphibious vehicles unless bridged
            if baseCosts[idx] < 2.2 then baseCosts[idx] = 2.2 end
            vehicleBlocked[idx] = true
          elseif gslow or gname == "mud" then
            if baseCosts[idx] < 2.0 then baseCosts[idx] = 2.0 end
          elseif gname == "road" or gname == "cobble" then
            if baseCosts[idx] > 0.75 then baseCosts[idx] = 0.75 end
            vehicleBlocked[idx] = false
          elseif gcov > 0 then
            -- Trenches, craters, sandbags, bunkers
            if gname == "concrete" and gcov > 40 then
              -- Concrete bunker footprint: blocks vehicles, high pass-through cost unless entering/exiting
              vehicleBlocked[idx] = true
              if buildingIds[idx] == 0 then
                buildingIds[idx] = 10000 + u
              end
            elseif gname == "wood" and (g.width or 0) ~= 89 then
              -- Wood building floor: blocks vehicles, tagged with buildingId
              vehicleBlocked[idx] = true
              if buildingIds[idx] == 0 then
                buildingIds[idx] = 20000 + u
              end
            else
              -- Standard field cover (trench, crater, foxhole, sandbag)
              if baseCosts[idx] == 1.0 or baseCosts[idx] == 1.30 then
                baseCosts[idx] = 0.85
              end
            end
          end
        end

        if (g.radius or 0) > 0 then
          markCircle(g.x, g.y, g.radius, applyCell)
        elseif (g.width or 0) > 0 and (g.length or 0) > 0 then
          markRect(g.x, g.y, g.x + g.width, g.y + g.length, applyCell)
        end
      end
    end
  end

  -- 4. Buildings (player.buildings)
  if player.buildings then
    for i = 1, #player.buildings do
      local b = player.buildings[i]
      local x1, y1, x2, y2, strictBlock = getBuildingFootprint(b, i)
      if x1 then
        markRect(x1 - 6, y1 - 6, x2 + 6, y2 + 6, function(idx)
          vehicleBlocked[idx] = true
          buildingIds[idx] = i
          if strictBlock then
            baseCosts[idx] = -1
          end
        end)
      end
    end
  end

  -- 5. Deco noGoZones / cliff boulders (player.deco)
  if player.deco then
    for i = 1, #player.deco do
      local d = player.deco[i]
      if d and (d.noGoZone == 1 or d.impassable == 1) and d.x and d.y then
        if (d.width or 0) > 0 and (d.length or 0) > 0 then
          markRect(d.x, d.y, d.x + d.width, d.y + d.length, function(idx)
            baseCosts[idx] = -1
            vehicleBlocked[idx] = true
          end)
        else
          local drad = d.radius or 32
          markCircle(d.x, d.y, drad, function(idx)
            baseCosts[idx] = -1
            vehicleBlocked[idx] = true
          end)
        end
      end
    end
  end

  -- Rocks (player.rocks) -> impassable boulders
  if player.rocks then
    for i = 1, #player.rocks do
      local r = player.rocks[i]
      if r and r.x and r.y then
        local rrad = ((50 * (r.size or 10)) / 10) * 0.85
        markCircle(r.x, r.y, rrad, function(idx)
          baseCosts[idx] = -1
          vehicleBlocked[idx] = true
        end)
      end
    end
  end

  -- Impassable LOS Blockers / Cliffs (player.losBlockers)
  if player.losBlockers then
    for i = 1, #player.losBlockers do
      local lb = player.losBlockers[i]
      if lb and lb.x and lb.y and (lb.type ~= "smoke" or lb.impassable == 1) then
        markCircle(lb.x, lb.y, lb.radius or 40, function(idx)
          baseCosts[idx] = -1
          vehicleBlocked[idx] = true
        end)
      end
    end
  end

  -- 6. Placeables: barriers (dragonTooth, palisade, barricade, obstacle) & mines
  if player.placeables then
    for i = 1, #player.placeables do
      local p = player.placeables[i]
      if p and p.x and p.y and p.x < 9000 then
        local pname = p.name or ""
        local barrierRad = BARRIER_PLACEABLES[pname]
        if p.noGoZone == 1 or p.impassable == 1 then
          barrierRad = p.radius or 32
        end
        if barrierRad then
          markCircle(p.x, p.y, barrierRad, function(idx)
            baseCosts[idx] = -1
            vehicleBlocked[idx] = true
          end)
        elseif pname == "barbedWire" or pname == "wire" or pname == "entanglement" or string.find(pname, "Wire") or string.find(pname, "wire") then
          markCircle(p.x, p.y, p.radius or 36, function(idx)
            if baseCosts[idx] > 0 and baseCosts[idx] < 6.5 then
              baseCosts[idx] = 6.5
            end
          end)
        elseif string.find(pname, "Mine") or string.find(pname, "mine") then
          -- Known/flagged mines get high avoidance cost
          if (p.flagged or 0) > 0 or p.faction == "allied" or p.known == 1 then
            markCircle(p.x, p.y, 40, function(idx)
              if baseCosts[idx] > 0 and baseCosts[idx] < 22.0 then
                baseCosts[idx] = 22.0
              end
            end)
          end
        end
      end
    end
  end

  -- 7. Active fires (player.fire) -> strong hazard avoidance (cost = 18.0)
  if player.fire then
    for i = 1, #player.fire do
      local f = player.fire[i]
      if f and f.x and f.y and (f.burnTime == nil or f.burnTime > 0) then
        local frad = math.max(34, (f.size or 0.5) * 45 + 24)
        markCircle(f.x, f.y, frad, function(idx)
          if baseCosts[idx] > 0 and baseCosts[idx] < 18.0 then
            baseCosts[idx] = 18.0
          end
        end)
      end
    end
  end

  -- 8. Minefield hazards (player.mineField)
  -- Detected / friendly mines get extreme penalty to steer around them safely
  if player.mineField then
    for i = 1, #player.mineField do
      local m = player.mineField[i]
      if m and m.x and m.y and m.x < 9000 then
        local isFlagged = (m.flagged or 0) > 0
        local isAllied = (m.faction == "allied")
        local isAxis = (m.faction == "axis")
        local mrad = math.max(35, (m.radius or 25) + 10)

        -- Allied soldiers avoid if flagged (detected) OR friendly allied mine
        if isFlagged or isAllied then
          markCircle(m.x, m.y, mrad, function(idx)
            if alliedMineCost[idx] < 28.0 then
              alliedMineCost[idx] = 28.0
            end
          end)
        end

        -- Axis soldiers avoid if flagged (detected) OR friendly axis mine
        if isFlagged or isAxis then
          markCircle(m.x, m.y, mrad, function(idx)
            if axisMineCost[idx] < 28.0 then
              axisMineCost[idx] = 28.0
            end
          end)
        end
      end
    end
  end

  navGrid.dirty = false
  navGrid.lastSyncTime = (player and player.missionTime) or 0
  pathfinding.stats.syncCount = pathfinding.stats.syncCount + 1
  if love.timer then
    pathfinding.stats.lastRebuildMs = (love.timer.getTime() - t0) * 1000
  end
end


-- ----------------------------------------------------------------------------
-- Sanitize & Nudge Destination Away from Hazards & Impassable Obstacles
-- ----------------------------------------------------------------------------
function pathfinding.findSafeDestination(wx, wy, unit)
  if not wx or not wy then return wx, wy end
  pathfinding.ensureSynced(false)

  local maxX = (player and player.endLine) and (player.endLine + 200) or 2000
  local maxY = (player and player.mapHeight) or 720

  local function isPointSafe(x, y)
    -- 1. Map bounds
    if x < 16 or x > maxX or y < 18 or y > (maxY - 18) then
      return false
    end

    -- 2. Active fire avoidance
    if player and player.fire then
      for i = 1, #player.fire do
        local f = player.fire[i]
        if f and f.x and f.y and (f.burnTime == nil or f.burnTime > 0) then
          local rad = math.max(36, (f.size or 0.5) * 45 + 24)
          if (x - f.x)^2 + (y - f.y)^2 < (rad * rad) then
            return false
          end
        end
      end
    end

    -- 3. Walkability & hazard threshold (< 5.0 filters out wire=6.5, mines=22+, fires=18+, obstacles=-1)
    local walkable, cost = pathfinding.isWalkableWorld(x, y, unit)
    return walkable and cost and cost < 5.0
  end

  -- If click location is already safe, keep it
  if isPointSafe(wx, wy) then
    return wx, wy
  end

  -- Radial search outward (up to 96px in 16px steps) to find the nearest clear spot
  for rad = 16, 96, 16 do
    local steps = math.max(8, math.floor((2 * math.pi * rad) / 16))
    for i = 0, steps - 1 do
      local ang = (i / steps) * 2 * math.pi
      local candX = wx + math.cos(ang) * rad
      local candY = wy + math.sin(ang) * rad
      if isPointSafe(candX, candY) then
        return candX, candY
      end
    end
  end

  return wx, wy
end

-- ----------------------------------------------------------------------------
-- Ensure the Nav-Grid is fresh
-- ----------------------------------------------------------------------------
function pathfinding.ensureSynced(force)
  if not player then return end
  local now = player.missionTime or 0
  if force or navGrid.dirty or math.abs(now - navGrid.lastSyncTime) >= 0.75 then
    pathfinding.rebuildGrid()
  end
end

function pathfinding.markDirty()
  navGrid.dirty = true
end

function pathfinding.invalidateHazards()
  navGrid.dirty = true
  if player then
    if player.deployedTroops then
      for i = 1, #player.deployedTroops do
        local u = player.deployedTroops[i]
        if u then
          u._pfRecheckTimer = 0
          u.pathQueue = nil
        end
      end
    end
    if player.deployedVehicles then
      for i = 1, #player.deployedVehicles do
        local v = player.deployedVehicles[i]
        if v then
          v._pfRecheckTimer = 0
          v.pathQueue = nil
        end
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- Evaluate effective cell cost for a specific unit and start/goal buildings
-- ----------------------------------------------------------------------------
local function getEffectiveCellCost(idx, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
  local base = navGrid.baseCosts[idx] or 1.0
  if base < 0 then
    return -1
  end
  if isVehicle and navGrid.vehicleBlocked[idx] then
    return -1
  end

  local bId = navGrid.buildingIds[idx] or 0
  if bId > 0 then
    if isVehicle then
      return -1
    end
    -- If soldier is starting inside or heading into this building, treat it as cover!
    if bId == startBldId or bId == goalBldId then
      if base < 6.0 then
        return 0.85
      end
    else
      -- Otherwise, block cutting straight through a building interior when moving past it
      return -1
    end
  end

  -- If goal destination is inside the trees, relax tree avoidance!
  if goalInTree and navGrid.treeIds[idx] and navGrid.treeIds[idx] > 0 then
    if not isVehicle then
      if navGrid.treeTrunkIds[idx] and navGrid.treeTrunkIds[idx] > 0 then
        return 1.8
      else
        return 0.95
      end
    end
  end

  if base == 6.5 and wireCutter then
    base = 1.05
  end

  local faction = (unit and unit.faction) or "allied"
  local minePen = (faction == "axis") and (navGrid.axisMineCost and navGrid.axisMineCost[idx])
                                      or  (navGrid.alliedMineCost and navGrid.alliedMineCost[idx])
  if minePen and minePen > 0 then
    base = base + minePen
  end

  return base
end

-- ----------------------------------------------------------------------------
-- Query whether a world coordinate is walkable
-- ----------------------------------------------------------------------------
function pathfinding.isWalkableWorld(wx, wy, unit, allowBuildingId)
  pathfinding.ensureSynced(false)
  local c, r = pathfinding.worldToGrid(wx, wy)
  local idx = cellIndex(c, r)
  local isVehicle = unit and (unit.turret ~= nil or unit.pivotSpeed ~= nil) or false
  local bId = allowBuildingId or (navGrid.buildingIds[idx] or 0)
  local cost = getEffectiveCellCost(idx, unit, isVehicle, bId, bId, canCutWire(unit))
  return cost > 0 and cost < 15.0, cost
end

-- ----------------------------------------------------------------------------
-- Check if a straight corridor between two grid cells is clear of obstacles
-- and high-cost hazards
-- ----------------------------------------------------------------------------
local function isCorridorClear(c1, r1, c2, r2, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
  local dc = c2 - c1
  local dr = r2 - r1
  local steps = math.max(math.abs(dc), math.abs(dr)) * 2
  if steps <= 1 then return true end
  local cols = navGrid.cols
  local rows = navGrid.rows
  for s = 1, steps - 1 do
    local t = s / steps
    local cc = math.floor(c1 + dc * t + 0.5)
    local rr = math.floor(r1 + dr * t + 0.5)
    if cc < 1 or cc > cols or rr < 1 or rr > rows then
      return false
    end
    local idx = (rr - 1) * cols + cc
    local cost = getEffectiveCellCost(idx, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
    if cost < 0 or cost >= 2.2 then
      return false
    end
  end
  return true
end

-- ----------------------------------------------------------------------------
-- Fast Straight-Line Check: Does the unit need A* detouring?
-- ----------------------------------------------------------------------------
function pathfinding.needsDetour(x1, y1, x2, y2, unit)
  pathfinding.ensureSynced(false)
  local dx = x2 - x1
  local dy = y2 - y1
  if (dx * dx + dy * dy) < (24 * 24) then
    return false
  end
  local c1, r1 = pathfinding.worldToGrid(x1, y1)
  local c2, r2 = pathfinding.worldToGrid(x2, y2)
  local startIdx = cellIndex(c1, r1)
  local goalIdx = cellIndex(c2, r2)
  local startBldId = navGrid.buildingIds[startIdx] or 0
  local goalBldId = navGrid.buildingIds[goalIdx] or 0
  local isVehicle = unit and (unit.turret ~= nil or unit.pivotSpeed ~= nil) or false
  local wireCutter = canCutWire(unit)

  return not isCorridorClear(c1, r1, c2, r2, unit, isVehicle, startBldId, goalBldId, wireCutter)
end

-- ----------------------------------------------------------------------------
-- Octile Heuristic for 8-Directional Grid
-- ----------------------------------------------------------------------------
local function octileHeuristic(cx, cy, gx, gy)
  local dx = math.abs(cx - gx)
  local dy = math.abs(cy - gy)
  if dx > dy then
    return (dx - dy) + SQRT2 * dy
  else
    return (dy - dx) + SQRT2 * dx
  end
end

-- ----------------------------------------------------------------------------
-- Find nearest walkable cell if start or goal falls inside a blocked cell
-- ----------------------------------------------------------------------------
local function findNearestWalkableCell(c, r, unit, isVehicle, startBldId, goalBldId, wireCutter)
  local cols = navGrid.cols
  local rows = navGrid.rows
  local idx = (r - 1) * cols + c
  local c0 = getEffectiveCellCost(idx, unit, isVehicle, startBldId, goalBldId, wireCutter)
  if c0 > 0 and c0 < 5.0 then
    return c, r
  end

  for rad = 1, 10 do
    local bestC, bestR, bestDist = nil, nil, math.huge
    for dr = -rad, rad do
      for dc = -rad, rad do
        if math.abs(dc) == rad or math.abs(dr) == rad then
          local nc, nr = c + dc, r + dr
          if nc >= 1 and nc <= cols and nr >= 1 and nr <= rows then
            local nIdx = (nr - 1) * cols + nc
            local nCost = getEffectiveCellCost(nIdx, unit, isVehicle, startBldId, goalBldId, wireCutter)
            if nCost > 0 and nCost < 5.0 then
              local d2 = dc * dc + dr * dr
              if d2 < bestDist then
                bestDist = d2
                bestC, bestR = nc, nr
              end
            end
          end
        end
      end
    end
    if bestC then
      return bestC, bestR
    end
  end
  return c, r
end

-- ----------------------------------------------------------------------------
-- Compute an 8-Way A* Path + Corridor / Box2D LOS String-Pulled Waypoints
-- Returns: waypointsTable ({ {x=..., y=...}, ... }), foundGoalBoolean
-- ----------------------------------------------------------------------------
function pathfinding.computePath(startX, startY, goalX, goalY, unit)
  pathfinding.ensureSynced(false)
  pathfinding.stats.pathsComputed = pathfinding.stats.pathsComputed + 1

  -- Nudge goal if placed on a hazard/obstacle
  goalX, goalY = pathfinding.findSafeDestination(goalX, goalY, unit)

  local cols = navGrid.cols
  local rows = navGrid.rows
  local sc, sr = pathfinding.worldToGrid(startX, startY)
  local gc, gr = pathfinding.worldToGrid(goalX, goalY)

  local rawStartIdx = cellIndex(sc, sr)
  local rawGoalIdx = cellIndex(gc, gr)
  local startBldId = navGrid.buildingIds[rawStartIdx] or 0
  local goalBldId = navGrid.buildingIds[rawGoalIdx] or 0
  local isVehicle = unit and (unit.turret ~= nil or unit.pivotSpeed ~= nil) or false
  local wireCutter = canCutWire(unit)

  -- Check if goal destination is inside the trees
  local goalInTree = false
  if navGrid.treeIds[rawGoalIdx] and navGrid.treeIds[rawGoalIdx] > 0 then
    goalInTree = true
  elseif player and player.forest then
    for fi = 1, #player.forest do
      local f = player.forest[fi]
      if f and f.x and f.y then
        local dx = goalX - f.x
        local dy = goalY - f.y
        local rad = (f.radius or 50) * 0.85
        if (dx * dx + dy * dy) <= (rad * rad) then
          goalInTree = true
          break
        end
      end
    end
  end

  -- Fast path: if straight corridor is clear, return direct single waypoint
  if isCorridorClear(sc, sr, gc, gr, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree) then
    pathfinding.stats.directPaths = pathfinding.stats.directPaths + 1
    return { { x = goalX, y = goalY } }, true
  end

  local origGc, origGr = gc, gr
  sc, sr = findNearestWalkableCell(sc, sr, unit, isVehicle, startBldId, goalBldId, wireCutter)
  gc, gr = findNearestWalkableCell(gc, gr, unit, isVehicle, startBldId, goalBldId, wireCutter)
  local goalAdjusted = (gc ~= origGc or gr ~= origGr)

  if sc == gc and sr == gr then
    local wx, wy = goalX, goalY
    if goalAdjusted then
      wx, wy = pathfinding.gridToWorld(gc, gr)
    end
    return { { x = wx, y = wy } }, true
  end

  local startIdx = (sr - 1) * cols + sc
  local goalIdx = (gr - 1) * cols + gc

  -- Binary min-heap open set
  local heapNodes = { startIdx }
  local heapF = { octileHeuristic(sc, sr, gc, gr) }
  local heapSize = 1

  local gScore = { [startIdx] = 0 }
  local cameFrom = {}
  local closed = {}

  local function pushHeap(nodeIdx, fVal)
    heapSize = heapSize + 1
    local i = heapSize
    heapNodes[i] = nodeIdx
    heapF[i] = fVal
    while i > 1 do
      local parent = math.floor(i / 2)
      if heapF[i] < heapF[parent] then
        heapNodes[i], heapNodes[parent] = heapNodes[parent], heapNodes[i]
        heapF[i], heapF[parent] = heapF[parent], heapF[i]
        i = parent
      else
        break
      end
    end
  end

  local function popHeap()
    if heapSize == 0 then return nil end
    local topNode = heapNodes[1]
    heapNodes[1] = heapNodes[heapSize]
    heapF[1] = heapF[heapSize]
    heapNodes[heapSize] = nil
    heapF[heapSize] = nil
    heapSize = heapSize - 1
    local i = 1
    while true do
      local left = i * 2
      local right = left + 1
      local smallest = i
      if left <= heapSize and heapF[left] < heapF[smallest] then
        smallest = left
      end
      if right <= heapSize and heapF[right] < heapF[smallest] then
        smallest = right
      end
      if smallest ~= i then
        heapNodes[i], heapNodes[smallest] = heapNodes[smallest], heapNodes[i]
        heapF[i], heapF[smallest] = heapF[smallest], heapF[i]
        i = smallest
      else
        break
      end
    end
    return topNode
  end

  local maxExpansions = 3500
  local expansions = 0
  local bestFallbackIdx = startIdx
  local bestFallbackH = heapF[1]

  while heapSize > 0 and expansions < maxExpansions do
    local currIdx = popHeap()
    if currIdx == goalIdx then
      bestFallbackIdx = goalIdx
      break
    end

    if not closed[currIdx] then
      closed[currIdx] = true
      expansions = expansions + 1

      local cr = math.floor((currIdx - 1) / cols) + 1
      local cc = currIdx - (cr - 1) * cols
      local currG = gScore[currIdx]

      local hNow = octileHeuristic(cc, cr, gc, gr)
      if hNow < bestFallbackH then
        bestFallbackH = hNow
        bestFallbackIdx = currIdx
      end

      for d = 1, 8 do
        local dir = DIRS[d]
        local nc = cc + dir[1]
        local nr = cr + dir[2]
        if nc >= 1 and nc <= cols and nr >= 1 and nr <= rows then
          local nIdx = (nr - 1) * cols + nc
          if not closed[nIdx] then
            local cellCost = getEffectiveCellCost(nIdx, unit, isVehicle, startBldId, goalBldId, wireCutter)
            if cellCost > 0 then
              -- Prevent diagonal corner-cutting across blocked cells
              local cornerBlocked = false
              if dir[1] ~= 0 and dir[2] ~= 0 then
                local c1Cost = getEffectiveCellCost((cr - 1) * cols + nc, unit, isVehicle, startBldId, goalBldId, wireCutter)
                local c2Cost = getEffectiveCellCost((nr - 1) * cols + cc, unit, isVehicle, startBldId, goalBldId, wireCutter)
                if c1Cost < 0 or c2Cost < 0 then
                  cornerBlocked = true
                end
              end
              if not cornerBlocked then
                local tentativeG = currG + dir[3] * cellCost
                local prevG = gScore[nIdx]
                if not prevG or tentativeG < prevG then
                  gScore[nIdx] = tentativeG
                  cameFrom[nIdx] = currIdx
                  local f = tentativeG + octileHeuristic(nc, nr, gc, gr) * 0.98
                  pushHeap(nIdx, f)
                end
              end
            end
          end
        end
      end
    end
  end

  local targetIdx = cameFrom[goalIdx] and goalIdx or bestFallbackIdx
  if targetIdx == startIdx then
    return { { x = goalX, y = goalY } }, false
  end

  -- Reconstruct grid cell sequence
  local rawCells = {}
  local trace = targetIdx
  while trace and trace ~= startIdx do
    local tr = math.floor((trace - 1) / cols) + 1
    local tc = trace - (tr - 1) * cols
    rawCells[#rawCells + 1] = { c = tc, r = tr }
    trace = cameFrom[trace]
  end
  rawCells[#rawCells + 1] = { c = sc, r = sr }

  local ordered = {}
  for i = #rawCells, 1, -1 do
    ordered[#ordered + 1] = rawCells[i]
  end

  -- String-pulling: collapse intermediate collinear/clear waypoints
  local simplified = { ordered[1] }
  local anchor = 1
  local n = #ordered
  while anchor < n do
    local furthest = anchor + 1
    for probe = n, anchor + 2, -1 do
      if isCorridorClear(
        ordered[anchor].c, ordered[anchor].r,
        ordered[probe].c, ordered[probe].r,
        unit, isVehicle, startBldId, goalBldId, wireCutter
      ) then
        furthest = probe
        break
      end
    end
    simplified[#simplified + 1] = ordered[furthest]
    anchor = furthest
  end

  local waypoints = {}
  for i = 2, #simplified do
    if i == #simplified and targetIdx == goalIdx and not goalAdjusted then
      waypoints[#waypoints + 1] = { x = goalX, y = goalY }
    else
      local wx, wy = pathfinding.gridToWorld(simplified[i].c, simplified[i].r)
      waypoints[#waypoints + 1] = { x = wx, y = wy }
    end
  end

  if #waypoints == 0 then
    local wx, wy = goalX, goalY
    if goalAdjusted then
      wx, wy = pathfinding.gridToWorld(gc, gr)
    end
    waypoints[1] = { x = wx, y = wy }
  end

  return waypoints, (targetIdx == goalIdx)
end

-- ----------------------------------------------------------------------------
-- Background Thread Pool Initialization & Dispatch (love.thread)
-- ----------------------------------------------------------------------------
pathfinding._THREAD_CODE = [=[
-- ============================================================================
-- includes/pathfinder_thread.lua
-- Background love.thread A* Pathfinding Worker for Mud and Blood
-- ============================================================================
-- Listens on channel "pf_requests" for batch/async pathfinding jobs:
--   {
--     cmd = "path",
--     reqId = <number>,
--     unitId = <number>,
--     cols = <number>,
--     rows = <number>,
--     cellSize = <number>,
--     originX = <number>,
--     originY = <number>,
--     startX = <number>,
--     startY = <number>,
--     goalX = <number>,
--     goalY = <number>,
--     costs = <flat array of numbers length cols*rows, <0 means blocked>
--   }
-- Pushes results to channel "pf_results":
--   {
--     reqId = <number>,
--     unitId = <number>,
--     found = <boolean>,
--     waypoints = { {x=..., y=...}, ... }
--   }
-- ============================================================================

local reqChannel = love.thread.getChannel("pf_requests")
local resChannel = love.thread.getChannel("pf_results")

local SQRT2 = 1.4142135623730951
local DIRS = {
  {  1,  0, 1.0   },
  { -1,  0, 1.0   },
  {  0,  1, 1.0   },
  {  0, -1, 1.0   },
  {  1,  1, SQRT2 },
  { -1,  1, SQRT2 },
  {  1, -1, SQRT2 },
  { -1, -1, SQRT2 }
}

local function octileHeuristic(cx, cy, gx, gy)
  local dx = math.abs(cx - gx)
  local dy = math.abs(cy - gy)
  if dx > dy then
    return (dx - dy) + SQRT2 * dy
  else
    return (dy - dx) + SQRT2 * dx
  end
end

local function isCorridorClear(costs, cols, rows, c1, r1, c2, r2)
  local dc = c2 - c1
  local dr = r2 - r1
  local steps = math.max(math.abs(dc), math.abs(dr)) * 2
  if steps <= 1 then return true end
  for s = 1, steps - 1 do
    local t = s / steps
    local cc = math.floor(c1 + dc * t + 0.5)
    local rr = math.floor(r1 + dr * t + 0.5)
    if cc < 1 or cc > cols or rr < 1 or rr > rows then
      return false
    end
    local cost = costs[(rr - 1) * cols + cc] or 1.0
    if cost < 0 or cost >= 4.0 then
      return false
    end
  end
  return true
end

local function solveAStar(job)
  local cols = job.cols
  local rows = job.rows
  local cellSize = job.cellSize or 32
  local originX = job.originX or 0
  local originY = job.originY or 0
  local costs = job.costs

  local function worldToGrid(wx, wy)
    local c = math.floor((wx - originX) / cellSize) + 1
    local r = math.floor((wy - originY) / cellSize) + 1
    if c < 1 then c = 1 elseif c > cols then c = cols end
    if r < 1 then r = 1 elseif r > rows then r = rows end
    return c, r
  end

  local function gridToWorld(c, r)
    return originX + (c - 0.5) * cellSize, originY + (r - 0.5) * cellSize
  end

  local sc, sr = worldToGrid(job.startX, job.startY)
  local gc, gr = worldToGrid(job.goalX, job.goalY)

  -- If goal cell is blocked, spiral search for closest walkable cell
  local function findNearestWalkable(c, r)
    local idx = (r - 1) * cols + c
    if (costs[idx] or 1.0) > 0 then return c, r end
    for rad = 1, 8 do
      local bestC, bestR, bestDist = nil, nil, math.huge
      for dr = -rad, rad do
        for dc = -rad, rad do
          if math.abs(dc) == rad or math.abs(dr) == rad then
            local nc, nr = c + dc, r + dr
            if nc >= 1 and nc <= cols and nr >= 1 and nr <= rows then
              local ncost = costs[(nr - 1) * cols + nc] or 1.0
              if ncost > 0 and ncost < 15.0 then
                local d2 = dc * dc + dr * dr
                if d2 < bestDist then
                  bestDist = d2
                  bestC, bestR = nc, nr
                end
              end
            end
          end
        end
      end
      if bestC then return bestC, bestR end
    end
    return c, r
  end

  sc, sr = findNearestWalkable(sc, sr)
  gc, gr = findNearestWalkable(gc, gr)

  if sc == gc and sr == gr then
    return true, { { x = job.goalX, y = job.goalY } }
  end

  local startIdx = (sr - 1) * cols + sc
  local goalIdx = (gr - 1) * cols + gc

  -- Binary min-heap open set
  local heapNodes = { startIdx }
  local heapF = { octileHeuristic(sc, sr, gc, gr) }
  local heapSize = 1

  local gScore = { [startIdx] = 0 }
  local cameFrom = {}
  local closed = {}

  local function pushHeap(nodeIdx, fVal)
    heapSize = heapSize + 1
    local i = heapSize
    heapNodes[i] = nodeIdx
    heapF[i] = fVal
    while i > 1 do
      local parent = math.floor(i / 2)
      if heapF[i] < heapF[parent] then
        heapNodes[i], heapNodes[parent] = heapNodes[parent], heapNodes[i]
        heapF[i], heapF[parent] = heapF[parent], heapF[i]
        i = parent
      else
        break
      end
    end
  end

  local function popHeap()
    if heapSize == 0 then return nil end
    local topNode = heapNodes[1]
    heapNodes[1] = heapNodes[heapSize]
    heapF[1] = heapF[heapSize]
    heapNodes[heapSize] = nil
    heapF[heapSize] = nil
    heapSize = heapSize - 1
    local i = 1
    while true do
      local left = i * 2
      local right = left + 1
      local smallest = i
      if left <= heapSize and heapF[left] < heapF[smallest] then
        smallest = left
      end
      if right <= heapSize and heapF[right] < heapF[smallest] then
        smallest = right
      end
      if smallest ~= i then
        heapNodes[i], heapNodes[smallest] = heapNodes[smallest], heapNodes[i]
        heapF[i], heapF[smallest] = heapF[smallest], heapF[i]
        i = smallest
      else
        break
      end
    end
    return topNode
  end

  local maxExpansions = job.maxExpansions or 4000
  local expansions = 0
  local bestFallbackIdx = startIdx
  local bestFallbackH = heapF[1]

  while heapSize > 0 and expansions < maxExpansions do
    local currIdx = popHeap()
    if currIdx == goalIdx then
      bestFallbackIdx = goalIdx
      break
    end

    if not closed[currIdx] then
      closed[currIdx] = true
      expansions = expansions + 1

      local cr = math.floor((currIdx - 1) / cols) + 1
      local cc = currIdx - (cr - 1) * cols
      local currG = gScore[currIdx]

      local hNow = octileHeuristic(cc, cr, gc, gr)
      if hNow < bestFallbackH then
        bestFallbackH = hNow
        bestFallbackIdx = currIdx
      end

      for d = 1, 8 do
        local dir = DIRS[d]
        local nc = cc + dir[1]
        local nr = cr + dir[2]
        if nc >= 1 and nc <= cols and nr >= 1 and nr <= rows then
          local nIdx = (nr - 1) * cols + nc
          if not closed[nIdx] then
            local cellCost = costs[nIdx] or 1.0
            if cellCost > 0 then
              -- Prevent diagonal corner-cutting across blocked cells
              local cornerBlocked = false
              if dir[1] ~= 0 and dir[2] ~= 0 then
                local c1Cost = costs[(cr - 1) * cols + nc] or 1.0
                local c2Cost = costs[(nr - 1) * cols + cc] or 1.0
                if c1Cost < 0 or c2Cost < 0 then
                  cornerBlocked = true
                end
              end
              if not cornerBlocked then
                local tentativeG = currG + dir[3] * cellCost
                local prevG = gScore[nIdx]
                if not prevG or tentativeG < prevG then
                  gScore[nIdx] = tentativeG
                  cameFrom[nIdx] = currIdx
                  local f = tentativeG + octileHeuristic(nc, nr, gc, gr) * 0.98
                  pushHeap(nIdx, f)
                end
              end
            end
          end
        end
      end
    end
  end

  local targetIdx = cameFrom[goalIdx] and goalIdx or bestFallbackIdx
  if targetIdx == startIdx then
    return false, { { x = job.goalX, y = job.goalY } }
  end

  -- Reconstruct grid path
  local rawCells = {}
  local trace = targetIdx
  while trace and trace ~= startIdx do
    local tr = math.floor((trace - 1) / cols) + 1
    local tc = trace - (tr - 1) * cols
    rawCells[#rawCells + 1] = { c = tc, r = tr }
    trace = cameFrom[trace]
  end
  rawCells[#rawCells + 1] = { c = sc, r = sr }

  -- Reverse into start -> goal order
  local ordered = {}
  for i = #rawCells, 1, -1 do
    ordered[#ordered + 1] = rawCells[i]
  end

  -- String-pulling simplification
  local simplified = { ordered[1] }
  local anchor = 1
  local n = #ordered
  while anchor < n do
    local furthest = anchor + 1
    for probe = n, anchor + 2, -1 do
      if isCorridorClear(costs, cols, rows, ordered[anchor].c, ordered[anchor].r, ordered[probe].c, ordered[probe].r) then
        furthest = probe
        break
      end
    end
    simplified[#simplified + 1] = ordered[furthest]
    anchor = furthest
  end

  local waypoints = {}
  for i = 2, #simplified do
    if i == #simplified and targetIdx == goalIdx then
      waypoints[#waypoints + 1] = { x = job.goalX, y = job.goalY }
    else
      local wx, wy = gridToWorld(simplified[i].c, simplified[i].r)
      waypoints[#waypoints + 1] = { x = wx, y = wy }
    end
  end

  if #waypoints == 0 then
    waypoints[1] = { x = job.goalX, y = job.goalY }
  end

  return (targetIdx == goalIdx), waypoints
end

while true do
  local job = reqChannel:demand()
  if not job or job.cmd == "quit" then
    break
  elseif job.cmd == "path" then
    local ok, found, waypoints = pcall(solveAStar, job)
    if ok then
      resChannel:push({
        reqId = job.reqId,
        unitId = job.unitId,
        goalX = job.goalX,
        goalY = job.goalY,
        found = found,
        waypoints = waypoints
      })
    else
      resChannel:push({
        reqId = job.reqId,
        unitId = job.unitId,
        goalX = job.goalX,
        goalY = job.goalY,
        found = false,
        error = tostring(found),
        waypoints = { { x = job.goalX, y = job.goalY } }
      })
    end
  end
end

]=]

function pathfinding.initThreadWorker()
  if workerThread then return true end
  if not (love and love.thread and love.thread.newThread) then
    return false
  end

  -- Launch thread worker directly from embedded _THREAD_CODE
  local ok, th = pcall(love.thread.newThread, pathfinding._THREAD_CODE)
  if not ok or not th then
    return false
  end

  reqChannel = love.thread.getChannel("pf_requests")
  resChannel = love.thread.getChannel("pf_results")
  th:start()
  workerThread = th
  return true
end

function pathfinding.requestPathAsync(unit, startX, startY, goalX, goalY)
  if not pathfinding.initThreadWorker() then
    local wps, found = pathfinding.computePath(startX, startY, goalX, goalY, unit)
    if unit then
      unit.pathQueue = wps
      unit._pfGoalX = goalX
      unit._pfGoalY = goalY
    end
    return nil
  end

  pathfinding.ensureSynced(false)
  local cols = navGrid.cols
  local rows = navGrid.rows
  local sc, sr = pathfinding.worldToGrid(startX, startY)
  local gc, gr = pathfinding.worldToGrid(goalX, goalY)
  local startBldId = navGrid.buildingIds[cellIndex(sc, sr)] or 0
  local goalBldId = navGrid.buildingIds[cellIndex(gc, gr)] or 0
  local isVehicle = unit and (unit.turret ~= nil or unit.pivotSpeed ~= nil) or false
  local wireCutter = canCutWire(unit)

  -- Snapshot effective costs for this unit
  local goalInTree = false
  if navGrid.treeIds[cellIndex(gc, gr)] and navGrid.treeIds[cellIndex(gc, gr)] > 0 then
    goalInTree = true
  end
  local snapshot = {}
  local total = cols * rows
  for i = 1, total do
    snapshot[i] = getEffectiveCellCost(i, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
  end

  local reqId = nextAsyncReqId
  nextAsyncReqId = nextAsyncReqId + 1
  pendingUnitsByReqId[reqId] = unit
  pathfinding.stats.asyncJobsSent = pathfinding.stats.asyncJobsSent + 1

  reqChannel:push({
    cmd = "path",
    reqId = reqId,
    unitId = unit and unit.id or 0,
    cols = cols,
    rows = rows,
    cellSize = navGrid.cellSize,
    originX = navGrid.originX,
    originY = navGrid.originY,
    startX = startX,
    startY = startY,
    goalX = goalX,
    goalY = goalY,
    costs = snapshot
  })

  return reqId
end

function pathfinding.pollAsyncResults()
  if not resChannel then return 0 end
  local count = 0
  while true do
    local msg = resChannel:pop()
    if not msg then break end
    count = count + 1
    pathfinding.stats.asyncJobsCompleted = pathfinding.stats.asyncJobsCompleted + 1
    local unit = pendingUnitsByReqId[msg.reqId]
    pendingUnitsByReqId[msg.reqId] = nil
    if unit and msg.waypoints then
      unit.pathQueue = msg.waypoints
      unit._pfGoalX = msg.goalX
      unit._pfGoalY = msg.goalY
    end
  end
  return count
end

-- ----------------------------------------------------------------------------
-- Per-Unit Steering & Waypoint Follower (Infantry & Vehicles)
-- ----------------------------------------------------------------------------
function pathfinding.getSteeringTarget(unit, dt)
  if not unit or not unit.targetx or not unit.targety then
    return unit and unit.x or 0, unit and unit.y or 0, false
  end

  -- Automatically shift destination point if placed on a hazard or unwalkable tile
  local safeX, safeY = pathfinding.findSafeDestination(unit.targetx, unit.targety, unit)
  if safeX ~= unit.targetx or safeY ~= unit.targety then
    unit.targetx = safeX
    unit.targety = safeY
  end

  if player and player.option_pathfindingEnabled == 0 then
    unit.pathQueue = nil
    return unit.targetx, unit.targety, false
  end

  local tx, ty = unit.targetx, unit.targety
  local ux, uy = unit.x, unit.y

  -- Check if destination changed or periodic hazard re-check is due
  local goalChanged = (not unit._pfGoalX) or (not unit._pfGoalY)
    or ((tx - unit._pfGoalX) * (tx - unit._pfGoalX) + (ty - unit._pfGoalY) * (ty - unit._pfGoalY) > 256)

  unit._pfRecheckTimer = (unit._pfRecheckTimer or 0) - (dt or 0.016)

  if goalChanged or (unit._pfRecheckTimer <= 0 and unit.pathQueue and #unit.pathQueue > 0) then
    unit._pfGoalX = tx
    unit._pfGoalY = ty
    unit._pfRecheckTimer = 1.2 + ((unit.id or 0) % 7) * 0.1
    local wps = pathfinding.computePath(ux, uy, tx, ty, unit)
    unit.pathQueue = wps
    unit._pfSnapTurn = true
  end

  local q = unit.pathQueue
  if not q or #q == 0 then
    return tx, ty, false
  end

  local wp = q[1]
  local reachRadius = (unit.turret ~= nil or unit.pivotSpeed ~= nil) and 38 or 16
  local snapTurn = false
  if unit._pfSnapTurn then
    snapTurn = true
    unit._pfSnapTurn = false
  end

  while wp and #q > 1 do
    local dx = wp.x - ux
    local dy = wp.y - uy
    if (dx * dx + dy * dy) <= (reachRadius * reachRadius) then
      table.remove(q, 1)
      wp = q[1]
      snapTurn = true
    else
      break
    end
  end

  if not wp then
    return tx, ty, snapTurn
  end

  return wp.x, wp.y, snapTurn
end

-- ----------------------------------------------------------------------------
-- Prevent units from clipping inside strictly impassable barriers
-- ----------------------------------------------------------------------------
function pathfinding.resolveObstacleCollision(unit, prevX, prevY)
  if not unit or (player and player.option_pathfindingEnabled == 0) then
    return
  end
  local c, r = pathfinding.worldToGrid(unit.x, unit.y)
  local idx = cellIndex(c, r)
  if (navGrid.baseCosts[idx] or 1.0) < 0 then
    -- If previous position was valid, slide along X or Y axis
    local pc, pr = pathfinding.worldToGrid(prevX, prevY)
    if (navGrid.baseCosts[cellIndex(pc, pr)] or 1.0) > 0 then
      local cxOnly, rPrev = pathfinding.worldToGrid(unit.x, prevY)
      local cPrev, ryOnly = pathfinding.worldToGrid(prevX, unit.y)
      if (navGrid.baseCosts[cellIndex(cxOnly, rPrev)] or 1.0) > 0 then
        unit.y = prevY
      elseif (navGrid.baseCosts[cellIndex(cPrev, ryOnly)] or 1.0) > 0 then
        unit.x = prevX
      else
        unit.x = prevX
        unit.y = prevY
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- Per-frame update hook
-- ----------------------------------------------------------------------------
function pathfinding.update(dt)
  pathfinding.pollAsyncResults()
  if player and player.deployedTroops then
    pathfinding.ensureSynced(false)
  end
end

-- ----------------------------------------------------------------------------
-- Debug Visualization Overlay (Shift+F9)
-- ----------------------------------------------------------------------------
function pathfinding.drawDebug()
  if not pathfinding.debugOverlay or not player then return end
  pathfinding.ensureSynced(false)

  local cs = navGrid.cellSize
  local sx = player.screenx or 0
  local sy = player.screeny or 0
  local cStart = math.max(1, math.floor((sx - navGrid.originX) / cs))
  local cEnd = math.min(navGrid.cols, math.ceil((sx + 1280 - navGrid.originX) / cs) + 1)

  for r = 1, navGrid.rows do
    local wy = navGrid.originY + (r - 1) * cs
    local rowOffset = (r - 1) * navGrid.cols
    for c = cStart, cEnd do
      local wx = navGrid.originX + (c - 1) * cs
      local idx = rowOffset + c
      local cost = navGrid.baseCosts[idx] or 1.0
      local bId = navGrid.buildingIds[idx] or 0
      if cost < 0 then
        love.graphics.setColor(0.95, 0.15, 0.15, 0.35)
        love.graphics.rectangle("fill", wx, wy, cs - 1, cs - 1)
      elseif cost >= 15.0 then
        love.graphics.setColor(1.0, 0.45, 0.0, 0.35)
        love.graphics.rectangle("fill", wx, wy, cs - 1, cs - 1)
      elseif cost >= 5.0 then
        love.graphics.setColor(0.95, 0.85, 0.1, 0.28)
        love.graphics.rectangle("fill", wx, wy, cs - 1, cs - 1)
      elseif bId > 0 then
        love.graphics.setColor(0.65, 0.35, 0.95, 0.22)
        love.graphics.rectangle("fill", wx, wy, cs - 1, cs - 1)
      elseif cost < 0.9 then
        love.graphics.setColor(0.15, 0.85, 0.35, 0.18)
        love.graphics.rectangle("fill", wx, wy, cs - 1, cs - 1)
      end
    end
  end

  -- Draw active unit waypoint chains
  if player.deployedTroops then
    love.graphics.setLineWidth(2)
    for i = 1, #player.deployedTroops do
      local d = player.deployedTroops[i]
      if d and d.health > 10 and d.pathQueue and #d.pathQueue > 0 then
        if d.faction == "allied" then
          love.graphics.setColor(0.2, 0.9, 1.0, 0.85)
        else
          love.graphics.setColor(1.0, 0.35, 0.35, 0.75)
        end
        local px, py = d.x, d.y
        for w = 1, #d.pathQueue do
          local wp = d.pathQueue[w]
          love.graphics.line(px, py, wp.x, wp.y)
          love.graphics.circle("fill", wp.x, wp.y, 3)
          px, py = wp.x, wp.y
        end
      end
    end
    love.graphics.setLineWidth(1)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return pathfinding
