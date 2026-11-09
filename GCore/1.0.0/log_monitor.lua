-- ============================================================================
-- log_monitor.lua — Runtime Log Bloat & Error Spam Detector for Mud and Blood
-- Part of GCore Mod
-- ============================================================================

local log_monitor = {}

-- Configurable thresholds
log_monitor.CHECK_INTERVAL = 2.0                -- Check every 2 seconds
log_monitor.GROWTH_SPAM_THRESHOLD = 250 * 1024  -- 250 KB growth in 2 seconds is runaway spam
log_monitor.MAX_SIZE_WARNING = 15 * 1024 * 1024 -- 15 MB total file size warning
log_monitor.ALERT_COOLDOWN = 30.0               -- Alert player at most once every 30s

-- Internal state
log_monitor.timer = 0
log_monitor.lastLogSize = 0
log_monitor.lastErrSize = 0
log_monitor.cooldownTimer = 0
log_monitor.totalWarnings = 0
log_monitor.logPath = nil
log_monitor.errPath = nil

-- Locate the active log files on disk or virtual filesystem
function log_monitor.init()
  local candidates = {
    "Mods/qm/log/latest.log"
  }
  if love.filesystem and love.filesystem.getSourceBaseDirectory then
    local base = love.filesystem.getSourceBaseDirectory()
    table.insert(candidates, base .. "/Mods/qm/log/latest.log")
  end
  if love.filesystem and love.filesystem.getSaveDirectory then
    table.insert(candidates, love.filesystem.getSaveDirectory() .. "/Mods/qm/log/latest.log")
  end

  for _, path in ipairs(candidates) do
    local f = io.open(path, "rb")
    if f then
      local size = f:seek("end") or 0
      f:close()
      log_monitor.logPath = path
      log_monitor.lastLogSize = size
      break
    end
  end

  -- Derive err.log path from logPath
  if log_monitor.logPath then
    log_monitor.errPath = log_monitor.logPath:gsub("latest%.log$", "err.log")
    local ef = io.open(log_monitor.errPath, "rb")
    if ef then
      log_monitor.lastErrSize = ef:seek("end") or 0
      ef:close()
    end
  end

  print("[GCore LogMonitor] Initialized. Monitoring: " .. tostring(log_monitor.logPath))
end

-- Periodically inspect file sizes and trigger player warning if bloat or error flood occurs
function log_monitor.update(dt)
  if not dt then return end

  if log_monitor.cooldownTimer > 0 then
    log_monitor.cooldownTimer = log_monitor.cooldownTimer - dt
  end

  log_monitor.timer = log_monitor.timer + dt
  if log_monitor.timer < log_monitor.CHECK_INTERVAL then
    return
  end
  log_monitor.timer = 0

  if not log_monitor.logPath then
    log_monitor.init()
    if not log_monitor.logPath then return end
  end

  -- 1. Check latest.log size
  local curLogSize = 0
  local f = io.open(log_monitor.logPath, "rb")
  if f then
    curLogSize = f:seek("end") or 0
    f:close()
  end

  -- 2. Check err.log size
  local curErrSize = 0
  if log_monitor.errPath then
    local ef = io.open(log_monitor.errPath, "rb")
    if ef then
      curErrSize = ef:seek("end") or 0
      ef:close()
    end
  end

  local growth = curLogSize - log_monitor.lastLogSize
  local errGrowth = curErrSize - log_monitor.lastErrSize
  log_monitor.lastLogSize = curLogSize
  log_monitor.lastErrSize = curErrSize

  -- Determine if warning should trigger
  local reason = nil
  if growth >= log_monitor.GROWTH_SPAM_THRESHOLD then
    reason = string.format("Rapid log spam detected (+%d KB/2s)", math.floor(growth / 1024))
  elseif curLogSize >= log_monitor.MAX_SIZE_WARNING then
    reason = string.format("Log file size is massive (%d MB)", math.floor(curLogSize / (1024 * 1024)))
  elseif errGrowth >= 512 then
    reason = "New errors logged in err.log"
  end

  if reason and log_monitor.cooldownTimer <= 0 then
    log_monitor.cooldownTimer = log_monitor.ALERT_COOLDOWN
    log_monitor.totalWarnings = log_monitor.totalWarnings + 1
    log_monitor.notifyPlayer(reason)
  end
end

-- Present in-game notification to the player
function log_monitor.notifyPlayer(reason)
  local msg = "MOD LOG WARNING: " .. reason .. "! Check Mods/qm/log/err.log"
  print("[GCore LogMonitor] " .. msg)

  if player and player.textCue then
    player.textCue[#player.textCue + 1] = {}
    player.textCue[#player.textCue].name = msg
    player.textCue[#player.textCue].x = (player.screenx or 0) + 600
    player.textCue[#player.textCue].y = 320
    player.textCue[#player.textCue].alpha = 255
  end

  if anounceStuff then
    pcall(anounceStuff, "WARNING: Mod error/log spam detected. See Mods/qm/log/err.log")
  end
end

return log_monitor
