-- perfkit_near.lua
-- "How many soldiers are near this one?" without walking the whole army.
--
-- The game answers that by looking at every soldier on the map, for every soldier that
-- asks: with 3,000 soldiers that is millions of distance checks a frame. Here the soldiers
-- are sorted once per frame into columns of the map, per faction, and a question only
-- looks at the columns within reach, in the factions it is about.
--
-- The answers are the game's, with one limit: the sorting is from the start of the frame.
-- A soldier who was added or removed is seen at once (the list's length changed, so it is
-- sorted again), health, faction and position are read live, and each column check allows
-- for movement within the frame. A soldier who changes sides is found on his new side
-- from the next frame.
--
-- Unlike the game's distanceCheck2 this does not set the globals shotdistance, shotabsx
-- and shotabsy; nothing reads them after these counts.

local Near = {}

local floor, sqrt, abs = math.floor, math.sqrt, math.abs

-- Width of a column in pixels.
Near.CELL = 256
-- How far a soldier may have moved since the frame began and still be found.
Near.MARGIN = 96
-- At most this many re-sorts in one frame when the list keeps changing length.
Near.MAX_REBUILDS = 16
-- Without a frame signal (newFrame is called from the game's draw) the sorting is still
-- redone after this many seconds.
Near.MAX_AGE = 0.25
-- Set from the option each frame; the patched game functions use their own loop when off.
Near.on = true

local NO_FACTION = {} -- stands in for a soldier without a faction
local NOBODY = {}     -- an id no soldier has

local frameNo = 0
local builtFrame, builtList, builtCount, builtAt = -1, nil, -1, 0
local rebuilds = 0
local nFactions = 0
local facKey, facCells, facOrder = {}, {}, {}
local facOf = {}
local facMin, facMax = {}, {} -- the lowest and highest column a faction has soldiers in
local indexOfId = {}

local function rebuild(list)
  nFactions = 0
  facOf = {}
  indexOfId = {}
  local n = #list
  for i = 1, n do
    local s = list[i]
    local id = s.id
    if id ~= nil and indexOfId[id] == nil then indexOfId[id] = i end
    local x = s.x
    if x ~= nil then
      local key = s.faction
      if key == nil then key = NO_FACTION end
      local k = facOf[key]
      if not k then
        nFactions = nFactions + 1
        k = nFactions
        facOf[key] = k
        facKey[k] = key
        facCells[k] = {}
        facOrder[k] = {}
        facMin[k], facMax[k] = nil, nil
      end
      local cells, orders = facCells[k], facOrder[k]
      local c = floor(x / Near.CELL)
      if not facMin[k] or c < facMin[k] then facMin[k] = c end
      if not facMax[k] or c > facMax[k] then facMax[k] = c end
      local cell = cells[c]
      if not cell then
        cell = {}
        cells[c] = cell
        orders[c] = {}
      end
      local at = #cell + 1
      cell[at] = s
      orders[c][at] = i -- its place in the game's list, for "the first one"
    end
  end
  for k = nFactions + 1, #facKey do facKey[k], facCells[k], facOrder[k] = nil, nil, nil end
  if builtFrame ~= frameNo then rebuilds = 0 end
  rebuilds = rebuilds + 1
  builtFrame, builtList, builtCount = frameNo, list, n
  builtAt = love.timer.getTime()
end

local function ensure()
  local list = player.deployedTroops
  if builtFrame ~= frameNo or builtList ~= list
    or (builtCount ~= #list and rebuilds < Near.MAX_REBUILDS)
    or love.timer.getTime() - builtAt > Near.MAX_AGE then
    rebuild(list)
  end
  return list
end

--- Once per frame: the next question sorts the soldiers again.
function Near.newFrame()
  frameNo = frameNo + 1
end

--- How many living soldiers of another faction are within `radius` of `dude`, not counting
--- `dude` himself: the game's enemyNearby (600), friendliesCloseToTarget (30) and enemyCqc
--- (30). `each`, if given, is called with every soldier counted.
function Near.count(dude, radius, each)
  ensure()
  local x, y = dude.x, dude.y
  if x == nil then return 0 end -- the game's distance check answers "far away" here
  local faction, id = dude.faction, dude.id
  local own = faction
  if own == nil then own = NO_FACTION end
  local reach = radius + Near.MARGIN
  local c1, c2 = floor((x - reach) / Near.CELL), floor((x + reach) / Near.CELL)
  local n = 0
  for k = 1, nFactions do
    if facKey[k] ~= own then
      local cells = facCells[k]
      for c = c1, c2 do
        local cell = cells[c]
        if cell then
          for j = 1, #cell do
            local s = cell[j]
            if s.faction ~= faction and s.health > 10 and s.id ~= id then
              local ax, ay = abs(x - s.x), abs(y - s.y)
              if sqrt(ax * ax + ay * ay) < radius then
                n = n + 1
                if each then each(s) end
              end
            end
          end
        end
      end
    end
  end
  return n
end

-- Living soldiers of the faction `faction` within `radius` of x, y, leaving out the one
-- with id `id`. Also the one that comes first in the game's list.
local function ofFaction(x, y, id, radius, faction)
  local key = faction
  if key == nil then key = NO_FACTION end
  local k = facOf[key]
  if not k then return 0, nil end
  local cells, orders = facCells[k], facOrder[k]
  local reach = radius + Near.MARGIN
  local n, first, firstAt = 0, nil, nil
  for c = floor((x - reach) / Near.CELL), floor((x + reach) / Near.CELL) do
    local cell = cells[c]
    if cell then
      local order = orders[c]
      for j = 1, #cell do
        local s = cell[j]
        if s.faction == faction and s.health > 10 and s.id ~= id then
          local ax, ay = abs(x - s.x), abs(y - s.y)
          if sqrt(ax * ax + ay * ay) < radius then
            n = n + 1
            local at = order[j]
            if not firstAt or at < firstAt then first, firstAt = s, at end
          end
        end
      end
    end
  end
  return n, first
end

--- How many living soldiers of the faction named `faction` are within `radius` of `dude`,
--- not counting `dude`: the game's axisNearby, alliedNearby, alliedAround and
--- alliedCloseBy.
function Near.countOf(dude, radius, faction)
  ensure()
  if dude.x == nil then return 0 end
  return (ofFaction(dude.x, dude.y, dude.id, radius, faction))
end

--- The same for `dude`'s own faction: the game's friendlyNearby and friendlyNearby2.
--- Also returns the first such soldier in the game's list (checkObstruction names him).
function Near.countOwn(dude, radius)
  ensure()
  if dude.x == nil then return 0, nil end
  return ofFaction(dude.x, dude.y, dude.id, radius, dude.faction)
end

--- How many living soldiers of any faction are within `radius` of `dude`, `dude` himself
--- included if he is alive: the game's soldierNearby.
function Near.countAll(dude, radius)
  ensure()
  local x, y = dude.x, dude.y
  if x == nil then return 0 end
  local n = 0
  for k = 1, nFactions do
    n = n + ofFaction(x, y, NOBODY, radius, facKey[k] ~= NO_FACTION and facKey[k] or nil)
  end
  return n
end

--- Where the soldier with this id is in the game's list, or nil when he has to be looked
--- for (the game's convertedId then walks the list).
function Near.indexOf(id)
  if id == nil then return nil end
  local list = ensure()
  local i = indexOfId[id]
  if i then
    local s = list[i]
    if s and s.id == id then return i end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- The AI's whole-army walks
-- ---------------------------------------------------------------------------

--- The game's alliedFrontLine: how far east a living, flagged Allied soldier (not one on
--- the bridge) has got. nil when there is none past 100; the game's own function then
--- goes on to unflagged soldiers and vehicles.
function Near.alliedFront()
  ensure()
  local k = facOf.allied
  if not k then return nil end
  local hi, lo = facMax[k], facMin[k]
  if not hi or hi - lo > 4096 then return nil end
  local cells = facCells[k]
  local front = 100
  for c = hi, lo, -1 do
    -- Nobody sorted into this column or a lower one can have got this far.
    if (c + 1) * Near.CELL + Near.MARGIN <= front then break end
    local cell = cells[c]
    if cell then
      for j = 1, #cell do
        local s = cell[j]
        if s.health > 0 and s.faction == "allied" and s.flagged > 0 and s.bridgeSoldier == 0
          and s.x > front then
          front = s.x
        end
      end
    end
  end
  if front > 100 then return front end
  return nil
end

local candidate, candidateAt = {}, {}

--- The game's closestflaggedEnemy: the id of the nearest flagged enemy that `dude` can
--- see, -1 for none. The game checks the line of sight to every enemy that is nearer than
--- the nearest seen so far, in list order; here the enemies are tried nearest first, so
--- the first one seen is the answer. Of two at the same distance the first in the list
--- wins, as in the game.
function Near.closestFlagged(dude)
  local list = player.deployedTroops
  local faction, id = dude.faction, dude.id
  local x, y = dude.x, dude.y
  local cn = 0
  for i = 1, #list do
    local s = list[i]
    if s.flagged > 0 and s.stealth <= 0 and s.faction ~= faction and s.health > 10 and s.id ~= id then
      local d
      local sx = s.x
      if x ~= nil and sx ~= nil then
        local ax, ay = abs(x - sx), abs(y - s.y)
        d = sqrt(ax * ax + ay * ay)
      else
        d = distanceCheck2(dude, s)
      end
      if d < 9999999 then
        cn = cn + 1
        candidate[cn], candidateAt[cn] = s, d
      end
    end
  end
  local found = -1
  while true do
    local best, bestAt = 0, 9999999
    for j = 1, cn do
      local d = candidateAt[j]
      if d < bestAt then best, bestAt = j, d end
    end
    if best == 0 then break end
    if los2(dude, candidate[best]) then
      found = candidate[best].id
      break
    end
    candidateAt[best] = math.huge
  end
  for j = 1, cn do candidate[j] = nil end
  return found
end

-- How many soldiers hold the "Original Six" award.
local ogFrame, ogList, ogCount, ogAt, ogHave = -1, nil, -1, 0, 0

--- The game's numberOfOGs, which it asks before every shot by walking every soldier's
--- awards. Counted once per frame, and again when an award is given.
function Near.originals()
  local list = player.deployedTroops
  local n = #list
  if ogFrame ~= frameNo or ogList ~= list or ogCount ~= n
    or love.timer.getTime() - ogAt > Near.MAX_AGE then
    local have = 0
    for i = 1, n do
      if hasAward(list[i], "Original Six") then have = have + 1 end
    end
    ogHave = have
    ogFrame, ogList, ogCount, ogAt = frameNo, list, n, love.timer.getTime()
  end
  return ogHave
end

--- An award was given: count again.
function Near.awardGiven()
  ogFrame = -1
end

-- Which decal names are on the map this frame.
local namesFrame, namesList, namesCount, namesAt, names = -1, nil, -1, 0, {}

--- Whether a decal of this name is on the map. A decal that appears in the very frame
--- another one is removed can go unseen until the next frame.
function Near.decalNamed(name)
  local list = player.deco
  local n = #list
  if namesFrame ~= frameNo or namesList ~= list or namesCount ~= n
    or love.timer.getTime() - namesAt > Near.MAX_AGE then
    names = {}
    for i = 1, n do
      local nm = list[i].name
      if nm ~= nil then names[nm] = true end
    end
    namesFrame, namesList, namesCount, namesAt = frameNo, list, n, love.timer.getTime()
  end
  return names[name] == true
end

--- What the game's enemyCqc does to each enemy in reach: a soldier in stealth is revealed,
--- unless he is a commando.
function Near.reveal(s)
  if hasBuffByTag("stealth", s) then
    if s.spec ~= "commando" then
      unstealth(s)
    end
  end
end

function Near.stats()
  return { factions = nFactions, rebuilds = rebuilds, frame = frameNo }
end

return Near
