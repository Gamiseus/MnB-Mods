-- perfkit_particles.lua
-- Particles, without replacing the game's particle file.
--
-- Three things live here:
--   1. Drawing. The game's two particle loops draw every particle, on screen or not, and
--      set the colour for each one. draw() skips what is off screen and only changes the
--      colour when the alpha changes. The result on screen is the game's.
--   2. Settled debris. A casing or a piece of rubble that has stopped moving looks the
--      same every frame until it expires, yet it is still updated and drawn each frame.
--      Settled debris is moved off the game's list onto a baked layer (see perfkit_layer),
--      and removed from the layer when its lifespan runs out or the broom is used.
--   3. A registry, so a mod can add a particle type with a few lines instead of patching
--      the game's 6,000-line addParticle. See register() and spawn().
--
-- The game's addParticle, particleUpdate and topParticleUpdate still run for every live
-- particle; they are wrapped, never rewritten.

local Layer = require "includes/perfkit_layer"

local floor = math.floor

local Particles = {}

-- Seconds between two looks for settled debris.
Particles.SETTLE_INTERVAL = 0.25
-- Debris with less than this many seconds left is not worth baking.
Particles.MIN_BAKE_LIFE = 3
-- A chunk is redrawn at most this often when debris in it expires.
Particles.EXPIRE_DELAY = 1.0

-- ---------------------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------------------

local defs = {}          -- typez -> definition
local anyCustomLive = false

-- Particles the game looks for by type after they have come to rest (a soldier picks
-- them up), or that do something when their lifespan ends. Never baked.
local keepLive = {
  intelPaper = true, intelMap = true, pamphletSmall = true,
  fragGrenade = true, contactGrenade = true, rifleGrenade = true, rocketGrenade = true,
  leuchtGrenade = true, stielgranate = true, flarePart = true, redFlarePart = true,
  muzzleFlash = true, bazookaFlash = true,
}
-- Sprites whose particle does something when its lifespan ends.
local keepLiveSprite = { flarePart = true, redFlarePart = true, kitchenSinkPart = true }

--- Adds a particle type.
-- def.setup(p, x, y, rotation)  fills in the particle. Every field already has a usable
--                               default (see baseline below); set what differs.
-- def.update(p, dt)             optional, every frame while the particle lives.
-- def.on_death(p)               optional, once, in the frame its lifespan runs out.
-- def.draw(p, image)            optional, draws it instead of the default.
-- def.top = true                optional, spawn() puts it on the top layer (above soldiers).
-- def.live = true               optional, never bake it as settled debris.
function Particles.register(typez, def)
  assert(type(typez) == "string" and typez ~= "", "Particles.register: a type name is needed")
  assert(type(def) == "table" and type(def.setup) == "function",
    "Particles.register: def.setup must be a function")
  defs[typez] = def
  if def.live or def.update or def.on_death or def.draw then
    keepLive[typez] = true
  end
end

--- Whether a mod registered this type.
function Particles.isRegistered(typez)
  return defs[typez] ~= nil
end

--- Stops a type from being baked as settled debris: for a game particle that your mod
--- looks for, moves or changes after it has come to rest.
function Particles.keepLive(typez)
  keepLive[typez] = true
end

-- The fields that the game's addParticle gives every particle, then the ones each of its
-- types sets, with neutral values.
local function baseline(p, typez, x, y, rotation)
  p.scale = 1
  p.targetx = nil
  p.targety = nil
  p.lob = 0
  p.targetRotation = rotation
  p.trail = ""
  p.faction = ""
  p.once = 0
  p.bounce = 0
  p.bounced = 0
  p.walled = 0
  p.wallImmune = 0
  p.shrink = 0
  p.replaceable = 0
  p.bounceAngle = 0
  p.waterSplash = false
  p.drift = 0
  p.immunity = 0
  p.sounded = 0
  p.typez = typez
  p.sprite = typez
  p.velocity = 0
  p.rotationz = rotation
  p.innerRotation = rotation
  p.spin = 0
  p.lifeSpan = 1
  p.nextFrame = ""
  p.x = x
  p.y = y
  p.drag = 0
  p.alpha = 255
  p.fade = 0
  p.expand = 0
  local img = _G[typez]
  if type(img) == "userdata" then
    p.xoffset, p.yoffset = img:getWidth() / 2, img:getHeight() / 2
  else
    p.xoffset, p.yoffset = 0, 0
  end
end

local origAddParticle, origUpdate, origTopUpdate

local function addParticle(particle, typez, x, y, rotation)
  local def = defs[typez]
  if not def then
    return origAddParticle(particle, typez, x, y, rotation)
  end
  if particle == nil then return end
  rotation = rotation or 0
  baseline(particle, typez, x, y, rotation)
  def.setup(particle, x, y, rotation)
  anyCustomLive = true
end

--- Creates a particle of any type, game or registered, and puts it on a list.
-- top: true for the top layer; nil uses the type's own `top`.
function Particles.spawn(typez, x, y, rotation, top)
  local p = {}
  _G.addParticle(p, typez, x, y, rotation or 0)
  if top == nil then
    local def = defs[typez]
    top = def and def.top or false
  end
  local list = top and player.topParticles or player.particles
  list[#list + 1] = p
  return p
end

local function runCustom(list, dt)
  local found = false
  for i = 1, #list do
    local p = list[i]
    local def = p and defs[p.typez]
    if def then
      found = true
      if def.update then def.update(p, dt) end
      if def.on_death and not p._pkDead and p.lifeSpan - dt < 0 then
        p._pkDead = true
        def.on_death(p)
      end
    end
  end
  return found
end

-- ---------------------------------------------------------------------------
-- Settled debris
-- ---------------------------------------------------------------------------

local layer = Layer.new()
local debris = {}        -- column -> array of settled particles
local nextExpiry = {}    -- column -> earliest expiry among its debris
local dirty = {}         -- column -> time left before its redraw
local clock = 0          -- particle time: advances only while the game updates particles
local settleTimer = 0
local lastList = nil
local debrisCount = 0
local batch = {}

local function describe(p)
  local img = _G[p.sprite]
  if type(img) ~= "userdata" then return nil end
  return img, p.x, p.y, p.innerRotation, 1, 1, p.xoffset, p.yoffset, p.alpha / 255
end

-- Settled: nothing about it changes any more except its lifespan.
local function settled(p)
  return p.velocity == 0 and p.spin == 0 and p.drift == 0
    and p.fade <= 0 and p.expand <= 0 and p.shrink == 0
    and p.immunity ~= 1 and p.targetx == nil
    -- The game ties some particles to a soldier through `faction` and removes them later.
    and (p.faction == "" or p.faction == 0)
    and p.lifeSpan > Particles.MIN_BAKE_LIFE
    and p.alpha > 0 and p.alpha <= 255
    and not keepLive[p.typez] and not keepLiveSprite[p.sprite]
    and type(_G[p.sprite]) == "userdata"
end

local function dropDebris()
  for k in pairs(debris) do debris[k] = nil end
  for k in pairs(nextExpiry) do nextExpiry[k] = nil end
  for k in pairs(dirty) do dirty[k] = nil end
  debrisCount = 0
  layer:reset()
end

-- Moves settled particles from the game's list to the baked layer, keeping the order of
-- the ones that stay.
local function settle(list)
  local n = #list
  local keep, nb = 0, 0
  for i = 1, n do
    local p = list[i]
    if settled(p) then
      nb = nb + 1
      batch[nb] = p
    else
      keep = keep + 1
      if keep ~= i then list[keep] = p end
    end
  end
  if nb == 0 then return end
  for i = keep + 1, n do list[i] = nil end

  layer:bake(batch, 1, nb, describe)
  for i = 1, nb do
    local p = batch[i]
    batch[i] = nil
    local col = floor(p.x / Layer.CHUNK_W)
    local d = debris[col]
    if not d then
      d = {}
      debris[col] = d
    end
    p._pkExpire = clock + p.lifeSpan
    d[#d + 1] = p
    if not nextExpiry[col] or p._pkExpire < nextExpiry[col] then
      nextExpiry[col] = p._pkExpire
    end
  end
  debrisCount = debrisCount + nb
end

-- Drops expired debris and redraws the chunks it was on.
local function expire(dt)
  for col, at in pairs(nextExpiry) do
    if clock >= at then
      local d = debris[col]
      local keep, soonest = 0, nil
      for i = 1, #d do
        local p = d[i]
        if p._pkExpire > clock then
          keep = keep + 1
          d[keep] = p
          if not soonest or p._pkExpire < soonest then soonest = p._pkExpire end
        end
      end
      debrisCount = debrisCount - (#d - keep)
      for i = keep + 1, #d do d[i] = nil end
      nextExpiry[col] = soonest
      for c = col - 1, col + 1 do
        if dirty[c] == nil then dirty[c] = Particles.EXPIRE_DELAY end
      end
    end
  end

  local due
  for col, left in pairs(dirty) do
    left = left - dt
    if left <= 0 then
      due = due or {}
      due[col] = true
      dirty[col] = nil
    else
      dirty[col] = left
    end
  end
  if not due then return end
  for col in pairs(due) do layer:clear(col) end
  -- Debris is filed under one column but may hang over into the next: redraw from the
  -- neighbours too.
  local done = {}
  for col in pairs(due) do
    for c = col - 1, col + 1 do
      local d = debris[c]
      if d and not done[c] then
        done[c] = true
        layer:bake(d, 1, #d, describe, due)
      end
    end
  end
end

--- Puts all baked debris back on the game's list, with the lifespan it has left.
function Particles.flush()
  if debrisCount == 0 then
    dropDebris()
    return
  end
  local list = player and player.particles
  for _, d in pairs(debris) do
    for i = 1, #d do
      local p = d[i]
      local left = p._pkExpire - clock
      p._pkExpire = nil
      if list and left > 0 then
        p.lifeSpan = left
        list[#list + 1] = p
      end
    end
  end
  dropDebris()
end

--- The broom removes every particle that is not immune; baked debris never is.
function Particles.onBroom()
  dropDebris()
end

local bakeEnabled = true

local function update(dt)
  if anyCustomLive then
    anyCustomLive = runCustom(player.particles, dt)
  end
  origUpdate(dt)

  local list = player.particles
  if list ~= lastList then
    -- A new battle or a loaded save: the old debris belongs to the old list.
    dropDebris()
    lastList = list
  end
  clock = clock + dt
  if not bakeEnabled then
    if debrisCount > 0 then Particles.flush() end
    return
  end
  settleTimer = settleTimer + dt
  if settleTimer >= Particles.SETTLE_INTERVAL then
    settleTimer = 0
    settle(list)
  end
  expire(dt)
end

local function topUpdate(dt)
  local top = player.topParticles
  local custom = false
  for i = 1, #top do
    if defs[top[i].typez] then custom = true break end
  end
  if custom then runCustom(top, dt) end
  origTopUpdate(dt)
end

--- Turns the baking of settled debris on or off. Off puts the debris back.
function Particles.setBaking(on)
  bakeEnabled = on and true or false
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local colorFromBytes

-- The game's own drawing of one particle.
local function drawOne(p, img, isTop)
  local g = love.graphics
  if isTop then
    g.draw(img, p.x, p.y, p.innerRotation, p.scale, p.scale, p.xoffset, p.yoffset)
    return false
  end
  local t = p.typez
  if t == "muzzleFlash" then
    -- Pass 1: bright core. Pass 2: halo, with the game's own colour call.
    g.setShader(muzzleFlashShader)
    g.setBlendMode("add")
    g.draw(img, p.x, p.y, p.innerRotation, p.scale, p.scale, p.xoffset, p.yoffset - 20)
    g.setShader()
    g.setColor(255, 230, 160, math.min(180, p.alpha))
    g.draw(img, p.x, p.y, p.innerRotation, p.scale * 1.1, p.scale * 1.1, p.xoffset, p.yoffset - 20)
    g.setBlendMode("alpha")
    return true -- the colour changed
  elseif t == "bazookaFlash" then
    g.draw(img, p.x, p.y, p.innerRotation, p.scale, p.scale, p.xoffset, p.yoffset - 20)
  elseif t == "flarePart" or t == "redFlarePart" then
    if randNbr(100) < 50 then
      local s = randNbr(15) / 10
      g.draw(img, p.x, p.y, math.rad(randNbr(360)), s, s, p.xoffset, p.yoffset)
    end
  else
    g.draw(img, p.x, p.y, p.innerRotation, p.scale, p.scale, p.xoffset, p.yoffset)
  end
  return false
end

--- Draws a particle list. Takes the place of the game's two particle loops.
-- cull: skip particles that are off screen.
function Particles.draw(list, isTop, cull)
  if not list then return end
  local g = love.graphics
  if not isTop and debrisCount > 0 then
    layer:draw(player.screenx or 0)
  end
  local n = #list
  if n == 0 then return end
  colorFromBytes = colorFromBytes or love.math.colorFromBytes

  local camX = player.screenx or 0
  local lastAlpha = nil
  for i = 1, n do
    local p = list[i]
    -- Off screen: further left or right than its own size could reach. Flares are kept:
    -- the game rolls dice for them every frame, and skipping them would shift its random
    -- numbers.
    local reach = 200 + 300 * (p.scale or 1)
    if not cull or (p.x > camX - reach and p.x < camX + 1280 + reach)
      or p.typez == "flarePart" or p.typez == "redFlarePart" then
      local img = _G[p.sprite]
      if img then
        local a = p.alpha
        if a ~= lastAlpha then
          g.setColor(colorFromBytes(255, 255, 255, a))
          lastAlpha = a
        end
        local def = defs[p.typez]
        if def and def.draw then
          def.draw(p, img)
          lastAlpha = nil
        elseif drawOne(p, img, isTop) then
          lastAlpha = nil
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------

--- Wraps the game's particle functions. Called once, when the game has loaded its files.
function Particles.install()
  if origAddParticle then return end
  origAddParticle = _G.addParticle
  origUpdate = _G.particleUpdate
  origTopUpdate = _G.topParticleUpdate
  _G.addParticle = addParticle
  _G.particleUpdate = update
  _G.topParticleUpdate = topUpdate
end

function Particles.stats()
  local chunks = 0
  for _ in pairs(layer.chunks) do chunks = chunks + 1 end
  return {
    live = player and player.particles and #player.particles or 0,
    top = player and player.topParticles and #player.topParticles or 0,
    baked = debrisCount,
    chunks = chunks,
  }
end

Particles._layer = layer -- for tests

return Particles
