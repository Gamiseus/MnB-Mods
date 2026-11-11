-- perfkit_decals.lua
-- Decal baking. The game draws every entry of player.deco every frame: blood, craters,
-- casings, rubble, thousands of draw calls late in a battle. Here each decal is drawn once
-- into a baked layer, and the layer is drawn instead.
--
-- The game stays in charge of player.deco: it adds, removes and caps decals exactly as in
-- vanilla. This module only watches the list.
--   * A decal it has not seen is stamped onto the layer.
--   * A decal that disappeared marks its chunk dirty; the chunk is redrawn shortly after.
-- Decals are compared by identity, so a decal added and another removed in the same frame
-- (which is what the game does at the decal limit) are both noticed.

local Layer = require "includes/perfkit_layer"

local floor = math.floor

local Decals = {}

-- How long a chunk may show a removed decal before it is redrawn, in seconds. Batches the
-- redraws when the game removes one old decal for every new one.
Decals.REBAKE_DELAY = 0.2

local layer = Layer.new()
local seen = setmetatable({}, { __mode = "k" }) -- decal -> the column it is counted in
local expected = {}                              -- column -> decals counted there
local present = {}                               -- scratch: column -> decals found this frame
local dirty = {}                                 -- column -> time left before its redraw
local lastList = nil
local lastCount = 0
local pendingFirst = nil                         -- scratch list of unseen decal indexes
local pending = {}

local function describe(d)
  local img = d and d.name and _G[d.name]
  if type(img) ~= "userdata" then return nil end
  local w, h = img:getDimensions()
  local s = (d.size or 10) / 10
  return img, d.x, d.y, d.rotation or 0, s, s, w / 2, h / 2, 1
end

local function forget()
  for k in pairs(seen) do seen[k] = nil end
  for k in pairs(expected) do expected[k] = nil end
  for k in pairs(dirty) do dirty[k] = nil end
  lastCount = 0
end

--- Throws the baked layer away; everything is drawn again on the next frame. Call it
--- after changing decals in place (moving one, or swapping its image).
function Decals.invalidate()
  layer:reset()
  forget()
  lastList = nil
end

local function markDirty(col, now)
  for c = col - 1, col + 1 do
    if dirty[c] == nil or now then
      dirty[c] = now and 0 or Decals.REBAKE_DELAY
    end
  end
end

-- Redraws the dirty chunks whose delay ran out, from the decals that touch them.
local function rebake(deco, n, dt)
  local due, any = nil, false
  for col, left in pairs(dirty) do
    left = left - dt
    if left <= 0 then
      due = due or {}
      due[col] = true
      dirty[col] = nil
      any = true
    else
      dirty[col] = left
    end
  end
  if not any then return end
  for col in pairs(due) do layer:clear(col) end
  layer:bake(deco, 1, n, describe, due)
end

-- One pass over the list: stamp the new decals, find the chunks that lost one.
local function sync(dt)
  local deco = player.deco
  if deco ~= lastList then
    -- A new battle or a loaded save: start over.
    layer:reset()
    forget()
    lastList = deco
  end
  local n = #deco

  for k in pairs(present) do present[k] = nil end
  local np = 0
  for i = 1, n do
    local d = deco[i]
    local col = seen[d]
    if col then
      present[col] = (present[col] or 0) + 1
    else
      np = np + 1
      pending[np] = d
    end
  end

  for col, want in pairs(expected) do
    local have = present[col] or 0
    if have < want then
      expected[col] = have
      markDirty(col)
    end
  end

  if np > 0 then
    layer:bake(pending, 1, np, describe)
    for i = 1, np do
      local d = pending[i]
      pending[i] = nil
      if type(d) == "table" then
        local col = floor((d.x or 0) / Layer.CHUNK_W)
        seen[d] = col
        expected[col] = (expected[col] or 0) + 1
      end
    end
  end

  rebake(deco, n, dt)
  lastCount = n
end

--- Draws the decals. Takes the place of the game's decal loop.
function Decals.draw(enabled)
  local deco = player and player.deco
  if not deco then return end
  if not enabled then
    if lastList then Decals.invalidate() end
    -- The game's own loop.
    for n = 1, #deco do
      local d = deco[n]
      local img = _G[d.name]
      love.graphics.draw(img, d.x, d.y, d.rotation, d.size / 10, d.size / 10,
        img:getWidth() / 2, img:getHeight() / 2)
    end
    return
  end
  sync(love.timer.getDelta())
  layer:draw(player.screenx or 0)
end

--- The broom removed decals: redraw without the delay.
function Decals.onBroom()
  for col in pairs(expected) do markDirty(col, true) end
end

--- Numbers for the debug overlay and tests.
function Decals.stats()
  local chunks = 0
  for _ in pairs(layer.chunks) do chunks = chunks + 1 end
  return { decals = lastCount, chunks = chunks }
end

Decals._layer = layer -- for tests

return Decals
