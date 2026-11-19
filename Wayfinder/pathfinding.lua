-- ============================================================================
-- includes/pathfinding.lua
-- Section 1.1: Tactical Nav-Grid, 8-Way A* + LOS String-Pulling & Thread Pool
-- ============================================================================
-- Provides obstacle- and hazard-aware navigation for both AI and player-
-- controlled infantry and vehicles in Mud and Blood (v0.5.3b, LOVE 11.4).
-- ============================================================================

local pathfinding = {}

pathfinding.CELL_SIZE = 16          -- px per grid cell
pathfinding.BODY_RADIUS = 8         -- a soldier's half-width: the margin kept around solid things
pathfinding.MARGIN_COST = 12        -- cost of a cell in that margin: avoided, but a way out of a tight spot
pathfinding.CORRIDOR_MAX_COST = 4.0 -- a straight line between waypoints avoids cells costing this or more
pathfinding.MAX_EXPANSIONS = 16000  -- A* cells looked at per path before the best partial path is used
pathfinding.NEAREST_SEARCH = 24     -- cells searched outward for a free cell when start or goal is blocked
pathfinding.UNSTICK_REPLAN = 0.4    -- s held back by an obstacle before the path is solved again
pathfinding.UNSTICK_PASS = 2.0      -- s held back before the unit is let through, as the game would
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

-- Placeables a soldier cannot walk through, by the game's own names, with the box around
-- each sprite's solid pixels: { x1, y1, x2, y2 } from the sprite's centre at the game's scale 1
-- (size 10). The game draws a placeable centred on x, y, scaled by size / 10 and turned by
-- its rotation, and the grid does the same. Measured from the game's sprites by
-- tools/sprite_footprints.py. Infantry can walk over anything in the game itself; these are
-- what Wayfinder routes around.
local SOLID_PLACEABLES = {
  dragonTooth = { -29.5, -26.5, 29.5, 25.5 },
  obstacle = { -68, -70.5, 69, 71.5 },
  hogBale1 = { -21.5, -19, 21.5, 19 },
  hogBale2 = { -28.5, -33.5, 28.5, 33.5 },
  hogBale3 = { -13, -50.5, 13, 50.5 },
  barricade = { -67, -28, 60, 31 },
  cartBarricade = { -60.5, -174.5, 60.5, 174.5 },
  barrelWall1 = { -30.5, -72, 30.5, 73 },
  barrelWall2 = { -38.5, -60.5, 40.5, 59.5 },
  brestWall = { -20.5, -100, 20.5, 100 },
  achWall = { -7, -50, 7, 50 },
  fence1 = { -6.5, -49, 7.5, 48 },
  fence2 = { -9, -50.5, 9, 50.5 },
  fence3 = { -13, -50, 13, 49 },
  palisade = { -16.5, -28.5, 16.5, 28.5 },
  car = { -63.5, -36, 63.5, 36 },
  tanker = { -52, -69, 52, 69 },
  civilianTruck1 = { -120.5, -317, 120.5, 317 },
  tractor = { -75.5, -61.5, 75.5, 61.5 },
  cart = { -45.5, -26.5, 44.5, 25.5 },
  bigCart = { -63, -29.5, 63, 29.5 },
  cisternWagon = { -58, -174.5, 57, 173.5 },
  trainArmored = { -51, -188.5, 49, 188.5 },
  cannon = { -107, -191, 107, 191 },
  radarBase = { -64, -31, 67, 68 },
  radarBase2 = { -64, -31, 67, 68 },
  brickStack = { -53, -92, 53, 92 },
  woodPile1 = { -81, -24.5, 81, 24.5 },
  plankPile = { -87, -26, 87, 26 },
  hayStack = { -42, -16.5, 40, 16.5 },
  hayBale = { -16.5, -14, 14.5, 14 },
  crate1 = { -16.5, -17.5, 16.5, 16.5 },
  crate2 = { -14, -12.5, 13, 12.5 },
  crate3 = { -24, -10, 24, 10 },
  crate4 = { -25.5, -13.5, 24.5, 12.5 },
  crate5 = { -15.5, -24, 15.5, 24 },
  crate6 = { -17.5, -16.5, 17.5, 16.5 },
  barrel1 = { -10, -13.5, 10, 13.5 },
  barrel2 = { -10, -11.5, 10, 11.5 },
  wheelBarrow = { -29.5, -11, 28.5, 10 },
  tomb1 = { -8, -19.5, 8, 19.5 },
  tomb2 = { -10.5, -26.5, 10.5, 26.5 },
  tomb3 = { -26, -26, 26, 26 },
  tomb4 = { -61.5, -27, 61.5, 27 },
  tomb7 = { -51, -23.5, 51, 23.5 },
  tomb8 = { -48, -17, 48, 17 },
}
pathfinding.SOLID_PLACEABLES = SOLID_PLACEABLES

-- Kinds of solid object, each with its own collision switch (config.toml, under Fine Tuned
-- Collisions). A kind that does not stop soldiers is still something paths prefer to go
-- round (VAULT_COST), and vehicles still go round it. Low walls and fences are off by
-- default: the game lays them in lines across the map, as cover to climb over.
pathfinding.COLLISION_KINDS = {
  { alias = "collideDragonTeethEnabled", default = true, names = { "dragonTooth" } },
  { alias = "collideHedgehogsEnabled", default = true, names = { "obstacle", "hogBale1", "hogBale2", "hogBale3" } },
  { alias = "collideBarricadesEnabled", default = true, names = { "barricade", "cartBarricade" } },
  { alias = "collideLowWallsEnabled", default = false, names = { "brestWall", "achWall", "barrelWall1", "barrelWall2" } },
  { alias = "collideFencesEnabled", default = false, names = { "fence1", "fence2", "fence3" } },
  { alias = "collidePalisadesEnabled", default = true, names = { "palisade" } },
  { alias = "collideVehiclesEnabled", default = true, names = { "car", "tanker", "civilianTruck1", "tractor", "cart", "bigCart", "cisternWagon", "trainArmored" } },
  { alias = "collideCannonsEnabled", default = true, names = { "cannon" } },
  { alias = "collideRadarEnabled", default = true, names = { "radarBase", "radarBase2" } },
  { alias = "collideStacksEnabled", default = true, names = { "brickStack", "woodPile1", "plankPile" } },
  { alias = "collideHayEnabled", default = true, names = { "hayStack", "hayBale" } },
  { alias = "collideCratesEnabled", default = true, names = { "crate1", "crate2", "crate3", "crate4", "crate5", "crate6", "barrel1", "barrel2", "wheelBarrow" } },
  { alias = "collideTombsEnabled", default = true, names = { "tomb1", "tomb2", "tomb3", "tomb4", "tomb7", "tomb8" } },
}
local KIND_OF = {}
for _, kind in ipairs(pathfinding.COLLISION_KINDS) do
  for _, name in ipairs(kind.names) do KIND_OF[name] = kind end
end
pathfinding.VAULT_COST = 6.0          -- an object soldiers may cross: crossed when going round costs more
pathfinding.BUILDING_COST = 4.0       -- a building cell on a path through it: at CORRIDOR_MAX_COST, so no
                                      -- shortcut cuts through, and the way round wins unless far longer

-- Cached nav-grid state
local navGrid = {
  originX = -256,
  originY = 0,
  cols = 60,
  rows = 23,
  cellSize = 16,
  baseCosts = {},       -- flat array [1 .. cols*rows], <0 = impassable, MARGIN_COST = next to it
  solid = {},           -- flat array [1 .. cols*rows], true = the object itself; what collision checks
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
-- The grid version the worker thread holds. A path request carries only the unit's own
-- details; the grid is sent again only after it was rebuilt.
local sentGridVersion = -1
local pendingUnitsByReqId = {}
-- unit -> request id it is waiting for. Kept beside the unit, not on it, so it is never saved.
local pendingReqByUnit = setmetatable({}, { __mode = "k" })
-- unit -> { x, y } of the last destination checked by findSafeDestination.
local checkedGoal = setmetatable({}, { __mode = "k" })
-- unit -> true when its path ends short of the destination (none goes all the way).
local partialPath = setmetatable({}, { __mode = "k" })
-- unit -> { x, y }: the destination it walks straight to across what is in the way, as the
-- game lets it, after a path that ends short.
local crossing = setmetatable({}, { __mode = "k" })

local function settingOn(alias)
  -- Mod Settings mirror a checkbox to player.option_<alias> as 1 or 0. Unset means on.
  return not (player and player["option_" .. alias] == 0)
end

-- A checkbox with its own default when unset.
local function setting(alias, default)
  local v = player and player["option_" .. alias]
  if v == nil then return default end
  return v == 1 or v == true
end

--- Whether solid objects of this placeable name stop infantry, by the collision options.
function pathfinding.collides(name)
  local kind = KIND_OF[name]
  if not kind or not setting("infantryCollisionEnabled", true) then return false end
  return setting(kind.alias, kind.default)
end

-- ----------------------------------------------------------------------------
-- The player's own soldiers
-- ----------------------------------------------------------------------------
-- unit -> true when the player's last move order to the soldier was a Direct Move (the key
-- held): straight to the spot, no detours. Kept beside the unit, never saved.
local directOrder = setmetatable({}, { __mode = "k" })

-- The keybind held while giving a Direct Move order (config.toml).
pathfinding.DIRECT_MOVE_ACTION = "wayfinder_direct_move"

local function isPlayerSoldier(unit)
  return unit.faction == "allied" and unit.playerControlled == 1
    and unit.turret == nil and unit.pivotSpeed == nil
end

--- Whether the unit walks its order straight, as in the game, with no detour and no
--- shifted destination: a player's soldier when "Pathfinding For Your Soldiers" is off, or
--- one whose last order was a Direct Move. The enemy and allied AI always use pathfinding.
function pathfinding.movesDirect(unit)
  if not unit or not isPlayerSoldier(unit) then return false end
  return directOrder[unit] == true or not settingOn("playerPathfindingEnabled")
end

local function directKeyHeld()
  local input = QM and QM.Input
  return input ~= nil and input.isDown ~= nil and input.isDown(pathfinding.DIRECT_MOVE_ACTION) == true
end

--- Just before the game hands out a move order: the soldiers about to get it, and whether
--- the Direct Move key is held.
function pathfinding.captureOrder()
  local order = { direct = directKeyHeld() }
  local troops = player and player.deployedTroops
  if troops then
    for i = 1, #troops do
      local t = troops[i]
      if t.selected and (t.onFire or 0) <= 0 then order[#order + 1] = t end
    end
  end
  return order
end

--- Just after: every soldier the order went to (the game deselects them) walks it straight
--- or by path, by whether the key was held.
function pathfinding.afterOrder(order)
  if not order or (altMove or 0) ~= 0 then return end
  for i = 1, #order do
    local t = order[i]
    if not t.selected then
      directOrder[t] = order.direct or nil
    end
  end
end

-- How far from a fire a unit is kept: the game burns a soldier within size * 75 px of a
-- fire (fires grow to size 2, 150 px); a margin keeps paths between grid cells clear too.
function pathfinding.fireRadius(f)
  return math.max(34, (f.size or 0.5) * 75 + 16)
end

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
          return g.x, g.y, g.x + g.width, g.y + g.length
        elseif (g.radius or 0) > 0 then
          local rad = g.radius * 0.65
          return g.x - rad, g.y - rad, g.x + rad, g.y + rad
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
      return bx, by, bx + bw, by + bl
    else
      return bx - bw * 0.5, by - bl * 0.5, bx + bw * 0.5, by + bl * 0.5
    end
  end

  local rad = (b.radius or 90) * 0.45
  if rad < 28 then rad = 28 end
  if rad > 140 then rad = 140 end
  return bx - rad, by - rad, bx + rad, by + rad
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
  -- What a building cell costs on a path through it; false when paths may only enter the
  -- building they start or end in.
  navGrid.throughBuildingCost = setting("pathThroughBuildingsEnabled", true) and pathfinding.BUILDING_COST or false
  navGrid.cols = cols
  navGrid.rows = rows
  navGrid.cellSize = cs

  local baseCosts = navGrid.baseCosts
  local solid = navGrid.solid
  local buildingIds = navGrid.buildingIds
  local treeIds = navGrid.treeIds
  local treeTrunkIds = navGrid.treeTrunkIds
  local vehicleBlocked = navGrid.vehicleBlocked
  local alliedMineCost = navGrid.alliedMineCost
  local axisMineCost = navGrid.axisMineCost
  local totalCells = cols * rows

  for i = 1, totalCells do
    baseCosts[i] = 1.0
    solid[i] = false
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

  -- Every cell a turned box touches, widened by pad. The box is in the object's own frame,
  -- as the game draws it: centred on cx, cy, scaled, then turned by rot. A cell counts when
  -- any part of it may be inside, so a thin wall is never missed between two cell centres.
  local function markBox(cx, cy, box, scale, rot, pad, fn)
    local x1, y1 = box[1] * scale - pad, box[2] * scale - pad
    local x2, y2 = box[3] * scale + pad, box[4] * scale + pad
    local cosR, sinR = math.cos(rot or 0), math.sin(rot or 0)
    local reach = math.max(math.abs(x1), math.abs(x2)) + math.max(math.abs(y1), math.abs(y2))
    local half = cs * 0.5
    local slack2 = 2 * half * half -- half a cell's diagonal, squared
    local c1 = math.max(1, math.floor((cx - reach - half - minX) / cs) + 1)
    local c2 = math.min(cols, math.floor((cx + reach + half - minX) / cs) + 1)
    local row1 = math.max(1, math.floor((cy - reach - half - minY) / cs) + 1)
    local row2 = math.min(rows, math.floor((cy + reach + half - minY) / cs) + 1)
    for r = row1, row2 do
      local dy = minY + (r - 0.5) * cs - cy
      local rowOffset = (r - 1) * cols
      for c = c1, c2 do
        local dx = minX + (c - 0.5) * cs - cx
        -- The cell centre in the box's frame, and its distance to the box.
        local u = dx * cosR + dy * sinR
        local v = -dx * sinR + dy * cosR
        local du = (u < x1 and x1 - u) or (u > x2 and u - x2) or 0
        local dv = (v < y1 and y1 - v) or (v > y2 and v - y2) or 0
        if du * du + dv * dv <= slack2 then
          fn(rowOffset + c, c, r)
        end
      end
    end
  end

  -- 1. Forest (player.forest): Trunks (high cost/obstacle) & Canopies (moderate brush avoidance)
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

  -- 2. Ground areas (player.groundType): cover, mud, water, wire, entanglement, floors
  if player.groundType then
    for u = 1, #player.groundType do
      local g = player.groundType[u]
      if g and g.x and g.y then
        local gname = g.name or ""
        local gcov = g.cover or 0
        local gslow = (g.slowy == "yes") or ((g.incline or 0) ~= 0)

        local applyCell = function(idx)
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

  -- 3. Buildings (player.buildings)
  if player.buildings then
    for i = 1, #player.buildings do
      local b = player.buildings[i]
      local x1, y1, x2, y2 = getBuildingFootprint(b, i)
      if x1 then
        markRect(x1 - 6, y1 - 6, x2 + 6, y2 + 6, function(idx)
          vehicleBlocked[idx] = true
          buildingIds[idx] = i
        end)
      end
    end
  end

  -- 4. Rocks (player.rocks): the game lets soldiers stand on them (stepOnRock), so only
  -- vehicles go around, within the game's own rock radius.
  if player.rocks then
    for i = 1, #player.rocks do
      local r = player.rocks[i]
      if r and r.x and r.y then
        markCircle(r.x, r.y, (50 * (r.size or 10)) / 10, function(idx)
          vehicleBlocked[idx] = true
        end)
      end
    end
  end

  -- 5. Placeables (player.placeables): solid objects by their sprites, and wire
  if player.placeables then
    local pad = pathfinding.BODY_RADIUS
    local marginCost = pathfinding.MARGIN_COST
    local function margin(idx)
      vehicleBlocked[idx] = true
      if baseCosts[idx] > 0 and baseCosts[idx] < marginCost then baseCosts[idx] = marginCost end
    end
    local function core(idx)
      solid[idx] = true
      baseCosts[idx] = -1
      vehicleBlocked[idx] = true
    end
    local vaultCost = pathfinding.VAULT_COST
    local function vehicleOnly(idx) vehicleBlocked[idx] = true end
    local function vault(idx)
      vehicleBlocked[idx] = true
      if baseCosts[idx] > 0 and baseCosts[idx] < vaultCost then baseCosts[idx] = vaultCost end
    end
    local collides = {}
    for name in pairs(SOLID_PLACEABLES) do collides[name] = pathfinding.collides(name) end
    for i = 1, #player.placeables do
      local p = player.placeables[i]
      -- The game parks hidden placeables far off the map.
      if p and p.x and p.y and p.x < 9000 then
        local pname = p.name or ""
        local box = SOLID_PLACEABLES[pname]
        if box then
          local scale = (tonumber(p.size) or 10) / 10
          if collides[pname] then
            markBox(p.x, p.y, box, scale, p.rotation or 0, pad, margin)
            markBox(p.x, p.y, box, scale, p.rotation or 0, 0, core)
          else
            markBox(p.x, p.y, box, scale, p.rotation or 0, pad, vehicleOnly)
            markBox(p.x, p.y, box, scale, p.rotation or 0, 0, vault)
          end
        elseif pname == "barbWire" or pname == "entanglement" then
          markCircle(p.x, p.y, p.radius or 36, function(idx)
            if baseCosts[idx] > 0 and baseCosts[idx] < 6.5 then
              baseCosts[idx] = 6.5
            end
          end)
        end
      end
    end
  end

  -- 6. Active fires (player.fire) -> strong hazard avoidance (cost = 18.0)
  if player.fire then
    for i = 1, #player.fire do
      local f = player.fire[i]
      if f and f.x and f.y and (f.burnTime == nil or f.burnTime > 0) then
        markCircle(f.x, f.y, pathfinding.fireRadius(f), function(idx)
          if baseCosts[idx] > 0 and baseCosts[idx] < 18.0 then
            baseCosts[idx] = 18.0
          end
        end)
      end
    end
  end

  -- 7. Minefield hazards (player.mineField)
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
  navGrid.version = (navGrid.version or 0) + 1 -- the worker thread is sent the grid once per version
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
          local rad = pathfinding.fireRadius(f)
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
-- A cheap summary of what the grid is built from that changes during a battle. The grid is
-- rebuilt, and sent to the worker again, only when it differs: at 16 px a grid is large.
local function worldSignature()
  local h = 0
  local function mix(v) h = (h * 31 + v) % 2147483647 end
  mix(player.placeables and #player.placeables or 0)
  mix(player.buildings and #player.buildings or 0)
  mix(player.groundType and #player.groundType or 0)
  mix(player.forest and #player.forest or 0)
  mix(player.rocks and #player.rocks or 0)
  mix(math.floor(player.endLine or 0))
  mix(setting("infantryCollisionEnabled", true) and 1 or 0)
  mix(setting("pathThroughBuildingsEnabled", true) and 1 or 0)
  for _, kind in ipairs(pathfinding.COLLISION_KINDS) do mix(setting(kind.alias, kind.default) and 1 or 0) end
  local fires = player.fire
  if fires then
    for i = 1, #fires do
      local f = fires[i]
      if f.burnTime == nil or f.burnTime > 0 then
        mix(math.floor((f.x or 0) + (f.y or 0) * 7 + (f.size or 0) * 1000))
      end
    end
  end
  local mines = player.mineField
  if mines then
    for i = 1, #mines do
      local m = mines[i]
      if (m.flagged or 0) > 0 then mix(math.floor((m.x or 0) + (m.y or 0) * 7)) end
    end
  end
  local buildings = player.buildings
  if buildings then
    for i = 1, #buildings do
      if (buildings[i].destroyed or 0) >= 1 then mix(i) end
    end
  end
  return h
end

function pathfinding.ensureSynced(force)
  if not player then return end
  local now = player.missionTime or 0
  if force or navGrid.dirty then
    navGrid.signature = worldSignature()
    pathfinding.rebuildGrid()
  elseif math.abs(now - navGrid.lastSyncTime) >= 0.75 then
    local sig = worldSignature()
    if sig ~= navGrid.signature then
      navGrid.signature = sig
      pathfinding.rebuildGrid()
    else
      navGrid.lastSyncTime = now
    end
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
-- The worker thread has its own copy of these rules (unitCellCost in _THREAD_CODE); keep
-- the two alike. tests/wayfinder_test.lua compares them.
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
    elseif navGrid.throughBuildingCost then
      -- Through another building: allowed, at a cost, so a short way round still wins.
      if base < navGrid.throughBuildingCost then base = navGrid.throughBuildingCost end
    else
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
  -- Four looks per cell crossed, so a line does not slip past a blocked cell's corner.
  local steps = math.max(math.abs(dc), math.abs(dr)) * 4
  if steps <= 1 then return true end
  local cols = navGrid.cols
  local rows = navGrid.rows
  local maxCost = pathfinding.CORRIDOR_MAX_COST
  for s = 1, steps - 1 do
    local t = s / steps
    local cc = math.floor(c1 + dc * t + 0.5)
    local rr = math.floor(r1 + dr * t + 0.5)
    if cc < 1 or cc > cols or rr < 1 or rr > rows then
      return false
    end
    local idx = (rr - 1) * cols + cc
    local cost = getEffectiveCellCost(idx, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
    if cost < 0 or cost >= maxCost then
      return false
    end
  end
  return true
end

-- Whether a straight line between two world points stays clear, for this unit: looked at
-- every quarter cell, so the unit's exact position counts, not its cell's centre.
local function isLineClear(x1, y1, x2, y2, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
  local cs = navGrid.cellSize
  local dx, dy = x2 - x1, y2 - y1
  local steps = math.ceil(math.sqrt(dx * dx + dy * dy) / (cs * 0.25))
  local maxCost = pathfinding.CORRIDOR_MAX_COST
  for s = 0, steps do
    local t = steps > 0 and s / steps or 0
    local c, r = pathfinding.worldToGrid(x1 + dx * t, y1 + dy * t)
    local cost = getEffectiveCellCost(cellIndex(c, r), unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
    if cost < 0 or cost >= maxCost then return false end
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

  for rad = 1, pathfinding.NEAREST_SEARCH do
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
  if isCorridorClear(sc, sr, gc, gr, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree)
    and isLineClear(startX, startY, goalX, goalY, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree) then
    pathfinding.stats.directPaths = pathfinding.stats.directPaths + 1
    return { { x = goalX, y = goalY } }, true
  end

  local origGc, origGr = gc, gr
  local origSc, origSr = sc, sr
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

  local maxExpansions = pathfinding.MAX_EXPANSIONS
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

  -- The path runs from the start cell's centre. When the unit stands in an obstacle's margin,
  -- or the first leg from where it really stands is not clear, it steps to that centre first.
  local first = waypoints[1]
  if sc ~= origSc or sr ~= origSr
    or not isLineClear(startX, startY, first.x, first.y, unit, isVehicle, startBldId, goalBldId, wireCutter, goalInTree) then
    local wx, wy = pathfinding.gridToWorld(sc, sr)
    table.insert(waypoints, 1, { x = wx, y = wy })
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
-- Listens on channel "pf_requests" for:
--   { cmd = "grid", version, cols, rows, cellSize, originX, originY,
--     baseCosts, buildingIds, treeIds, treeTrunkIds, vehicleBlocked,
--     alliedMineCost, axisMineCost }      the nav-grid, sent after each rebuild
--   { cmd = "path", reqId, unitId, gridVersion, startX, startY, goalX, goalY,
--     isVehicle, startBldId, goalBldId, wireCutter, goalInTree, axis }
--   { cmd = "quit" }
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

local function isCorridorClear(costs, cols, rows, c1, r1, c2, r2, maxCost)
  local dc = c2 - c1
  local dr = r2 - r1
  -- Four looks per cell crossed, so a line does not slip past a blocked cell's corner.
  local steps = math.max(math.abs(dc), math.abs(dr)) * 4
  if steps <= 1 then return true end
  for s = 1, steps - 1 do
    local t = s / steps
    local cc = math.floor(c1 + dc * t + 0.5)
    local rr = math.floor(r1 + dr * t + 0.5)
    if cc < 1 or cc > cols or rr < 1 or rr > rows then
      return false
    end
    local cost = costs[(rr - 1) * cols + cc] or 1.0
    if cost < 0 or cost >= maxCost then
      return false
    end
  end
  return true
end

-- Whether a straight line between two world points stays clear, looked at every quarter cell.
local function isLineClear(costs, g, x1, y1, x2, y2)
  local cs, cols, rows = g.cellSize or 16, g.cols, g.rows
  local ox, oy = g.originX or 0, g.originY or 0
  local maxCost = g.corridorMaxCost or 4.0
  local dx, dy = x2 - x1, y2 - y1
  local steps = math.ceil(math.sqrt(dx * dx + dy * dy) / (cs * 0.25))
  for s = 0, steps do
    local t = steps > 0 and s / steps or 0
    local c = math.floor((x1 + dx * t - ox) / cs) + 1
    local r = math.floor((y1 + dy * t - oy) / cs) + 1
    if c < 1 or c > cols or r < 1 or r > rows then return false end
    local cost = costs[(r - 1) * cols + c] or 1.0
    if cost < 0 or cost >= maxCost then return false end
  end
  return true
end

-- The grid the main thread sent last ({ cmd = "grid", ... }).
local grid = nil

-- What a cell costs this unit. The same rules as getEffectiveCellCost on the main thread;
-- keep the two alike.
local function unitCellCost(g, job, idx)
  local base = g.baseCosts[idx] or 1.0
  if base < 0 then return -1 end
  local isVehicle = job.isVehicle
  if isVehicle and g.vehicleBlocked[idx] then return -1 end

  local bId = g.buildingIds[idx] or 0
  if bId > 0 then
    if isVehicle then return -1 end
    if bId == job.startBldId or bId == job.goalBldId then
      if base < 6.0 then return 0.85 end
    elseif g.throughBuildingCost then
      if base < g.throughBuildingCost then base = g.throughBuildingCost end
    else
      return -1
    end
  end

  if job.goalInTree and g.treeIds[idx] and g.treeIds[idx] > 0 then
    if not isVehicle then
      if g.treeTrunkIds[idx] and g.treeTrunkIds[idx] > 0 then
        return 1.8
      else
        return 0.95
      end
    end
  end

  if base == 6.5 and job.wireCutter then base = 1.05 end

  local minePen
  if job.axis then minePen = g.axisMineCost[idx] else minePen = g.alliedMineCost[idx] end
  if minePen and minePen > 0 then base = base + minePen end
  return base
end

local function solveAStar(job)
  local g = grid
  if not g or g.version ~= job.gridVersion then
    error("no grid for this request")
  end
  local cols = g.cols
  local rows = g.rows
  local cellSize = g.cellSize or 16
  local originX = g.originX or 0
  local originY = g.originY or 0
  -- Costs are worked out when first asked for and kept for the rest of this request.
  local costs = setmetatable({}, { __index = function(t, idx)
    local v = unitCellCost(g, job, idx)
    rawset(t, idx, v)
    return v
  end })

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
    for rad = 1, g.nearestSearch or 24 do
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

  local origSc, origSr = sc, sr
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

  local maxExpansions = g.maxExpansions or 16000
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
      if isCorridorClear(costs, cols, rows, ordered[anchor].c, ordered[anchor].r, ordered[probe].c, ordered[probe].r, g.corridorMaxCost or 4.0) then
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

  -- The path runs from the start cell's centre. When the unit stands in an obstacle's margin,
  -- or the first leg from where it really stands is not clear, it steps to that centre first.
  local first = waypoints[1]
  if sc ~= origSc or sr ~= origSr or not isLineClear(costs, g, job.startX, job.startY, first.x, first.y) then
    local wx, wy = gridToWorld(sc, sr)
    table.insert(waypoints, 1, { x = wx, y = wy })
  end

  return (targetIdx == goalIdx), waypoints
end

while true do
  local job = reqChannel:demand()
  if not job or job.cmd == "quit" then
    break
  elseif job.cmd == "grid" then
    grid = job
  elseif job.cmd == "cost" then
    -- For tests: what one cell costs under a request's details.
    resChannel:push({ reqId = job.reqId, cost = grid and unitCellCost(grid, job, job.idx) })
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
  sentGridVersion = -1 -- a new worker holds no grid yet
  th:start()
  workerThread = th
  return true
end

--- Stops the worker thread. Called from love.quit: a thread left waiting on its channel
--- can keep the game from closing.
function pathfinding.shutdown()
  if workerThread and reqChannel then
    reqChannel:push({ cmd = "quit" })
    workerThread = nil
  end
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

  local goalInTree = false
  if navGrid.treeIds[cellIndex(gc, gr)] and navGrid.treeIds[cellIndex(gc, gr)] > 0 then
    goalInTree = true
  end

  -- The worker works out each cell's cost for this unit itself, from the grid it holds.
  -- Sending the grid copies it, so that happens once per rebuild, not once per request.
  if sentGridVersion ~= navGrid.version then
    sentGridVersion = navGrid.version
    pathfinding.stats.gridsSent = (pathfinding.stats.gridsSent or 0) + 1
    reqChannel:push({
      cmd = "grid",
      version = navGrid.version,
      cols = cols,
      rows = rows,
      cellSize = navGrid.cellSize,
      maxExpansions = pathfinding.MAX_EXPANSIONS,
      nearestSearch = pathfinding.NEAREST_SEARCH,
      corridorMaxCost = pathfinding.CORRIDOR_MAX_COST,
      throughBuildingCost = navGrid.throughBuildingCost,
      originX = navGrid.originX,
      originY = navGrid.originY,
      baseCosts = navGrid.baseCosts,
      buildingIds = navGrid.buildingIds,
      treeIds = navGrid.treeIds,
      treeTrunkIds = navGrid.treeTrunkIds,
      vehicleBlocked = navGrid.vehicleBlocked,
      alliedMineCost = navGrid.alliedMineCost,
      axisMineCost = navGrid.axisMineCost
    })
  end

  local reqId = nextAsyncReqId
  nextAsyncReqId = nextAsyncReqId + 1
  pendingUnitsByReqId[reqId] = unit
  if unit then pendingReqByUnit[unit] = reqId end
  pathfinding.stats.asyncJobsSent = pathfinding.stats.asyncJobsSent + 1

  reqChannel:push({
    cmd = "path",
    reqId = reqId,
    unitId = unit and unit.id or 0,
    gridVersion = navGrid.version,
    startX = startX,
    startY = startY,
    goalX = goalX,
    goalY = goalY,
    isVehicle = isVehicle and true or false,
    startBldId = startBldId,
    goalBldId = goalBldId,
    wireCutter = wireCutter and true or false,
    goalInTree = goalInTree,
    axis = (unit and unit.faction) == "axis"
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
    if unit then
      -- Only the newest request counts: an older answer is for a destination the unit
      -- no longer has.
      local newest = pendingReqByUnit[unit] == msg.reqId
      if newest then pendingReqByUnit[unit] = nil end
      local tx, ty = unit.targetx, unit.targety
      local current = tx and ty
        and (tx - msg.goalX) * (tx - msg.goalX) + (ty - msg.goalY) * (ty - msg.goalY) <= 256
      if newest and current and msg.waypoints then
        unit.pathQueue = msg.waypoints
        partialPath[unit] = (msg.found == false) or nil
        unit._pfGoalX = msg.goalX
        unit._pfGoalY = msg.goalY
        unit._pfSnapTurn = true
      end
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

  -- The player's soldier goes exactly where he was sent.
  if pathfinding.movesDirect(unit) then
    unit.pathQueue = nil
    unit._pfGoalX, unit._pfGoalY = nil, nil
    return unit.targetx, unit.targety, false
  end

  -- Shift the destination if it is on a hazard or an unwalkable tile. Checked once per
  -- destination, not every frame.
  if settingOn("safeDestinationEnabled") then
    local seen = checkedGoal[unit]
    if not seen or seen.x ~= unit.targetx or seen.y ~= unit.targety then
      local safeX, safeY = pathfinding.findSafeDestination(unit.targetx, unit.targety, unit)
      unit.targetx = safeX
      unit.targety = safeY
      if not seen then
        seen = {}
        checkedGoal[unit] = seen
      end
      seen.x, seen.y = safeX, safeY
    end
  end

  if not settingOn("pathfindingEnabled") then
    unit.pathQueue = nil
    return unit.targetx, unit.targety, false
  end

  local tx, ty = unit.targetx, unit.targety
  local ux, uy = unit.x, unit.y

  -- Crossing to a destination no path reaches: straight on.
  local cross = crossing[unit]
  if cross then
    if cross.x == tx and cross.y == ty then
      unit.pathQueue = nil
      return tx, ty, false
    end
    crossing[unit] = nil
  end

  -- Check if destination changed or periodic hazard re-check is due
  local goalChanged = (not unit._pfGoalX) or (not unit._pfGoalY)
    or ((tx - unit._pfGoalX) * (tx - unit._pfGoalX) + (ty - unit._pfGoalY) * (ty - unit._pfGoalY) > 256)

  unit._pfRecheckTimer = (unit._pfRecheckTimer or 0) - (dt or 0.016)

  if goalChanged or (unit._pfRecheckTimer <= 0 and unit.pathQueue and #unit.pathQueue > 0) then
    unit._pfGoalX = tx
    unit._pfGoalY = ty
    unit._pfRecheckTimer = 1.2 + ((unit.id or 0) % 7) * 0.1
    if settingOn("asyncPathsEnabled") and pathfinding.initThreadWorker() then
      -- Solved on the worker thread. Until the answer arrives the unit keeps its old
      -- path, or heads straight for the destination when it has none.
      if goalChanged then unit.pathQueue = nil end
      pathfinding.requestPathAsync(unit, ux, uy, tx, ty)
    else
      local found
      unit.pathQueue, found = pathfinding.computePath(ux, uy, tx, ty, unit)
      partialPath[unit] = (found == false) or nil
      unit._pfSnapTurn = true
    end
  end

  local q = unit.pathQueue
  if not q or #q == 0 then
    return tx, ty, false
  end

  local wp = q[1]
  -- Infantry turn close to a waypoint: cutting the corner early would clip what it goes round.
  local reachRadius = (unit.turret ~= nil or unit.pivotSpeed ~= nil) and 38 or 6
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

  -- At the end of a path that stops short: no way round, so the unit crosses what is in the
  -- way, as the game itself lets it, instead of standing there.
  if #q == 1 and partialPath[unit] then
    local dx, dy = wp.x - ux, wp.y - uy
    if dx * dx + dy * dy <= reachRadius * reachRadius then
      crossing[unit] = { x = tx, y = ty }
      unit.pathQueue = nil
      return tx, ty, true
    end
  end

  -- On a path the unit aims at its waypoint every frame. The game only turns a walking
  -- soldier now and then; drifting off a path that passes an obstacle runs him into it.
  return wp.x, wp.y, true
end

-- ----------------------------------------------------------------------------
-- Prevent units from clipping inside strictly impassable barriers
-- ----------------------------------------------------------------------------
-- unit -> { held = seconds held back lately, through = seconds left walking through }.
-- Kept beside the unit, never saved.
local unstick = setmetatable({}, { __mode = "k" })

local function frameTime()
  local dt = love and love.timer and love.timer.getDelta and love.timer.getDelta()
  if not dt or dt <= 0 or dt > 0.25 then dt = 1 / 60 end
  return dt
end

--- After the game moved a soldier: keeps him out of solid cells by sliding along them. A
--- soldier held back for UNSTICK_REPLAN seconds gets his path solved again from where he
--- stands; one held back for UNSTICK_PASS seconds is let through for a moment, as the game
--- itself would. Nobody stays stuck on an obstacle.
function pathfinding.resolveObstacleCollision(unit, prevX, prevY)
  if not unit or not settingOn("pathfindingEnabled") or pathfinding.movesDirect(unit) then
    return
  end
  local cross = crossing[unit]
  if cross and cross.x == unit.targetx and cross.y == unit.targety then return end
  local st = unstick[unit]
  local dt = frameTime()
  if st and st.through > 0 then
    st.through = st.through - dt
    return
  end
  -- Paths keep BODY_RADIUS clear of objects; the collision only stops a step into the
  -- object itself, so brushing the margin costs nothing.
  local solid = navGrid.solid
  local c, r = pathfinding.worldToGrid(unit.x, unit.y)
  local wantX, wantY = unit.x, unit.y
  if solid[cellIndex(c, r)] then
    -- Only a step into a solid cell is undone; a soldier already inside one walks out.
    local pc, pr = pathfinding.worldToGrid(prevX, prevY)
    if not solid[cellIndex(pc, pr)] then
      local cxOnly, rPrev = pathfinding.worldToGrid(unit.x, prevY)
      local cPrev, ryOnly = pathfinding.worldToGrid(prevX, unit.y)
      if not solid[cellIndex(cxOnly, rPrev)] then
        unit.y = prevY
      elseif not solid[cellIndex(cPrev, ryOnly)] then
        unit.x = prevX
      else
        unit.x = prevX
        unit.y = prevY
      end
    end
  end

  -- Held back: he got less than half of the step he took.
  local want = (wantX - prevX) ^ 2 + (wantY - prevY) ^ 2
  local got = (unit.x - prevX) ^ 2 + (unit.y - prevY) ^ 2
  if want > 0 and got < want * 0.25 then
    if not st then
      st = { held = 0, through = 0, replanned = false }
      unstick[unit] = st
    end
    st.held = st.held + dt
    if st.held >= pathfinding.UNSTICK_PASS then
      unit.x, unit.y = wantX, wantY
      st.held, st.through, st.replanned = 0, 1.0, false
    elseif st.held >= pathfinding.UNSTICK_REPLAN and not st.replanned then
      st.replanned = true
      unit.pathQueue = nil
      unit._pfGoalX, unit._pfGoalY = nil, nil
    end
  elseif st then
    st.held = math.max(0, st.held - dt)
    if st.held == 0 then st.replanned = false end
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

-- For tests.
pathfinding._cellCost = getEffectiveCellCost
function pathfinding._grid() return navGrid end
function pathfinding._cellIndexAt(wx, wy) return cellIndex(pathfinding.worldToGrid(wx, wy)) end

return pathfinding
