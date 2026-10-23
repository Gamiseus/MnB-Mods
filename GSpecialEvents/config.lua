-- ============================================================================
-- config.lua — GSpecialEvents Configuration Definition for GMenu
-- Dynamic, single-page settings: switching the active event dynamically populates
-- its specific options (e.g. Halloween MoonGrave) directly beneath the cycler.
-- ============================================================================

local function isHalloweenActive()
  return (SpecialEvents and SpecialEvents.getActiveEvent() == "Halloween")
end

local config = {
  name = "Special Events",
  options = {
    -- ========================================================================
    -- 1. PRIMARY EVENT SELECTOR (Always Visible)
    -- ========================================================================
    {
      id = "event_select",
      label = "Active Special Event",
      type = "cycle",
      options = { "Auto", "Halloween", "Xmas", "Remembrance", "Brest", "HoG", "Aachen", "Cologne", "Outskirt", "None" },
      labels = {
        "Auto (Calendar)",
        "Halloween (Moon Grave)",
        "Christmas (Bastogne)",
        "Remembrance (Tribute)",
        "Brest (Urban)",
        "Heart of Germany",
        "Aachen (Back Alleys)",
        "Cologne (Reinforced)",
        "Outskirts (Hill 103)",
        "None (Disabled)"
      },
      default = "Auto",
      description = "Designate which special event mode is active and available on the Classic Mode deployment screen (Default: Auto)",
      get = function()
        return (SpecialEvents and SpecialEvents.getSelectedEvent()) or "Auto"
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.setSelectedEvent(val)
        end
      end
    },

    -- ========================================================================
    -- 2. HALLOWEEN DYNAMIC CONFIGURATION (Visible when Active Event == Halloween)
    -- ========================================================================
    {
      id = "halloween_3way_zombies",
      label = "Zombies Attack Germans",
      type = "checkbox",
      default = 1,
      description = "Enables zombies to hunt and melee attack German troops in Halloween MoonGrave (3-way war)",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.zombiesAttackGermans) or 1
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.zombiesAttackGermans = (val == 1 or val == true) and 1 or 0
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_3way_germans",
      label = "Germans Attack Zombies",
      type = "checkbox",
      default = 1,
      description = "Enables German infantry, gunners, and officers to acquire and shoot undead zombies",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.germansAttackZombies) or 1
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.germansAttackZombies = (val == 1 or val == true) and 1 or 0
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_reanimation",
      label = "Corpse Reanimation",
      type = "checkbox",
      default = 1,
      description = "Enables fallen Allied and Axis soldiers to rise from the dead as zombies after a short delay",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.corpseReanimation) or 1
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.corpseReanimation = (val == 1 or val == true) and 1 or 0
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_reanim_target",
      label = "Reanimation Condition",
      type = "cycle",
      options = { "Zombie Kills Only", "All Casualties" },
      labels = { "Zombie Kills Only", "All Casualties" },
      default = "Zombie Kills Only",
      description = "Determines whether only soldiers slain by zombies reanimate, or all battlefield casualties",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.reanimationTarget) or "Zombie Kills Only"
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.reanimationTarget = val
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_reanim_delay",
      label = "Rising Delay",
      type = "cycle",
      options = { 1.0, 5.0, 15.0, 30.0 },
      labels = { "1s (Rapid)", "5s (Standard)", "15s (Slow)", "30s (Lurking)" },
      default = 5.0,
      description = "Seconds elapsed after a soldier's death before their corpse reanimates as a zombie",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.reanimationDelay) or 5.0
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.reanimationDelay = tonumber(val) or 2.5
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_zombie_hp",
      label = "Zombie Health",
      type = "cycle",
      options = { 100, 250, 500, 750, 1000, 2000 },
      labels = { "100 (Fragile)", "250 (Weak)", "500 (Standard)", "750 (Hardy)", "1000 (Brute)", "2000 (Juggernaut)" },
      default = 500,
      description = "Maximum health pool of newly spawned and reanimated zombies (Vanilla: 500)",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.zombieHealth) or 500
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.zombieHealth = tonumber(val) or 500
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_zombie_speed",
      label = "Zombie Speed",
      type = "cycle",
      options = { 0.6, 1.0, 1.3, 1.65, 2.0 },
      labels = { "0.6x (Shambler)", "1.00x (Standard)", "1.30x (Fast)", "1.65x (Runner)", "2.00x (Sprinter)" },
      default = 1.0,
      description = "Movement speed multiplier applied to zombies during MoonGrave",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.zombieSpeedMult) or 1.0
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.zombieSpeedMult = tonumber(val) or 1.0
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_spawns",
      label = "Spawn Distribution",
      type = "cycle",
      options = { "Distributed", "Tombs Only", "Everywhere" },
      labels = { "Distributed (Front & Tombs)", "Tombs Only (Vanilla)", "Everywhere (Chaotic)" },
      default = "Distributed",
      description = "Where zombies spawn: dynamic frontline & tombs, tombs only, or all over the map",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.spawnDistribution) or "Distributed"
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.spawnDistribution = val
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_wave_freq",
      label = "Wave Rising Chance",
      type = "cycle",
      options = { 10, 25, 40, 75, 100 },
      labels = { "10% (Vanilla)", "25% (Frequent)", "40% (Swarm)", "75% (Nightmare)", "100% (Every Wave)" },
      default = 25,
      description = "Percentage probability per enemy wave for an undead rising to occur (Vanilla: 10%)",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.waveSpawnChance) or 25
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.waveSpawnChance = tonumber(val) or 25
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_zombie_dmg",
      label = "Zombie Claws Damage",
      type = "cycle",
      options = { 15, 25, 40, 60 },
      labels = { "15 (Light)", "25 (Standard)", "40 (Vicious)", "60 (Lethal)" },
      default = 25,
      description = "Base damage dealt by zombies in close quarters melee combat",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.zombieClawsDamage) or 25
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.zombieClawsDamage = tonumber(val) or 25
          SpecialEvents.saveSettings()
        end
      end
    },
    {
      id = "halloween_sound_death",
      label = "Revive Zombie Audio",
      type = "checkbox",
      default = 1,
      description = "Plays the unused vanilla zombieDeathSound when an undead zombie is eliminated",
      showIf = isHalloweenActive,
      get = function()
        return (SpecialEvents and SpecialEvents.settings.halloween.soundDeath) or 1
      end,
      set = function(val)
        if SpecialEvents then
          SpecialEvents.settings.halloween.soundDeath = (val == 1 or val == true) and 1 or 0
          SpecialEvents.saveSettings()
        end
      end
    }
  }
}

return config
