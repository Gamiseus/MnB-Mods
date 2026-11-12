-- perfkit_profiler.lua
-- Says where the frame time goes. The report is written to Mods/qm/perfkit-profile.txt
-- and summarised in the log.
--
-- Two ways of measuring:
--
--   "timing" (the default): every named function is timed on the way in and out
--   (perfkit_timing.lua). Runs on the game's own thread and cannot freeze it.
--
--   "sampling": LuaJIT's built-in sampler (jit.profile). It sees lines and functions held
--   in locals, and tells compiled from interpreted code. But it interrupts the game from a
--   second thread, and in this game that has frozen the process: once when the sampler
--   was stopped, once a few seconds after a profile while it was left running. The report
--   is saved before either can happen. Use it knowing that, and restart the game after.

local Profiler = {}

local Timing = require "includes/perfkit_timing"

local ok_prof, prof = pcall(require, "jit.profile")
Profiler.samplingAvailable = ok_prof and type(prof) == "table"
Profiler.available = true

local STACK_DEPTH = 24
local TOP = 30
-- The start of a timing profile is used to find the functions called too often: at least
-- this many frames and this long, so that the game's once-a-second work is seen too.
local CALIBRATION_FRAMES = 20
local CALIBRATION_SECONDS = 1.25

local running = false
local engine = "timing"
local timeLeft = 0
local frames, frameTimes, drawCalls, batched
local startedAt = 0
local note = ""

-- timing
local calibrating = false
local calibrated = 0
local timedFrames, timedSeconds = 0, 0

-- sampling
local sampling = false -- LuaJIT's sampler is switched on (it stays on between profiles)
local MAX_STACKS = 20000
local stackCount = 0
local stacks, leafLines, states, total

local function onSample(thread, samples, vmstate)
  if not running or engine ~= "sampling" then return end
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
--- `how` is "timing" (default) or "sampling"; see the top of this file.
function Profiler.start(seconds, label, how)
  if running then return false, "already running" end
  how = how or "timing"
  if how == "sampling" and not Profiler.samplingAvailable then
    return false, "jit.profile is not available"
  end
  engine = how
  frames, frameTimes, drawCalls, batched = 0, {}, 0, 0
  timeLeft = seconds or 10
  note = label or ""
  startedAt = love.timer.getTime()
  if engine == "sampling" then
    stacks, leafLines, states, total = {}, {}, {}, 0
    stackCount = 0
    if not sampling then
      prof.start("fi1", onSample)
      sampling = true
    end
  else
    Timing.start({ [Profiler] = true })
    calibrating = true
    calibrated = 0
    timedFrames, timedSeconds = 0, 0
  end
  running = true
  return true
end

--- Switches LuaJIT's sampler off. Not called by PerfKit: in the game this call has frozen
--- the process. Use it only to test whether it still does.
function Profiler.shutdown()
  if running and engine == "sampling" then running = false end
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

-- The six most common particle types on the two lists, as "name 1200, name 800".
local function particleKinds(...)
  local counts, names = {}, {}
  for k = 1, select("#", ...) do
    local list = select(k, ...)
    if type(list) == "table" then
      for i = 1, #list do
        local t = list[i].typez
        if t ~= nil then
          t = tostring(t)
          if not counts[t] then
            counts[t] = 0
            names[#names + 1] = t
          end
          counts[t] = counts[t] + 1
        end
      end
    end
  end
  if #names == 0 then return nil end
  table.sort(names, function(a, b)
    if counts[a] ~= counts[b] then return counts[a] > counts[b] end
    return a < b
  end)
  local parts = {}
  for i = 1, math.min(6, #names) do parts[i] = names[i] .. " " .. counts[names[i]] end
  return table.concat(parts, ", ")
end

-- The graphics card and processor, to compare reports from different computers.
local function machineLine()
  local parts = {}
  local g = love.graphics
  if g and g.getRendererInfo then
    local ok, _, _, _, device = pcall(g.getRendererInfo)
    if ok and device then parts[#parts + 1] = tostring(device) end
  end
  if love.system and love.system.getProcessorCount then
    local ok, n = pcall(love.system.getProcessorCount)
    if ok and n then parts[#parts + 1] = n .. " processor threads" end
  end
  if g and g.getDimensions then
    local ok, w, h = pcall(g.getDimensions)
    if ok and w then parts[#parts + 1] = string.format("window %d x %d", w, h) end
  end
  if #parts == 0 then return nil end
  return "Computer: " .. table.concat(parts, ", ") .. "."
end

-- The part both kinds of report start with. Returns the average frame time.
local function header(add, elapsed, kind)
  table.sort(frameTimes)
  local nf = #frameTimes
  local sum = 0
  for i = 1, nf do sum = sum + frameTimes[i] end
  local avg = nf > 0 and sum / nf or 0
  local p99 = nf > 0 and frameTimes[math.max(1, math.floor(nf * 0.99))] or 0
  local worst = nf > 0 and frameTimes[nf] or 0

  add("PerfKit profile (%s)%s", kind, note ~= "" and (": " .. note) or "")
  add("%s, %.1f seconds, %d frames", os.date("%Y-%m-%d %H:%M:%S"), elapsed, nf)
  add("")
  add("Frames: %.1f FPS average. Frame time %.2f ms average, %.2f ms at the 99th percentile, %.2f ms worst.",
    avg > 0 and 1 / avg or 0, avg * 1000, p99 * 1000, worst * 1000)
  add("Draw calls per frame: %.0f sent to the GPU, %.0f more merged into those by batching.",
    nf > 0 and drawCalls / nf or 0, nf > 0 and batched / nf or 0)
  if type(player) == "table" then
    add("In play at the end: %d soldiers, %d vehicles, %d particles, %d top particles, %d decals.",
      count(player.deployedTroops), count(player.deployedVehicles), count(player.particles),
      count(player.topParticles), count(player.deco))
    local kinds = particleKinds(player.particles, player.topParticles)
    if kinds then add("Most common particles: %s.", kinds) end
    local pk = rawget(_G, "PerfKit")
    if type(pk) == "table" and pk.Particles and pk.Particles.stats then
      add("Settled debris on the baked layer: %d.", pk.Particles.stats().baked)
    end
  end
  local machine = machineLine()
  if machine then add("%s", machine) end
  add("")
  return avg
end

local function timingReport(elapsed, data)
  local out = {}
  local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
  header(add, elapsed, "timing")

  local nf = math.max(1, timedFrames)
  local frame = timedSeconds / nf -- average seconds per timed frame
  local function share(t) return frame > 0 and 100 * (t / nf) / frame or 0 end

  local timed, counted = data.rows, data.heavy
  local ownSum, timedCalls = 0, 0
  for _, r in ipairs(timed) do
    ownSum = ownSum + r.own
    timedCalls = timedCalls + r.calls
  end

  add("%d functions watched over %d frames. Times are per frame; the share is of the frame time.", data.wrapped, timedFrames)
  add("")
  add("Own time (inside the function itself, without the timed functions it calls):")
  add("      ms   share    calls  function")
  table.sort(timed, function(a, b) return a.own > b.own end)
  for i = 1, math.min(TOP, #timed) do
    local r = timed[i]
    add("  %6.2f  %5.1f%%  %7.1f  %s", 1000 * r.own / nf, share(r.own), r.calls / nf, r.name)
  end
  add("")
  add("Total time (including everything the function calls):")
  add("      ms   share    calls  function")
  table.sort(timed, function(a, b) return a.total > b.total end)
  for i = 1, math.min(TOP, #timed) do
    local r = timed[i]
    add("  %6.2f  %5.1f%%  %7.1f  %s", 1000 * r.total / nf, share(r.total), r.calls / nf, r.name)
  end
  add("")
  if #counted > 0 then
    add("Called too often to time (counted in the first %.1f seconds, then left alone; their time is", CALIBRATION_SECONDS)
    add("in their caller's own time):")
    add("   calls per frame  function")
    table.sort(counted, function(a, b) return a.perFrame > b.perFrame end)
    for i = 1, math.min(TOP, #counted) do
      add("  %16.0f  %s", counted[i].perFrame, counted[i].name)
    end
    add("")
  end
  local slow = data.slowest
  if slow and #slow.top > 0 then
    add("Slowest frame: %.1f ms. Own time in it:", 1000 * slow.span)
    for _, e in ipairs(slow.top) do
      add("  %7.1f ms  %s", 1000 * e.own, e.name)
    end
    add("")
  end
  local outside = frame - ownSum / nf
  add("Outside every watched function: %.2f ms (%.1f%%). This is LÖVE's own loop: showing the",
    1000 * outside, frame > 0 and 100 * outside / frame or 0)
  add("frame, waiting for the display, sleeping.")
  local t = data.traces
  add("JIT compiler: %d traces compiled, %d attempts given up, %d times all compiled code was thrown away.",
    t.compiled, t.aborted, t.flushes)
  if t.flushes > 0 then
    add("  Compiled code being thrown away means the game outgrows LuaJIT's code cache and keeps recompiling.")
  end
  local cost = timedCalls * data.perTimed
  add("Measuring cost about %.2f ms per frame (%.0f ns per timed call).",
    1000 * cost / nf, data.perTimed * 1e9)
  add("Not seen: functions held only in a local, and single lines.")
  return table.concat(out, "\n") .. "\n"
end

local function samplingReport(elapsed)
  local out = {}
  local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
  local function pct(n) return total > 0 and (100 * n / total) or 0 end
  header(add, elapsed, "sampling")

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

  add("%d samples. Where the time went, by kind:", total)
  for _, e in ipairs(sorted(states)) do
    add("  %5.1f%%  %s", pct(e[2]), STATE_NAMES[e[1]] or e[1])
  end
  add("")
  add("The sampler itself makes the JIT compiler give up and retry, so its share is overstated.")
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
function Profiler.stop()
  if not running then return nil end
  running = false
  print("[PerfKit] profile finished, building the report")
  local elapsed = love.timer.getTime() - startedAt
  local text
  if engine == "sampling" then
    -- The sampler stays on, idle: stopping it has frozen the game (see the top of this file).
    text = samplingReport(elapsed)
  else
    text = timingReport(elapsed, Timing.finish())
  end
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
  if engine == "sampling" then
    print("[PerfKit] The sampler is still on. Restart the game before playing on: it has frozen the game before.")
  end
  return text, path
end

--- Once per frame while profiling. Returns true on the frame the profile ends.
function Profiler.frame(dt)
  if not running then return end
  frames = frames + 1
  frameTimes[frames] = dt
  local st = love.graphics.getStats()
  drawCalls = drawCalls + st.drawcalls
  batched = batched + (st.drawcallsbatched or 0)
  if engine == "timing" then
    if calibrating then
      calibrated = calibrated + dt
      if frames >= CALIBRATION_FRAMES and calibrated >= CALIBRATION_SECONDS then
        Timing.calibrate(frames)
        calibrating = false
      else
        Timing.calibrating(frames)
      end
      return -- the measured time starts after the calibration
    end
    Timing.mark()
    timedFrames = timedFrames + 1
    timedSeconds = timedSeconds + dt
  end
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
