-- ============================================================================
-- gmenu_ui.lua — GMenu UI Rendering & Native Interaction Engine for Mud and Blood
-- Standardized, non-destructive UI for Mod Operations and Mod Options
-- ============================================================================

local gmenu_core = require "includes/gmenu_core"
local gmenu_ui = {}

-- Sound trigger helper
local function playClickSound()
  local sfx = (weaponInspect1 and _G["weaponInspect" .. randNbr(5)]) or clickSound
  if sfx and type(sfx.clone) == "function" then
    local ok, c = pcall(sfx.clone, sfx)
    if ok and c and type(c.play) == "function" then
      pcall(c.play, c)
    end
  end
end

--- Helper: Draw text with clean 1px drop shadow and dynamic font downscaling
-- Prevents text from escaping bounding boxes and avoids muddy 4-way black outlines
local function drawCleanShadowText(text, x, y, limit, align, font, textColor)
  local f = font or cardFont or bigFont
  local fade = uiFade or 255
  local tc = textColor or { 255, 255, 255, fade }

  -- Auto-downscale font if text width exceeds button/tab bounding limit
  if limit and f and type(f.getWidth) == "function" then
    if f:getWidth(text) > limit then
      if f == bigFont and cardFont and cardFont:getWidth(text) <= limit then
        f = cardFont
      elseif nonoFont then
        f = nonoFont
      end
    end
  end

  if f then love.graphics.setFont(f) end

  -- Clean 1px bottom-right drop shadow
  love.graphics.printf({{love.math.colorFromBytes(0, 0, 0, math.min(180, fade))}, text}, x + 1, y + 1, limit or 200, align or "left")
  -- Crisp foreground text
  love.graphics.printf({{love.math.colorFromBytes(tc[1], tc[2], tc[3], tc[4] or fade)}, text}, x, y, limit or 200, align or "left")
end

--- Legacy wrapper maintaining compatibility with existing callers
local function drawShadowText(text, x, y, limit, align, font, textColor)
  drawCleanShadowText(text, x, y, limit, align, font, textColor)
end

-- ============================================================================
-- MAIN MENU INTEGRATION (menuPage == 1)
-- ============================================================================

--- Register native M&B Button on the main menu
function gmenu_ui.registerMainMenuButton()
  local hasModes = gmenu_core and gmenu_core.menuButtons and #gmenu_core.menuButtons > 0
  local hasOptions = gmenu_core and gmenu_core.modList and #gmenu_core.modList > 0
  if not hasModes and not hasOptions then
    return
  end
  local bx = (player and player.bloop == 1) and 340 or 120
  if hasModes then
    buttons[#buttons + 1] = Button.new(bx, 686, 190, 30, "menu_modOps", "active", true, "Browse and launch custom mod game modes")
  else
    buttons[#buttons + 1] = Button.new(bx, 686, 190, 30, "menu_modOptions", "active", true, "Configure installed mod options and settings")
  end
end

--- Global click handler dispatched by M&B buttonEngine
function _G.menu_modOpsButton()
  playClickSound()
  print("[GMenu] Navigating to Mod Operations (Page 85)")
  menuPage = gmenu_core.PAGE_MOD_MODES
  mouseOverText = ""
  contextualText = ""
end

--- Render Main Menu trigger text
function gmenu_ui.drawMainMenuButton()
  local hasModes = gmenu_core and gmenu_core.menuButtons and #gmenu_core.menuButtons > 0
  local hasOptions = gmenu_core and gmenu_core.modList and #gmenu_core.modList > 0
  if not hasModes and not hasOptions then
    return
  end

  local mx, my = love.mouse.getPosition()
  local bx = (player and player.bloop == 1) and 340 or 120
  local by = 685
  local bw = 190
  local bh = 30
  local hovered = (mx >= bx and mx <= bx + bw and my >= by - 5 and my <= by + bh)

  local fade = uiFade or 255
  local textColor = hovered and { 101, 24, 24, fade } or { 211, 211, 211, fade }
  local label = hasModes and "MOD OPERATIONS >" or "MOD OPTIONS >"

  drawCleanShadowText(label, bx, by, bw, "left", bigFont, textColor)
end

-- ============================================================================
-- SCREEN 85: MOD OPERATIONS HUB (CUSTOM GAME MODES)
-- ============================================================================

local function getModeCardLayout()
  local buttonsList = gmenu_core.menuButtons or {}
  local count = #buttonsList
  local cardW = 200
  local cardH = 465
  local startY = 185
  local gap = 25

  local totalWidth = count * cardW + math.max(0, count - 1) * gap
  local startX = 75
  if totalWidth < 1100 then
    startX = math.floor((1280 - totalWidth) / 2)
  end

  return buttonsList, count, cardW, cardH, startY, gap, startX
end

--- Register native M&B Buttons on Screen 85
function gmenu_ui.registerModModesButtons()
  -- 1. Back button (returns to vanilla Main Menu)
  buttons[#buttons + 1] = Button.new(32, 686, 60, 30, "menu_back", "active", true, mouseOverBack)

  -- 2. Mod Options trigger (isolated on mod operations page)
  if gmenu_core.modList and #gmenu_core.modList > 0 then
    buttons[#buttons + 1] = Button.new(120, 686, 170, 30, "menu_modOptions", "active", true, "Configure settings for installed mods")
  end

  -- 3. Custom game mode cards
  local buttonsList, count, cardW, cardH, startY, gap, startX = getModeCardLayout()
  for i, btn in ipairs(buttonsList) do
    local cardX = startX + (i - 1) * (cardW + gap)
    local btnLabel = "gmenu_mode_" .. i
    buttons[#buttons + 1] = Button.new(cardX, startY, cardW, cardH, btnLabel, "active", true, btn.description or btn.title)

    -- Register global click handler
    _G[btnLabel .. "Button"] = function()
      playClickSound()
      print(string.format("[GMenu] Launching custom mode: %s (ID: %s)", btn.title, btn.id))
      mouseOverText = ""
      contextualText = ""
      if btn.onClick then
        pcall(btn.onClick)
      end
    end
  end
end

--- Global click handler to open Mod Options from Mod Operations
function _G.menu_modOptionsButton()
  playClickSound()
  print("[GMenu] Navigating to Mod Options (Page 86)")
  menuPage = gmenu_core.PAGE_MOD_OPTIONS
  mouseOverText = ""
  contextualText = ""
end

--- Render Screen 85 (Mod Operations Hub)
function gmenu_ui.drawModModes()
  local fade = uiFade or 255
  local mx, my = love.mouse.getPosition()

  -- Top Header
  drawCleanShadowText("MOD OPERATIONS", 30, 130, 600, "left", bigFont)
  if nonoFont then
    love.graphics.setFont(nonoFont)
    love.graphics.setColor(love.math.colorFromBytes(180, 180, 180, fade))
    love.graphics.print("COMMUNITY EXPANSIONS & CUSTOM THEATERS", 32, 160)
  end

  -- Back Button Text (Bottom Left)
  local backHovered = (mx >= 30 and mx <= 100 and my >= 680 and my <= 715)
  local backColor = backHovered and { 101, 24, 24, fade } or { 255, 255, 255, fade }
  drawCleanShadowText("BACK", 35, 685, 100, "left", bigFont, backColor)

  -- Mod Options Trigger Text (Next to Back on Mod Operations Page)
  if gmenu_core.modList and #gmenu_core.modList > 0 then
    local optHovered = (mx >= 120 and mx <= 290 and my >= 680 and my <= 715)
    local optColor = optHovered and { 101, 24, 24, fade } or { 211, 211, 211, fade }
    drawCleanShadowText("MOD OPTIONS >", 120, 685, 200, "left", bigFont, optColor)
  end

  local buttonsList, count, cardW, cardH, startY, gap, startX = getModeCardLayout()
  if count == 0 then
    drawCleanShadowText("No custom game modes installed.", 50, 220, 600, "left", bigFont)
    return
  end

  for i, btn in ipairs(buttonsList) do
    local cardX = startX + (i - 1) * (cardW + gap)
    local hovered = (mx >= cardX and mx <= cardX + cardW and my >= startY and my <= startY + cardH)

    -- Card Background Fill
    love.graphics.setColor(love.math.colorFromBytes(255, 255, 255, hovered and 175 or 120))
    love.graphics.rectangle("fill", cardX, startY, cardW, cardH)

    -- Card Picture Frame Outline
    local frameX = cardX + 25
    local frameY = startY + 25
    local frameW = 150
    local frameH = 340

    love.graphics.setColor(love.math.colorFromBytes(0, 0, 0, fade))
    love.graphics.rectangle("line", frameX, frameY, frameW, frameH)

    -- Icon Image Drawing
    if btn.iconImage then
      love.graphics.setColor(love.math.colorFromBytes(101, 24, 24, fade))
      local imgW = btn.iconImage:getWidth()
      local imgH = btn.iconImage:getHeight()
      local sx = frameW / imgW
      local sy = frameH / imgH
      love.graphics.draw(btn.iconImage, frameX, frameY, 0, sx, sy)
    else
      -- Fallback stencil box if mod has no icon
      love.graphics.setColor(love.math.colorFromBytes(60, 60, 60, fade))
      love.graphics.rectangle("fill", frameX + 2, frameY + 2, frameW - 4, frameH - 4)
      love.graphics.setColor(love.math.colorFromBytes(140, 140, 140, fade))
      if nonoFont then love.graphics.setFont(nonoFont) end
      love.graphics.printf("CUSTOM OP", frameX, frameY + (frameH / 2) - 10, frameW, "center")
    end

    -- Outer Highlight Border when hovered
    if hovered then
      love.graphics.setColor(love.math.colorFromBytes(101, 24, 24, fade))
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", cardX, startY, cardW, cardH)
      love.graphics.setLineWidth(1)
    end

    -- Mode Title
    local titleColor = hovered and { 101, 24, 24, fade } or { 255, 255, 255, fade }
    drawCleanShadowText(btn.title:upper(), cardX, startY + 380, cardW, "center", bigFont, titleColor)

    -- Mode Subtitle / Short description
    if btn.subtitle and nonoFont then
      love.graphics.setFont(nonoFont)
      love.graphics.setColor(love.math.colorFromBytes(0, 0, 0, fade))
      love.graphics.printf(btn.subtitle, cardX + 10, startY + 415, cardW - 20, "center")
    end
  end
end

-- ============================================================================
-- SCREEN 86: MOD OPTIONS PANEL
-- ============================================================================

local function getActiveModAndOptions()
  local modList = gmenu_core.modList or {}
  if #modList == 0 then return nil, nil end
  local activeModId = modList[gmenu_core.activeModIndex] or modList[1]
  local modData = gmenu_core.optionsByMod[activeModId]
  return activeModId, modData
end

--- Register native M&B Buttons on Screen 86
function gmenu_ui.registerModOptionsButtons()
  -- 1. Back button (returns to Mod Operations Hub)
  buttons[#buttons + 1] = Button.new(32, 686, 60, 30, "gmenu_opt_back", "active", true, mouseOverBack)

  local modList = gmenu_core.modList or {}
  if #modList == 0 then return end

  -- 2. Mod Tab Buttons (if multiple mods registered options)
  if #modList > 1 then
    local tabStartX = 280
    local tabY = 125
    local tabW = 160
    local tabH = 32

    for mIdx, mId in ipairs(modList) do
      local mData = gmenu_core.optionsByMod[mId]
      local tabX = tabStartX + (mIdx - 1) * (tabW + 10)
      local tabLabel = "gmenu_tab_" .. mIdx
      buttons[#buttons + 1] = Button.new(tabX, tabY, tabW, tabH, tabLabel, "active", true, "Select " .. (mData and mData.name or mId))

      _G[tabLabel .. "Button"] = function()
        playClickSound()
        gmenu_core.activeModIndex = mIdx
      end
    end
  end

  -- 3. Option Card Buttons for Active Mod
  local activeModId, modData = getActiveModAndOptions()
  if not modData or not modData.options then return end

  local options = gmenu_core.getVisibleOptions(activeModId)
  if #options == 0 then return end

  local cardW = 500
  local cardH = 50
  local rowGap = 12

  for idx, opt in ipairs(options) do
    local col = math.floor((idx - 1) / 7)
    local row = (idx - 1) % 7
    local cardX = 50 + col * 525
    local cardY = 185 + row * (cardH + rowGap)

    local optLabel = "gmenu_opt_" .. idx
    buttons[#buttons + 1] = Button.new(cardX, cardY, cardW, cardH, optLabel, "active", true, opt.description or opt.label)

    _G[optLabel .. "Button"] = function()
      local optType = opt.type or "checkbox"
      local curVal = gmenu_core.getOptionValue(activeModId, opt)

      if optType == "checkbox" or optType == "bool" then
        local nextVal
        if type(curVal) == "boolean" then
          nextVal = not curVal
        else
          nextVal = (curVal == 0 or curVal == false or curVal == nil) and 1 or 0
        end
        playClickSound()
        gmenu_core.setOptionValue(activeModId, opt, nextVal)
        print(string.format("[GMenu] Toggled %s.%s = %s", activeModId, opt.id, tostring(nextVal)))

      elseif optType == "cycle" or optType == "stepper" then
        if opt.options and #opt.options > 0 then
          local curIdx = 1
          for oIdx, val in ipairs(opt.options) do
            if val == curVal then curIdx = oIdx; break end
          end

          -- Dual-direction cycling based on click position:
          -- Left half clicks (<) step backward, Right half clicks (>) step forward
          local clickMx, _ = love.mouse.getPosition()
          local btnW = 175
          local btnX = cardX + cardW - btnW - 15
          local midX = btnX + (btnW * 0.5)

          local nextIdx
          if clickMx < midX then
            nextIdx = (curIdx - 2 + #opt.options) % #opt.options + 1
          else
            nextIdx = (curIdx % #opt.options) + 1
          end

          local nextVal = opt.options[nextIdx]
          playClickSound()
          gmenu_core.setOptionValue(activeModId, opt, nextVal)
          print(string.format("[GMenu] Cycled %s.%s = %s (dir: %s)", activeModId, opt.id, tostring(nextVal), clickMx < midX and "prev" or "next"))
        end

      elseif optType == "button" then
        playClickSound()
        if opt.onClick then pcall(opt.onClick) end
      end
    end
  end
end

--- Global click handler to return from Mod Options
function _G.gmenu_opt_backButton()
  playClickSound()
  local hasModes = gmenu_core and gmenu_core.menuButtons and #gmenu_core.menuButtons > 0
  if hasModes then
    print("[GMenu] Returning from Mod Options to Mod Operations (Page 85)")
    menuPage = gmenu_core.PAGE_MOD_MODES
  else
    print("[GMenu] Returning from Mod Options to Main Menu (Page 1)")
    menuPage = 1
  end
  mouseOverText = ""
  contextualText = ""
end

--- Render Screen 86 (Mod Options Panel)
function gmenu_ui.drawModOptions()
  local fade = uiFade or 255
  local mx, my = love.mouse.getPosition()
  local currentTooltip = ""

  -- Top Header
  drawCleanShadowText("MOD OPTIONS", 30, 130, 400, "left", bigFont)

  -- Back Button Text (Bottom Left)
  local backHovered = (mx >= 30 and mx <= 100 and my >= 680 and my <= 715)
  local backColor = backHovered and { 101, 24, 24, fade } or { 255, 255, 255, fade }
  drawCleanShadowText("BACK", 35, 685, 100, "left", bigFont, backColor)

  local modList = gmenu_core.modList or {}
  if #modList == 0 then
    drawCleanShadowText("No configurable mod options found.", 50, 220, 600, "left", bigFont)
    return
  end

  -- Tab Bar for Switching Between Multiple Mods
  if #modList > 1 then
    local tabStartX = 280
    local tabY = 125
    local tabW = 160
    local tabH = 32

    for mIdx, mId in ipairs(modList) do
      local mData = gmenu_core.optionsByMod[mId]
      local tabX = tabStartX + (mIdx - 1) * (tabW + 10)
      local isSelected = (mIdx == gmenu_core.activeModIndex)
      local tabHovered = (mx >= tabX and mx <= tabX + tabW and my >= tabY and my <= tabY + tabH)

      love.graphics.setColor(love.math.colorFromBytes(255, 255, 255, (isSelected or tabHovered) and 180 or 100))
      love.graphics.rectangle("fill", tabX, tabY, tabW, tabH)

      if isSelected then
        love.graphics.setColor(love.math.colorFromBytes(101, 24, 24, fade))
        love.graphics.rectangle("fill", tabX, tabY + tabH - 4, tabW, 4)
      end

      -- Vertically centered tab text using cardFont
      local tabColor = isSelected and { 101, 24, 24, fade } or { 255, 255, 255, fade }
      drawCleanShadowText(mData.name, tabX, tabY + 4, tabW, "center", cardFont or bigFont, tabColor)
    end
  end

  -- Active Mod Options
  local activeModId, modData = getActiveModAndOptions()
  if not modData or not modData.options or #modData.options == 0 then
    drawCleanShadowText("No configurable options for this mod.", 50, 220, 600, "left", bigFont)
    return
  end

  local options = gmenu_core.getVisibleOptions(activeModId)
  if #options == 0 then
    drawCleanShadowText("No options visible in this view.", 50, 220, 600, "left", bigFont)
    return
  end

  local cardW = 500
  local cardH = 50
  local rowGap = 12

  for idx, opt in ipairs(options) do
    local col = math.floor((idx - 1) / 7)
    local row = (idx - 1) % 7
    local cardX = 50 + col * 525
    local cardY = 185 + row * (cardH + rowGap)

    local hovered = (mx >= cardX and mx <= cardX + cardW and my >= cardY and my <= cardY + cardH)
    if hovered and opt.description then
      currentTooltip = opt.description
    end

    -- Option Card Background
    love.graphics.setColor(love.math.colorFromBytes(255, 255, 255, hovered and 165 or 120))
    love.graphics.rectangle("fill", cardX, cardY, cardW, cardH)

    -- Option Label (bounded, clean shadow)
    local labelFont = cardFont or bigFont
    drawCleanShadowText(opt.label:upper(), cardX + 20, cardY + 14, 280, "left", labelFont)

    -- Control Widget Rendering
    local optType = opt.type or "checkbox"
    local curVal = gmenu_core.getOptionValue(activeModId, opt)

    if optType == "checkbox" or optType == "bool" then
      -- Checkbox with solid high-contrast background and border
      local boxX = cardX + cardW - 50
      local boxY = cardY + 15
      love.graphics.setColor(love.math.colorFromBytes(35, 35, 38, 220))
      love.graphics.rectangle("fill", boxX, boxY, 20, 20)
      love.graphics.setColor(love.math.colorFromBytes(80, 85, 95, 255))
      love.graphics.rectangle("line", boxX, boxY, 20, 20)

      if curVal == 1 or curVal == true then
        love.graphics.setColor(love.math.colorFromBytes(180, 35, 35, fade))
        love.graphics.rectangle("fill", boxX + 3, boxY + 3, 14, 14)
      end

    elseif optType == "cycle" or optType == "stepper" then
      -- Sleek, high-contrast cycle button with dual-direction indicators
      local btnW = 175
      local btnX = cardX + cardW - btnW - 15
      local btnY = cardY + 10
      local btnH = 30
      local btnHovered = (mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH)
      local leftHovered = btnHovered and (mx < btnX + (btnW * 0.5))
      local rightHovered = btnHovered and (mx >= btnX + (btnW * 0.5))

      -- Dark slate background for high contrast
      love.graphics.setColor(love.math.colorFromBytes(28, 30, 34, 240))
      love.graphics.rectangle("fill", btnX, btnY, btnW, btnH)

      -- Hover state: highlight respective half
      if leftHovered then
        love.graphics.setColor(love.math.colorFromBytes(101, 24, 24, 210))
        love.graphics.rectangle("fill", btnX + 1, btnY + 1, math.floor(btnW * 0.5) - 1, btnH - 2)
      elseif rightHovered then
        love.graphics.setColor(love.math.colorFromBytes(101, 24, 24, 210))
        love.graphics.rectangle("fill", btnX + math.floor(btnW * 0.5), btnY + 1, math.ceil(btnW * 0.5) - 1, btnH - 2)
      end

      -- Clean border
      love.graphics.setColor(love.math.colorFromBytes(75, 80, 90, 255))
      love.graphics.rectangle("line", btnX, btnY, btnW, btnH)

      -- Format display label
      local displayLabel = tostring(curVal)
      if opt.labels and type(opt.labels) == "table" and opt.options then
        for optIdx, oVal in ipairs(opt.options) do
          if oVal == curVal and opt.labels[optIdx] then
            displayLabel = opt.labels[optIdx]
            break
          end
        end
      end

      local fontToUse = (#displayLabel > 12) and (nonoFont or cardFont or bigFont) or (cardFont or bigFont)
      local textOffsetY = (fontToUse == nonoFont) and 6 or 4
      local valColor = { 255, 255, 255, fade }

      -- High contrast white text with clean 1px drop shadow
      drawCleanShadowText("< " .. displayLabel .. " >", btnX, btnY + textOffsetY, btnW, "center", fontToUse, valColor)

    elseif optType == "button" then
      local btnX = cardX + cardW - 130
      local btnY = cardY + 10
      local btnW = 110
      local btnH = 30
      local btnHovered = (mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH)

      love.graphics.setColor(love.math.colorFromBytes(28, 30, 34, 240))
      love.graphics.rectangle("fill", btnX, btnY, btnW, btnH)

      if btnHovered then
        love.graphics.setColor(love.math.colorFromBytes(101, 24, 24, 210))
        love.graphics.rectangle("fill", btnX + 1, btnY + 1, btnW - 2, btnH - 2)
      end

      love.graphics.setColor(love.math.colorFromBytes(75, 80, 90, 255))
      love.graphics.rectangle("line", btnX, btnY, btnW, btnH)

      local btnColor = { 255, 255, 255, fade }
      drawCleanShadowText(opt.buttonText or "EXECUTE", btnX, btnY + 4, btnW, "center", cardFont or bigFont, btnColor)
    end
  end

  -- Bottom Tooltip Bar (clamped inside window bounds)
  if currentTooltip ~= "" and nonoFont then
    love.graphics.setColor(love.math.colorFromBytes(0, 0, 0, 160))
    love.graphics.rectangle("fill", 50, 640, 1025, 30)
    love.graphics.setFont(nonoFont)
    love.graphics.setColor(love.math.colorFromBytes(255, 255, 255, fade))
    love.graphics.printf(currentTooltip, 60, 646, 1005, "left")
  end
end

-- Export functions to gmenu_core
gmenu_core.UI = gmenu_ui
gmenu_core.registerMainMenuButton = gmenu_ui.registerMainMenuButton
gmenu_core.registerModModesButtons = gmenu_ui.registerModModesButtons
gmenu_core.registerModOptionsButtons = gmenu_ui.registerModOptionsButtons
gmenu_core.drawMainMenuButton = gmenu_ui.drawMainMenuButton
gmenu_core.drawModModes = gmenu_ui.drawModModes
gmenu_core.drawModOptions = gmenu_ui.drawModOptions

return gmenu_ui
