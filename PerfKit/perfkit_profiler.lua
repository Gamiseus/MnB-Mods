-- perfkit_profiler.lua
-- A sampling profiler for the running game, on LuaJIT's built-in jit.profile.
--
-- While it runs, LuaJIT interrupts the game about once a millisecond and reports where it
-- is. Counting those reports says which functions and lines the time goes to, and how much
-- of it is spent in compiled code, in the interpreter, in the garbage collector and in
-- engine calls such as drawing. The cost while running is a few percent.
--
-- The report is written to Mods/qm/perfkit-profile.txt and summarised in the log.
--
-- Stopping LuaJIT's sampler (jit.profile.stop) froze the game when a profile finished, so
-- a finished profile no longer stops it. The report is built and saved first; the sampler
-- then stays on and its samples are thrown away until the next profile. An idle sampler
-- costs a fraction of a percent. Profiler.shutdown() really stops it, at your own risk.

local Profiler = {}

local ok_prof, prof = pcall(require, "jit.profile")
Profiler.available = ok_prof and type(prof) == "table"

local STACK_DEPTH = 24
local TOP = 30

local running = false   -- a profile is being taken
local sampling = false  -- LuaJIT's sampler is switched on (it stays on between profiles)
local MAX_STACKS = 20000
local stackCount = 0
local timeLeft = 0
local stacks, leafLines, states, total
local frames, frameTimes, drawCalls, batched
local startedAt = 0
local note = ""

local function onSample(thread, samples, vmstate)
  if not running then return end
  total = total + samples
  states[vmstate] = (states[vmstate] or 0) + samples
  -- One string per distinct call stack: "file:function;file:function;...", leaf first.
  local s = prof.dumpstack(thread, "pF;", STACK_DEPTH)
  local seen = stacks[s]
  if seen then
    stacks[s] = seen + samples
  elseif stackCount < MAX_STACKS then
    stackCount = stackCount + 1
    stacks[s] = samples
  end
  local l = prof.dumpstack(thread, "pl", 1)
  leafLines[l] = (leafLines[l] or 0) + samples
end

function Profiler.isRunning()
  return running
end

--- Starts profiling for `seconds` (default 10). `label` is written into the report.
function Profiler.start(seconds, label)
  if running then return false, "already running" end
  if not Profiler.available then return false, "jit.profile is not available" end
  stacks, leafLines, states, total = {}, {}, {}, 0
  stackCount = 0
  frames, frameTimes, drawCalls, batched = 0, {}, 0, 0
  timeLeft = seconds or 10
  note = label or ""
  startedAt = love.timer.getTime()
  if not sampling then
    prof.start("fi1", onSample)
    sampling = true
  end
  running = true
  return true
end

--- Switches LuaJIT's sampler off. Not called by PerfKit: in the game this call has frozen
--- the process. Use it only to test whether it still does.
function Profiler.shutdown()
  running = false
  if sampling then
    print("[PerfKit] stopping the sampler (jit.profile.stop)...")
    prof.stop()
    sampling = false
    print("[PerfKit] sampler stopped")
  end
end

local function sorted(counts)
  local list = {}
  for k, v in pairs(counts) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  return list
end

local function pct(n)
  return total > 0 and (100 * n / total) or 0
end

local STATE_NAMES = {
  N = "compiled Lua (JIT)",
  I = "interpreted Lua (not compiled)",
  C = "engine and C calls (drawing, audio, physics, file access)",
  G = "garbage collector",
  J = "JIT compiler at work",
}

local function count(list)
  return type(list) == "table" and #list or 0
end

local function buildReport(elapsed)
  local out = {}
  local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end

  -- Self time: the function at the top of the stack. Inclusive: every function on it.
  local selfT, incl = {}, {}
  for stack, n in pairs(stacks) do
    local first = true
    local seen = {}
    for fn in stack:gmatch("[^;]+") do
      if first then
        selfT[fn] = (selfT[fn] or 0) + n
        first = false
      end
      if not seen[fn] then
        seen[fn] = true
        incl[fn] = (incl[fn] or 0) + n
      end
    end
  end

  table.sort(frameTimes)
  local nf = #frameTimes
  local sum = 0
  for i = 1, nf do sum = sum + frameTimes[i] end
  local avg = nf > 0 and sum / nf or 0
  local p99 = nf > 0 and frameTimes[math.max(1, math.floor(nf * 0.99))] or 0
  local worst = nf > 0 and frameTimes[nf] or 0

  add("PerfKit profile%s", note ~= "" and (": " .. note) or "")
  add("%s, %.1f seconds, %d frames, %d samples", os.date("%Y-%m-%d %H:%M:%S"), elapsed, nf, total)
  add("")
  add("Frames: %.1f FPS average. Frame time %.2f ms average, %.2f ms at the 99th percentile, %.2f ms worst.",
    avg > 0 and 1 / avg or 0, avg * 1000, p99 * 1000, worst * 1000)
  add("Draw calls per frame: %.0f sent to the GPU, %.0f more merged into those by batching.",
    nf > 0 and drawCalls / nf or 0, nf > 0 and batched / nf or 0)
  if type(player) == "table" then
    add("In play at the end: %d soldiers, %d vehicles, %d particles, %d top particles, %d decals.",
      count(player.deployedTroops), count(player.deployedVehicles), count(player.particles),
      count(player.topParticles), count(player.deco))
  end
  add("")
  add("Where the time went, by kind:")
  for _, e in ipairs(sorted(states)) do
    add("  %5.1f%%  %s", pct(e[2]), STATE_NAMES[e[1]] or e[1])
  end
  add("")
  add("A large 'interpreted' share means the hot code is not being compiled. A large 'engine'")
  add("share points at drawing or other engine calls; see which functions make them below.")
  add("")
  add("Functions by their own time (time inside the function itself, not in what it calls):")
  local list = sorted(selfT)
  for i = 1, math.min(TOP, #list) do add("  %5.1f%%  %s", pct(list[i][2]), list[i][1]) end
  add("")
  add("Functions by total time (including everything they call):")
  list = sorted(incl)
  for i = 1, math.min(TOP, #list) do add("  %5.1f%%  %s", pct(list[i][2]), list[i][1]) end
  add("")
  add("Hottest lines:")
  list = sorted(leafLines)
  for i = 1, math.min(TOP, #list) do add("  %5.1f%%  %s", pct(list[i][2]), list[i][1]) end
  add("")
  add("Hottest call paths (innermost first):")
  list = sorted(stacks)
  for i = 1, math.min(12, #list) do
    add("  %5.1f%%  %s", pct(list[i][2]), (list[i][1]:gsub(";$", ""):gsub(";", "  <  ")))
  end
  return table.concat(out, "\n") .. "\n"
end

--- Ends the profile and writes the report. Returns the report text and the file path.
--- The sampler itself stays on, idle (see the top of this file).
function Profiler.stop()
  if not running then return nil end
  running = false -- from here on samples are thrown away
  print("[PerfKit] profile finished, building the report")
  local text = buildReport(love.timer.getTime() - startedAt)
  Profiler.lastReport = text

  local path
  local okq, qm = pcall(require, "qm")
  if okq and type(qm) == "table" and type(qm.mod_dir) == "string" then
    path = qm.mod_dir .. "/qm/perfkit-profile.txt"
    local f = io.open(path, "w")
    if f then
      f:write(text)
      f:close()
    else
      path = nil
    end
  end
  if not path then
    -- No QuarterMaster path: the game's save folder.
    pcall(love.filesystem.write, "perfkit-profile.txt", text)
    path = "perfkit-profile.txt (save folder)"
  end
  print("[PerfKit] Profile written to " .. path)
  -- The first part of the report goes to the log as well.
  local shown = 0
  for line in text:gmatch("[^\n]*") do
    shown = shown + 1
    if shown > 26 then break end
    if line ~= "" then print("[PerfKit] " .. line) end
  end
  return text, path
end

--- Once per frame while profiling.
function Profiler.frame(dt)
  if not running then return end
  frames = frames + 1
  frameTimes[frames] = dt
  local st = love.graphics.getStats()
  drawCalls = drawCalls + st.drawcalls
  batched = batched + (st.drawcallsbatched or 0)
  timeLeft = timeLeft - dt
  if timeLeft <= 0 then
    Profiler.stop()
    return true
  end
end

function Profiler.timeLeft()
  return running and timeLeft or 0
end

return Profiler
