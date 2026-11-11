-- perfkit.lua
-- PerfKit: makes long battles cheaper to draw and update, without replacing any of
-- the game's files. Everything it changes can be switched off in Mod Settings.
--
-- For other mods (global PerfKit):
--   PerfKit.Particles.register(typez, def)   add a particle type
--   PerfKit.Particles.spawn(typez, x, y, rotation, top)
--   PerfKit.Particles.keepLive(typez)        never bake this type as settled debris
--   PerfKit.Decals.invalidate()              redraw the decal layer after changing decals in place
--   PerfKit.Profiler.start(seconds, label)   profile the game; the report goes to Mods/qm/
--   PerfKit.Atlas.reset()                    rebuild the atlas after replacing images at run time
-- See README.md.

local PerfKit = {}
_G.PerfKit = PerfKit

PerfKit.Decals = require "includes/perfkit_decals"
PerfKit.Particles = require "includes/perfkit_particles"
PerfKit.Atlas = require "includes/perfkit_atlas"
PerfKit.Profiler = require "includes/perfkit_profiler"

local MOD_ID = "perfkit"

-- A checkbox from Mod Settings. Stored as true/false or 1/0 depending on where it was set.
local function setting(id, default)
  local s = QM and QM.settings and QM.settings[MOD_ID]
  local v = s and s[id]
  if v == nil then return default end
  return v == true or v == 1
end
PerfKit.setting = setting

--- Takes the place of the game's decal loop (drawFiles.lua).
function PerfKit.drawDecals()
  PerfKit.Decals.draw(setting("bake_decals", true))
end

--- Takes the place of the game's two particle loops (drawFiles.lua).
function PerfKit.drawParticles(list, isTop)
  PerfKit.Particles.setBaking(setting("bake_debris", true))
  PerfKit.Particles.draw(list, isTop, setting("cull_particles", true))
end

-- ---------------------------------------------------------------------------
-- Overlay and log watch
-- ---------------------------------------------------------------------------

local overlay = false

function PerfKit.toggleOverlay()
  overlay = not overlay
end

local function cue(text)
  print("[PerfKit] " .. text)
  if type(player) == "table" and type(player.textCue) == "table" then
    player.textCue[#player.textCue + 1] = { name = text, x = (player.screenx or 0) + 600, y = 300, alpha = 255 }
  end
end

--- Profiles the next ten seconds and writes Mods/qm/perfkit-profile.txt.
function PerfKit.profile()
  local P = PerfKit.Profiler
  if P.isRunning() then
    P.stop()
    cue("Profile stopped. See Mods/qm/perfkit-profile.txt")
    return
  end
  local label = string.format("atlas %s, decal baking %s, debris baking %s, particle culling %s",
    setting("atlas", false) and "on" or "off", setting("bake_decals", true) and "on" or "off",
    setting("bake_debris", true) and "on" or "off", setting("cull_particles", true) and "on" or "off")
  local ok, why = P.start(10, label)
  cue(ok and "Profiling for 10 seconds..." or ("Cannot profile: " .. tostring(why)))
end

-- Warns once in a while when the log grows fast: usually a mod printing every frame, which
-- costs far more time than anything this mod saves. Debug mode only.
local watch = { timer = 0, size = nil, cooldown = 0, path = nil, checked = false }
local GROWTH = 250 * 1024 -- bytes in one interval
local INTERVAL = 2

local function logSize()
  if not watch.checked then
    watch.checked = true
    local ok, qm = pcall(require, "qm")
    if ok and type(qm) == "table" and qm.debug and type(qm.log_path) == "string" then
      watch.path = qm.log_path
    end
  end
  if not watch.path then return nil end
  local f = io.open(watch.path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

local function watchLog(dt)
  watch.timer = watch.timer + dt
  watch.cooldown = watch.cooldown - dt
  if watch.timer < INTERVAL then return end
  watch.timer = 0
  local size = logSize()
  if not size then return end
  if watch.size and size - watch.size > GROWTH and watch.cooldown <= 0 then
    watch.cooldown = 30
    print(string.format("[PerfKit] The log grew %d KB in %d seconds. Something is printing every frame.",
      (size - watch.size) / 1024, INTERVAL))
    if type(anounceStuff) == "function" then
      pcall(anounceStuff, "Log spam detected. See Mods/qm/log/latest.log")
    end
  end
  watch.size = size
end

--- Once per frame, from the game's draw (map coordinates).
function PerfKit.frame()
  local dt = love.timer.getDelta()
  watchLog(dt)
  PerfKit.Atlas.setEnabled(setting("atlas", false))
  if PerfKit.Profiler.frame(dt) then
    cue("Profile done. See Mods/qm/perfkit-profile.txt")
  end
  if not overlay then return end
  local g = love.graphics
  local st = g.getStats()
  local p = PerfKit.Particles.stats()
  local d = PerfKit.Decals.stats()
  local a = PerfKit.Atlas.stats()
  local text = string.format(
    "FPS %d   draw calls %d   batched %d\nparticles: %d live, %d top, %d baked (%d chunks)\ndecals: %d (%d chunks)\natlas: %s   texture memory %.0f MB%s",
    love.timer.getFPS(), st.drawcalls, st.drawcallsbatched or 0,
    p.live, p.top, p.baked, p.chunks, d.decals, d.chunks,
    a.enabled and string.format("%d sprites on %d pages", a.sprites, a.pages) or "off",
    st.texturememory / 1048576,
    PerfKit.Profiler.isRunning() and string.format("\nprofiling, %.0f s left", PerfKit.Profiler.timeLeft()) or "")
  local x, y = (player.screenx or 0) + 12, (player.screeny or 0) + 96
  local r, gr, b, a = g.getColor()
  g.setColor(0, 0, 0, 0.6)
  g.rectangle("fill", x - 6, y - 4, 430, PerfKit.Profiler.isRunning() and 94 or 76)
  g.setColor(1, 1, 1, 1)
  g.print(text, x, y)
  g.setColor(r, gr, b, a)
end

-- ---------------------------------------------------------------------------
-- Install. The game's files are loaded by the time this module is required.
-- ---------------------------------------------------------------------------

PerfKit.Particles.install()

if type(broomerButton) == "function" and not PerfKit._broom then
  local orig = broomerButton
  PerfKit._broom = orig
  function broomerButton(...)
    local a, b, c = orig(...)
    PerfKit.Particles.onBroom()
    PerfKit.Decals.onBroom()
    return a, b, c
  end
end

print("[PerfKit] ready")

return PerfKit
