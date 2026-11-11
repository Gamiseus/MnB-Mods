-- combat_reaction.lua
-- What a player's soldier does when a move order runs into the enemy: stop and return
-- fire, or sprint to nearby cover, then resume the order when the area is clear.
--
-- The state of each soldier is kept beside the soldier, not on it, so nothing extra goes
-- into save files and no other mod's fields are touched.
--
-- Cost: looking for threats means distance and line-of-sight checks against the enemy.
-- A soldier looks about five times a second, not every frame, checks sight only to the
-- few nearest enemies, and does not look at all while standing still outside a reaction.

local Reaction = {}

Reaction.SCAN_INTERVAL = 0.2   -- seconds between two looks, per soldier
Reaction.SIGHT_CHECKS = 4      -- line-of-sight checks per look, nearest enemies first
Reaction.SIGHT_RANGE = 600
Reaction.NEAR_RANGE = 520
Reaction.VEHICLE_RANGE = 650
Reaction.COVER_RADIUS = 160

local CALLOUTS = {
  cover = { "Taking fire! Finding cover!", "Ambush! Hit the dirt!", "Enemy contact! Take cover!", "Under heavy fire! Moving to cover!" },
  contact = { "Hostiles spotted! Get down!", "Germans sighted! Take cover!", "Enemy contact front!", "Movement ahead! Watch your fire!" },
  secure = { "Threat eliminated! Moving out!", "All clear! Resuming move!", "Area secure! Moving out!", "Hostiles down! Keep moving!" },
  retaliate = { "Returning fire! Cover me!", "Enemy sighted! Opening fire!", "Engaging hostiles!", "Contact front! Firing!" },
}

local states = setmetatable({}, { __mode = "k" })

local function stateOf(dude)
  local s = states[dude]
  if not s then
    -- Spread the looks of a squad over different frames.
    s = { scanIn = ((dude.id or 0) % 10) * Reaction.SCAN_INTERVAL / 10, threat = {} }
    states[dude] = s
  end
  return s
end

local function say(dude, list)
  floatyText(dude, list[randNbr(#list)])
end

local function alive(u)
  return u and (u.dead or 0) == 0 and (u.health or 0) > 10
end

--- Forgets a soldier's reaction and the order it interrupted. For a new order or Halt.
function Reaction.clear(dude)
  local s = states[dude]
  if not s then return end
  s.active, s.sprinting, s.retaliating, s.retaliationDone = nil, nil, nil, nil
  s.clearTimer, s.savedX, s.savedY = nil, nil, nil
end

--- Whether the soldier is reacting to contact right now.
function Reaction.isActive(dude)
  local s = states[dude]
  return s ~= nil and s.active == true
end

-- ---------------------------------------------------------------------------
-- Threats
-- ---------------------------------------------------------------------------

local candidates = {}

local function byDistance(a, b) return a.d < b.d end

-- Fills s.threat: the nearest visible enemy, the nearest enemy at all, and whether the
-- soldier is under direct threat.
local function scan(dude, s)
  local t = s.threat
  t.visible, t.visibleDist, t.near, t.nearDist, t.nearCount, t.direct = nil, 99999, nil, 99999, 0, false

  local n = 0
  local troops = player.deployedTroops
  for o = 1, #troops do
    local e = troops[o]
    if e.faction == "axis" and alive(e) then
      local d = distanceCheck2(dude, e)
      if d <= Reaction.SIGHT_RANGE then
        local hidden = (e.flagged or 0) <= 0 and (hasBuffByTag("stealth", e) or hasBuffByTag("camo", e))
        if not hidden then
          if d <= Reaction.NEAR_RANGE then
            t.nearCount = t.nearCount + 1
            if d < t.nearDist then t.nearDist, t.near = d, e end
          end
          n = n + 1
          local c = candidates[n]
          if not c then
            c = {}
            candidates[n] = c
          end
          c.unit, c.d, c.vehicle = e, d, false
        end
      end
    end
  end
  local vehicles = player.deployedVehicles
  if vehicles then
    for o = 1, #vehicles do
      local v = vehicles[o]
      if v.faction == "axis" and alive(v) then
        local d = distanceCheck2(dude, v)
        if d <= Reaction.VEHICLE_RANGE then
          t.nearCount = t.nearCount + 1
          if d < t.nearDist then t.nearDist, t.near = d, v end
          n = n + 1
          local c = candidates[n]
          if not c then
            c = {}
            candidates[n] = c
          end
          c.unit, c.d, c.vehicle = v, d, true
        end
      end
    end
  end
  for i = n + 1, #candidates do candidates[i] = nil end
  if n == 0 then return end

  table.sort(candidates, byDistance)
  for i = 1, math.min(n, Reaction.SIGHT_CHECKS) do
    local c = candidates[i]
    if los2(dude, c.unit) then
      local e = c.unit
      if not t.visible then t.visible, t.visibleDist = e, c.d end
      if c.vehicle or c.d <= 420 or (e.aim or 0) > 0 or e.target == dude.id or (e.flagged or 0) > 0 then
        t.direct = true
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Cover
-- ---------------------------------------------------------------------------

local function enemyWithin(x, y, range)
  local troops = player.deployedTroops
  for o = 1, #troops do
    local e = troops[o]
    if e.faction == "axis" and (e.health or 0) > 10 and distanceCheck(x, y, e.x, e.y) < range then
      return true
    end
  end
  return false
end

local function crowdAt(dude, x, y)
  local crowd = 0
  local troops = player.deployedTroops
  for o = 1, #troops do
    local m = troops[o]
    if m.faction == dude.faction and m.id ~= dude.id and distanceCheck(x, y, m.x, m.y) < 50 then
      crowd = crowd + 1
    end
  end
  return crowd
end

local function inCoverPatch(x, y)
  local ground = player.groundType
  if ground then
    for u = 1, #ground do
      local g = ground[u]
      if (g.cover or 0) > 0 and (g.width or 0) > 0 and (g.length or 0) > 0
        and x >= g.x and x <= g.x + g.width and y >= g.y and y <= g.y + g.length then
        return true
      end
    end
  end
  local forest = player.forest
  if forest then
    for u = 1, #forest do
      local f = forest[u]
      if distanceCheck(x, y, f.x, f.y) <= (f.radius or 30) then return true end
    end
  end
  return false
end

local probe = { x = 0, y = 0 }

-- The best cover within reach: close, not next to the enemy, not crowded, not on fire,
-- preferably not closer to the threat and with a line of fire to it.
-- Returns x, y, or nil when there is none.
local function findCover(dude, threat)
  local px, py = dude.x, dude.y
  local radius = Reaction.COVER_RADIUS

  -- The order's own destination, when it is close and already in cover.
  if dude.targetx and dude.targety and distanceCheck(px, py, dude.targetx, dude.targety) <= 90
    and inCoverPatch(dude.targetx, dude.targety) then
    return dude.targetx, dude.targety
  end

  local threatDist = threat and distanceCheck(px, py, threat.x, threat.y) or 99999
  local bestScore, bestX, bestY = 99999, nil, nil

  local function consider(x, y, base, coverValue, sightBonus, sightPenalty, crowdLimit)
    if enemyWithin(x, y, 140) or fireNearby(x, y) then return end
    if crowdLimit and crowdAt(dude, x, y) > crowdLimit then return end
    local score = base - coverValue
    if threat then
      local d = distanceCheck(x, y, threat.x, threat.y)
      if d < threatDist - 30 then
        score = score + 160
      elseif d >= threatDist and crowdLimit then
        score = score - 25
      end
      -- Only spots that could still win are worth a line-of-sight check.
      if score - sightBonus < bestScore then
        probe.x, probe.y = x, y
        if los2(probe, threat) then score = score - sightBonus else score = score + sightPenalty end
      else
        return
      end
    end
    if score < bestScore then bestScore, bestX, bestY = score, x, y end
  end

  local ground = player.groundType
  if ground then
    for u = 1, #ground do
      local g = ground[u]
      if (g.cover or 0) > 0 and (g.width or 0) > 0 and (g.length or 0) > 0 then
        local nearX = math.max(g.x, math.min(px, g.x + g.width))
        local nearY = math.max(g.y, math.min(py, g.y + g.length))
        local d = distanceCheck(px, py, nearX, nearY)
        if d <= radius then
          local x = math.max(g.x + 8, math.min(nearX, g.x + g.width - 8))
          local y = math.max(g.y + 8, math.min(nearY, g.y + g.length - 8))
          consider(x, y, d, (g.cover or 0) * 0.4, 60, 45, 2)
        end
      end
    end
  end
  local forest = player.forest
  if forest then
    for u = 1, #forest do
      local f = forest[u]
      local d = distanceCheck(px, py, f.x, f.y)
      if d <= radius and d > 20 then
        consider(f.x, f.y, d + 20, 0, 40, 30, nil)
      end
    end
  end
  return bestX, bestY
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

local function inCover(dude)
  return underCover(dude) or (dude.cover or 0) > 0
end

local function face(dude, unit, dist)
  if not unit then return end
  dude.rotation = math.atan2(dude.y - unit.y, dude.x - unit.x) + 1.5707
  return dist
end

local function engage(dude, unit, dist)
  if not unit then return end
  dude.targetPointer = unit.id
  dude.targetDistance = dist
  dude.aim = 1
  face(dude, unit)
end

local function hold(dude)
  dude.temporaryStop = 2.0
  dude.targetx, dude.targety = dude.x, dude.y
  dude.pathQueue = nil
  dude._pfGoalX, dude._pfGoalY = nil, nil
end

local function runTo(dude, x, y)
  dude.temporaryStop = 0
  dude.targetx, dude.targety = x, y
  if pathfinding and pathfinding.requestPathAsync then
    pathfinding.requestPathAsync(dude, dude.x, dude.y, x, y)
  end
end

-- The reaction is over: back to the interrupted order.
local function resume(dude, s)
  local x, y = s.savedX, s.savedY
  Reaction.clear(dude)
  s.hysteresis = 4.0
  dude.temporaryStop = 0
  say(dude, CALLOUTS.secure)
  if x and y then runTo(dude, x, y) end
end

local function standOrRun(dude, s, threat, dist, standChance, runText)
  local cx, cy
  if not inCover(dude) then cx, cy = findCover(dude, threat) end
  if cx and randNbr(100) >= standChance then
    s.sprinting = true
    runTo(dude, cx, cy)
    floatyText(dude, runText)
    return false
  end
  s.sprinting = nil
  hold(dude)
  engage(dude, threat, dist)
  return true
end

-- ---------------------------------------------------------------------------

--- Once per frame for each of the player's soldiers.
function Reaction.update(dude, dt)
  if dude.faction ~= "allied" or (dude.dead or 0) == 1 or (dude.health or 0) <= 0 then return end
  local s = states[dude]

  if s and (s.hysteresis or 0) > 0 then s.hysteresis = s.hysteresis - dt end
  if (dude.confused or 0) > 0 or (dude.retreating or 0) > 0 or (dude.pinned or 0) > 0 or (dude.onFire or 0) > 0 then
    return
  end

  local moving = dude.targetx and dude.targety
    and (math.abs(dude.x - dude.targetx) > 12 or math.abs(dude.y - dude.targety) > 12)
  local active = s and s.active
  -- Standing still and not reacting: nothing to interrupt, nothing to look for.
  if not active and not moving then return end

  s = s or stateOf(dude)
  s.scanIn = s.scanIn - dt
  if s.scanIn <= 0 then
    s.scanIn = Reaction.SCAN_INTERVAL
    scan(dude, s)
  end
  local t = s.threat
  -- A unit seen at the last look may have died since.
  local visible = alive(t.visible) and t.visible or nil
  local near = alive(t.near) and t.near or nil
  local threat = visible or near
  local danger = dude.danger or 0
  local takingFire = danger >= 30 or (t.direct and visible ~= nil)

  if active then
    if s.retaliating then
      -- A veteran fires first, then decides.
      dude.temporaryStop = 2.0
      dude.targetx, dude.targety = dude.x, dude.y
      engage(dude, threat, t.visibleDist)
      s.retaliationTimer = s.retaliationTimer - dt
      if s.retaliationTimer <= 0 then
        s.retaliating, s.retaliationDone = nil, true
        if not threat and (t.nearCount or 0) == 0 then
          resume(dude, s)
        elseif not inCover(dude) then
          if standOrRun(dude, s, threat, t.visibleDist, 50, "Moving to better cover!") then
            floatyText(dude, "Hold the line! Engaging!")
          end
        end
      end
      return
    end

    if s.sprinting then
      local left = distanceCheck(dude.x, dude.y, dude.targetx or dude.x, dude.targety or dude.y)
      if left < 24 or inCover(dude) then
        s.sprinting = nil
        dude.temporaryStop = 2.0
        dude.pathQueue = nil
        if visible then engage(dude, visible, t.visibleDist) else face(dude, near) end
      end
      return
    end

    -- Halted: fight until nothing has been near for a while.
    dude.temporaryStop = 2.0
    if visible then engage(dude, visible, t.visibleDist) else face(dude, near) end
    if (near ~= nil) or takingFire or danger >= 20 then
      s.clearTimer = nil
    else
      s.clearTimer = (s.clearTimer or 4.0) - dt
      if s.clearTimer <= 0 then resume(dude, s) end
    end
    return
  end

  -- Moving, not yet reacting: does the enemy interrupt the order?
  if not (takingFire or visible) then return end
  if (s.hysteresis or 0) > 0 and not takingFire then return end

  s.savedX = s.savedX or dude.targetx
  s.savedY = s.savedY or dude.targety
  s.active = true
  s.clearTimer = nil

  local veteran = (dude.kills or 0) >= 1 or (dude.xp or 0) >= 15
  if veteran and not s.retaliationDone and threat then
    s.retaliating = true
    s.retaliationTimer = 1.6 + randNbr(8) / 10
    hold(dude)
    engage(dude, threat, t.visibleDist)
    say(dude, CALLOUTS.retaliate)
  else
    local standChance = 35
    if dude.spec == "gunner" or dude.spec == "sniper" or dude.bipod == 1 then
      standChance = 70
    elseif t.visibleDist < 180 then
      standChance = 60
    end
    if standOrRun(dude, s, threat, t.visibleDist, standChance, CALLOUTS.cover[randNbr(#CALLOUTS.cover)]) then
      if takingFire then
        floatyText(dude, "Taking fire! Return fire!")
      else
        say(dude, CALLOUTS.contact)
      end
    end
  end

  if spamTimer <= 0 then
    spamTimer = 2
    local sfx = _G["lineStop" .. randNbr(14)]
    if sfx then
      local clone = sfx:clone()
      clone:setVolume(stepScale(dude) / 2.0)
      clone:play()
    end
  end
end

Reaction._states = states -- for tests

return Reaction
