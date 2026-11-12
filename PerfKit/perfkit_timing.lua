-- perfkit_timing.lua
-- Times the game's functions without a second thread.
--
-- While a profile runs, every Lua function reachable by name (globals, and functions in
-- global tables two levels down, such as love.update or pathfinding.requestPathAsync) is
-- swapped for a wrapper that reads a clock on the way in and out. From that come each
-- function's own time, its time including what it calls, and how often it is called.
--
-- A function called very often would be slowed badly by a wrapper, and the game with it.
-- So the profile starts with a short calibration in which calls are only counted; the
-- functions called most are then put back at once and left alone (their time shows up in
-- their caller's own time), and timing starts for the rest. When the profile ends every
-- function is put back.
--
-- Not seen: functions held only in a `local`, and lines inside a function.

local Timing = {}

-- Functions called more often than this per frame are counted, not timed.
Timing.HEAVY_CALLS = 1500
-- How deep to look into global tables for functions.
Timing.DEPTH = 2

-- ---- clock -----------------------------------------------------------------

local now
do
  -- QueryPerformanceCounter through the FFI: the JIT compiles the call, so timed code
  -- stays compiled.
  local ok, ffi = pcall(require, "ffi")
  if ok and ffi.os == "Windows" then
    local declared = pcall(ffi.cdef, [[
      int QueryPerformanceCounter(int64_t *t);
      int QueryPerformanceFrequency(int64_t *f);
    ]])
    if declared then
      local buf = ffi.new("int64_t[1]")
      local C = ffi.C
      if pcall(function() C.QueryPerformanceFrequency(buf) end) and tonumber(buf[0]) > 0 then
        local period = 1 / tonumber(buf[0])
        C.QueryPerformanceCounter(buf)
        local base = buf[0]
        now = function()
          C.QueryPerformanceCounter(buf)
          return tonumber(buf[0] - base) * period
        end
      end
    end
  end
  if not now then
    now = (love and love.timer and love.timer.getTime) or os.clock
  end
end
Timing.now = now

-- ---- state -----------------------------------------------------------------

local OFF, COUNT, TIME = 0, 1, 2
local MAX_DEPTH = 200

-- Wrappers and their numbers live for the whole session: a wrapper someone kept from an
-- earlier profile must still find its own entry.
local slots = {}      -- { tbl, key, orig, wrapper }
local wrapperOf = {}  -- original function -> wrapper (one wrapper per function)
local idOf = {}       -- wrapper -> its number
local names, mode, calls, selfT, inclT = {}, {}, {}, {}, {}
local active, activeGen = {}, {}
local stId, stStart, stChild = {}, {}, {}
local sp, gen = 0, 0
local nIds = 0
local running = false
local perTimed, perCounted = 0, 0
local traceCb, traces
local heavy = {}  -- { name, perFrame }: put back after the calibration
-- For the slowest frame: each function's own time at the last frame mark.
local prevOwn, lastMark, slowest = {}, nil, nil

local function leave(id, d, ...)
  -- stId differs when the profile ended, or an error or a coroutine left this entry behind.
  if stId[d] == id then
    local dt = now() - stStart[d]
    selfT[id] = selfT[id] + dt - stChild[d]
    local a = active[id] - 1
    active[id] = a
    if a <= 0 then inclT[id] = inclT[id] + dt end -- a recursive call is counted once
    stId[d] = 0
    sp = d - 1
    if d > 1 then stChild[d - 1] = stChild[d - 1] + dt end
  end
  return ...
end

local function wrap(id, f)
  return function(...)
    local m = mode[id]
    if m == OFF then return f(...) end
    calls[id] = calls[id] + 1
    if m == COUNT then return f(...) end
    local d = sp + 1
    if d > MAX_DEPTH then d = 1 end -- entries left behind by errors: start over
    if d == 1 then gen = gen + 1 end
    if activeGen[id] ~= gen then
      activeGen[id] = gen
      active[id] = 0
    end
    active[id] = active[id] + 1
    sp = d
    stId[d] = id
    stChild[d] = 0
    stStart[d] = now()
    return leave(id, d, f(...))
  end
end

local function newId(name)
  nIds = nIds + 1
  local id = nIds
  names[id], mode[id], calls[id], selfT[id], inclT[id] = name, OFF, 0, 0, 0
  active[id], activeGen[id] = 0, 0
  return id
end

local function isLua(f)
  local info = debug.getinfo(f, "S")
  return info and info.what == "Lua"
end

-- Tables never looked into: Lua's own, and this profiler.
local function skipTables()
  local skip = { [Timing] = true }
  for _, n in ipairs({ "package", "debug", "jit", "string", "table", "math", "os", "io", "coroutine", "bit" }) do
    local t = rawget(_G, n)
    if type(t) == "table" then skip[t] = true end
  end
  if type(package) == "table" and type(package.loaded) == "table" then skip[package.loaded] = true end
  return skip
end

local function collect(tbl, prefix, depth, visited, found)
  if visited[tbl] then return end
  visited[tbl] = true
  for k, v in next, tbl do
    if type(k) == "string" and k:sub(1, 4) ~= "__qm" then
      local tv = type(v)
      if tv == "function" then
        if not idOf[v] and isLua(v) then
          found[#found + 1] = { tbl = tbl, key = k, fn = v, name = prefix .. k }
        end
      elseif tv == "table" and depth < Timing.DEPTH then
        collect(v, prefix .. k .. ".", depth + 1, visited, found)
      end
    end
  end
end

-- What one timed and one counted call cost, measured on an empty function.
local function measureOverhead()
  if perTimed > 0 then return end
  local function empty() end
  local N = 20000
  local t0 = now()
  for _ = 1, N do empty() end
  local plain = now() - t0
  local id = newId("(overhead)")
  local w = wrap(id, empty)
  mode[id] = TIME
  t0 = now()
  for _ = 1, N do w() end
  perTimed = math.max(0, (now() - t0 - plain) / N)
  mode[id] = COUNT
  t0 = now()
  for _ = 1, N do w() end
  perCounted = math.max(0, (now() - t0 - plain) / N)
  mode[id] = OFF
  calls[id], selfT[id], inclT[id] = 0, 0, 0
  sp = 0
end

function Timing.isRunning()
  return running
end

--- Swaps in the wrappers. `extraSkip` is a set of tables to leave alone.
function Timing.start(extraSkip)
  if running then return false end
  slots = {}
  sp = 0
  measureOverhead()
  for id = 1, nIds do
    mode[id], calls[id], selfT[id], inclT[id] = OFF, 0, 0, 0
  end

  local visited = skipTables()
  for t in pairs(extraSkip or {}) do visited[t] = true end
  local found = {}
  collect(_G, "", 0, visited, found)
  table.sort(found, function(a, b) return a.name < b.name end)
  for _, e in ipairs(found) do
    local w = wrapperOf[e.fn]
    if not w then
      w = wrap(newId(e.name), e.fn)
      wrapperOf[e.fn] = w
      idOf[w] = nIds
    end
    mode[idOf[w]] = COUNT -- the calibration only counts
    slots[#slots + 1] = { tbl = e.tbl, key = e.key, orig = e.fn, wrapper = w }
    rawset(e.tbl, e.key, w)
  end

  -- How busy the JIT compiler is: counted from its own events, on this thread.
  traces = { compiled = 0, aborted = 0, flushes = 0 }
  heavy = {}
  prevOwn, lastMark, slowest = {}, nil, nil
  if type(jit) == "table" and type(jit.attach) == "function" then
    traceCb = function(what)
      if what == "stop" then traces.compiled = traces.compiled + 1
      elseif what == "abort" then traces.aborted = traces.aborted + 1
      elseif what == "flush" then traces.flushes = traces.flushes + 1 end
    end
    if not pcall(jit.attach, traceCb, "trace") then traceCb = nil end
  end
  running = true
  return true, #slots
end

--- Once per frame. Remembers the slowest frame (from one call to the next) and which
--- functions' own time it went to.
function Timing.mark()
  if not running then return end
  local t = now()
  if lastMark then
    local span = t - lastMark
    if not slowest or span > slowest.span then
      local top = {}
      for id = 1, nIds do
        local own = selfT[id] - (prevOwn[id] or 0)
        if own > span * 0.01 then top[#top + 1] = { name = names[id], own = own } end
      end
      table.sort(top, function(a, b) return a.own > b.own end)
      for i = #top, 9, -1 do top[i] = nil end
      slowest = { span = span, top = top }
    end
  end
  for id = 1, nIds do prevOwn[id] = selfT[id] end
  lastMark = t
end

-- Puts back the functions called more than `factor` times the limit so far.
local function cull(frameCount, factor)
  local limit = Timing.HEAVY_CALLS * factor * frameCount
  local isHeavy, any = {}, false
  for id = 1, nIds do
    if mode[id] == COUNT and calls[id] > limit then
      isHeavy[id], any = true, true
      heavy[#heavy + 1] = { name = names[id], perFrame = calls[id] / frameCount }
      mode[id] = OFF
    end
  end
  if not any then return end
  for _, s in ipairs(slots) do
    if isHeavy[idOf[s.wrapper]] and rawget(s.tbl, s.key) == s.wrapper then
      rawset(s.tbl, s.key, s.orig)
    end
  end
end

--- Each frame of the calibration: a function called far more often than the limit goes
--- back straight away, so the game is slowed for two frames and not for the whole
--- calibration.
function Timing.calibrating(frameCount)
  if running and frameCount >= 2 then cull(frameCount, 4) end
end

--- Ends the calibration: the functions called very often go back and are left alone from
--- here on, timing starts for the rest, and the totals start again from zero.
--- `frameCount` is how many frames the calibration saw.
function Timing.calibrate(frameCount)
  if not running then return end
  cull(math.max(1, frameCount), 1)
  for id = 1, nIds do
    if mode[id] == COUNT then mode[id] = TIME end
    calls[id], selfT[id], inclT[id] = 0, 0, 0
  end
  traces.compiled, traces.aborted, traces.flushes = 0, 0, 0
  prevOwn, lastMark, slowest = {}, nil, nil
end

--- Puts every function back and returns what was measured:
--- { rows = { { name, calls, own, total } ... }, heavy = { { name, perFrame } ... }, traces, perTimed }.
function Timing.finish()
  if not running then return nil end
  running = false
  if traceCb then
    pcall(jit.attach, traceCb)
    traceCb = nil
  end
  local rows = {}
  for id = 1, nIds do
    if calls[id] > 0 then
      rows[#rows + 1] = { name = names[id], calls = calls[id], own = selfT[id], total = inclT[id] }
    end
    mode[id] = OFF
  end
  -- Only where the wrapper is still in place; a slot someone replaced meanwhile is theirs.
  -- A wrapper that stays behind anywhere passes straight through.
  local kept = 0
  for _, s in ipairs(slots) do
    local now_ = rawget(s.tbl, s.key)
    if now_ == s.wrapper then
      rawset(s.tbl, s.key, s.orig)
    elseif now_ ~= s.orig then
      kept = kept + 1
    end
  end
  for d = 1, #stId do stId[d] = 0 end
  sp = 0
  local wrapped = #slots
  slots = {}
  return { rows = rows, heavy = heavy, traces = traces, slowest = slowest, perTimed = perTimed, wrapped = wrapped, replaced = kept }
end

return Timing
