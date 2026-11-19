-- combat_reaction.lua
-- React to contact: a player's soldier on a move order who sees the enemy stops, aims,
-- fires a couple of rounds, and carries on with the order.
--
-- The soldier is paused with the game's own temporaryStop, so the order, its destination
-- and Wayfinder's path all stay as they are; the game's own soldier code aims and fires.
-- This module only says when to pause, at whom to aim, and when the pause is over.
--
-- The state of each soldier is kept beside the soldier, not on it, so nothing extra goes
-- into save files.
--
-- Cost: a moving soldier looks for the enemy about five times a second, not every frame,
-- and checks line of sight to the few nearest enemies only. A soldier standing still
-- outside a reaction does not look at all.

local Reaction = {}

Reaction.SCAN_INTERVAL = 0.2   -- seconds between two looks, per soldier
Reaction.SIGHT_CHECKS = 4      -- line-of-sight checks per look, nearest enemies first
Reaction.SIGHT_RANGE = 600     -- infantry farther than this does not stop the soldier
Reaction.VEHICLE_RANGE = 650
Reaction.BURST = 2             -- rounds fired before moving on
Reaction.MAX_STOP = 5          -- seconds: the longest a stop lasts, fired or not
Reaction.COOLDOWN = 3          -- seconds of moving before the soldier stops again
Reaction.CALLOUT_QUIET = 10    -- seconds without contact before the next contact is called out

local CALLOUTS = { "Contact!", "Enemy sighted!", "Contact front!", "Engaging!", "Hostiles spotted!" }

local states = setmetatable({}, { __mode = "k" })

local function stateOf(dude)
  local s = states[dude]
  if not s then
    -- Spread the looks of a squad over different frames.
    s = { scanIn = ((dude.id or 0) % 10) * Reaction.SCAN_INTERVAL / 10, cooldown = 0, quiet = Reaction.CALLOUT_QUIET }
    states[dude] = s
  end
  return s
end

local function alive(u)
  return u ~= nil and (u.dead or 0) == 0 and (u.health or 0) > 10
end

-- Whether the unit is still on the map: the game removes the dead from its lists.
local function present(unit, vehicle)
  local list = vehicle and player.deployedVehicles or player.deployedTroops
  local find = vehicle and convertedId2 or convertedId
  if find then
    local k = find(unit.id)
    return k ~= nil and k > 0 and list[k] == unit
  end
  for i = 1, #list do
    if list[i] == unit then return true end
  end
  return false
end

local function moving(dude)
  return dude.targetx and dude.targety
    and (math.abs(dude.x - dude.targetx) > 12 or math.abs(dude.y - dude.targety) > 12)
end

-- Rounds in the gun: what each shot takes one from.
local function rounds(dude)
  local w = dude.weapon
  if not w then return 0 end
  if w.class == "atRifle" then return tonumber(dude.atRifleShot) or 0 end
  return tonumber(w.ammo) or 0
end

local function canShoot(dude)
  local w = dude.weapon
  return w ~= nil and (w.jammed or 0) ~= 1 and rounds(dude) > 0
end

--- Ends the soldier's stop, if any; the order goes on. For a new order or Halt.
function Reaction.clear(dude)
  local s = states[dude]
  if not s or not s.active then return end
  s.active, s.target, s.vehicle, s.timer, s.fired, s.lastRounds = nil, nil, nil, nil, nil, nil
  dude.temporaryStop = 0
end

--- Whether the soldier is stopped to fire right now.
function Reaction.isActive(dude)
  local s = states[dude]
  return s ~= nil and s.active == true
end

-- ---------------------------------------------------------------------------
-- Looking for the enemy
-- ---------------------------------------------------------------------------

local candidates = {}

local function byDistance(a, b) return a.d < b.d end

local function add(n, unit, d, vehicle)
  local c = candidates[n]
  if not c then
    c = {}
    candidates[n] = c
  end
  c.unit, c.d, c.vehicle = unit, d, vehicle
end

-- The nearest enemy the soldier can see: unit, distance, whether it is a vehicle.
local function nearestVisible(dude)
  local n = 0
  local troops = player.deployedTroops
  for o = 1, #troops do
    local e = troops[o]
    if e.faction == "axis" and alive(e) then
      local d = distanceCheck2(dude, e)
      if d <= Reaction.SIGHT_RANGE
        and not ((e.flagged or 0) <= 0 and (hasBuffByTag("stealth", e) or hasBuffByTag("camo", e))) then
        n = n + 1
        add(n, e, d, false)
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
          n = n + 1
          add(n, v, d, true)
        end
      end
    end
  end
  for i = n + 1, #candidates do candidates[i] = nil end
  if n == 0 then return nil end
  table.sort(candidates, byDistance)
  for i = 1, math.min(n, Reaction.SIGHT_CHECKS) do
    local c = candidates[i]
    if los2(dude, c.unit) then return c.unit, c.d, c.vehicle end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Stop, aim, fire
-- ---------------------------------------------------------------------------

-- Points the game's firing code at the unit. The game fires when aim is 1 and targetPointer
-- names a unit in sight; semi-automatic and automatic weapons also need rounds left in the
-- burst (currentROF).
local function aimAt(dude, unit, vehicle)
  dude.targetPointer = unit.id
  dude.vehicleTarget = vehicle and 1 or 0
  dude.targetDistance = distanceCheck2(dude, unit)
  dude.aim = 1
  local action = dude.weapon and dude.weapon.action
  if (action == "semi" or action == "auto") and (dude.currentROF or 0) <= 0 then
    dude.currentROF = Reaction.BURST
  end
  dude.rotation = math.atan2(dude.y - unit.y, dude.x - unit.x) + 1.5707
end

-- The game's time to bring a weapon up: heavier weapons take longer.
local function aimTime(dude)
  local bulk = (dude.weapon and tonumber(dude.weapon.bulk)) or 10
  local t = ((bulk / 10) + (randNbr(30) / 10) + 0.1) / 2
  return t * (100 - (tonumber(dude.bulkBonus) or 0)) / 100
end

local function stop(dude, s, unit, vehicle)
  s.active, s.target, s.vehicle = true, unit, vehicle
  s.timer, s.fired, s.lastRounds = Reaction.MAX_STOP, 0, rounds(dude)
  dude.temporaryStop = 1
  if dude.bipod == 1 or (dude.primarySwap or "") ~= "" then dude.state = "proneAim" else dude.state = "aim" end
  aimAt(dude, unit, vehicle)
  dude.actionTimer = math.min(tonumber(dude.actionTimer) or 0, aimTime(dude))

  if s.quiet >= Reaction.CALLOUT_QUIET then
    floatyText(dude, CALLOUTS[randNbr(#CALLOUTS)])
    if (spamTimer or 0) <= 0 then
      spamTimer = 2
      local sfx = _G["lineStop" .. randNbr(14)]
      if sfx then
        local clone = sfx:clone()
        clone:setVolume(stepScale(dude) / 2.0)
        clone:play()
      end
    end
  end
  s.quiet = 0
end

local function carryOn(dude, s)
  Reaction.clear(dude)
  s.cooldown = Reaction.COOLDOWN
  s.scanIn = Reaction.SCAN_INTERVAL
end

-- ---------------------------------------------------------------------------

--- Once per frame for each of the player's soldiers.
function Reaction.update(dude, dt)
  if dude.faction ~= "allied" then return end
  local s = states[dude]
  if s then
    if s.cooldown > 0 then s.cooldown = s.cooldown - dt end
    if not s.active then s.quiet = s.quiet + dt end
  end

  -- The game's own reactions come first: a soldier who is down, pinned, panicking or on
  -- fire is the game's to move.
  local busy = (dude.dead or 0) == 1 or (dude.health or 0) <= 10 or (dude.confused or 0) > 0
    or (dude.retreating or 0) > 0 or (dude.pinned or 0) > 0 or (dude.onFire or 0) > 0

  if s and s.active then
    if busy then return carryOn(dude, s) end
    local now = rounds(dude)
    if now < s.lastRounds then s.fired = s.fired + (s.lastRounds - now) end
    s.lastRounds = now
    s.timer = s.timer - dt
    if s.fired >= Reaction.BURST or s.timer <= 0 or not moving(dude) then
      return carryOn(dude, s)
    end
    s.scanIn = s.scanIn - dt
    local gone = not alive(s.target)
    if not gone and s.scanIn <= 0 then
      s.scanIn = Reaction.SCAN_INTERVAL
      gone = not present(s.target, s.vehicle)
    end
    if gone then
      -- Target down before the burst was out: the next one in sight, or move on.
      local unit, _, vehicle = nearestVisible(dude)
      if not unit then return carryOn(dude, s) end
      s.target, s.vehicle = unit, vehicle
      aimAt(dude, unit, vehicle)
    elseif dude.aim ~= 1 or dude.targetPointer ~= s.target.id then
      -- The game let go of the target (a bolt cycled, a burst ended): aim again.
      aimAt(dude, s.target, s.vehicle)
    end
    dude.temporaryStop = 1
    return
  end

  if busy or not moving(dude) then return end
  s = s or stateOf(dude)
  s.scanIn = s.scanIn - dt
  if s.scanIn > 0 then return end
  s.scanIn = Reaction.SCAN_INTERVAL
  if s.cooldown > 0 or not canShoot(dude) then return end

  local unit, _, vehicle = nearestVisible(dude)
  if unit then stop(dude, s, unit, vehicle) end
end

Reaction._states = states -- for tests

return Reaction
