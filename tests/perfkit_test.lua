-- Tests for PerfKit against a stub of LÖVE and of the game. No game needed:
--   lua tests/perfkit_test.lua        (from the MnB-Mods folder)

package.path = "PerfKit/?.lua;" .. package.path
for _, m in ipairs({ "perfkit_layer", "perfkit_decals", "perfkit_particles", "perfkit_atlas", "perfkit_profiler", "perfkit" }) do
  package.preload["includes/" .. m] = function() return dofile("PerfKit/" .. m .. ".lua") end
end

-- ---- stub LÖVE -------------------------------------------------------------
local draws = {}      -- every love.graphics.draw: { target = canvas or "screen", what = image }
local current = nil
local clears = 0
local dtNow = 1 / 60

local function image(name, w, h)
  return setmetatable({ name = name }, { __index = {
    getWidth = function() return w end, getHeight = function() return h end,
    getDimensions = function() return w, h end,
    typeOf = function(_, t) return t == "Image" end,
    release = function() end,
  } })
end
-- The modules test for userdata; make the stubs pass as such.
local realType = type
function type(v)
  if realType(v) == "table" and rawget(v, "__ud") then return "userdata" end
  return realType(v)
end
local function ud(t) t.__ud = true return t end

love = {
  timer = { getDelta = function() return dtNow end, getFPS = function() return 60 end, getTime = os.clock },
  filesystem = { write = function() return true end },
  math = { colorFromBytes = function(r, g, b, a) return r / 255, g / 255, b / 255, (a or 255) / 255 end },
  graphics = {
    newCanvas = function(w, h) return ud(image("canvas", w, h)) end,
    getCanvas = function() return current end,
    setCanvas = function(c) current = c end,
    clear = function() clears = clears + 1; if current then current.cleared = (current.cleared or 0) + 1 end end,
    draw = function(what, x, y, ...) draws[#draws + 1] = { target = current or "screen", what = what, x = x, y = y, args = { what, x, y, ... } } end,
    getShader = function() return nil end, setShader = function() end,
    getColor = function() return 1, 1, 1, 1 end, setColor = function() end,
    getBlendMode = function() return "alpha", "alphamultiply" end, setBlendMode = function() end,
    getScissor = function() end, setScissor = function() end,
    push = function() end, pop = function() end, origin = function() end,
    getStats = function() return { drawcalls = 0, drawcallsbatched = 0, texturememory = 0 } end,
    rectangle = function() end, print = function() end,
    getSystemLimits = function() return { texturesize = 16384 } end,
    newQuad = function(x, y, w, h) return ud({ x = x, y = y, w = w, h = h }) end,
  },
}

-- ---- stub game -------------------------------------------------------------
blood1 = ud(image("blood1", 40, 40))
shell = ud(image("shell", 8, 8))
intelPaper = ud(image("intelPaper", 20, 20))
spark = ud(image("spark", 10, 10))
function randNbr(n) return 1 end

player = { deco = {}, particles = {}, topParticles = {}, screenx = 0, screeny = 0 }

local vanillaAdds, vanillaUpdates = 0, 0
function addParticle(p, typez, x, y, rot)
  vanillaAdds = vanillaAdds + 1
  p.typez, p.sprite, p.x, p.y = typez, typez, x, y
  p.velocity, p.spin, p.drift, p.fade, p.expand, p.shrink = 0, 0, 0, 0, 0, 0
  p.immunity, p.lifeSpan, p.alpha, p.scale, p.faction = 0, 100, 255, 1, ""
  p.innerRotation, p.xoffset, p.yoffset = rot, 4, 4
end
-- The game's update, reduced to what matters here: lifespan and removal.
function particleUpdate(dt)
  vanillaUpdates = vanillaUpdates + 1
  for i = #player.particles, 1, -1 do
    local p = player.particles[i]
    p.lifeSpan = p.lifeSpan - dt
    if p.lifeSpan < 0 then table.remove(player.particles, i) end
  end
end
function topParticleUpdate(dt) end
local broomed = 0
function broomerButton()
  broomed = broomed + 1
  for i = #player.particles, 1, -1 do
    if player.particles[i].immunity ~= 1 then table.remove(player.particles, i) end
  end
  for i = #player.deco, 1, -1 do table.remove(player.deco, i) end
end

local PerfKit = require "includes/perfkit"
local Layer = require "includes/perfkit_layer"
local P, D = PerfKit.Particles, PerfKit.Decals

local passed = 0
local function check(cond, msg)
  if not cond then error("FAILED: " .. msg, 2) end
  passed = passed + 1
end
local function screenDraws()
  local n = 0
  for _, d in ipairs(draws) do if d.target == "screen" then n = n + 1 end end
  return n
end
local function canvasDraws()
  local n = 0
  for _, d in ipairs(draws) do if d.target ~= "screen" then n = n + 1 end end
  return n
end
local function reset() draws = {} end
local function decal(x) return { name = "blood1", x = x, y = 300, rotation = 0, size = 10 } end

-- ---- layer -----------------------------------------------------------------
do
  local c0, c1 = Layer.columns(1270, 30)
  check(c0 == 0 and c1 == 1, "a sprite across a chunk edge touches both chunks")
  check(Layer.reach(40, 40, 1, 1, 20, 20) > 28 and Layer.reach(40, 40, 1, 1, 20, 20) < 30, "reach is the half diagonal")
end

-- ---- decals ----------------------------------------------------------------
for i = 1, 5 do player.deco[i] = decal(100 * i) end
reset(); PerfKit.drawDecals()
check(canvasDraws() == 5, "each decal is stamped once")
check(screenDraws() == 1, "one chunk is drawn for five decals")
reset(); PerfKit.drawDecals()
check(canvasDraws() == 0 and screenDraws() == 1, "nothing is stamped again")

-- The game at its decal limit: one removed, one added, same count.
table.remove(player.deco, 1)
player.deco[#player.deco + 1] = decal(900)
reset(); PerfKit.drawDecals()
check(canvasDraws() == 1, "the new decal is stamped although the count is the same")
dtNow = 0.5
reset(); PerfKit.drawDecals()
check(canvasDraws() == 5, "the chunk that lost a decal is redrawn from the five left")
dtNow = 1 / 60
reset(); PerfKit.drawDecals()
check(canvasDraws() == 0, "and only once")

-- A decal across two chunks is in both.
player.deco[#player.deco + 1] = decal(1275)
reset(); PerfKit.drawDecals()
check(canvasDraws() == 2, "a decal on a chunk edge is stamped into both chunks")
check(D.stats().chunks == 2, "two chunks exist")

-- Option off: the game's loop, and the layer is dropped.
QM = { settings = { perfkit = { bake_decals = false } } }
reset(); PerfKit.drawDecals()
check(screenDraws() == #player.deco and canvasDraws() == 0, "with baking off every decal is drawn directly")
check(D.stats().chunks == 0, "and the canvases are released")
QM.settings.perfkit.bake_decals = 1
reset(); PerfKit.drawDecals()
check(canvasDraws() == #player.deco + 1, "turned back on, everything is stamped again")

-- A new battle replaces the list.
player.deco = { decal(50) }
reset(); PerfKit.drawDecals()
check(canvasDraws() == 1 and D.stats().decals == 1, "a new decal list starts over")

-- ---- particle registry -----------------------------------------------------
local p = P.spawn("shell", 10, 10, 0)
check(vanillaAdds == 1 and p.sprite == "shell", "a game type still goes to the game's addParticle")

local updates, deaths = 0, 0
P.register("spark", {
  setup = function(q) q.lifeSpan = 0.05; q.velocity = 5 end,
  update = function(q, dt) updates = updates + 1 end,
  on_death = function(q) deaths = deaths + 1 end,
})
check(P.isRegistered("spark") and not P.isRegistered("shell"), "isRegistered")
local s = P.spawn("spark", 20, 20, 1.5)
check(vanillaAdds == 1, "a registered type does not reach the game's addParticle")
check(s.typez == "spark" and s.sprite == "spark" and s.alpha == 255 and s.trail == "" and s.lob == 0
  and s.xoffset == 5 and s.lifeSpan == 0.05 and s.innerRotation == 1.5, "baseline fields plus setup")
check(#player.particles == 2, "spawn puts it on the list")
for _ = 1, 6 do particleUpdate(1 / 60) end
check(updates >= 3 and deaths == 1, "update runs each frame and on_death once (" .. updates .. ", " .. deaths .. ")")
check(#player.particles == 1, "the game removed the dead particle")
check(not pcall(P.register, "bad", {}), "register needs a setup function")

-- ---- settled debris --------------------------------------------------------
player.particles = {}
particleUpdate(1 / 60) -- notices the new list
local a = P.spawn("shell", 100, 100, 0)
local moving = P.spawn("shell", 200, 100, 0); moving.velocity = 30
local paper = P.spawn("intelPaper", 300, 100, 0)
local tied = P.spawn("shell", 400, 100, 0); tied.faction = 7
local b = P.spawn("shell", 500, 100, 0); b.lifeSpan = 10
local immune = P.spawn("shell", 600, 100, 0); immune.immunity = 1
reset()
for _ = 1, 20 do particleUpdate(1 / 60) end
check(P.stats().baked == 2, "two settled casings are baked (" .. P.stats().baked .. ")")
check(#player.particles == 4 and player.particles[1] == moving and player.particles[2] == paper
  and player.particles[3] == tied and player.particles[4] == immune,
  "moving, pickup, soldier-tied and immune particles stay, in order")
check(canvasDraws() == 2, "each baked casing is stamped once")
reset(); PerfKit.drawParticles(player.particles, false)
check(screenDraws() == 5, "one chunk plus the four live particles are drawn")

-- Off-screen particles are skipped.
moving.x = 9000
reset(); PerfKit.drawParticles(player.particles, false)
check(screenDraws() == 4, "an off-screen particle is not drawn")
QM.settings.perfkit.cull_particles = false
reset(); PerfKit.drawParticles(player.particles, false)
check(screenDraws() == 5, "unless culling is off")
QM.settings.perfkit.cull_particles = true
moving.x = 200

-- Expiry: b had 10 seconds.
for _ = 1, 60 * 12 do particleUpdate(1 / 60) end
check(P.stats().baked == 1, "the casing with 10 seconds left expired")

-- Flush puts debris back with the time it has left.
P.flush()
check(P.stats().baked == 0 and player.particles[#player.particles] == a, "flush returns debris to the game's list")
check(a.lifeSpan > 80 and a.lifeSpan < 90, "with its remaining lifespan (" .. a.lifeSpan .. ")")
check(a._pkExpire == nil, "and without the mod's bookkeeping field")

-- Baking off: nothing leaves the list.
QM.settings.perfkit.bake_debris = false
PerfKit.drawParticles(player.particles, false)
local before = #player.particles
for _ = 1, 30 do particleUpdate(1 / 60) end
check(P.stats().baked == 0 and #player.particles == before, "with baking off the list is untouched")
QM.settings.perfkit.bake_debris = true
PerfKit.drawParticles(player.particles, false)
for _ = 1, 30 do particleUpdate(1 / 60) end
check(P.stats().baked == 1, "and on again it is baked again")

-- The broom clears baked debris and redraws decals.
broomerButton()
check(broomed == 1 and P.stats().baked == 0, "the broom clears baked debris")
check(#player.particles == 1 and player.particles[1] == immune, "and the game's broom still ran")

-- keepLive
P.keepLive("shell")
local k = P.spawn("shell", 100, 100, 0)
for _ = 1, 30 do particleUpdate(1 / 60) end
check(P.stats().baked == 0, "a type marked keepLive is never baked")

-- Overlay and frame hook do not error.
PerfKit.toggleOverlay()
PerfKit.frame()

-- ---- atlas -----------------------------------------------------------------
local A = PerfKit.Atlas
backdrop = ud(image("backdrop", 1280, 720)) -- too large to pack
do
  -- Layout: nothing overlaps, and a full page starts the next one.
  local list = {}
  for i = 1, 40 do list[i] = { w = 100, h = 100 - i, name = "s" .. i } end
  local placed, npages = A._layout(list, 256)
  check(placed > 0 and placed < 40 and npages == 6, "sprites that do not fit on the allowed pages are left out (" .. placed .. ", " .. npages .. ")")
  for i = 1, placed do
    for j = i + 1, placed do
      local a, b = list[i], list[j]
      local apart = a.page ~= b.page or a.x + a.w + 1 <= b.x - 1 or b.x + b.w + 1 <= a.x - 1
        or a.y + a.h + 1 <= b.y - 1 or b.y + b.h + 1 <= a.y - 1
      if not apart then error("sprites " .. i .. " and " .. j .. " overlap") end
    end
  end
  passed = passed + 1
end

local plainDraw = love.graphics.draw
QM.settings.perfkit.atlas = true
PerfKit.frame()
check(A.stats().enabled and A.stats().sprites == 4 and A.stats().pages == 1,
  "the four small sprites are packed, the backdrop is not (" .. A.stats().sprites .. ")")
check(love.graphics.draw ~= plainDraw, "love.graphics.draw is wrapped")
reset(); love.graphics.draw(blood1, 10, 20, 0.5, 2, 2, 20, 20)
local d = draws[#draws]
check(d.what == A._map[blood1].tex and d.x == A._map[blood1].quad, "a packed sprite is drawn from its page with its quad")
reset(); love.graphics.draw(backdrop, 0, 0)
check(draws[1].what == backdrop, "an unpacked image is drawn as it is")
local someQuad = love.graphics.newQuad(0, 0, 4, 4)
reset(); love.graphics.draw(blood1, someQuad, 5, 5)
check(draws[1].what == blood1, "a draw that already has a quad is left alone")
love.graphics.setShader(ud({}))
reset(); love.graphics.draw(blood1, 10, 20)
check(draws[1].what == blood1, "under a shader the original image is drawn")
love.graphics.setShader()
reset(); love.graphics.draw(blood1, 10, 20)
check(draws[1].what ~= blood1, "and from the page again once the shader is off")

-- An image QuarterMaster shows at half its pixel size: the page draw is scaled to match.
QM.Sprites = {
  rawSize = function(img) if img == shell then return 16, 16 end return img:getWidth(), img:getHeight() end,
  scaleOf = function(img) if img == shell then return 0.5, 0.25 end return 1, 1 end,
}
A.reset(); PerfKit.frame()
check(A._map[shell].kx == 0.5 and A._map[shell].ky == 0.25 and A._map[shell].quad.w == 16,
  "the page holds the real pixels of a rescaled image")
reset(); love.graphics.draw(shell, 100, 100, 0, 2, 2, 4, 4)
local sd = draws[1]
check(sd.args[6] == 1 and sd.args[7] == 0.5 and sd.args[8] == 8 and sd.args[9] == 16,
  "and draws it scaled to its shown size, origin in real pixels")
QM.Sprites = nil

QM.settings.perfkit.atlas = false
PerfKit.frame()
check(not A.stats().enabled and A.stats().pages == 0, "turned off, the pages are released")
reset(); love.graphics.draw(blood1, 10, 20)
check(draws[1].what == blood1, "and sprites are drawn directly again")

-- ---- profiler --------------------------------------------------------------
local Prof = PerfKit.Profiler
if Prof.available then
  check(Prof.start(0.15, "test"), "the profiler starts")
  check(not Prof.start(1), "and refuses to start twice")
  local function burn() local x = 0 for i = 1, 200000 do x = x + math.sin(i) end return x end
  local done = false
  local t0 = os.clock()
  while not done and os.clock() - t0 < 5 do
    burn()
    done = Prof.frame(0.05) or false
  end
  check(done and not Prof.isRunning(), "it stops by itself when the time is up")
  local r = Prof.lastReport
  check(r:find("Functions by their own time", 1, true) and r:find("burn", 1, true),
    "the report names the function that used the time")
  check(r:find("FPS average", 1, true) and r:find("Hottest lines", 1, true), "and has frame times and lines")
  -- A second profile reuses the sampler, which was left on.
  check(Prof.start(0.1, "again"), "a second profile starts")
  t0 = os.clock()
  done = false
  while not done and os.clock() - t0 < 5 do burn(); done = Prof.frame(0.05) or false end
  check(done and Prof.lastReport:find("again", 1, true), "and reports under its own label")
  Prof.shutdown()
else
  print("perfkit_test: jit.profile not available here; profiler checks skipped")
end

print(string.format("perfkit_test: %d checks passed", passed))
