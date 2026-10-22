-- ============================================================================
-- gmenu_core.lua — GMenu Core API & Config Discovery Engine for Mud and Blood
-- Standardized UI framework for mod game modes, options, and config.lua
-- ============================================================================

local gmenu_core = {}

-- Page IDs for custom GMenu screens
gmenu_core.PAGE_MOD_MODES = 85
gmenu_core.PAGE_MOD_OPTIONS = 86

-- Dynamic Page Allocator & Registry (assigns collision-free menuPage IDs to mods)
gmenu_core.nextDynamicPage = 100
gmenu_core.customPages = {}      -- Table: pageNumber -> { number, id, modId, draw, registerButtons }
gmenu_core.pageLookup = {}       -- Table: "modId:pageId" -> pageNumber

-- Registry storage
gmenu_core.menuButtons = {}     -- Array of registered custom game modes / main menu cards
gmenu_core.optionsByMod = {}     -- Table: modId -> { name = "...", options = { ... } }
gmenu_core.modList = {}          -- Ordered array of modIds that registered options
gmenu_core.activeModIndex = 1    -- Currently selected tab on Mod Options screen
gmenu_core.hoveredTooltip = ""   -- Tooltip description of currently hovered option
gmenu_core.savedSettings = {}    -- Persistent key-value table saved to saveModSettings.lua

--- Dynamically allocate a unique, collision-free menuPage number for a mod
-- Ensures multiple mods never accidentally claim the same menuPage ID.
-- @param modId String: unique mod identifier (e.g. "warfare")
-- @param pageId String: screen name (e.g. "briefing")
-- @param drawFn Function: draw routine called during drawState1()
-- @param registerButtonsFn Function: button registration routine called during buttonUpdateMenu()
-- @return Number: unique assigned menuPage number (e.g. 100, 101...)
function gmenu_core.allocatePage(modId, pageId, drawFn, registerButtonsFn)
  local key = (modId or "global") .. ":" .. (pageId or tostring(gmenu_core.nextDynamicPage))
  if gmenu_core.pageLookup[key] then
    local existingNum = gmenu_core.pageLookup[key]
    if drawFn then gmenu_core.customPages[existingNum].draw = drawFn end
    if registerButtonsFn then gmenu_core.customPages[existingNum].registerButtons = registerButtonsFn end
    return existingNum
  end

  local pageNum = gmenu_core.nextDynamicPage
  gmenu_core.nextDynamicPage = gmenu_core.nextDynamicPage + 1

  local entry = {
    number = pageNum,
    id = pageId,
    modId = modId,
    draw = drawFn,
    registerButtons = registerButtonsFn
  }
  gmenu_core.customPages[pageNum] = entry
  gmenu_core.pageLookup[key] = pageNum

  print(string.format("[GMenu] Dynamically assigned unique menuPage %d to [%s:%s]", pageNum, modId or "mod", pageId or "screen"))
  return pageNum
end

--- Retrieve the dynamically allocated menuPage number for a mod screen
function gmenu_core.getPage(modId, pageId)
  local key = (modId or "global") .. ":" .. (pageId or "")
  return gmenu_core.pageLookup[key]
end

-- Safe sound trigger helper
local function playSfx(sfx)
  if sfx and type(sfx.clone) == "function" then
    local ok, c = pcall(sfx.clone, sfx)
    if ok and c and type(c.play) == "function" then
      pcall(c.play, c)
    end
  end
end

-- ============================================================================
-- PERSISTENCE (saveModSettings.lua)
-- ============================================================================

function gmenu_core.loadSavedSettings()
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo("saveModSettings.lua") then
    local ok, chunk = pcall(love.filesystem.load, "saveModSettings.lua")
    if ok and type(chunk) == "function" then
      local ok2, data = pcall(chunk)
      if ok2 and type(data) == "table" then
        gmenu_core.savedSettings = data
      end
    end
  end
end

function gmenu_core.saveCurrentSettings()
  if love and love.filesystem then
    local ser = require "includes/ser"
    if ser then
      local ok, str = pcall(ser, gmenu_core.savedSettings)
      if ok and str then
        love.filesystem.write("saveModSettings.lua", "return " .. str)
      end
    end
  end
end

-- ============================================================================
-- REGISTRATION APIS
-- ============================================================================

--- Register a custom game mode / campaign button for the Mod Operations page
-- @param def Table: { id, title, subtitle, description, icon, priority, onClick }
function gmenu_core.registerMenuButton(def)
  if not def or not def.id or not def.title then return end

  -- Avoid duplicate registrations
  for i, btn in ipairs(gmenu_core.menuButtons) do
    if btn.id == def.id then
      gmenu_core.menuButtons[i] = def
      return
    end
  end

  def.priority = def.priority or 50

  -- Load image icon if provided as string path
  if type(def.icon) == "string" then
    local candidates = {
      def.icon,
      (def.modDir and (def.modDir .. "/" .. def.icon)),
      ("Mods/" .. (def.modId or "") .. "/" .. def.icon)
    }
    local baseFilename = def.icon:match("[^/\\]+$")
    if baseFilename and def.modId then
      table.insert(candidates, "Mods/" .. def.modId .. "/" .. baseFilename)
    end

    local img = nil
    for _, p in ipairs(candidates) do
      if p and not img then
        if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(p) then
          local ok, data = pcall(love.filesystem.newFileData, p)
          if ok and data then
            local imgOk, loaded = pcall(love.graphics.newImage, data)
            if imgOk then img = loaded; break end
          end
        end
        local f = io.open(p, "rb")
        if f then
          local bytes = f:read("*a")
          f:close()
          if bytes and #bytes > 0 then
            local ok, data = pcall(love.filesystem.newFileData, bytes, def.id .. "_icon.png")
            if ok and data then
              local imgOk, loaded = pcall(love.graphics.newImage, data)
              if imgOk then img = loaded; break end
            end
          end
        end
      end
    end
    def.iconImage = img
  elseif type(def.icon) == "userdata" then
    def.iconImage = def.icon
  end

  table.insert(gmenu_core.menuButtons, def)
  table.sort(gmenu_core.menuButtons, function(a, b) return (a.priority or 50) > (b.priority or 50) end)
  print(string.format("[GMenu] Registered custom game mode button: '%s' (ID: %s)", def.title, def.id))
end

--- Register a configurable option entry into the Mod Options menu
-- @param modId String: unique mod identifier (e.g. "tactical_overhaul")
-- @param modName String: display name of the mod (e.g. "Tactical Overhaul")
-- @param def Table: { id, label, type, options, labels, description, default, get, set }
function gmenu_core.registerOption(modId, modName, def)
  if not modId or not def or not def.id or not def.label then return end

  if not gmenu_core.optionsByMod[modId] then
    gmenu_core.optionsByMod[modId] = {
      id = modId,
      name = modName or modId,
      options = {}
    }
    table.insert(gmenu_core.modList, modId)
  end

  local modEntry = gmenu_core.optionsByMod[modId]

  -- Replace existing or append
  local found = false
  for i, opt in ipairs(modEntry.options) do
    if opt.id == def.id then
      modEntry.options[i] = def
      found = true
      break
    end
  end
  if not found then
    table.insert(modEntry.options, def)
  end

  -- Initialize saved setting if not already present
  if not gmenu_core.savedSettings[modId] then
    gmenu_core.savedSettings[modId] = {}
  end
  if gmenu_core.savedSettings[modId][def.id] == nil and def.default ~= nil then
    gmenu_core.savedSettings[modId][def.id] = def.default
  end

  -- If mod provides custom get/set, apply default if needed
  if def.set and def.get and def.get() == nil and def.default ~= nil then
    def.set(def.default)
  end
end

--- Get current value of an option
function gmenu_core.getOptionValue(modId, opt)
  if opt.get then
    local ok, val = pcall(opt.get)
    if ok and val ~= nil then return val end
  end
  if gmenu_core.savedSettings[modId] and gmenu_core.savedSettings[modId][opt.id] ~= nil then
    return gmenu_core.savedSettings[modId][opt.id]
  end
  return opt.default
end

--- Set new value for an option
function gmenu_core.setOptionValue(modId, opt, newVal)
  if not gmenu_core.savedSettings[modId] then
    gmenu_core.savedSettings[modId] = {}
  end
  gmenu_core.savedSettings[modId][opt.id] = newVal
  gmenu_core.saveCurrentSettings()

  if opt.set then
    pcall(opt.set, newVal)
  end
end

--- Get array of options that should be displayed (filters by showIf if defined)
function gmenu_core.getVisibleOptions(modId)
  local modData = gmenu_core.optionsByMod[modId]
  if not modData or not modData.options then return {} end
  local list = {}
  for _, opt in ipairs(modData.options) do
    local isVis = true
    if opt.showIf and type(opt.showIf) == "function" then
      local ok, res = pcall(opt.showIf)
      if ok and res == false then isVis = false end
    end
    if isVis then
      table.insert(list, opt)
    end
  end
  return list
end

-- ============================================================================
-- DYNAMIC CONFIG.LUA DISCOVERY
-- ============================================================================

--- Scan Mods/ directory for config.lua in any mod folder
function gmenu_core.discoverConfigs()
  local modBases = { "Mods" }
  if love.filesystem and love.filesystem.getSourceBaseDirectory then
    table.insert(modBases, love.filesystem.getSourceBaseDirectory() .. "/Mods")
  end
  if love.filesystem and love.filesystem.getSaveDirectory then
    table.insert(modBases, love.filesystem.getSaveDirectory() .. "/Mods")
  end

  local scannedDirs = {}

  for _, base in ipairs(modBases) do
    local dirs = {}
    -- Virtual LÖVE FS query
    if love.filesystem and love.filesystem.getDirectoryItems then
      local ok, items = pcall(love.filesystem.getDirectoryItems, "Mods")
      if ok and type(items) == "table" then
        for _, item in ipairs(items) do
          table.insert(dirs, item)
        end
      end
    end

    -- Direct disk scan fallback
    local ok_os, entries = pcall(function()
      local t = {}
      local p = io.popen('dir "' .. base:gsub("/", "\\") .. '" /b /ad 2>nul')
      if p then
        for line in p:lines() do
          t[#t + 1] = line:gsub("%s+$", "")
        end
        p:close()
      end
      return t
    end)
    if ok_os and type(entries) == "table" then
      for _, e in ipairs(entries) do
        table.insert(dirs, e)
      end
    end

    for _, dirName in ipairs(dirs) do
      if dirName ~= "qm" and dirName ~= "lovely" and not scannedDirs[dirName] then
        scannedDirs[dirName] = true
        gmenu_core.loadModConfig(dirName, base .. "/" .. dirName)
      end
    end
  end
end

--- Attempt to load config.lua from a specific mod directory
function gmenu_core.loadModConfig(modId, fullPath)
  local configCandidates = {
    "Mods/" .. modId .. "/config.lua",
    fullPath .. "/config.lua"
  }

  for _, path in ipairs(configCandidates) do
    local chunk = nil
    if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path) then
      local ok, loaded = pcall(love.filesystem.load, path)
      if ok and type(loaded) == "function" then chunk = loaded end
    end
    if not chunk then
      local f = io.open(path, "r")
      if f then
        local code = f:read("*a")
        f:close()
        if code and #code > 0 then
          local ok, loaded = pcall(loadstring or load, code, path)
          if ok and type(loaded) == "function" then chunk = loaded end
        end
      end
    end

    if chunk then
      local ok, result = pcall(chunk)
      if ok and type(result) == "table" then
        gmenu_core.applyConfigTable(modId, result, fullPath)
        print("[GMenu] Loaded config.lua for mod: " .. modId)
        break
      end
    end
  end
end

--- Apply definitions loaded from a config.lua table
function gmenu_core.applyConfigTable(modId, cfg, fullPath)
  local name = cfg.name or modId

  -- Register options if defined
  if type(cfg.options) == "table" then
    for _, opt in ipairs(cfg.options) do
      gmenu_core.registerOption(modId, name, opt)
    end
  end

  -- Register main menu buttons if defined
  if type(cfg.menuButtons) == "table" then
    for _, btn in ipairs(cfg.menuButtons) do
      btn.id = btn.id or (modId .. "_" .. (btn.title or "btn"))
      btn.modId = modId
      btn.modDir = fullPath
      gmenu_core.registerMenuButton(btn)
    end
  end

  -- Register custom mod screens with dynamic menuPage allocation
  if type(cfg.pages) == "table" then
    for pageId, pageDef in pairs(cfg.pages) do
      if type(pageDef) == "table" then
        local num = gmenu_core.allocatePage(modId, pageId, pageDef.draw, pageDef.buttons or pageDef.registerButtons)
        pageDef.menuPage = num
      end
    end
  end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function gmenu_core.init()
  gmenu_core.loadSavedSettings()
  gmenu_core.discoverConfigs()
  print(string.format("[GMenu] Framework initialized. Modes: %d | Mods with Options: %d",
    #gmenu_core.menuButtons, #gmenu_core.modList))
end

return gmenu_core
