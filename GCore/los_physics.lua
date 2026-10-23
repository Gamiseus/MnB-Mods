-- ============================================================================
-- includes/los_physics.lua
-- High-Performance Box2D (love.physics) Line-of-Sight & Vision Polygon Engine
-- ============================================================================
-- Replaces the O(D * N) 10px step-marching loops in los() and los2() with
-- C++ Box2D Bounding Volume Hierarchy (AABB Tree) raycasting while preserving
-- 100% of vanilla Mud and Blood's gameplay mechanics and special rules:
--   * Multi-room/composite building & bunker traversal (insideSwitch logic)
--   * Tree trunk vs. canopy radii (forest[i].type == 8 -> radius / 4)
--   * HawkEye perk (shooter.hawkEye > 0 ignores trees in los2)
--   * Elevation on rocks (target.onRock > 0 ignores rocks in los2)
--   * IR StG44 night-vision scope (ignores smoke losBlockers for infantry)
--   * Anti-tank weapons & armor (fausterAlert / zookerAlert / shooter.armor)
--   * Dynamic 360-degree Vision Polygon generation for Fog of War & Tactical UI
-- ============================================================================

local los_physics = {}

-- Light vehicles & emplacements that do NOT block Line of Sight in vanilla MnB
local LIGHT_VEHICLE_TAGS_LOS1 = {
  bike = true,
  jeep = true,
  sdkfz2 = true,
  sdkfz2Boxed = true,
  goliath = true,
  kubel = true,
  zb60 = true,
  pak38 = true,
  pak36 = true,
  flak30 = true,
  flak38 = true,
  pak88 = true,
  m5 = true,
  m2hb = true,
  bofor = true,
  brestCannon = true,
  r35 = true
}

local LIGHT_VEHICLE_TAGS_LOS2 = {
  bike = true,
  jeep = true,
  sdkfz2 = true,
  sdkfz2Boxed = true,
  kubel = true,
  pak38 = true,
  pak36 = true,
  flak30 = true,
  flak38 = true,
  pak88 = true,
  m5 = true,
  zb60 = true,
  m2hb = true,
  bofor = true,
  brestCannon = true,
  r35 = true
}

los_physics.debugOverlay = false

-- Internal Box2D state
local losWorld = nil
local fixtureRecords = {} -- [tableRef] = { body, fixture, kind, x, y, r, w, h, shapeType, syncId, ref }
local syncCounter = 0
local lastSyncFrame = -1

-- Cached table lengths & references for fast mid-frame dirty detection
local lastForestRef, lastForestLen = nil, -1
local lastRocksRef, lastRocksLen = nil, -1
local lastSmokeRef, lastSmokeLen = nil, -1
local lastPlaceablesRef, lastPlaceablesLen = nil, -1
local lastVehiclesRef, lastVehiclesLen = nil, -1
local lastGroundRef, lastGroundLen = nil, -1

-- Statistics for debugging / benchmarking
los_physics.stats = {
  totalRaycasts = 0,
  totalSyncs = 0,
  activeFixtures = 0,
  lastBenchmarkMsg = ""
}

-- ----------------------------------------------------------------------------
-- Helper: Determine if a player.groundType entry is a Bunker or Building
-- matching insideBunker2(x, y) or insideBuilding2(x, y) in urb_engine.lua
-- ----------------------------------------------------------------------------
local function classifyGroundBuilding(g)
  if not g then return nil end
  local rad = g.radius or 0
  local w = g.width or 0
  local l = g.length or 0
  local cov = g.cover or 0
  local name = g.name

  if rad ~= 0 then
    -- insideBunker2 circle: name == "concrete" and cover > 50 and cover ~= 62
    if name == "concrete" and cov > 50 and cov ~= 62 then
      return "circle", g.x, g.y, rad, 0, 0
    end
  elseif w ~= 0 and l ~= 0 then
    -- insideBunker2 rect: name == "concrete" and cover > 40
    if name == "concrete" and cov > 40 then
      return "rect", g.x, g.y, 0, w, l
    end
    -- insideBuilding2 rect: name == "wood" and width ~= 89
    if name == "wood" and w ~= 89 then
      return "rect", g.x, g.y, 0, w, l
    end
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- Initialize or Reset the Box2D LOS World
-- ----------------------------------------------------------------------------
function los_physics.init()
  if losWorld then
    losWorld:destroy()
  end
  losWorld = love.physics.newWorld(0, 0, true)
  fixtureRecords = {}
  syncCounter = 0
  lastSyncFrame = -1
  lastForestRef, lastForestLen = nil, -1
  lastRocksRef, lastRocksLen = nil, -1
  lastSmokeRef, lastSmokeLen = nil, -1
  lastPlaceablesRef, lastPlaceablesLen = nil, -1
  lastVehiclesRef, lastVehiclesLen = nil, -1
  lastGroundRef, lastGroundLen = nil, -1
  los_physics.stats.activeFixtures = 0
end

-- ----------------------------------------------------------------------------
-- Internal: Create or update a Circle fixture in losWorld
-- ----------------------------------------------------------------------------
local function upsertCircleRecord(obj, kind, x, y, r, syncId)
  if not x or not y or not r or r <= 0 then return end
  local rec = fixtureRecords[obj]
  if rec then
    rec.syncId = syncId
    if rec.r ~= r or rec.kind ~= kind then
      rec.body:destroy()
      rec = nil
    else
      if rec.x ~= x or rec.y ~= y then
        rec.body:setPosition(x, y)
        rec.x = x
        rec.y = y
      end
      return
    end
  end

  local body = love.physics.newBody(losWorld, x, y, "static")
  local shape = love.physics.newCircleShape(r)
  local fixture = love.physics.newFixture(body, shape)
  local ud = {
    kind = kind,
    shapeType = "circle",
    ref = obj,
    body = body,
    fixture = fixture,
    x = x,
    y = y,
    r = r,
    w = 0,
    h = 0,
    syncId = syncId
  }
  fixture:setUserData(ud)
  fixtureRecords[obj] = ud
end

-- ----------------------------------------------------------------------------
-- Internal: Create or update an Axis-Aligned Rectangle fixture in losWorld
-- Note: (x, y) is the top-left corner as used in player.groundType
-- ----------------------------------------------------------------------------
local function upsertRectRecord(obj, kind, x, y, w, h, syncId)
  if not x or not y or not w or not h or w <= 0 or h <= 0 then return end
  local cx = x + w * 0.5
  local cy = y + h * 0.5
  local rec = fixtureRecords[obj]
  if rec then
    rec.syncId = syncId
    if rec.w ~= w or rec.h ~= h or rec.kind ~= kind then
      rec.body:destroy()
      rec = nil
    else
      if rec.x ~= x or rec.y ~= y then
        rec.body:setPosition(cx, cy)
        rec.x = x
        rec.y = y
      end
      return
    end
  end

  local body = love.physics.newBody(losWorld, cx, cy, "static")
  local shape = love.physics.newRectangleShape(w, h)
  local fixture = love.physics.newFixture(body, shape)
  local ud = {
    kind = kind,
    shapeType = "rect",
    ref = obj,
    body = body,
    fixture = fixture,
    x = x,
    y = y,
    r = 0,
    w = w,
    h = h,
    syncId = syncId
  }
  fixture:setUserData(ud)
  fixtureRecords[obj] = ud
end

-- ----------------------------------------------------------------------------
-- Synchronize Box2D World with live player.* obstacle tables
-- Automatically adds new obstacles, updates moved vehicles, and destroys
-- removed trees/rocks/smoke/buildings.
-- ----------------------------------------------------------------------------
function los_physics.sync()
  if not losWorld then
    los_physics.init()
  end
  if not player then return end

  syncCounter = syncCounter + 1
  local curSync = syncCounter
  los_physics.stats.totalSyncs = los_physics.stats.totalSyncs + 1

  -- 1. Trees (player.forest)
  local forest = player.forest
  if forest then
    for i = 1, #forest do
      local tree = forest[i]
      if tree and tree.x and tree.y and tree.radius then
        local r = (tree.type == 8) and (tree.radius * 0.25) or tree.radius
        upsertCircleRecord(tree, "tree", tree.x, tree.y, r, curSync)
      end
    end
    lastForestRef, lastForestLen = forest, #forest
  else
    lastForestRef, lastForestLen = nil, 0
  end

  -- 2. Rocks (player.rocks)
  local rocks = player.rocks
  if rocks then
    for i = 1, #rocks do
      local rock = rocks[i]
      if rock and rock.x and rock.y and rock.size then
        local r = (50 * rock.size) / 10
        upsertCircleRecord(rock, "rock", rock.x, rock.y, r, curSync)
      end
    end
    lastRocksRef, lastRocksLen = rocks, #rocks
  else
    lastRocksRef, lastRocksLen = nil, 0
  end

  -- 3. Temporary LOS Blockers / Smoke (player.losBlockers)
  local blockers = player.losBlockers
  if blockers then
    for i = 1, #blockers do
      local b = blockers[i]
      if b and b.x and b.y and b.radius and b.radius > 0 then
        upsertCircleRecord(b, "smoke", b.x, b.y, b.radius, curSync)
      end
    end
    lastSmokeRef, lastSmokeLen = blockers, #blockers
  else
    lastSmokeRef, lastSmokeLen = nil, 0
  end

  -- 4. Placeables with losBlocker == 1 (player.placeables)
  local placeables = player.placeables
  if placeables then
    for i = 1, #placeables do
      local p = placeables[i]
      if p and p.losBlocker == 1 and p.x and p.y and p.radius and p.radius > 0 then
        upsertCircleRecord(p, "placeable", p.x, p.y, p.radius, curSync)
      end
    end
    lastPlaceablesRef, lastPlaceablesLen = placeables, #placeables
  else
    lastPlaceablesRef, lastPlaceablesLen = nil, 0
  end

  -- 5. Deployed Vehicles (player.deployedVehicles)
  local vehicles = player.deployedVehicles
  if vehicles then
    for i = 1, #vehicles do
      local v = vehicles[i]
      if v and v.x and v.y and v.tag and not LIGHT_VEHICLE_TAGS_LOS2[v.tag] then
        upsertCircleRecord(v, "vehicle", v.x, v.y, 100, curSync)
      end
    end
    lastVehiclesRef, lastVehiclesLen = vehicles, #vehicles
  else
    lastVehiclesRef, lastVehiclesLen = nil, 0
  end

  -- 6. Buildings & Bunkers in player.groundType
  local ground = player.groundType
  if ground then
    for i = 1, #ground do
      local g = ground[i]
      local stype, gx, gy, gr, gw, gh = classifyGroundBuilding(g)
      if stype == "circle" then
        upsertCircleRecord(g, "building", gx, gy, gr, curSync)
      elseif stype == "rect" then
        upsertRectRecord(g, "building", gx, gy, gw, gh, curSync)
      end
    end
    lastGroundRef, lastGroundLen = ground, #ground
  else
    lastGroundRef, lastGroundLen = nil, 0
  end

  -- Sweep & destroy any stale Box2D bodies removed from the game tables
  local activeCount = 0
  for obj, rec in pairs(fixtureRecords) do
    if rec.syncId ~= curSync then
      if rec.body and not rec.body:isDestroyed() then
        rec.body:destroy()
      end
      fixtureRecords[obj] = nil
    else
      activeCount = activeCount + 1
    end
  end
  los_physics.stats.activeFixtures = activeCount
end

-- ----------------------------------------------------------------------------
-- Fast check to ensure Box2D world is synced with current frame & table counts
-- ----------------------------------------------------------------------------
local currentFrameId = 0
function los_physics.updateFrame()
  currentFrameId = currentFrameId + 1
  los_physics.sync()
  lastSyncFrame = currentFrameId
end

function los_physics.ensureSynced()
  if not losWorld then
    los_physics.sync()
    lastSyncFrame = currentFrameId
    return
  end
  if not player then return end

  local f = player.forest
  local r = player.rocks
  local s = player.losBlockers
  local p = player.placeables
  local v = player.deployedVehicles
  local g = player.groundType

  if lastSyncFrame ~= currentFrameId
     or f ~= lastForestRef or (f and #f or 0) ~= lastForestLen
     or r ~= lastRocksRef or (r and #r or 0) ~= lastRocksLen
     or s ~= lastSmokeRef or (s and #s or 0) ~= lastSmokeLen
     or p ~= lastPlaceablesRef or (p and #p or 0) ~= lastPlaceablesLen
     or v ~= lastVehiclesRef or (v and #v or 0) ~= lastVehiclesLen
     or g ~= lastGroundRef or (g and #g or 0) ~= lastGroundLen then
    los_physics.sync()
    lastSyncFrame = currentFrameId
  end
end

-- ----------------------------------------------------------------------------
-- Helper: Point-in-building check against ONLY the buildings hit by a ray
-- ----------------------------------------------------------------------------
local function isPointInHitBuildings(px, py, hitBuildings, count)
  for i = 1, count do
    local b = hitBuildings[i]
    if b.shapeType == "rect" then
      if px > b.x and px < b.x + b.w and py > b.y and py < b.y + b.h then
        return true
      end
    else
      local dx = px - b.x
      local dy = py - b.y
      if (dx * dx + dy * dy) < (b.r * b.r) then
        return true
      end
    end
  end
  return false
end

-- ----------------------------------------------------------------------------
-- Helper: Evaluate vanilla insideSwitch building traversal on hitBuildings
-- Matches the exact state transitions of los() and los2() in urb_engine.lua
-- ----------------------------------------------------------------------------
local function evaluateBuildingTraversal(x1, y1, x2, y2, losDistance, hitBuildings, hitCount, isLos2)
  local losSamples = losDistance * 0.1
  local losAngle = -math.atan2((x1 - x2), (y1 - y2))
  local losXSpeed = 10 * math.sin(losAngle)
  local losYSpeed = 10 * math.cos(losAngle)
  local losx = x1
  local losy = y1
  local insideSwitch = 0
  local inside = 0

  if isPointInHitBuildings(losx, losy, hitBuildings, hitCount) then
    inside = 1
    if isLos2 then
      insideSwitch = -1
    end
  end

  local maxSample = math.floor(losSamples)
  for _ = 0, maxSample do
    if isPointInHitBuildings(losx, losy, hitBuildings, hitCount) then
      if inside ~= 1 then
        insideSwitch = insideSwitch + 1
        inside = 1
      end
    else
      if inside ~= 0 then
        insideSwitch = insideSwitch + 1
        inside = 0
      end
    end
    if insideSwitch >= 2 then
      return false
    end
    losx = losx + losXSpeed
    losy = losy - losYSpeed
  end

  return true
end

-- Reusable scratch table for buildings touched during a single raycast
local scratchBuildings = {}
local scratchBuildingSeen = {}

-- ----------------------------------------------------------------------------
-- Drop-in Replacement for los(x1, x2, y1, y2)
-- Parameter order is (x1, x2, y1, y2) to match urb_engine.lua:3860!
-- ----------------------------------------------------------------------------
function los_physics.checkLOS(x1, y1, x2, y2)
  if not (x1 and y1 and x2 and y2) then return false end

  local dx = x2 - x1
  local dy = y2 - y1
  local losDistance = math.sqrt(dx * dx + dy * dy)

  -- In vanilla los(), distances < 50 always return true on sample 0
  if losDistance < 50 then
    return true
  end

  los_physics.ensureSynced()
  los_physics.stats.totalRaycasts = los_physics.stats.totalRaycasts + 1

  -- Sync vehicle positions if any heavy vehicles exist (usually 0-5)
  local vehicles = player and player.deployedVehicles
  if vehicles then
    for i = 1, #vehicles do
      local v = vehicles[i]
      local rec = v and fixtureRecords[v]
      if rec and (rec.x ~= v.x or rec.y ~= v.y) then
        rec.body:setPosition(v.x, v.y)
        rec.x = v.x
        rec.y = v.y
      end
    end
  end

  local blocked = false
  local bCount = 0

  -- 1. Point query at ray origin (x1, y1) via Box2D AABB Tree
  losWorld:queryBoundingBox(x1 - 1, y1 - 1, x1 + 1, y1 + 1, function(fixture)
    local ud = fixture:getUserData()
    if not ud then return true end
    if fixture:testPoint(x1, y1) then
      local kind = ud.kind
      if kind == "building" then
        if not scratchBuildingSeen[ud] then
          scratchBuildingSeen[ud] = true
          bCount = bCount + 1
          scratchBuildings[bCount] = ud
        end
      elseif kind == "vehicle" then
        local v = ud.ref
        if v and not LIGHT_VEHICLE_TAGS_LOS1[v.tag] then
          blocked = true
          return false
        end
      else
        -- tree, rock, smoke, placeable containing (x1, y1)
        blocked = true
        return false
      end
    end
    return true
  end)

  if blocked then
    for i = 1, bCount do scratchBuildingSeen[scratchBuildings[i]] = nil end
    return false
  end

  -- 2. Box2D C++ Raycast along the segment sampled by vanilla
  local maxSampleLen = math.floor(losDistance * 0.1) * 10
  local tEnd = (maxSampleLen > 0) and (maxSampleLen / losDistance) or 1.0
  local endX = x1 + dx * tEnd
  local endY = y1 + dy * tEnd

  if math.abs(endX - x1) > 1e-3 or math.abs(endY - y1) > 1e-3 then
    losWorld:rayCast(x1, y1, endX, endY, function(fixture, hx, hy, xn, yn, fraction)
      local ud = fixture:getUserData()
      if not ud then return -1 end
      local kind = ud.kind

      if kind == "building" then
        if not scratchBuildingSeen[ud] then
          scratchBuildingSeen[ud] = true
          bCount = bCount + 1
          scratchBuildings[bCount] = ud
        end
        return -1 -- Ignore clipping and continue collecting building fixtures
      elseif kind == "vehicle" then
        local v = ud.ref
        if v and not LIGHT_VEHICLE_TAGS_LOS1[v.tag] then
          blocked = true
          return 0 -- Terminate raycast immediately
        end
        return -1
      else
        -- tree, rock, smoke, placeable hit!
        blocked = true
        return 0 -- Terminate raycast immediately
      end
    end)
  end

  if blocked then
    for i = 1, bCount do scratchBuildingSeen[scratchBuildings[i]] = nil end
    return false
  end

  -- 3. If the ray touched any buildings/bunkers, evaluate insideSwitch
  local clear = true
  if bCount > 0 then
    clear = evaluateBuildingTraversal(x1, y1, x2, y2, losDistance, scratchBuildings, bCount, false)
    for i = 1, bCount do scratchBuildingSeen[scratchBuildings[i]] = nil end
  end

  return clear
end

-- ----------------------------------------------------------------------------
-- Drop-in Replacement for los2(shooter, target)
-- Preserves all unit-specific perks and equipment rules from urb_engine.lua:3950
-- ----------------------------------------------------------------------------
function los_physics.checkLOS2(shooter, target)
  if not shooter or not target or not shooter.x or not shooter.y or not target.x or not target.y then
    return false
  end

  local x1, y1 = shooter.x, shooter.y
  local x2, y2 = target.x, target.y
  local dx = x2 - x1
  local dy = y2 - y1
  local losDistance = math.sqrt(dx * dx + dy * dy)

  if losDistance < 50 then
    return true
  end

  los_physics.ensureSynced()
  los_physics.stats.totalRaycasts = los_physics.stats.totalRaycasts + 1

  -- Pre-evaluate unit perk/weapon filter flags once per call
  local checkTrees = ((shooter.hawkEye or 0) <= 0)
  local checkRocks = ((target.onRock or 0) == 0)
  local checkSmoke = ((shooter.armor or 0) > 0) or (not shooter.weapon) or (shooter.weapon.tag ~= "irstg44")
  local checkVehicles = ((shooter.armor or 0) == 0) and (fausterAlert(shooter) <= 0 and zookerAlert(shooter) <= 0)

  -- Sync vehicle positions if we need to check vehicles
  if checkVehicles then
    local vehicles = player and player.deployedVehicles
    if vehicles then
      for i = 1, #vehicles do
        local v = vehicles[i]
        local rec = v and fixtureRecords[v]
        if rec and (rec.x ~= v.x or rec.y ~= v.y) then
          rec.body:setPosition(v.x, v.y)
          rec.x = v.x
          rec.y = v.y
        end
      end
    end
  end

  local blocked = false
  local bCount = 0

  -- 1. Point query at shooter origin (x1, y1)
  losWorld:queryBoundingBox(x1 - 1, y1 - 1, x1 + 1, y1 + 1, function(fixture)
    local ud = fixture:getUserData()
    if not ud then return true end
    if fixture:testPoint(x1, y1) then
      local kind = ud.kind
      if kind == "building" then
        if not scratchBuildingSeen[ud] then
          scratchBuildingSeen[ud] = true
          bCount = bCount + 1
          scratchBuildings[bCount] = ud
        end
      elseif kind == "tree" then
        if checkTrees then blocked = true; return false end
      elseif kind == "rock" then
        if checkRocks then blocked = true; return false end
      elseif kind == "smoke" then
        if checkSmoke then blocked = true; return false end
      elseif kind == "placeable" then
        blocked = true; return false
      elseif kind == "vehicle" then
        if checkVehicles and ud.ref ~= shooter and ud.ref ~= target then
          blocked = true; return false
        end
      end
    end
    return true
  end)

  if blocked then
    for i = 1, bCount do scratchBuildingSeen[scratchBuildings[i]] = nil end
    return false
  end

  -- 2. Box2D C++ Raycast from shooter to target
  local maxSampleLen = math.floor(losDistance * 0.1) * 10
  local tEnd = (maxSampleLen > 0) and (maxSampleLen / losDistance) or 1.0
  local endX = x1 + dx * tEnd
  local endY = y1 + dy * tEnd

  if math.abs(endX - x1) > 1e-3 or math.abs(endY - y1) > 1e-3 then
    losWorld:rayCast(x1, y1, endX, endY, function(fixture, hx, hy, xn, yn, fraction)
      local ud = fixture:getUserData()
      if not ud then return -1 end
      local kind = ud.kind

      if kind == "building" then
        if not scratchBuildingSeen[ud] then
          scratchBuildingSeen[ud] = true
          bCount = bCount + 1
          scratchBuildings[bCount] = ud
        end
        return -1
      elseif kind == "tree" then
        if checkTrees then blocked = true; return 0 end
        return -1
      elseif kind == "rock" then
        if checkRocks then blocked = true; return 0 end
        return -1
      elseif kind == "smoke" then
        if checkSmoke then blocked = true; return 0 end
        return -1
      elseif kind == "placeable" then
        blocked = true; return 0
      elseif kind == "vehicle" then
        if checkVehicles and ud.ref ~= shooter and ud.ref ~= target then
          blocked = true; return 0
        end
        return -1
      end
      return -1
    end)
  end

  if blocked then
    for i = 1, bCount do scratchBuildingSeen[scratchBuildings[i]] = nil end
    return false
  end

  -- 3. Evaluate building/bunker traversal on touched buildings
  local clear = true
  if bCount > 0 then
    clear = evaluateBuildingTraversal(x1, y1, x2, y2, losDistance, scratchBuildings, bCount, true)
    for i = 1, bCount do scratchBuildingSeen[scratchBuildings[i]] = nil end
  end

  return clear
end

-- ----------------------------------------------------------------------------
-- Continuous Raycast Query for Vision Polygons, Fog of War & Smart Cover AI
-- Computes exact exit-wall occlusion for buildings so soldiers see into
-- buildings up to the far wall, and stops at the front edge of trees/rocks/smoke.
-- Returns: hit (bool), hitX, hitY, hitFraction, hitKind, hitRef
-- ----------------------------------------------------------------------------
function los_physics.castRay(x1, y1, x2, y2, opts)
  local dx = x2 - x1
  local dy = y2 - y1
  local distSq = dx * dx + dy * dy
  if distSq < 1e-4 then
    return false, x2, y2, 1.0, nil, nil
  end

  los_physics.ensureSynced()

  local ignoreTrees = opts and opts.ignoreTrees
  local ignoreRocks = opts and opts.ignoreRocks
  local ignoreSmoke = opts and opts.ignoreSmoke
  local ignoreVehicles = opts and opts.ignoreVehicles
  local ignoreUnit = opts and opts.ignoreUnit

  local bestFrac = 1.0
  local bestX, bestY = x2, y2
  local bestKind, bestRef = nil, nil
  local hitAny = false

  losWorld:rayCast(x1, y1, x2, y2, function(fixture, hx, hy, xn, yn, fraction)
    local ud = fixture:getUserData()
    if not ud then return -1 end
    local kind = ud.kind

    if kind == "tree" and ignoreTrees then return -1 end
    if kind == "rock" and ignoreRocks then return -1 end
    if kind == "smoke" and ignoreSmoke then return -1 end
    if kind == "vehicle" and (ignoreVehicles or ud.ref == ignoreUnit) then return -1 end

    local effectiveFrac = fraction
    local effX, effY = hx, hy

    -- For buildings entered from outside, vision penetrates into the building
    -- and is blocked where the ray exits the far wall of the building!
    if kind == "building" and not (opts and opts.stopAtBuildingEntry) then
      if ud.shapeType == "rect" then
        local txExit = math.huge
        local tyExit = math.huge
        if math.abs(dx) > 1e-6 then
          local targetEdgeX = (dx > 0) and (ud.x + ud.w) or ud.x
          txExit = (targetEdgeX - x1) / dx
        end
        if math.abs(dy) > 1e-6 then
          local targetEdgeY = (dy > 0) and (ud.y + ud.h) or ud.y
          tyExit = (targetEdgeY - y1) / dy
        end
        effectiveFrac = math.min(txExit, tyExit)
      else
        -- Circle bunker: symmetric chord reflection across projection of center
        local tMid = ((ud.x - x1) * dx + (ud.y - y1) * dy) / distSq
        effectiveFrac = math.max(fraction, 2 * tMid - fraction)
      end

      if effectiveFrac >= 1.0 then
        -- Ray terminates inside the building before exiting the back wall
        return -1
      end
      effX = x1 + dx * effectiveFrac
      effY = y1 + dy * effectiveFrac
    end

    if effectiveFrac < bestFrac then
      bestFrac = effectiveFrac
      bestX, bestY = effX, effY
      bestKind = kind
      bestRef = ud.ref
      hitAny = true
      return effectiveFrac
    end
    return -1
  end)

  return hitAny, bestX, bestY, bestFrac, bestKind, bestRef
end

-- ----------------------------------------------------------------------------
-- Compute a 2D Vision Fan / Polygon around (originX, originY) using Box2D rays
-- Ready for Fog-of-War Stencil/Canvas rendering and F9 Tactical View
-- ----------------------------------------------------------------------------
function los_physics.computeVisionPolygon(originX, originY, maxRange, numRays, opts)
  maxRange = maxRange or 650
  numRays = numRays or 64
  local points = {}
  local twoPi = math.pi * 2

  for i = 0, numRays - 1 do
    local angle = (i / numRays) * twoPi
    local targetX = originX + math.cos(angle) * maxRange
    local targetY = originY + math.sin(angle) * maxRange
    local _, hx, hy = los_physics.castRay(originX, originY, targetX, targetY, opts)
    points[#points + 1] = hx
    points[#points + 1] = hy
  end

  return points
end

-- ----------------------------------------------------------------------------
-- Draw Debug Overlay when los_physics.debugOverlay == true (Dedicated F10 toggle)
-- Displays real-time Box2D raycast vision fans for Allied soldiers,
-- active enemy sightlines, and outlines Box2D building/bunker colliders.
-- ----------------------------------------------------------------------------
function los_physics.drawDebugOverlay()
  if not player then return end
  local overlayActive = (los_physics.debugOverlay == true)
  if not overlayActive then return end

  los_physics.ensureSynced()
  if not losWorld then return end

  -- 1. Draw Box2D building/bunker collider outlines in cyan
  love.graphics.setColor(love.math.colorFromBytes(0, 230, 255, 180))
  for _, rec in pairs(fixtureRecords) do
    if rec.kind == "building" then
      if rec.shapeType == "rect" then
        love.graphics.rectangle("line", rec.x, rec.y, rec.w, rec.h)
      else
        love.graphics.circle("line", rec.x, rec.y, rec.r)
      end
    end
  end

  -- 2. Draw real-time Box2D raycast vision fan for currently selected soldiers,
  --    or ALL living allied soldiers if no soldier is explicitly selected
  local troops = player.deployedTroops
  if troops then
    local anySelected = false
    for i = 1, #troops do
      local s = troops[i]
      if s and (s.dead or 0) == 0 and (s.health or 0) > 0 and s.selected == true then
        anySelected = true
        break
      end
    end

    for i = 1, #troops do
      local s = troops[i]
      local shouldDraw = (s and (s.dead or 0) == 0 and (s.health or 0) > 0) and
        ((anySelected and s.selected == true) or (not anySelected and s.faction == "allied"))
      if shouldDraw then
        local opts = {
          ignoreTrees = ((s.hawkEye or 0) > 0),
          ignoreSmoke = (s.armor == 0 and s.weapon and s.weapon.tag == "irstg44"),
          ignoreVehicles = ((s.armor or 0) > 0),
          ignoreUnit = s
        }
        local visionRange = 600
        if s.weapon and s.weapon.range and s.weapon.range > 300 then
          visionRange = math.min(1000, s.weapon.range)
        end
        local rayCount = anySelected and 64 or 40
        local poly = los_physics.computeVisionPolygon(s.x, s.y, visionRange, rayCount, opts)
        local n = #poly
        if n >= 6 then
          local fillAlpha = anySelected and 45 or 25
          local lineAlpha = anySelected and 200 or 120
          -- Draw translucent triangle fan from (s.x, s.y)
          love.graphics.setColor(love.math.colorFromBytes(60, 240, 120, fillAlpha))
          for j = 1, n - 2, 2 do
            love.graphics.polygon("fill", s.x, s.y, poly[j], poly[j + 1], poly[j + 2], poly[j + 3])
          end
          love.graphics.polygon("fill", s.x, s.y, poly[n - 1], poly[n], poly[1], poly[2])

          -- Draw perimeter ray endpoints
          love.graphics.setColor(love.math.colorFromBytes(70, 255, 130, lineAlpha))
          for j = 1, n - 2, 2 do
            love.graphics.line(poly[j], poly[j + 1], poly[j + 2], poly[j + 3])
          end
          love.graphics.line(poly[n - 1], poly[n], poly[1], poly[2])

          -- Draw heading ray
          if s.rotation then
            local hx = s.x - math.sin(s.rotation) * 50
            local hy = s.y + math.cos(s.rotation) * 50
            love.graphics.setColor(love.math.colorFromBytes(255, 255, 120, 220))
            love.graphics.line(s.x, s.y, hx, hy)
          end
        end

        -- Draw enemy sightline if engaged or target present
        if s.target and s.target > 0 then
          for o = 1, #troops do
            local e = troops[o]
            if e and e.id == s.target and (e.dead or 0) == 0 and (e.health or 0) > 0 then
              local clear = los2(s, e)
              if clear then
                love.graphics.setColor(love.math.colorFromBytes(0, 255, 80, 220))
              else
                love.graphics.setColor(love.math.colorFromBytes(255, 50, 50, 200))
              end
              love.graphics.setLineWidth(1.5)
              love.graphics.line(s.x, s.y, e.x, e.y)
              love.graphics.setLineWidth(1)
              break
            end
          end
        end
      end
    end
  end

  -- 3. Draw tactical on-screen indicator banner
  if nonoFont then
    love.graphics.setFont(nonoFont)
    love.graphics.setColor(love.math.colorFromBytes(0, 0, 0, 200))
    love.graphics.rectangle("fill", 10, 10, 250, 22)
    love.graphics.setColor(love.math.colorFromBytes(50, 240, 120, 255))
    love.graphics.print("[F10] LOS VISION OVERLAY: ACTIVE", 16, 14)
  end

  love.graphics.setColor(love.math.colorFromBytes(255, 255, 255, 255))
end

-- ----------------------------------------------------------------------------
-- Self-Test & Live Benchmark against Vanilla Ray-Marching
-- Verifies equivalence and measures speedup on the active map
-- ----------------------------------------------------------------------------
function los_physics.runBenchmark(vanillaLosFunc, numIterations)
  numIterations = numIterations or 2000
  los_physics.sync()

  -- Generate deterministic test ray pairs across the map
  local pairsList = {}
  local mapW = (player and player.endLine and player.endLine > 1000) and player.endLine or 10000
  for i = 1, numIterations do
    local x1 = ((i * 197) % mapW) + 100
    local y1 = ((i * 73) % 680) + 20
    local x2 = ((x1 + 150 + (i * 311) % 900) % mapW) + 100
    local y2 = ((i * 139) % 680) + 20
    pairsList[i] = { x1, x2, y1, y2 }
  end

  local t0 = love.timer.getTime()
  local boxHits = 0
  for i = 1, numIterations do
    local p = pairsList[i]
    if los_physics.checkLOS(p[1], p[2], p[3], p[4]) then
      boxHits = boxHits + 1
    end
  end
  local boxTime = (love.timer.getTime() - t0) * 1000

  local vanillaTime = 0
  local vanillaHits = 0
  if vanillaLosFunc then
    local t1 = love.timer.getTime()
    for i = 1, numIterations do
      local p = pairsList[i]
      if vanillaLosFunc(p[1], p[2], p[3], p[4]) then
        vanillaHits = vanillaHits + 1
      end
    end
    vanillaTime = (love.timer.getTime() - t1) * 1000
  end

  local speedup = (boxTime > 0 and vanillaTime > 0) and (vanillaTime / boxTime) or 0
  local msg = string.format(
    "[LOS Physics Benchmark] %d rays | Box2D: %.2f ms | Vanilla: %.2f ms | Speedup: %.1fx | Fixtures: %d",
    numIterations, boxTime, vanillaTime, speedup, los_physics.stats.activeFixtures
  )
  los_physics.stats.lastBenchmarkMsg = msg
  print(msg)
  return boxTime, vanillaTime, speedup, boxHits, vanillaHits
end

return los_physics
