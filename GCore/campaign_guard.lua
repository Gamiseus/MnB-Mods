local campaign_guard = {}

local function isCampaignMenuState()
  return player and player.gameType == 0 and player.ui_gameStarted == 0
end

--- Ensure slots 1..6 of player.deployedTroops are Allied player-controlled soldiers.
--- Only acts on the Campaign profile while no mission is in progress.
function campaign_guard.ensureValidSquad()
  if not isCampaignMenuState() then return end
  player.deployedTroops = player.deployedTroops or {}

  local squad, others = {}, {}
  for i = 1, #player.deployedTroops do
    local u = player.deployedTroops[i]
    if type(u) == "table" then
      if u.faction == "allied" and u.playerControlled == 1 and #squad < 6 then
        squad[#squad + 1] = u
      else
        others[#others + 1] = u
      end
    end
  end

  local needed = 6 - #squad
  local outOfOrder = false
  for i = 1, math.min(6, #player.deployedTroops) do
    if player.deployedTroops[i] ~= squad[i] then outOfOrder = true break end
  end

  if needed <= 0 and not outOfOrder then return end

  if needed > 0 then
    print(string.format("[GCore CampaignGuard] Campaign squad missing %d soldier(s); generating replacements", needed))
    if not createAlliedSoldier then return end
    for _ = 1, needed do
      local u = {}
      createAlliedSoldier(u)
      squad[#squad + 1] = u
    end
  else
    print("[GCore CampaignGuard] Reordering deployedTroops so squad occupies slots 1-6")
  end

  local rebuilt = {}
  for _, u in ipairs(squad) do rebuilt[#rebuilt + 1] = u end
  for _, u in ipairs(others) do rebuilt[#rebuilt + 1] = u end
  player.deployedTroops = rebuilt
end

--- Reload the Campaign profile if we are on the main menu with a non-campaign profile in memory.
function campaign_guard.restoreCampaignIfActive()
  if not player then return end
  if player.gameType ~= 0 and love and love.filesystem and love.filesystem.getInfo('saveMNB3.lua') then
    print("[GCore CampaignGuard] Non-campaign profile in memory on main menu; reloading saveMNB3.lua")
    local ok, loaded = pcall(function() return love.filesystem.load('saveMNB3.lua')() end)
    if ok and type(loaded) == "table" then
      player = loaded
      player.gameType = 0
    end
  end
  campaign_guard.ensureValidSquad()
end

--- Called right before saveMNB3.lua is written.
function campaign_guard.sanitizeSave()
  campaign_guard.ensureValidSquad()
end

_G.campaign_guard = campaign_guard
return campaign_guard
