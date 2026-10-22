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
