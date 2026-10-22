-- ============================================================================
-- config.lua - GDumper options page for GMenu (Mod Options)
-- ============================================================================

local function statusText()
  if not (GDumper and GDumper.available()) then
    return "Injector does not support dumping - update winmm.dll"
  end
  local r = GDumper.lastResult
  if not r then return "No dump performed this session" end
  if r.ok then
    return string.format("Last: %d files (%s) at %s", r.count or 0, r.scope, os.date("%H:%M:%S", r.time))
  end
  return "Last dump failed: " .. tostring(r.err)
end

local config = {
  name = "Game File Dumper",
  options = {
    {
      id = "dump_lua",
      label = "Dump Vanilla Lua Scripts",
      type = "button",
      buttonText = "DUMP",
      description = "Extract all original (unpatched) .lua files to Mods/qm/game-dump  [Ctrl+Shift+D]",
      onClick = function() if GDumper then GDumper.dump("lua") end end,
    },
    {
      id = "dump_assets",
      label = "Dump Full Game Archive",
      type = "button",
      buttonText = "DUMP",
      description = "Extract every file (scripts, images, audio, fonts) to Mods/qm/game-dump-full  [Ctrl+Shift+Alt+D]",
      onClick = function() if GDumper then GDumper.dump("assets") end end,
    },
    {
      id = "dump_status",
      label = "Status",
      type = "button",
      buttonText = "CHECK",
      description = "Show the result of the last dump",
      onClick = function()
        local msg = statusText()
        print("[GDumper] " .. msg)
        if player and player.textCue then
          player.textCue[#player.textCue + 1] = { name = msg, x = (player.screenx or 0) + 500, y = 300, alpha = 255 }
        end
      end,
    },
  },
}

return config
