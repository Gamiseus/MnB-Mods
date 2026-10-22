-- ============================================================================
-- gdumper.lua - On-demand vanilla game file dumper for Mud and Blood
-- Part of GDumper Mod
--
-- Calls into the QuarterMaster injector (qm.dump_game_files), which reads the
-- ORIGINAL, UNPATCHED files straight out of the fused game archive (mnb.exe).
-- Because it reads the archive (not the in-memory patched buffers), the output
-- is always pristine vanilla code, regardless of which mods are installed.
--
-- Public API (global `GDumper`):
--   GDumper.dump(scope)      scope = "lua" | "assets" | "all"
--   GDumper.available()      true if the running injector supports dumping
--   GDumper.lastResult       { ok, count, path, scope, err, time }
-- ============================================================================

local GDumper = {}
_G.GDumper = GDumper

-- Scope definitions: output folder (relative to Mods/) + archive filter
GDumper.SCOPES = {
  lua    = { dir = "qm/game-dump",        filter = "lua", label = "Vanilla Lua scripts" },
  assets = { dir = "qm/game-dump-full",   filter = "*",   label = "Full game archive (scripts + assets)" },
}

GDumper.lastResult = nil

local function getQM()
  local ok, qm = pcall(require, "qm")
  if ok and type(qm) == "table" then return qm end
  return nil
end

function GDumper.available()
  local qm = getQM()
  return qm ~= nil and type(qm.dump_game_files) == "function"
end

-- Show feedback in-game (floating cue) when a match/menu is active, and always log it
local function notify(msg)
  print("[GDumper] " .. msg)
  if player and player.textCue then
    local cue = {}
    cue.name = msg
    cue.x = (player.screenx or 0) + 500
    cue.y = 300
    cue.alpha = 255
    player.textCue[#player.textCue + 1] = cue
  end
end

-- Write a small sidecar describing the dump so it is clear what the folder contains
local function writeInfoFile(path, scope, def, count)
  local f = io.open(path .. "/_DUMP_INFO.txt", "w")
  if not f then return end
  local qm = getQM()
  f:write("Mud and Blood - Vanilla Game File Dump\n")
  f:write("=======================================\n")
  f:write("Created:      " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  f:write("Scope:        " .. scope .. " (" .. def.label .. ")\n")
  f:write("Filter:       " .. def.filter .. "\n")
  f:write("Files:        " .. tostring(count) .. "\n")
  f:write("QuarterMaster " .. tostring(qm and qm.version or "?") .. "\n")
  f:write("Game version: " .. tostring(currentVersion or "?") .. "\n\n")
  f:write("These files were read directly from the game archive (mnb.exe).\n")
  f:write("They are the ORIGINAL vanilla files - no mod patches are applied.\n\n")
  f:write("Related QuarterMaster folders (automatic, created on every launch):\n")
  f:write("  qm/game-dump/  original copy of each file a mod patches\n")
  f:write("  qm/dump/       the PATCHED result of each file a mod patches (+ .json patch map)\n")
  f:close()
end

--- Dump vanilla files.
-- @param scope "lua" (default), "assets", or "all" (both)
-- @return ok, countOrError, path
function GDumper.dump(scope)
  scope = scope or "lua"

  if scope == "all" then
    local ok1, c1 = GDumper.dump("lua")
    local ok2, c2, p2 = GDumper.dump("assets")
    return ok1 and ok2, (tonumber(c1) or 0) + (tonumber(c2) or 0), p2
  end

  local def = GDumper.SCOPES[scope]
  if not def then
    notify("Unknown dump scope: " .. tostring(scope))
    return false, "unknown scope"
  end

  local qm = getQM()
  if not qm or type(qm.dump_game_files) ~= "function" then
    notify("Dump failed: injector does not support dumping (update winmm.dll)")
    return false, "unsupported injector"
  end

  local okCall, ok, countOrErr, path = pcall(qm.dump_game_files, def.dir, def.filter)
  if not okCall then
    notify("Dump failed: " .. tostring(ok))
    GDumper.lastResult = { ok = false, err = tostring(ok), scope = scope, time = os.time() }
    return false, tostring(ok)
  end

  if ok then
    writeInfoFile(path, scope, def, countOrErr)
    notify(string.format("Dumped %d files -> Mods/%s", countOrErr, def.dir))
  else
    notify("Dump failed: " .. tostring(countOrErr))
  end

  GDumper.lastResult = {
    ok = ok, count = ok and countOrErr or 0, err = (not ok) and countOrErr or nil,
    path = path, scope = scope, time = os.time(),
  }
  return ok, countOrErr, path
end

--- Hotkey handler. Ctrl+Shift+D = Lua scripts, Ctrl+Shift+Alt+D = full archive.
-- Returns true if the key was consumed.
function GDumper.onKeyPressed(key)
  if key ~= "d" then return false end
  local ctrl  = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  if not (ctrl and shift) then return false end
  local alt = love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
  GDumper.dump(alt and "assets" or "lua")
  return true
end

function GDumper.init()
  if GDumper.available() then
    print("[GDumper] Ready. Ctrl+Shift+D = dump vanilla Lua, Ctrl+Shift+Alt+D = dump full archive")
  else
    print("[GDumper] WARNING: running injector has no qm.dump_game_files - dumping disabled")
  end
end

return GDumper
