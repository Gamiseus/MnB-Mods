-- squad_tactics.lua
-- Squad Tactics: smarter group move orders, soldiers that react to contact while moving,
-- and a configurable squad size limit. The patches in qm.toml only call into this module.
--
-- For other mods (global SquadTactics):
--   SquadTactics.Move       the squad move planner (see smart_move.lua)
--   SquadTactics.Reaction   contact reactions: clear(dude), isActive(dude)
--   SquadTactics.squadLimit()

local SquadTactics = {}
_G.SquadTactics = SquadTactics

SquadTactics.Move = require "includes/smart_move"
SquadTactics.Reaction = require "includes/combat_reaction"

local MOD_ID = "squad_tactics"

local function raw(id)
  local s = QM and QM.settings and QM.settings[MOD_ID]
  return s and s[id]
end

local function on(id)
  local v = raw(id)
  if v == nil then return true end
  return v == true or v == 1
end

-- ---------------------------------------------------------------------------
-- Move orders
-- ---------------------------------------------------------------------------

--- Before the game hands out a move order: the soldiers about to receive it.
function SquadTactics.captureSelection()
  local batch = {}
  local troops = player.deployedTroops
  for i = 1, #troops do
    local t = troops[i]
    if t.selected and t.onFire <= 0 then batch[#batch + 1] = t end
  end
  return batch
end

--- After the game handed out the order (everyone sent to the click, plus or minus 100 px):
--- spread the group over positions that suit each soldier, and show where each is going.
function SquadTactics.afterMoveOrder(batch, x, y)
  if not batch then return end
  for i = 1, #batch do SquadTactics.Reaction.clear(batch[i]) end
  if #batch < 2 or not on("smart_move") then return end
  if player.landed ~= 1 or altMove ~= 0 then return end
  if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then return end

  -- Only soldiers the game really sent there: the order may not have gone out at all.
  local moved, ids = {}, {}
  for i = 1, #batch do
    local t = batch[i]
    if t.targetx and math.abs(t.targetx - x) <= 100 and math.abs(t.targety - y) <= 100 then
      moved[#moved + 1] = t
      ids[t.id] = true
    end
  end
  if #moved < 2 then return end

  if #moved >= 50 then
    -- Said before the work starts: if the game ever stalls here, the log shows it.
    print("[SquadTactics] placing a group of " .. #moved .. " soldiers")
  end
  SquadTactics.Move.assignSquadMoveOrder(moved, x, y)

  -- One destination marker per soldier, in place of the game's single one.
  local list = player.particles
  for i = #list, 1, -1 do
    if ids[list[i].faction] then table.remove(list, i) end
  end
  for i = 1, #moved do
    local t = moved[i]
    local dot = {}
    addParticle(dot, "moveDot", t.targetx, t.targety, math.rad(randNbr(360)))
    dot.faction = t.id
    list[#list + 1] = dot
  end
end

--- Halt (H): the soldier stays put, so there is no order to come back to.
function SquadTactics.onHalt(dude)
  SquadTactics.Reaction.clear(dude)
end

-- ---------------------------------------------------------------------------
-- Per soldier, per frame
-- ---------------------------------------------------------------------------

function SquadTactics.updateSoldier(dude, dt)
  -- The game sets temporaryStop but only some of its code counts it down.
  local stop = dude.temporaryStop or 0
  if stop > 0 then
    stop = stop - dt
    dude.temporaryStop = stop > 0 and stop or 0
  end
  if dude.onFire == 0 and on("combat_reactions") then
    SquadTactics.Reaction.update(dude, dt)
  end
end

-- ---------------------------------------------------------------------------
-- Squad size limit
-- ---------------------------------------------------------------------------

--- How many exposed soldiers the Germans tolerate before counter-assaults start.
--- math.huge when the limit is off. The game's own value is 6.
function SquadTactics.squadLimit()
  local v = raw("squad_limit")
  if v == nil then return 6 end
  local n = tonumber(v)
  if not n then return math.huge end -- "OFF"
  return n
end

--- The chance in 100 that the Germans' answer to an oversized squad goes on for another
--- round. The game uses the squad's size itself and keeps going while a 1-100 dice roll
--- comes up under it: with more than 100 soldiers under the player's command the roll is
--- always under, the loop never ends and the game locks up. Capped here.
SquadTactics.MAX_PRESSURE = 90
function SquadTactics.sizePressure()
  local n = squadSizer()
  if n > SquadTactics.MAX_PRESSURE then return SquadTactics.MAX_PRESSURE end
  return n
end

--- The text the game announces when the squad is over the limit, or nil for the game's own.
function SquadTactics.sizeWarning(limit)
  if limit == 6 then return nil end
  return "More than " .. tostring(limit) .. " troops have been detected by the Germans!! Use Camnets"
end

return SquadTactics
