local sin, cos, rad, deg, atan2, abs = math.sin, math.cos, math.rad, math.deg, math.atan2, math.abs
local PI = 3.141592653589793
local HALF_PI = 1.5707963267948966

local particlePool = {}
local MAX_POOL_SIZE = 1500

local function acquireParticle()
  local p = particlePool[#particlePool]
  if p then
    particlePool[#particlePool] = nil
    return p
  end
  return {}
end

local function releaseParticle(p)
  if p and #particlePool < MAX_POOL_SIZE then
    p.targetx = nil
    p.targety = nil
    p.trail = ""
    p.sprite = nil
    p.nextFrame = ""
    p.sleeping = nil
    particlePool[#particlePool + 1] = p
  end
end

function topParticleUpdate(dt)
  local list = player.topParticles
  if not list then return end
  local count = #list
  local writeIdx = 1
  local dt60 = dt * 60

  for readIdx = 1, count do
    local ticle = list[readIdx]

    if ticle then
      ticle.lifeSpan = ticle.lifeSpan - dt
      ticle.targetRotation = ticle.rotationz
    if(ticle.typez == "pamphlet") then
      ticle.targetRotation = rad(randNbr(360))
    end
    ticle.innerRotation = ticle.innerRotation + (ticle.spin * dt60)
    ticle.x = ticle.x + ticle.drift

    if(ticle.drag > 0 and ticle.velocity > 0) then 
      ticle.velocity = ticle.velocity - (ticle.drag * dt60)
      if(ticle.velocity <= 0) then 
        ticle.velocity = 0
        ticle.spin = 0
      end
    end

    if(ticle.fade > 0) then 
      ticle.alpha = ticle.alpha - (ticle.fade * dt60)
    end

    local rotDiff = ticle.targetRotation - ticle.rotationz
    if(abs(rotDiff) > 0.1) then
      if(rotDiff > 0) then
        ticle.rotationz = ticle.rotationz + 0.1
      else 
        ticle.rotationz = ticle.rotationz - 0.1
      end
    end

    ticle.scale = ticle.scale + (ticle.expand * dt)

    -- Pre-computed move step (skip trig if stationary)
    if(ticle.velocity > 0) then
      local moveStep = ticle.velocity * dt
      local moveAngle = ticle.rotationz + PI
      ticle.x = ticle.x + sin(moveAngle) * moveStep
      ticle.y = ticle.y - cos(moveAngle) * moveStep
    end

    if(ticle.lifeSpan >= 0) then
      list[writeIdx] = ticle
      writeIdx = writeIdx + 1
    else
      if(ticle.typez == "parachute") then
        player.lootables[#player.lootables+1] = {}
        player.lootables[#player.lootables].name = "cargoCrate"
        player.lootables[#player.lootables].x = ticle.x
        player.lootables[#player.lootables].y = ticle.y
        player.lootables[#player.lootables].flagged = 1
        player.lootables[#player.lootables].faction = "allied"
        player.lootables[#player.lootables].argument = ticle.faction
        player.lootables[#player.lootables].size = 10
        player.lootables[#player.lootables].rotation = rad(randNbr(360))
        local clone_sfx12 = crateDrop:clone()
        clone_sfx12:setVolume(ambiantScale(alliedFrontLine(), 360))
        clone_sfx12:play() 
        if(randNbr(100) < 50) then 
          local clone_sfx13
          if(player.tension > 0) then 
            clone_sfx13 = _G["supply"..randNbr(7)]:clone()
          else
            clone_sfx13 = _G["crateJoke"..randNbr(3)]:clone()
          end
          clone_sfx13:setVolume(ambiantScale(alliedFrontLine(), 360))
          clone_sfx13:play() 
        end
      elseif(ticle.typez == "parachuteAxis") then
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "groundParachute"
        player.deco[#player.deco].x = ticle.x
        player.deco[#player.deco].y = ticle.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        local clone_sfx12 = _G["paraLand"..randNbr(6)]:clone()
        clone_sfx12:setVolume(ambiantScale(alliedFrontLine(), 360))
        clone_sfx12:play()
        createParaFJ(ticle.x, ticle.y)
      elseif(ticle.typez == "parachuteAllied") then
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "groundParachute"
        player.deco[#player.deco].x = ticle.x
        player.deco[#player.deco].y = ticle.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        local clone_sfx12 = _G["paraLand"..randNbr(6)]:clone()
        clone_sfx12:setVolume(ambiantScale(alliedFrontLine(), 360))
        clone_sfx12:play() 
        createPara(ticle.x - randNbr(200) + 100, ticle.y - randNbr(200) + 100, player.gameType)
        if(ticle.faction == 99) then 
          player.deployedTroops[#player.deployedTroops].bridgeSoldier = 1
        end
        if(stepInTree(player.deployedTroops[#player.deployedTroops])) then 
          for o = 1, 6, 1 do
            local newPart = acquireParticle()
            addParticle(newPart, "leafChip", player.deployedTroops[#player.deployedTroops].x, player.deployedTroops[#player.deployedTroops].y, rad(randNbr(360)))
            table.insert(player.particles, newPart)
          end
          spawnBlood(player.deployedTroops[#player.deployedTroops])
          player.deployedTroops[#player.deployedTroops].health = player.deployedTroops[#player.deployedTroops].health - randNbr(25)
          local clone_sfx1 = _G["treeLand"..randNbr(5)]:clone()
          clone_sfx1:setVolume(stepScale(player.deployedTroops[#player.deployedTroops]) / 2.3)
          clone_sfx1:play() 
          local clone_sfx17 = _G["alliedHurt"..randNbr(30)]:clone()
          clone_sfx17:setVolume(stepScale(player.deployedTroops[#player.deployedTroops]) / 2.3)
          clone_sfx17:play() 
        end
      elseif(ticle.typez == "pamphlet") then
          player.deco[#player.deco+1] = {}
          player.deco[#player.deco].name = "pamphletSmall"
          player.deco[#player.deco].x = ticle.x
          player.deco[#player.deco].y = ticle.y
          player.deco[#player.deco].size = 10
          player.deco[#player.deco].immunity = 1
          player.deco[#player.deco].rotation = rad(randNbr(360))
        end
        releaseParticle(ticle)
      end
    end
  end

  for i = writeIdx, count do
    list[i] = nil
  end
end

function spawnParticle(typez, x, y, rotationz, isTop)
  local p = acquireParticle()
  addParticle(p, typez, x, y, rotationz)
  local targetList = isTop and player.topParticles or player.particles
  targetList[#targetList + 1] = p
  return p
end


local function getCenterOffsets(sprite, swap)
  local img = _G[sprite]
  if img and img.getWidth then
    local w = img:getWidth() * 0.5
    local h = img:getHeight() * 0.5
    if swap then return h, w else return w, h end
  end
  return 15, 15
end

local P_REGISTRY = {}

-- 1. Helper: Standard Debris & Flashes
local function setupBaseDebris(p, sprite, vel, spin, life, xo, yo, drag, scale, trail)
  p.sprite = sprite
  p.velocity = vel
  p.spin = spin
  p.lifeSpan = life
  p.xoffset = xo
  p.yoffset = yo
  p.drag = drag or 3
  p.scale = scale or 1
  p.trail = trail or ""
end

-- 2. Helper: Vehicle Debris Family
local function setupVehicleDebris(p, typez, scale, xoffset, yoffset, drag, vel, life)
  p.sprite = typez
  p.velocity = vel or (50 + randNbr(300))
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = life or (240 * (player and player.option_maxParticles or 1))
  if xoffset and yoffset then
    p.xoffset = xoffset
    p.yoffset = yoffset
  else
    p.xoffset, p.yoffset = getCenterOffsets(typez, true)
  end
  p.drag = drag or 3
  p.scale = scale or 1.2
  p.trail = (randNbr(100) < 50) and "smokeDrip" or ""
end

-- 3. Helper: Gibs Family
local function setupGib(p, typez)
  p.sprite = typez
  p.velocity = 50 + randNbr(300)
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset = 6
  p.yoffset = 9
  p.drag = 3
  p.scale = 1.2
  p.trail = "bloodDrip"
end

-- 4. Helper: Magazines
local function setupMag(p, typez)
  p.sprite = typez
  p.velocity = 50 + randNbr(70)
  p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 30 * (player and player.option_maxParticles or 1)
  p.xoffset, p.yoffset = getCenterOffsets(typez, false)
  p.drag = 3
  p.waterSplash = true
end

-- 5. Helper: Empty Weapon Tubes
local function setupEmptyWeapon(p, typez, sprite)
  p.sprite = sprite or typez
  p.velocity = 50 + randNbr(70)
  p.rotationz = p.rotationz - math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 60 * (player and player.option_maxParticles or 1)
  p.xoffset, p.yoffset = getCenterOffsets(p.sprite, false)
  p.drag = 3
  p.waterSplash = true
end

-- 6. Helper: Smoke Props
local function setupSmokeProp(p, typez, sprite)
  p.sprite = sprite
  p.velocity = 50 + randNbr(70)
  p.rotationz = math.rad(randNbr(360))
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset = 7
  p.yoffset = 10
  p.drag = 3
  p.scale = 1
  p.replaceable = 1
  p.immunity = 1
end

-- 7. Helper: Smoke Balls
local function setupSmokeBall(p, typez)
  p.sprite = typez .. randNbr(3)
  p.velocity = 10
  p.innerRotation = p.rotationz
  p.spin = 0
  p.lifeSpan = 20
  p.xoffset = 5
  p.yoffset = 5
  p.drag = 0.1
  p.alpha = 50
  p.fade = randNbr(5) / 10
  p.expand = 0
end

-- 8. Helper: Smoke Screens
local function setupSmokeScreen(p, typez, sprite, expand, life)
  p.typez = "bigSmoke"
  p.sprite = sprite or typez
  p.velocity = randNbr(3)
  p.rotationz = randNbr(360)
  p.innerRotation = randNbr(360)
  p.spin = (randNbr(6) - 3) / 1000
  p.lifeSpan = life or 20
  p.xoffset = 100
  p.yoffset = 90
  p.drag = 0
  p.alpha = 150
  p.fade = 0.05
  p.expand = expand or 0.0001
  p.scale = 0.5
  p.immunity = 1
end

-- 9. Helper: Drips
local function setupDrip(p, typez, sprite, xo, yo)
  p.typez = (typez == "waterDrips" and "waterDrip" or typez)
  p.sprite = sprite or (p.typez .. randNbr(3))
  p.velocity = 0
  p.innerRotation = p.rotationz
  p.spin = 0
  p.lifeSpan = 15
  p.xoffset = xo or 5
  p.yoffset = yo or 5
  p.drag = 0.1
  p.alpha = 150
  p.fade = randNbr(10) / 5
  p.expand = 0
end

-- 10. Helper: Thrown Smoke Grenades
local function setupThrownSmoke(p, typez)
  p.typez = "fragGrenade"
  p.sprite = typez
  p.velocity = 500
  p.spin = randNbr(100) / 10
  p.lifeSpan = 2
  p.xoffset = 7
  p.yoffset = 10
  p.drag = 1
  p.immunity = 1
end

-- Flashes & Hits
P_REGISTRY["muzzleFlash"] = function(p)
  p.sprite = "muzzleFlash" .. randNbr(5)
  p.lifeSpan = 0.05; p.nextFrame = "muzzleFlash2"; p.xoffset = 18; p.yoffset = -25; p.alpha = 100; p.immunity = 1
end
P_REGISTRY["flamerFlash"] = function(p)
  p.sprite = "flamerFlame" .. randNbr(4)
  p.lifeSpan = 0.03; p.xoffset = 65; p.yoffset = -35; p.alpha = 25; p.immunity = 1
end
P_REGISTRY["extinguisherFlash"] = function(p)
  p.sprite = "extinguisherFlame" .. randNbr(4)
  p.lifeSpan = 0.03; p.xoffset = 154; p.yoffset = -35; p.alpha = 25
end
P_REGISTRY["metalFlash"] = function(p)
  p.sprite = "flarePart"; p.rotationz = 0; p.innerRotation = 0; p.lifeSpan = 0.05; p.xoffset = 14; p.yoffset = -20; p.alpha = 100
end
P_REGISTRY["armorHit"] = function(p)
  p.sprite = "armorHit"; p.lifeSpan = 0.05; p.alpha = 100
end
P_REGISTRY["bigArmorHit"] = function(p)
  p.sprite = "bigArmorHit"; p.lifeSpan = 0.08; p.xoffset, p.yoffset = getCenterOffsets(p.sprite, false); p.alpha = 100
end
P_REGISTRY["tankFlash1"] = function(p)
  p.sprite = "bazookaFlash1"; p.velocity = 2000; p.lifeSpan = 0.03; p.xoffset = 20; p.yoffset = -60; p.alpha = 100
end
P_REGISTRY["tankFlash2"] = function(p)
  p.sprite = "bazookaFlash2"; p.velocity = 3000; p.lifeSpan = 0.04; p.xoffset = 20; p.yoffset = -60; p.alpha = 100
end
P_REGISTRY["bazookaFlash1"] = function(p)
  p.sprite = "bazookaFlash1"; p.velocity = 50; p.lifeSpan = 0.3; p.xoffset = 20; p.yoffset = -20; p.alpha = 100
end
P_REGISTRY["bazookaFlash2"] = function(p)
  p.sprite = "bazookaFlash2"; p.velocity = 300; p.lifeSpan = 0.3; p.xoffset = 20; p.yoffset = -60; p.alpha = 100
end
P_REGISTRY["muzzleSpark"] = function(p)
  p.sprite = "muzzleSpark"; p.velocity = 600 + randNbr(200); p.rotationz = p.rotationz + math.rad(10 - randNbr(20))
  p.lifeSpan = 5; p.xoffset = 8; p.yoffset = -20; p.fade = 10
end

-- Shells & Clips
P_REGISTRY["shell"] = function(p)
  p.sprite = "shell"; p.velocity = 50 + randNbr(70); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 10
  p.lifeSpan = 30 * (player and player.option_maxParticles or 1); p.xoffset = 2; p.yoffset = 2; p.drag = 1
end
P_REGISTRY["smallShell"] = function(p)
  p.sprite = "smallShell"; p.velocity = 50 + randNbr(70); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 10
  p.lifeSpan = 30 * (player and player.option_maxParticles or 1); p.xoffset = 1; p.yoffset = 1; p.drag = 1
end
P_REGISTRY["bigShell"] = function(p)
  p.sprite = "bigShell"; p.velocity = 50 + randNbr(70); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 30
  p.lifeSpan = 30 * (player and player.option_maxParticles or 1)
  p.xoffset, p.yoffset = getCenterOffsets("bigShell", true); p.drag = 1
end
P_REGISTRY["shotGunShell"] = function(p)
  p.sprite = "shotGunShell"; p.velocity = 50 + randNbr(70); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = 10 - randNbr(20)
  p.lifeSpan = 30 * (player and player.option_maxParticles or 1); p.xoffset = 2; p.yoffset = 2; p.drag = 1; p.alpha = 100
end
P_REGISTRY["m1Clip"] = function(p)
  p.sprite = "m1Clip"; p.velocity = 50 + randNbr(70); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = -randNbr(3)
  p.lifeSpan = 30 * (player and player.option_maxParticles or 1); p.xoffset = 2; p.yoffset = 2; p.drag = 1
end
P_REGISTRY["link"] = function(p)
  p.sprite = "link"; p.velocity = 50 + randNbr(70); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = 10 - randNbr(20)
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset = 2; p.yoffset = 2; p.drag = 1; p.alpha = 100
end

-- Magazines
P_REGISTRY["genericMag"] = setupMag
local mags = { "m3Mag", "g43Mag", "mg15Mag", "ammoBox", "ammoPan", "barMag", "brenMag", "tommyMag", "m1CarbineMag", "mp40Mag", "stgMag", "ppshMag" }
for i = 1, #mags do P_REGISTRY[mags[i]] = setupMag end

-- Empty Launchers/Weapons
P_REGISTRY["emptyFaust"] = function(p) setupEmptyWeapon(p, "emptyFaust", "emptyFaust") end
P_REGISTRY["emptyImprovedFaust"] = function(p) setupEmptyWeapon(p, "emptyImprovedFaust", "emptyImprovedFaust") end
P_REGISTRY["emptyFlieger"] = function(p) setupEmptyWeapon(p, "emptyFlieger", "emptyFlieger") end
P_REGISTRY["emptyBoys"] = function(p) setupEmptyWeapon(p, "emptyBoys", "emptyBoysRifle") end
P_REGISTRY["emptyPz39"] = function(p) setupEmptyWeapon(p, "emptyPz39", "emptyPz39Rifle") end
P_REGISTRY["emptyLeuchtPistole"] = function(p) setupEmptyWeapon(p, "emptyLeuchtPistole", "emptyLeuchtPistole") end

-- Smokes & Atmospheric Clouds
P_REGISTRY["bigSmoke"] = function(p)
  p.sprite = "bigSmoke"; p.velocity = randNbr(3); p.rotationz = randNbr(360); p.innerRotation = randNbr(360)
  p.spin = 0.001; p.lifeSpan = 10; p.xoffset = 70; p.yoffset = 60; p.alpha = 100; p.fade = 0.2; p.expand = 0.001; p.scale = 0.5
end
P_REGISTRY["blackSmoke"] = function(p)
  p.sprite = "blackSmoke"; p.velocity = randNbr(3); p.rotationz = randNbr(360); p.innerRotation = randNbr(360)
  p.spin = 0.001; p.lifeSpan = 8; p.xoffset = 100; p.yoffset = 90; p.alpha = 90; p.fade = 0.2; p.expand = 0.003; p.scale = 0.5
end
P_REGISTRY["frontSmoke"] = function(p)
  p.sprite = "frontSmoke" .. randNbr(3); p.velocity = 30; p.lifeSpan = 30; p.xoffset = 20; p.yoffset = 0; p.drag = 0.1; p.alpha = 50; p.fade = randNbr(5) / 10; p.expand = 0.1
end
P_REGISTRY["exSmoke"] = function(p)
  p.typez = "lilSteam"; p.sprite = "lilSteam" .. randNbr(4); p.velocity = 60 + randNbr(80); p.rotationz = p.rotationz + math.rad(15 - randNbr(30))
  p.lifeSpan = 0.5 + (randNbr(50) / 10); p.xoffset = 5; p.yoffset = 5; p.drag = 0.01; p.alpha = 75; p.fade = randNbr(5) / 10; p.expand = 0.5
end
P_REGISTRY["frontSmokeBig"] = function(p)
  p.sprite = "frontSmokeBig" .. randNbr(3); p.velocity = 0.1; p.lifeSpan = 30; p.xoffset = 20; p.yoffset = -100; p.alpha = 50; p.fade = randNbr(5) / 10; p.expand = 0.3
end
P_REGISTRY["lilSmoke"] = function(p)
  p.sprite = "lilSmoke" .. randNbr(4); p.velocity = 0.001; p.lifeSpan = 20; p.xoffset = 5; p.yoffset = 5; p.drag = 0.1; p.alpha = 75; p.fade = randNbr(5) / 10; p.expand = 0.7
end
P_REGISTRY["lilSteam"] = function(p)
  p.sprite = "lilSteam" .. randNbr(4); p.velocity = 0.001; p.lifeSpan = 20; p.xoffset = 5; p.yoffset = 5; p.drag = 0.1; p.alpha = 75; p.fade = randNbr(5) / 10; p.expand = 0.2
end
P_REGISTRY["dustCloud"] = function(p)
  p.sprite = "dustCloud"; p.innerRotation = randNbr(360); p.spin = (randNbr(6) - 3) / 1000; p.lifeSpan = 20 + randNbr(10); p.xoffset = 49; p.yoffset = 44; p.alpha = 80; p.fade = 0.15; p.expand = 0.001
end
P_REGISTRY["steamCloud"] = P_REGISTRY["dustCloud"]

-- Smoke Balls & Smoke Grenade Puffs
local sBalls = { "whiteSmokeBall", "blackSmokeBall", "redSmokeBall", "pinkSmokeBall", "greySmokeBall", "purpleSmokeBall", "blueSmokeBall", "yellowSmokeBall", "smoke1", "smoke2", "smoke3" }
for i = 1, #sBalls do
  local name = sBalls[i]
  if name:sub(1, 5) == "smoke" and #name == 6 then
    P_REGISTRY[name] = function(p)
      p.sprite = name; p.velocity = 10; p.lifeSpan = 20; p.xoffset = 5; p.yoffset = 5; p.drag = 0.1; p.alpha = 50; p.fade = randNbr(5) / 10
    end
  else
    P_REGISTRY[name] = setupSmokeBall
  end
end

-- Smoke Screens
P_REGISTRY["smokeScreen"] = function(p) setupSmokeScreen(p, "smokeScreen", "bigSmoke", 0.01) end
P_REGISTRY["smokeScreen2"] = function(p)
  setupSmokeScreen(p, "smokeScreen2", "smokeScreen2", 0.01)
  p.xoffset, p.yoffset = getCenterOffsets("smokeScreen2", true)
end
P_REGISTRY["smokeScreen3"] = function(p)
  setupSmokeScreen(p, "smokeScreen3", "smokeScreen3", 0.01, 5)
  p.xoffset, p.yoffset = getCenterOffsets("smokeScreen3", true)
end
local sScreens = { "redSmokeScreen", "pinkSmokeScreen", "purpleSmokeScreen", "yellowSmokeScreen", "greySmokeScreen", "blueSmokeScreen" }
for i = 1, #sScreens do P_REGISTRY[sScreens[i]] = setupSmokeScreen end

-- Sparks & Fire
P_REGISTRY["spark1"] = function(p)
  p.sprite = "spark1"; p.velocity = 100 + randNbr(200); p.rotationz = p.rotationz + math.rad(20 - randNbr(40)); p.innerRotation = randNbr(360); p.spin = 10 - randNbr(20); p.lifeSpan = 5; p.drag = randNbr(3); p.fade = 5
end
P_REGISTRY["spark2"] = function(p)
  p.sprite = "spark2"; p.velocity = 100 + randNbr(200); p.rotationz = p.rotationz + math.rad(20 - randNbr(40)); p.innerRotation = randNbr(360); p.spin = 10 - randNbr(20); p.lifeSpan = 5; p.xoffset = 1.5; p.yoffset = 1.5; p.drag = randNbr(3); p.fade = 5
end
P_REGISTRY["spark3"] = function(p)
  p.sprite = "spark3"; p.velocity = 100 + randNbr(200); p.rotationz = p.rotationz + math.rad(20 - randNbr(40)); p.innerRotation = randNbr(360); p.spin = 10 - randNbr(20); p.lifeSpan = 5; p.drag = randNbr(3); p.fade = 5
end
P_REGISTRY["fireSpark"] = function(p)
  p.typez = "spark" .. randNbr(3); p.sprite = p.typez; p.velocity = 100 + randNbr(200); p.rotationz = math.rad(180); p.innerRotation = 0; p.lifeSpan = 5; p.drag = randNbr(3); p.fade = 5
end
P_REGISTRY["fireBall"] = function(p)
  p.sprite = "fireBall"; p.velocity = (500 + randNbr(700)) * 1.5; p.rotationz = p.rotationz + math.rad(20 - randNbr(40)); p.lifeSpan = 0.2; p.drag = 10; p.fade = 5; p.shrink = ((5 + randNbr(20)) / 10) * 2
end
P_REGISTRY["brightBall"] = function(p)
  p.sprite = "brightBall"; p.velocity = 350 + randNbr(300); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10; p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset, p.yoffset = getCenterOffsets("brightBall", true); p.drag = 0.5; p.fade = 5; p.scale = 0.5; p.trail = (randNbr(100) < 50) and "burnDrip" or ""
end

-- Projectile Balls (wpBall, gasBall, waterBall, etc.)
local function setupProjBall(p, baseName, trailName, drift)
  p.sprite = baseName .. randNbr(3)
  p.velocity = 200 + randNbr(300)
  p.innerRotation = randNbr(360)
  p.lifeSpan = (randNbr(baseName == "waterBall" and 10 or 20) * (player and player.option_maxParticles or 1)) / 10
  if baseName == "waterBall" then p.xoffset = 0; p.yoffset = 0 else p.xoffset, p.yoffset = getCenterOffsets(p.sprite, true) end
  p.drag = 3
  p.scale = 0.5
  p.drift = drift or 0
  p.trail = trailName
end
P_REGISTRY["wpBall"] = function(p) setupProjBall(p, "wpBall", "wpDrip") end
P_REGISTRY["gasBall"] = function(p) setupProjBall(p, "gasBall", "gasDrip") end
P_REGISTRY["waterBall"] = function(p) setupProjBall(p, "waterBall", "waterDrips", -4) end
P_REGISTRY["waterBall2"] = function(p) p.typez = "waterBall"; setupProjBall(p, "waterBall", "waterDrips", 0) end
P_REGISTRY["exploDebris"] = function(p)
  p.typez = "wpBall"; p.sprite = "exploDebris" .. randNbr(4); p.velocity = 200 + randNbr(300); p.innerRotation = randNbr(360)
  p.lifeSpan = (randNbr(20) * (player and player.option_maxParticles or 1)) / 10; p.xoffset, p.yoffset = getCenterOffsets(p.sprite, true); p.drag = 3; p.scale = 0.5; p.trail = "smokeDrip"
end
P_REGISTRY["metalChunk"] = function(p)
  p.sprite = "metalChunk" .. randNbr(10); p.velocity = 200 + randNbr(300); p.innerRotation = randNbr(360)
  p.lifeSpan = 120 * (player and player.option_maxParticles or 1); p.xoffset, p.yoffset = getCenterOffsets(p.sprite, true); p.drag = 2; p.trail = "smokeDrip"
end
P_REGISTRY["fish"] = function(p)
  p.sprite = "fish" .. randNbr(2)
  if randNbr(100) >= 90 then p.sprite = "fish3" end
  if randNbr(100) >= 80 then p.sprite = "fish4" end
  p.velocity = 200 + randNbr(300); p.innerRotation = randNbr(360); p.lifeSpan = 10 * (player and player.option_maxParticles or 1); p.drag = 3; p.scale = 0.1; p.trail = "someDrips"
end

-- Tracers
local tracers = { tracer = 950, tankTracer = 950, tracerAA = 950, tracerAP = 1000, tracerInc = 900, tracerRed = 990 }
for name, spd in pairs(tracers) do
  P_REGISTRY[name] = function(p) p.sprite = name; p.velocity = spd; p.lifeSpan = 0.2; p.alpha = 100 end
end

-- Drips
P_REGISTRY["bloodDrip"] = function(p) setupDrip(p, "bloodDrip") end
P_REGISTRY["wpDrip"] = function(p) setupDrip(p, "wpDrip") end
P_REGISTRY["waterDrips"] = function(p) setupDrip(p, "waterDrips", "waterDrip" .. randNbr(3)) end
P_REGISTRY["smokeDrip"] = function(p) setupDrip(p, "smokeDrip") end
P_REGISTRY["gasDrip"] = function(p) setupDrip(p, "gasDrip") end
P_REGISTRY["someDrips"] = function(p)
  setupDrip(p, "someDrips", (randNbr(100) < 75) and ("waterDrip" .. randNbr(3)) or ("bloodDrip" .. randNbr(3)))
end
P_REGISTRY["burnDrip"] = function(p) setupDrip(p, "burnDrip", "spark" .. randNbr(3), 1.5, 1.5) end
P_REGISTRY["flareDrip"] = function(p) setupDrip(p, "flareDrip", "flareDrip" .. randNbr(3), 1.5, 1.5) end

-- Pixels
local function setupPix(p, typez, xo, yo, drag)
  p.sprite = typez
  p.velocity = 200 + randNbr(100)
  p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360)
  p.spin = 10 - randNbr(20)
  p.lifeSpan = 5
  p.xoffset = xo or 2
  p.yoffset = yo or 2
  p.drag = drag or 5
  p.alpha = 100
end
for i = 1, 6 do P_REGISTRY["pix" .. i] = setupPix end

local function setupBloodPix(p, typez)
  p.sprite = typez
  p.velocity = 1000
  p.rotationz = p.rotationz + math.rad(90)
  p.innerRotation = 0
  p.lifeSpan = 60 * (player and player.option_maxParticles or 1)
  p.xoffset = 2
  p.yoffset = 2
  p.drag = 50 + randNbr(200)
  p.alpha = (typez == "bloodPix4") and 200 or 100
end
for i = 1, 5 do P_REGISTRY["bloodPix" .. i] = setupBloodPix end

-- Parachutes & Pamphlets
local function setupChute(p, typez)
  p.sprite = typez; p.velocity = randNbr(3) / 10; p.rotationz = randNbr(360); p.innerRotation = randNbr(360)
  p.spin = 0.001; p.lifeSpan = 5; p.xoffset = 25; p.yoffset = 25; p.expand = -0.03; p.scale = 0.5
end
P_REGISTRY["parachute"] = setupChute
P_REGISTRY["parachuteAxis"] = setupChute
P_REGISTRY["parachuteAllied"] = setupChute
P_REGISTRY["pamphlet"] = function(p)
  p.sprite = "pamphlet"; p.velocity = randNbr(3) / 10; p.rotationz = randNbr(360); p.innerRotation = randNbr(360)
  p.spin = 0.05 + (randNbr(20) / 100)
  if randNbr(100) < 50 then p.spin = -p.spin end
  p.lifeSpan = 5; p.xoffset = 15; p.yoffset = 19; p.expand = -0.05; p.immunity = 1
end
P_REGISTRY["pamphletSmall"] = function(p)
  p.sprite = "pamphletSmall"; p.velocity = randNbr(3) / 10; p.rotationz = randNbr(360); p.innerRotation = randNbr(360)
  p.lifeSpan = 500; p.xoffset = 7; p.yoffset = 9; p.immunity = 1
end
P_REGISTRY["bouncingBetty"] = function(p)
  p.sprite = "bettyPopped"; p.rotationz = randNbr(360); p.innerRotation = randNbr(360); p.spin = 0.1
  p.lifeSpan = 1; p.xoffset = 7; p.yoffset = 15; p.expand = 1; p.scale = 0.5; p.immunity = 1
end
P_REGISTRY["moveDot"] = function(p)
  p.sprite = "moveDot"; p.innerRotation = 0.7; p.lifeSpan = 3; p.fade = 1.5; p.expand = 0.001
end

-- Debris, Planks & Building Rubble
local function setupDebris170(p, sprite, xo, yo, drag, lifeMult)
  p.sprite = sprite
  p.velocity = 50 + randNbr(170)
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = (lifeMult or 120) * (player and player.option_maxParticles or 1)
  p.xoffset = xo
  p.yoffset = yo
  p.drag = drag or 3
end

P_REGISTRY["tree_debris"] = function(p) setupDebris170(p, "tree_debris" .. randNbr(4), 40, 40) end
P_REGISTRY[""] = P_REGISTRY["tree_debris"]
P_REGISTRY["barn_debris"] = function(p) setupDebris170(p, "barn_debris" .. randNbr(3), 40, 40) end
P_REGISTRY["bresGun_debris"] = function(p) p.typez = "brestGun_debris"; setupDebris170(p, "brestGun_debris" .. randNbr(3), 40, 40) end
P_REGISTRY["sapBranch"] = function(p) setupDebris170(p, "sapBranch" .. randNbr(3), 40, 40) end
P_REGISTRY["repairDebris"] = function(p) setupDebris170(p, "repairDebris" .. randNbr(4), 10, 10) end
P_REGISTRY["glassShard"] = function(p) setupDebris170(p, "glassShard" .. randNbr(3), 5, 7, 6) end
P_REGISTRY["rock_debris"] = function(p) setupDebris170(p, "rock_debris" .. randNbr(4), 17, 17) end
P_REGISTRY["achWallDebris"] = function(p) setupDebris170(p, "achWallDebris", 17, 17) end
P_REGISTRY["brestWallDebris"] = function(p) setupDebris170(p, "brestWallDebris" .. randNbr(6), 17, 17) end
P_REGISTRY["brestFortDebris"] = function(p) setupDebris170(p, "brestFortDebris" .. randNbr(4), 17, 17) end
P_REGISTRY["darkBrick_debris"] = function(p) setupDebris170(p, "darkBrick" .. randNbr(2), 9, 5) end
P_REGISTRY["mausoleumBrick"] = function(p) setupDebris170(p, "mausoleumBrick", 9, 5) end
P_REGISTRY["branch"] = function(p) setupDebris170(p, "branch", 33, 38, 3, 240) end
P_REGISTRY["telephonePostDebris1"] = function(p)
  setupDebris170(p, "telephonePostDebris1", 0, 0)
  p.xoffset, p.yoffset = getCenterOffsets("telephonePostDebris1", true)
end
P_REGISTRY["telephonePostDebris2"] = function(p)
  setupDebris170(p, "telephonePostDebris2", 0, 0)
  p.xoffset, p.yoffset = getCenterOffsets("telephonePostDebris2", true)
end
P_REGISTRY["achBushDebris"] = function(p)
  p.sprite = "achBushDebris" .. randNbr(3)
  setupDebris170(p, p.sprite, 0, 0)
  p.xoffset, p.yoffset = getCenterOffsets(p.sprite, true)
end
P_REGISTRY["achLeave"] = function(p)
  setupDebris170(p, "achLeave", 0, 0)
  p.xoffset, p.yoffset = getCenterOffsets("achLeave", true)
end
P_REGISTRY["bandage"] = function(p)
  p.sprite = "bandage_" .. randNbr(5); p.velocity = 50 + randNbr(170); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 20
  p.lifeSpan = 60 * (player and player.option_maxParticles or 1); p.xoffset, p.yoffset = getCenterOffsets(p.sprite, false); p.drag = 3
end

-- Debris 250 (Bunkers & Traps)
local function setupDebris250(p, sprite, xo, yo)
  p.sprite = sprite
  p.velocity = 50 + randNbr(250)
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset = xo
  p.yoffset = yo
  p.drag = 3
end
P_REGISTRY["bunker2_debris"] = function(p) setupDebris250(p, "bunker2_debris" .. randNbr(4), 25, 25) end
P_REGISTRY["tombDebris"] = function(p)
  p.sprite = "tombDebris" .. randNbr(3)
  setupDebris250(p, p.sprite, 0, 0)
  p.xoffset, p.yoffset = getCenterOffsets(p.sprite, true)
end
P_REGISTRY["imoDebris"] = function(p) setupDebris250(p, "imoDebris" .. randNbr(4), 15, 15) end
P_REGISTRY["tankTrapDebris"] = function(p) setupDebris250(p, "tankTrapDebris", 15, 15) end

-- Environmental Foliage & Wood
P_REGISTRY["tree_leaf"] = function(p)
  p.sprite = "leaf" .. randNbr(6); p.velocity = 50 + randNbr(170); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 15 * (player and player.option_maxParticles or 1); p.xoffset = 5; p.yoffset = 9; p.drag = 1; p.fade = 0.2
end
P_REGISTRY["leafChip"] = function(p)
  p.sprite = "leafChip" .. randNbr(5); p.velocity = 25 + randNbr(80); p.innerRotation = randNbr(360); p.spin = (2 - randNbr(4)) / 10
  p.lifeSpan = 60 * (player and player.option_maxParticles or 1); p.xoffset = 6; p.yoffset = 6; p.drag = 1
end
P_REGISTRY["variousLeaf"] = function(p)
  p.sprite = "leaf" .. randNbr(6); p.velocity = 50 + randNbr(170); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 15 * (player and player.option_maxParticles or 1); p.xoffset, p.yoffset = getCenterOffsets(p.sprite, true); p.drag = 1.5; p.fade = 0.2
end
P_REGISTRY["axisHelmet"] = function(p)
  p.sprite = "trenchProp21"; p.velocity = 50 + randNbr(300); p.innerRotation = randNbr(360); p.spin = (3 - randNbr(6)) / 10
  p.lifeSpan = 60 * (player and player.option_maxParticles or 1); p.xoffset = 13; p.yoffset = 12; p.drag = 3; p.trail = "bloodDrip"
end
P_REGISTRY["plant_debris"] = function(p)
  p.sprite = "plant_debris" .. randNbr(4); p.velocity = 50 + randNbr(170); p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 100
  p.lifeSpan = 60 * (player and player.option_maxParticles or 1); p.xoffset = 7; p.yoffset = 7; p.drag = 1
end
P_REGISTRY["log"] = function(p)
  p.sprite = "log" .. randNbr(3); p.velocity = 100 + randNbr(220); p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 100
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset = 17; p.yoffset = 17; p.drag = 2
end
P_REGISTRY["cartWheel"] = function(p)
  p.sprite = "cartWheel"; p.velocity = 100 + randNbr(220); p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 100
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset = 7.5; p.yoffset = 20; p.drag = 2
end
P_REGISTRY["carWheel"] = P_REGISTRY["cartWheel"]
for i = 1, 10 do
  P_REGISTRY["car_debris" .. i] = function(p)
    p.sprite = "car_debris" .. i; p.velocity = 100 + randNbr(320); p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 100
    p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset = 7.5; p.yoffset = 20; p.drag = 2
  end
end
P_REGISTRY["hayStack_debris"] = function(p)
  p.sprite = "hayStack_debris" .. randNbr(3); p.velocity = 50 + randNbr(170); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset = 2; p.yoffset = 2; p.drag = 1
end
P_REGISTRY["smallPlank"] = function(p)
  p.sprite = "smallPlank" .. randNbr(4); p.velocity = 50 + randNbr(170); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset = 10; p.yoffset = 5; p.drag = 3
end

local function setupRotatingPlank(p, sprite, xo, yo, drag, vel)
  p.sprite = sprite
  p.velocity = vel or (50 + randNbr(300))
  p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset = xo
  p.yoffset = yo
  p.drag = drag or 1
end
P_REGISTRY["bigPlank"] = function(p) setupRotatingPlank(p, "bigPlank" .. randNbr(3), 25, 5, 1) end
P_REGISTRY["woodPlank"] = function(p) setupRotatingPlank(p, "woodPlank", 25, 5, 1) end
P_REGISTRY["house_debris"] = function(p) setupRotatingPlank(p, "house_debris" .. randNbr(5), 5, 5, 1) end
P_REGISTRY["cinderBlock"] = function(p) setupRotatingPlank(p, "cinderBlock", 7, 10, 1, 20 + randNbr(300)) end
P_REGISTRY["sandBag"] = function(p) setupRotatingPlank(p, "sandBag", 7, 10, 1, 20 + randNbr(300)) end
P_REGISTRY["corrugated"] = function(p) setupRotatingPlank(p, "corrugated", 40, 30, 1, 20 + randNbr(300)) end

for i = 1, 3 do
  P_REGISTRY["fence" .. i .. "_debris"] = function(p) setupRotatingPlank(p, "fence" .. i .. "_debris" .. randNbr(3), 5, 5, 1) end
  P_REGISTRY["fence" .. i .. "_post"] = function(p) setupRotatingPlank(p, "fence" .. i .. "_post", 5, 5, 1) end
end

-- Ground Splash Particles
local function setupGroundDrip(p, typez, life, fade, drag)
  p.sprite = typez .. randNbr(3)
  p.velocity = 200 + randNbr(100)
  p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360)
  p.lifeSpan = life or 1
  p.xoffset = 2
  p.yoffset = 2
  p.drag = drag or 9
  p.fade = fade or 10
end
P_REGISTRY["waterDrip"] = function(p) setupGroundDrip(p, "waterDrip") end
P_REGISTRY["mudDrip"] = function(p) setupGroundDrip(p, "mudDrip") end
P_REGISTRY["snowBall"] = function(p) setupGroundDrip(p, "snowBall") end
P_REGISTRY["feather"] = function(p)
  p.sprite = "feather" .. randNbr(3); p.velocity = 200 + randNbr(100); p.rotationz = p.rotationz + math.rad(90 + (20 - randNbr(40)))
  p.innerRotation = randNbr(360); p.spin = (10 - randNbr(20)) / 10; p.lifeSpan = 30; p.xoffset = 2; p.yoffset = 2; p.drag = 9
end
P_REGISTRY["seaFoam"] = function(p)
  p.sprite = "seaFoam" .. randNbr(4); p.velocity = 300 + randNbr(30); p.rotationz = math.rad(90); p.innerRotation = 0; p.lifeSpan = 15
  p.xoffset = 60; p.yoffset = 150; p.alpha = 10 + randNbr(15); p.fade = 0.01; p.expand = randNbr(10) / 1000
end
P_REGISTRY["snowFlake"] = function(p)
  p.sprite = "snowFlake"; p.velocity = 10; p.rotationz = 180; p.innerRotation = 180; p.lifeSpan = 20; p.targetx = p.x; p.targety = p.y + 100
  p.xoffset = 2; p.yoffset = 2; p.drag = 0.01; p.fade = randNbr(5) / 10; p.expand = 0.2
end
P_REGISTRY["wave"] = function(p)
  p.sprite = "wave"; p.velocity = 100; p.rotationz = math.rad(270); p.innerRotation = 0; p.lifeSpan = 8; p.x = 800; p.y = 336
  p.xoffset = 250; p.yoffset = 350; p.drag = 0.5; p.alpha = 50; p.fade = randNbr(5) / 10; p.expand = randNbr(5) / 100
end
P_REGISTRY["lilGrass"] = function(p)
  p.sprite = "lilGrass" .. randNbr(4); p.velocity = 10 + randNbr(27); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 20 * (player and player.option_maxParticles or 1); p.xoffset = 7.5; p.yoffset = 7.5; p.drag = 0.4; p.fade = randNbr(5) / 10
end

-- Live Rounds
local function setupLiveRound(p, baseType, xo, yo)
  p.typez = baseType .. randNbr(5)
  p.sprite = p.typez
  p.velocity = 150 + randNbr(250)
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset = xo
  p.yoffset = yo
  p.drag = 2
  p.replaceable = 1
  p.immunity = 1
end
P_REGISTRY["liveRoundLarge"] = function(p) setupLiveRound(p, "liveRoundLarge", 9, 30) end
P_REGISTRY["liveRoundMed"] = function(p) setupLiveRound(p, "liveRoundMed", 4, 15) end
P_REGISTRY["liveRoundSmall"] = function(p) setupLiveRound(p, "liveRoundSmall", 4, 15) end

-- Thrown Projectiles & Grenades
P_REGISTRY["fragGrenade"] = function(p)
  p.sprite = "frag"; p.velocity = 500; p.spin = randNbr(10) / 10; p.lifeSpan = 4; p.xoffset = 20; p.yoffset = 20; p.drag = 1
  p.targetx = 0; p.targety = 0; p.lob = 0; p.immunity = 1
end
P_REGISTRY["fragGrenade2"] = function(p)
  p.sprite = "fragVc"; p.velocity = 500; p.spin = randNbr(40) / 10; p.lifeSpan = 4; p.xoffset = 6; p.yoffset = 18; p.drag = 1
  p.targetx = 0; p.targety = 0; p.lob = 0; p.immunity = 1
end
P_REGISTRY["molotovPart"] = function(p)
  p.typez = "fragGrenade"; p.sprite = "loot_molotov"; p.velocity = 500; p.spin = randNbr(5) / 10; p.lifeSpan = 4; p.xoffset = 5; p.yoffset = 20; p.drag = 1
  p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "smokeDrip"; p.immunity = 1
end
P_REGISTRY["contactGrenadePart"] = function(p)
  p.typez = "contactGrenade"; p.sprite = "contactFragPart"; p.velocity = 600; p.spin = randNbr(5) / 10; p.lifeSpan = 3
  p.xoffset, p.yoffset = getCenterOffsets("contactFragPart", false); p.drag = 1; p.targetx = 0; p.targety = 0; p.lob = 0; p.immunity = 1
end
P_REGISTRY["blendkorperPart"] = function(p)
  p.typez = "fragGrenade"; p.sprite = "loot_blendkorper"; p.velocity = 500; p.spin = randNbr(5) / 10; p.lifeSpan = 4; p.xoffset = 5; p.yoffset = 20; p.drag = 1
  p.targetx = 0; p.targety = 0; p.lob = 0; p.immunity = 1
end
P_REGISTRY["atGrenadePart"] = function(p)
  p.typez = "fragGrenade"; p.sprite = "loot_atGrenade"; p.velocity = 500; p.spin = randNbr(5) / 10; p.lifeSpan = 4; p.xoffset = 5; p.yoffset = 20; p.drag = 1
  p.targetx = 0; p.targety = 0; p.lob = 0; p.immunity = 1
end
P_REGISTRY["kitchenSinkPart"] = function(p)
  p.typez = "fragGrenade"; p.sprite = "kitchenSinkPart"; p.velocity = 500; p.spin = randNbr(3) / 10; p.lifeSpan = 60
  p.xoffset, p.yoffset = getCenterOffsets("kitchenSinkPart", true); p.drag = 1; p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "waterDrips"; p.immunity = 1
end
P_REGISTRY["flarePart"] = function(p)
  p.sprite = "flarePart"; p.velocity = 500; p.lifeSpan = 5; p.xoffset = 14; p.yoffset = 12; p.drag = 1; p.targetx = 0; p.targety = 0; p.lob = 0; p.immunity = 1
end
P_REGISTRY["redFlarePart"] = function(p)
  p.sprite = "redFlarePart"; p.velocity = 500; p.lifeSpan = 5; p.xoffset = 14; p.yoffset = 12; p.drag = 1; p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "flareDrip"; p.immunity = 1
end
P_REGISTRY["rifleGrenade"] = function(p)
  p.sprite = "rifleGrenade"; p.velocity = 500; p.lifeSpan = 4; p.xoffset = 14; p.yoffset = 12; p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "smokeDrip"; p.immunity = 1
end
P_REGISTRY["leuchtGrenade"] = function(p)
  p.sprite = "leuchtGrenade"; p.velocity = 400; p.lifeSpan = 4; p.xoffset = 14; p.yoffset = 12; p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "smokeDrip"; p.immunity = 1
end
P_REGISTRY["rocketGrenade"] = function(p)
  p.sprite = "rocketGrenade"; p.velocity = 750 + randNbr(250); p.lifeSpan = 2; p.xoffset = 14; p.yoffset = 12; p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "smokeDrip"; p.immunity = 1
end
P_REGISTRY["stielgranate"] = function(p)
  p.sprite = "stielgranate"; p.velocity = 500; p.lifeSpan = 4; p.xoffset = 14; p.yoffset = 12; p.targetx = 0; p.targety = 0; p.lob = 0; p.trail = "smokeDrip"; p.immunity = 1
end

local thrownSmokes = { "smokeGrenade", "redSmokeGrenade", "pinkSmokeGrenade", "greySmokeGrenade", "purpleSmokeGrenade", "yellowSmokeGrenade", "blueSmokeGrenade" }
for i = 1, #thrownSmokes do P_REGISTRY[thrownSmokes[i]] = setupThrownSmoke end

-- Props & Ground Items
local function setupPropCommon(p, sprite, xo, yo, rep)
  p.sprite = sprite
  p.velocity = 50 + randNbr(70)
  p.rotationz = math.rad(randNbr(360))
  p.innerRotation = randNbr(360)
  p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1)
  p.xoffset = xo
  p.yoffset = yo
  p.drag = 3
  if rep then p.replaceable = 1 end
end

P_REGISTRY["fragProp"] = function(p) setupPropCommon(p, "fragVc", 6, 11) end
P_REGISTRY["intelPaper"] = function(p) setupPropCommon(p, "intelPaper", 6, 11) end
P_REGISTRY["intelMap"] = function(p) setupPropCommon(p, "intelMap", 6, 11) end
P_REGISTRY["smokeProp"] = function(p) setupPropCommon(p, "smokeGrenade", 6, 11) end
P_REGISTRY["actionablePaper"] = function(p)
  p.sprite = "actionablePaper"; p.velocity = 90 + randNbr(70); p.rotationz = math.rad(randNbr(360)); p.innerRotation = randNbr(360); p.spin = (1 - randNbr(3)) / 10
  p.lifeSpan = 240 * (player and player.option_maxParticles or 1); p.xoffset, p.yoffset = getCenterOffsets("actionablePaper", false); p.drag = 3
end
P_REGISTRY["faustProp"] = function(p) setupPropCommon(p, "trenchProp2", 46, 27) end
P_REGISTRY["flareGunProp"] = function(p) setupPropCommon(p, "flareGunProp", 7, 11, true) end
P_REGISTRY["flareProp"] = function(p) setupPropCommon(p, "flareProp", 7, 3) end
P_REGISTRY["rgProp"] = function(p) setupPropCommon(p, "rifleGrenade", 10, 10, true) end
P_REGISTRY["mortarProp"] = function(p) setupPropCommon(p, "mortarProp", 22, 9) end
P_REGISTRY["mortarShellProp"] = function(p) setupPropCommon(p, "mortarShellProp", 12, 12) end
P_REGISTRY["radioProp"] = function(p) setupPropCommon(p, "radioProp", 22, 17, true) end
P_REGISTRY["medPackProp"] = function(p) setupPropCommon(p, "medPackProp", 15, 10); p.lifeSpan = 240 end
P_REGISTRY["ironCrossProp"] = function(p) setupPropCommon(p, "ironCrossProp", 15, 10) end
P_REGISTRY["molotovProp"] = function(p) setupPropCommon(p, "loot_molotov", 15, 10) end
P_REGISTRY["blendkorperProp"] = function(p)
  setupPropCommon(p, "loot_blendkorper", 0, 0)
  p.xoffset, p.yoffset = getCenterOffsets("loot_blendkorper", true)
end

local smokeProps = { "redSmokeProp", "pinkSmokeProp", "greySmokeProp", "purpleSmokeProp", "yellowSmokeProp", "blueSmokeProp" }
for i = 1, #smokeProps do
  local name = smokeProps[i]
  local spr = name:gsub("Prop", "Grenade")
  P_REGISTRY[name] = function(p) setupSmokeProp(p, name, spr) end
end

-- Specific Vehicle Debris & Turrets
local p4Offsets = {
  { 27, 13 }, { 13, 12 }, { 12, 8 }, { 25, 13 }, { 12, 22 }, { 12, 22 }, { 12, 22 },
  { 8, 8 }, { 8, 25 }, { 7, 12 }, { 12, 22 }, { 12, 22 }, { 12, 22 }
}
for i = 1, 13 do
  P_REGISTRY["panzer4_debris" .. i] = function(p) setupVehicleDebris(p, "panzer4_debris" .. i, 1.2, p4Offsets[i][1], p4Offsets[i][2]) end
end
for i = 1, 9 do
  P_REGISTRY["opel_debris" .. i] = function(p) setupVehicleDebris(p, "opel_debris" .. i, 1.2, 27, 13) end
end

P_REGISTRY["panzer4_debTurret"] = function(p) setupVehicleDebris(p, "panzer4Turret", 1.2, 46, 65) end
P_REGISTRY["flakPanzer_debTurret"] = function(p) setupVehicleDebris(p, "flakPanzerTurret", 1.2, 46, 65) end
P_REGISTRY["stuart_debTurret"] = function(p) setupVehicleDebris(p, "stuartTurret", 1.2, 125, 125) end
P_REGISTRY["radarDebris"] = function(p) p.typez = "radarTop"; setupVehicleDebris(p, "radarTop", 1.2) end
P_REGISTRY["barrelDebris"] = function(p) setupVehicleDebris(p, "barrelDebris" .. randNbr(6), 0.8) end
P_REGISTRY["cisternPart"] = function(p) setupVehicleDebris(p, "cisternDebris" .. randNbr(6), 0.8) end
P_REGISTRY["cisternDebris"] = function(p) setupVehicleDebris(p, "cisternDebris" .. randNbr(5), 1.2) end
P_REGISTRY["confeti"] = function(p) setupVehicleDebris(p, "confeti" .. randNbr(5), 1.2) end
P_REGISTRY["xmasBawl"] = function(p) setupVehicleDebris(p, "xmasBawl", 0.5, 12, 22) end

-- All 21 Gib Types
local allGibs = {
  "gib_alliedChest", "gib_axisChest", "gib_alliedLeg", "gib_axisLeg", "gib_axisLimb", "gib_alliedLimb",
  "gib_head", "gib_eye", "gib_gib", "gib_brain", "gib_bone", "gib_boot", "gib_gut", "gib_heart",
  "gib_leftHand", "gib_rightHand", "gib_liver", "gib_lungs", "gib_rib", "gib_sack", "gib_spine"
}
for i = 1, #allGibs do P_REGISTRY[allGibs[i]] = setupGib end


function addParticle(particle, typez, x, y, rotationz)
  particle = particle or acquireParticle()

  -- Common Baselines
  particle.scale = 1
  particle.targetx = nil
  particle.targety = nil
  particle.lob = 0
  particle.targetRotation = rotationz
  particle.trail = ""
  particle.faction = 0
  particle.once = 0
  particle.bounce = 0
  particle.bounced = 0
  particle.walled = 0
  particle.wallImmune = 0
  particle.shrink = 0
  particle.replaceable = 0
  particle.bounceAngle = randNbr(5) - 3
  particle.waterSplash = false
  particle.drift = 0
  particle.immunity = 0
  particle.sounded = 0
  particle.x = x
  particle.y = y
  particle.typez = typez
  particle.rotationz = rotationz
  particle.innerRotation = rotationz
  particle.sleeping = nil
  particle.velocity = 0
  particle.spin = 0
  particle.drag = 0
  particle.fade = 0
  particle.expand = 0
  particle.alpha = 255
  particle.nextFrame = ""
  particle.xoffset = 0
  particle.yoffset = 0

  -- 1. Exact Match via Hash Map (Covers 99% of calls instantly)
  local directHandler = P_REGISTRY[typez]
  if directHandler then
    directHandler(particle, typez)
    return particle
  end

  -- 2. Pattern Match Fallbacks (For dynamically generated numbers or prefixes)
  if typez:find("bone") then
    setupVehicleDebris(particle, typez, 1)
  elseif typez:find("molotov_debris") then
    particle.sprite = typez
    particle.velocity = 50 + randNbr(100)
    particle.innerRotation = randNbr(360)
    particle.spin = (1 - randNbr(3)) / 15
    particle.lifeSpan = 30 * (player and player.option_maxParticles or 1)
    particle.xoffset, particle.yoffset = getCenterOffsets(typez, true)
    particle.drag = 3
  elseif typez:find("riverFluff") then
    particle.typez = "riverFluff" .. randNbr(7)
    particle.sprite = particle.typez
    particle.rotationz = 90
    particle.innerRotation = 0
    particle.lifeSpan = 24 * (player and player.option_maxParticles or 1)
    particle.fade = 1 / randNbr(10)
    particle.drift = 1 / randNbr(10)
  elseif typez:find("deadCow") then
    setupVehicleDebris(particle, typez, 1, nil, nil, 3)
    particle.trail = "bloodDrip"
  elseif typez:find("bridgePart") then
    setupVehicleDebris(particle, typez, 0.6)
    particle.velocity = 100 + randNbr(300)
    particle.spin = (1 - randNbr(3)) / 20
    particle.xoffset, particle.yoffset = getCenterOffsets(typez, false)
  elseif typez:find("germRank") then
    setupVehicleDebris(particle, typez, 0.6, nil, nil, 3, 50 + randNbr(50))
    particle.xoffset, particle.yoffset = getCenterOffsets(typez, false)
    particle.trail = ""
  elseif typez:find("santaGib") then
    setupVehicleDebris(particle, typez, 1.2)
    if particle.sprite == "santaGib2" or particle.sprite == "santaGib4" then
      particle.trail = "bloodDrip"
    end
  elseif typez:find("civilianTruckDebris") then
    setupVehicleDebris(particle, typez, 0.35, 27, 13)
  elseif typez:find("panther_debris") or typez:find("puma_debris") or typez:find("churchill_debris") or typez:find("r35_debris") or typez:find("pak88_debris") then
    setupVehicleDebris(particle, typez, 1.2)
    particle.xoffset, particle.yoffset = getCenterOffsets(typez, false)
  elseif typez:find("flak30_debris") or typez:find("sdkfz2_debris") then
    setupVehicleDebris(particle, typez, 0.5)
  elseif typez:find("gliderDebris") then
    setupVehicleDebris(particle, typez, 1.0)
  elseif typez:find("jeep_debris") or typez:find("tankerDebris") or typez:find("howitzer_debris") or typez:find("cannon_debris") or typez:find("trapDoorDebris") or typez:find("m10_debris") or typez:find("sdkfz222_debris") or typez:find("tiger_debris") or typez:find("greyHound_debris") or typez:find("alarm_debris") or typez:find("sdkfz_debris") or typez:find("bike_debris") or typez:find("kubel_debris") or typez:find("pak38_debris") or typez:find("pak36_debris") or typez:find("bofor_debris") then
    setupVehicleDebris(particle, typez, 1.2, 27, 13)
  elseif typez:find("_debris") then
    setupVehicleDebris(particle, typez, 1.2)
  else
    -- Fallback default debris
    setupVehicleDebris(particle, typez, 1)
  end

  return particle
end

-- Helper: Handles grenade and flare death effects when lifespan expires
local function handleParticleDeath(ticle)
  if(ticle.typez == "fragGrenade") then 
    local foox = ticle.x
    local fooy = ticle.y
    if(ticle.sprite == "frag" or ticle.sprite == "fragVc") then 
      fragBlast(foox, fooy)
    elseif(ticle.sprite == "loot_atGrenade") then 
      atGrenadeBlast(foox, fooy)
    elseif(ticle.sprite == "smokeGrenade") then 
      smokeBlast(foox, fooy)
    elseif(ticle.sprite == "redSmokeGrenade") then 
      redSmokeBlast(foox, fooy)
    elseif(ticle.sprite == "pinkSmokeGrenade") then 
      pinkSmokeBlast(foox, fooy)
    elseif(ticle.sprite == "greySmokeGrenade") then 
      greySmokeBlast(foox, fooy)
    elseif(ticle.sprite == "yellowSmokeGrenade") then 
      yellowSmokeBlast(foox, fooy)
    elseif(ticle.sprite == "purpleSmokeGrenade") then 
      purpleSmokeBlast(foox, fooy)
    elseif(ticle.sprite == "blueSmokeGrenade") then 
      blueSmokeBlast(foox, fooy)
    elseif(ticle.sprite == "loot_molotov") then 
      molotovBlast(foox, fooy)
    elseif(ticle.sprite == "leuchtGrenade") then 
      createExplosion("rifleGrenadeExplosion", foox, fooy)
    elseif(ticle.sprite == "loot_blendkorper") then 
      blendkorperBlast(foox, fooy)      
    end
  elseif(ticle.sprite == "flarePart" and ticle.faction ~= "allied") then
    if(alliedEw() == false) then germanArtyPrefire(ticle.x, ticle.y) end
  elseif(ticle.sprite == "kitchenSinkPart") then
    local clone_sfx = flareDrop:clone()
    clone_sfx:setVolume(stepScale(ticle))
    clone_sfx:play()          
    player.deco[#player.deco+1] = {}
    player.deco[#player.deco].name = "kitchenSinkPart"
    player.deco[#player.deco].x = ticle.x
    player.deco[#player.deco].y = ticle.y
    player.deco[#player.deco].size = 10
    player.deco[#player.deco].rotation = randNbr(360) 
  elseif(ticle.sprite == "redFlarePart" and ticle.faction ~= "allied") then
    if(player.counterIntelTimer > 0) then 
      ticle.x = ticle.x + 1200
      me262Strike(ticle.x, ticle.y)
      anounceStuff("ME262 strike redirected with Counter Intelligence!!")
    else
      if(alliedEw() == false) then me262Strike(ticle.x, ticle.y) end
    end
  end
end

function particleUpdate(dt)
  -- 1. Reverse loops for water & mine circles
  for i = #player.waterCircles, 1, -1 do
    player.waterCircles[i].timer = player.waterCircles[i].timer + (dt * 50)
    if(player.waterCircles[i].timer > 300) then 
      table.remove(player.waterCircles, i)
    end
  end

  for i = #player.mineCircles, 1, -1 do
    player.mineCircles[i].timer = player.mineCircles[i].timer + (dt * 50)
    if(player.mineCircles[i].timer > 300) then 
      table.remove(player.mineCircles, i)
    end
  end

  -- 2. Compaction, sleep & pooled particle loop with cached math
  local list = player.particles
  if not list then return end
  local count = #list
  local writeIdx = 1
  local dtTemp = dt * 60
  local spawnedMidUpdate = {} -- Collect new particles safely

  for readIdx = 1, count do
    local ticle = list[readIdx]

    if ticle then
      -- FAST PATH: Resting particles
      if ticle.sleeping then
        ticle.lifeSpan = ticle.lifeSpan - dt
        if ticle.lifeSpan < 0 then
          handleParticleDeath(ticle)
          releaseParticle(ticle)
        else
          list[writeIdx] = ticle
          writeIdx = writeIdx + 1
        end
      else
      -- ACTIVE PATH: Moving particles
      local isDead = false

      ticle.lifeSpan = ticle.lifeSpan - dt
      ticle.wallImmune = ticle.wallImmune - dt
      ticle.targetRotation = ticle.rotationz
      ticle.innerRotation = ticle.innerRotation + (ticle.spin * dtTemp)
      ticle.x = ticle.x + ticle.drift

      if(ticle.drag > 0 and ticle.velocity > 0) then 
        if(ticle.trail ~= "" and randNbr(100) < 25) then
          local newPart = acquireParticle()
          addParticle(newPart, ticle.trail, ticle.x + (3 - randNbr(6)), ticle.y + (3 - randNbr(6)), ticle.innerRotation)
          if(player.landed == 0) then 
            newPart.drift = -8
          end
          spawnedMidUpdate[#spawnedMidUpdate + 1] = newPart
        end
        ticle.velocity = ticle.velocity - (ticle.drag * dtTemp)
        if(ticle.velocity <= 0) then 
          ticle.velocity = 0
          ticle.spin = 0
          if(ticle.replaceable == 1) then
            replaceTicle(ticle)
            isDead = true
          else
            if(ticle.fade <= 0 and ticle.drift == 0 and (ticle.expand or 0) == 0 and (ticle.shrink or 0) == 0 and ticle.targetx == nil and ticle.trail == "") then
              ticle.sleeping = true
            end
          end
        end
      end

      if(not isDead and ticle.fade > 0) then 
        ticle.alpha = ticle.alpha - (ticle.fade * dtTemp)
      end

      if(not isDead and ticle.lob > 0 and ticle.velocity ~= 0 and ticle.walled == 0) then 
        if(distanceCheck(ticle.x, ticle.y, ticle.targetx, ticle.targety) > (ticle.lob * 0.5) * dt) then 
          ticle.expand = 0.1
        else
          ticle.expand = -0.1
        end
      end

      if(not isDead) then
        if(ticle.expand > 0) then 
          if(ticle.typez == "fragGrenade" or ticle.typez == "flarePart" or ticle.typez == "contactGrenade" or ticle.typez == "redFlarePart" or ticle.typez == "rifleGrenade" or ticle.typez == "leuchtGrenade" or ticle.typez == "rocketGrenade" or ticle.typez == "stielgranate") then 
            if(ticle.velocity > 0 and ticle.walled == 0 and ticle.bounce == 0) then 
              ticle.scale = ticle.scale + (ticle.expand * dt)
            end
            if(ticle.scale > 2) then ticle.scale = 2 end
          else
            ticle.scale = ticle.scale + (ticle.expand * dt)
          end
        else
          if(ticle.shrink == 0) then 
            ticle.scale = 1
          end
        end

        if(ticle.shrink > 0 and ticle.scale > 0.0001) then 
          ticle.scale = ticle.scale - (ticle.shrink * dt)
        end

        if(ticle.velocity > 0) then 
          local camX = player and player.screenx or 0
          local onScreen = (ticle.x >= camX - 100 and ticle.x <= camX + 1380)

          if(onScreen and ticle.typez == "shell" and ticle.sounded < 1 and ticle.velocity < 30) then 
            local surface = groundSurfaceTell(ticle)
            local clone_sfx4 = _G["shell_"..surface.."_"..randNbr(10)]
            if clone_sfx4 then
              clone_sfx4 = clone_sfx4:clone()
              clone_sfx4:setVolume(stepScale(ticle) / 3)
              clone_sfx4:setPitch((80 + randNbr(40)) / 100) 
              clone_sfx4:play()
            end
            ticle.sounded = 1
            if(surface == "water") then createWaterCircle(ticle.x, ticle.y, 1) end
          elseif(ticle.typez == "smallShell" and ticle.sounded < 1 and ticle.velocity < 30) then 
            local surface = groundSurfaceTell(ticle)
            local clone_sfx4 = _G["shellPistol_"..surface.."_"..randNbr(10)]
            if clone_sfx4 then
              clone_sfx4 = clone_sfx4:clone()
              clone_sfx4:setVolume(stepScale(ticle) / 3)
              clone_sfx4:setPitch((80 + randNbr(40)) / 100) 
              clone_sfx4:play()
            end
            ticle.sounded = 1
            if(surface == "water") then createWaterCircle(ticle.x, ticle.y, 1) end
          elseif(ticle.typez == "bigShell" and ticle.sounded < 1 and ticle.velocity < 30) then 
            local surface = groundSurfaceTell(ticle)
            local clone_sfx44 = _G["shellBigSound"..randNbr(10)]
            if clone_sfx44 then
              clone_sfx44 = clone_sfx44:clone()
              clone_sfx44:setVolume(stepScale(ticle))
              clone_sfx44:setPitch((80 + randNbr(40)) / 100) 
              clone_sfx44:play()
            end
            ticle.sounded = 1
            if(surface == "water") then createWaterCircle(ticle.x, ticle.y, 1) end
          elseif(ticle.waterSplash and ticle.sounded < 1 and ticle.velocity < 30) then 
            ticle.sounded = 1
            local surface = groundSurfaceTell(ticle)
            if(surface == "water") then 
              local clone_sfx44 = waterSplashing:clone()
              clone_sfx44:setVolume(stepScale(ticle))
              clone_sfx44:setPitch((80 + randNbr(40)) / 100) 
              clone_sfx44:play()
              createWaterCircle(ticle.x, ticle.y, 1)
            end
          end
        end

        -- Cached atan2 with HALF_PI constant
        if(ticle.targetx ~= nil and ticle.bounce ~= 1) then 
          ticle.targetRotation = atan2(ticle.y - ticle.targety, ticle.x - ticle.targetx) + HALF_PI
        end

        -- Cached deg/rad rotation interpolation
        if(ticle.typez == "fragGrenade" or ticle.typez == "flarePart" or ticle.typez == "contactGrenade" or ticle.typez == "redFlarePart" or ticle.typez == "rifleGrenade" or ticle.typez == "leuchtGrenade" or ticle.typez == "rocketGrenade" or ticle.typez == "stielgranate") then 
          local intendedRotation = deg(ticle.targetRotation)
          local currentRotation = deg(ticle.rotationz)
          local diff = currentRotation - intendedRotation
          if diff > 360 then diff = diff - 360 end
          if diff < -180 then diff = diff + 360 end
          local dAngle = (diff >= 180 or diff < 0) and 0.5 or -0.5
          currentRotation = currentRotation + dAngle
          if(ticle.typez ~= "rifleGrenade" and ticle.typez ~= "rocketGrenade" and ticle.typez ~= "leuchtGrenade" and ticle.typez ~= "fragGrenade" and ticle.typez ~= "contactGrenade" and ticle.typez ~= "flarePart" and ticle.typez ~= "redFlarePart" and ticle.typez ~= "kitchenSinkPart" and ticle.typez ~= "stielgranate") then
            ticle.rotationz = rad(currentRotation) 
          else
            ticle.rotationz = rad(intendedRotation)
            if(ticle.typez == "rifleGrenade" or ticle.typez == "leuchtGrenade" or ticle.typez == "rocketGrenade") then 
              ticle.innerRotation = rad(intendedRotation)
            end
          end
        end

        -- Target arrival / bounce
        if(ticle.targetx ~= nil and distanceCheck(ticle.x, ticle.y, ticle.targetx, ticle.targety) < 10 and ticle.bounce == 0) then 
          ticle.bounce = 1
          ticle.velocity = 100 + randNbr(200) 
          ticle.drag = 5
          ticle.targetx = ticle.x + 150 - randNbr(300) 
          ticle.targety = ticle.y + 150 - randNbr(300)
          ticle.spin = 0

          if(ticle.typez == "fragGrenade") then 
            local clone_sfx
            if(ticle.sprite == "kitchenSinkPart") then 
              clone_sfx = kitchenSinkBounce:clone()
              clone_sfx:setVolume(stepScale(ticle))
              clone_sfx:play() 
              local newPart = acquireParticle()
              addParticle(newPart, "dustCloud", ticle.x + 20 - randNbr(40), ticle.y + 20 - randNbr(40), randNbr(360))
              spawnedMidUpdate[#spawnedMidUpdate + 1] = newPart 
            else
              clone_sfx = _G["fragBounce"..randNbr(3)]:clone()
              clone_sfx:setVolume(stepScale(ticle))
              clone_sfx:play() 
            end

            if(ticle.sprite == "loot_molotov") then 
              if(inWater(ticle) == false) then 
                player.fightIntensity = player.fightIntensity + 5
                molotovBlast(ticle.x, ticle.y)
              else
                local clone_sfx44 = waterSplashing:clone()
                clone_sfx44:setVolume(stepScale(ticle))
                clone_sfx44:setPitch((80 + randNbr(40)) / 100) 
                clone_sfx44:play()
                createWaterCircle(ticle.x, ticle.y, 10)
                createWaterCircle(ticle.x, ticle.y, 25)
                createWaterCircle(ticle.x, ticle.y, 35)
                createLootByName("loot_molotov", ticle.x, ticle.y)
                local clone_sfx1 = steamSound:clone()
                clone_sfx1:setPitch((80 + randNbr(40)) / 100)
                clone_sfx1:setVolume(stepScale(ticle))
                clone_sfx1:play()  
                local newPart = acquireParticle()
                addParticle(newPart, "bigSmoke", ticle.x, ticle.y, rad(randNbr(360)))
                spawnedMidUpdate[#spawnedMidUpdate + 1] = newPart  
                for o = 1, 10, 1 do
                  local wPart = acquireParticle()
                  addParticle(wPart, "waterBall2", ticle.x, ticle.y, ticle.rotationz + rad(randNbr(100) - 50))
                  spawnedMidUpdate[#spawnedMidUpdate + 1] = wPart
                end         
              end
              isDead = true
            elseif(ticle.sprite == "loot_blendkorper") then 
              if(inWater(ticle) == false) then 
                player.fightIntensity = player.fightIntensity + 5
                blendkorperBlast(ticle.x, ticle.y)
              else
                createLootByName("loot_blendkorper", ticle.x, ticle.y)
                local clone_sfx44 = waterSplashing:clone()
                clone_sfx44:setVolume(stepScale(ticle))
                clone_sfx44:setPitch((80 + randNbr(40)) / 100) 
                clone_sfx44:play()
                createWaterCircle(ticle.x, ticle.y, 10)
                createWaterCircle(ticle.x, ticle.y, 25)
                createWaterCircle(ticle.x, ticle.y, 35)
                for o = 1, 10, 1 do
                  local wPart = acquireParticle()
                  addParticle(wPart, "waterBall2", ticle.x, ticle.y, ticle.rotationz + rad(randNbr(100) - 50))
                  spawnedMidUpdate[#spawnedMidUpdate + 1] = wPart
                end  
              end
              isDead = true 
            elseif(ticle.sprite == "loot_atGrenade") then 
              clone_sfx = _G["fragBounce"..randNbr(3)]:clone()
              clone_sfx:setVolume(stepScale(ticle))
              clone_sfx:play()  
              local newPart = acquireParticle()
              addParticle(newPart, "dustCloud", ticle.x + 20 - randNbr(40), ticle.y + 20 - randNbr(40), randNbr(360))
              spawnedMidUpdate[#spawnedMidUpdate + 1] = newPart        
            end
          elseif(ticle.typez == "flarePart") then
            local clone_sfx = flareDrop:clone()
            clone_sfx:setVolume(stepScale(ticle))
            clone_sfx:play() 
            player.deco[#player.deco+1] = {}
            player.deco[#player.deco].name = "groundBlast"
            player.deco[#player.deco].x = ticle.x
            player.deco[#player.deco].y = ticle.y
            player.deco[#player.deco].size = 4
            player.deco[#player.deco].rotation = randNbr(360) 
            if(ticle.faction == "allied" and ticle.once == 0) then 
              ticle.once = 1
              player.delayedAction[#player.delayedAction+1] = {}
              player.delayedAction[#player.delayedAction].action = "flareLoop"
              player.delayedAction[#player.delayedAction].timer = 2
              player.delayedAction[#player.delayedAction].arg1 = ticle.x
              player.delayedAction[#player.delayedAction].arg2 = ticle.y
              player.delayedAction[#player.delayedAction].arg3 = 1
              player.delayedAction[#player.delayedAction].arg4 = 0
              player.delayedAction[#player.delayedAction].arg5 = 0 
              player.alliedFlarex = ticle.x
              player.alliedFlarey = ticle.y
            end
          elseif(ticle.typez == "redFlarePart") then
            local clone_sfx = flareDrop:clone()
            clone_sfx:setVolume(stepScale(ticle))
            clone_sfx:play() 
            player.deco[#player.deco+1] = {}
            player.deco[#player.deco].name = "groundBlast"
            player.deco[#player.deco].x = ticle.x
            player.deco[#player.deco].y = ticle.y
            player.deco[#player.deco].size = 4
            player.deco[#player.deco].rotation = randNbr(360) 
          elseif(ticle.typez == "rifleGrenade") then 
            createExplosion("rifleGrenadeExplosion", ticle.x, ticle.y)
            isDead = true
          elseif(ticle.typez == "leuchtGrenade") then 
            createExplosion("rifleGrenadeExplosion", ticle.x, ticle.y)
            isDead = true
          elseif(ticle.typez == "contactGrenade") then 
            contactFragBlast(ticle.x, ticle.y)
            isDead = true
          elseif(ticle.typez == "rocketGrenade") then 
            createExplosion("fleigExplosion", ticle.x, ticle.y)
            isDead = true
          elseif(ticle.typez == "stielgranate") then 
            createExplosion("shrekExplosion", ticle.x, ticle.y)
            isDead = true
          end
        end

        -- Wall penetration checks
        if(not isDead and ticle.walled == 0 and ticle.wallImmune <= 0) then 
          if(penetrateBunker(ticle) or penetrateHouse(ticle) or penetrateWoodBunker(ticle) or penetratePillBox(ticle)) then
            ticle.targetx = nil
            ticle.rotationz = rad(deg(ticle.rotationz) + 180 + (randNbr(90) - 45)) 
            ticle.targetRotation = ticle.rotationz
            ticle.walled = 1
            ticle.velocity = ticle.velocity * 0.5
            ticle.drag = ticle.drag + (1 * dt)
            local clone_sfx77 = _G["fragWall"..randNbr(4)]:clone()
            clone_sfx77:setVolume(stepScale(player.deco[#player.deco]))
            clone_sfx77:play() 
            local sparkDice = randNbr(6) + 2
            for o = 1, sparkDice, 1 do
              local newPart = acquireParticle()
              addParticle(newPart, "muzzleSpark", ticle.x, ticle.y, randNbr(360))
              spawnedMidUpdate[#spawnedMidUpdate + 1] = newPart
            end  
            local smokeDice = randNbr(6) + 2
            for o = 1, smokeDice, 1 do
              local newPart = acquireParticle()
              addParticle(newPart, "smoke"..randNbr(3), ticle.x + (5 - randNbr(10)), ticle.y + (5 - randNbr(10)), randNbr(360))
              spawnedMidUpdate[#spawnedMidUpdate + 1] = newPart
            end
            if(ticle.sprite == "loot_molotov") then 
              molotovBlast(ticle.x, ticle.y)
              isDead = true
            elseif(ticle.sprite == "loot_blendkorper") then 
              blendkorperBlast(ticle.x, ticle.y)
              isDead = true
            elseif(ticle.typez == "rifleGrenade" or ticle.typez == "leuchtGrenade") then 
              createExplosion("rifleGrenadeExplosion", ticle.x, ticle.y)
              isDead = true
            elseif(ticle.typez == "contactGrenade") then 
              contactFragBlast(ticle.x, ticle.y)
              isDead = true
            elseif(ticle.typez == "rocketGrenade") then 
              createExplosion("fleigExplosion", ticle.x, ticle.y)
              isDead = true
            elseif(ticle.typez == "stielgranate") then 
              createExplosion("shrekExplosion", ticle.x, ticle.y)
              isDead = true
            end
          end      
        end

        if(ticle.bounce == 1) then 
          ticle.rotationz = ticle.rotationz + rad(ticle.bounceAngle)
        end

        -- Cached step movement: pre-compute step and angle once, skip if velocity is 0
        if(ticle.velocity > 0) then
          local moveStep = ticle.velocity * dt
          local moveAngle = ticle.rotationz + PI
          ticle.x = ticle.x + sin(moveAngle) * moveStep
          ticle.y = ticle.y - cos(moveAngle) * moveStep
        end

        -- Active lifespan expiration
        if(not isDead and ticle.lifeSpan < 0) then
          handleParticleDeath(ticle)
          isDead = true
        end
      end

      -- Compaction decision
      if isDead or ticle.lifeSpan < 0 then
        releaseParticle(ticle)
      else
        list[writeIdx] = ticle
        writeIdx = writeIdx + 1
      end
    end
  end
end

  -- 1. Transfer any particles inserted by external callbacks during the frame
  local rawLen = #list
  for i = count + 1, rawLen do
    local extPart = list[i]
    if extPart ~= nil then
      list[writeIdx] = extPart
      list[i] = nil
      writeIdx = writeIdx + 1
    end
  end

  -- 2. Append all queued mid-update particles (trails, bounces, splashes)
  for i = 1, #spawnedMidUpdate do
    list[writeIdx] = spawnedMidUpdate[i]
    writeIdx = writeIdx + 1
  end

  -- 3. Clean up the trailing tail so the array remains strictly contiguous
  local maxTail = math.max(rawLen, count)
  for i = writeIdx, maxTail do
    list[i] = nil
  end
end


function createFire(x, y, size)
  player.fire[#player.fire+1] = {}
  player.fire[#player.fire].fire = 1
  player.fire[#player.fire].x = x
  player.fire[#player.fire].y = y
  player.fire[#player.fire].size = size/10
  player.fire[#player.fire].burnTime = 5 + randNbr(30)
  player.fire[#player.fire].babies = 0
  player.fire[#player.fire].followID = 0
  if(player.gameType == 1) then 
    player.mnb2Fire = player.mnb2Fire + 1
  end
end


function destruction(x, y, radius, foo)
  local rad2 = radius * radius
  local radHalf2 = (radius * 0.5) * (radius * 0.5)
  local radDouble2 = (radius * 2) * (radius * 2)

  -- 1. Forest destruction (reverse loop + squared distance)
  for ii = #player.forest, 1, -1 do
    local datTreeTho = player.forest[ii]
    local tdx = datTreeTho.x - x
    local tdy = datTreeTho.y - y
    if (tdx * tdx + tdy * tdy) < rad2 then
      player.deco[#player.deco+1] = {}
      player.deco[#player.deco].name = "tree_destroyed"
      player.deco[#player.deco].x = datTreeTho.x
      player.deco[#player.deco].y = datTreeTho.y
      player.deco[#player.deco].size = datTreeTho.size
      player.deco[#player.deco].rotation = rad(randNbr(360))

      if(datTreeTho.type == 11) then 
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "sapBranch", datTreeTho.x, datTreeTho.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end   
      else
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "tree_debris", datTreeTho.x, datTreeTho.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        if(datTreeTho.type ~= 12) then 
          for o = 1, 20, 1 do
            local newPart = acquireParticle()
            addParticle(newPart, "tree_leaf", datTreeTho.x, datTreeTho.y, rad(randNbr(360)))
            table.insert(player.particles, newPart)
          end 
        end        
      end

      if(datTreeTho.type == 10) then 
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "xmasBawl", datTreeTho.x, datTreeTho.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
      end

      local clone_sfx = _G["treeDestroyed"..randNbr(4)]:clone()
      clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
      clone_sfx:play()
      table.remove(player.forest, ii)
      
      if(player.gameType == 1) then 
        player.mnb2TreeDestroyed = player.mnb2TreeDestroyed + 1
      else
        player.treeDestroyed = player.treeDestroyed + 1
      end
      checkRibCondition(3)
    end
  end

  -- 2. Placeables destruction
  for i = #player.placeables, 1, -1 do
    local place = player.placeables[i]
    local pdx = place.x - x
    local pdy = place.y - y

    if(place.name == "achBush1") then 
      local bdx = (place.x - 100) - x
      if (bdx * bdx + pdy * pdy) < rad2 then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "achBush1_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 7
        player.deco[#player.deco].rotation = place.rotation      
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "achBushDebris", place.x - 100, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 25, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "achLeave", place.x - 100, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        deleteRelatedCover(place.cheeseID)  
        table.remove(player.placeables, i) 
      end
    elseif(place.name == "achBush2") then
      local bdx = (place.x + 100) - x
      if (bdx * bdx + pdy * pdy) < rad2 then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "achBush1_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 7
        player.deco[#player.deco].rotation = place.rotation      
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "achBushDebris", place.x + 100, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 25, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "achLeave", place.x + 100, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        deleteRelatedCover(place.cheeseID)  
        table.remove(player.placeables, i) 
      end
    elseif (pdx * pdx + pdy * pdy) < rad2 then
      if(place.name == "plant") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "plant_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "plant_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = plantDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "fence1" or place.name == "fence2" or place.name == "fence3") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = place.name.."_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, place.name.."_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 2, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, place.name.."_post", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = wallExplosion:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)  
      elseif(place.name == "brestWall") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = place.name.."_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "brestWallDebris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = wallExplosion:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)  
      elseif(place.name == "achWall") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = place.name.."Destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "achWallDebris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = wallExplosion:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)          
      elseif(place.name == "crate1" or place.name == "crate4" or place.name == "crate5") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate1_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "tomb1" or place.name == "tomb2" or place.name == "tomb3") then 
        deleteRelatedCover(place.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "tombDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "tombDebris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = _G["tombDest"..randNbr(5)]:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "tomb4") then 
        deleteRelatedCover(place.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "destroyedBigTomb"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "tombDebris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bone"..randNbr(2)+1, place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local bList = { "bone1", "bone4", "bone5" }
        for b = 1, #bList do
          local newPart = acquireParticle()
          addParticle(newPart, bList[b], place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local clone_sfx = _G["tombDest"..randNbr(5)]:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "tomb7" or place.name == "tomb8") then 
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bone"..randNbr(2)+1, place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        if(randNbr(100) < 25) then 
          local bList = { "bone1", "bone4", "bone5" }
          for b = 1, #bList do
            local newPart = acquireParticle()
            addParticle(newPart, bList[b], place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart)
          end
        else
          fakeGib(place.x, place.y, "axis")
        end
        local clone_sfx = casketDestroyedSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "ammoCrateLargeClosed" or place.name == "ammoCrateLargeOpen") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate1_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
        local dicer = randNbr(4)
        for o = 1, dicer, 1 do
          player.delayedAction[#player.delayedAction+1] = {}
          player.delayedAction[#player.delayedAction].action = "createExplosion"
          player.delayedAction[#player.delayedAction].timer = randNbr(15)/10
          player.delayedAction[#player.delayedAction].arg1 = "snapExplosion"
          player.delayedAction[#player.delayedAction].arg2 = player.deco[#player.deco].x
          player.delayedAction[#player.delayedAction].arg3 = player.deco[#player.deco].y
          player.delayedAction[#player.delayedAction].arg4 = 0
          player.delayedAction[#player.delayedAction].arg5 = 0 
        end
        local dicer2 = randNbr(10)
        for o = 1, dicer2, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "liveRoundLarge", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart) 
        end 
      elseif(place.name == "tanker") then 
        for o = 1, 3 do
          local newPart = acquireParticle()
          addParticle(newPart, "tankerDebris"..o, place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "tankerDebris"..(3+randNbr(7)), place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = smallVehicleExplosion:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        if(randNbr(100) < 25) then 
          local numberz = randNbr(5) 
          for o = 1, numberz, 1 do
            createFire(place.x + (randNbr(300)-150), place.y + (randNbr(300)-150), 4)
          end
        end
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "tankerDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 5
        player.deco[#player.deco].rotation = rad(randNbr(360))
        table.remove(player.placeables, i)
      elseif(place.name == "brickStack") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate2_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 25, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "fence2_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = rockDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)    
      elseif(place.name == "ammoCrateMedOpen" or place.name == "ammoCrateMedClosed") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate1_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
        local dicer = randNbr(4)
        for o = 1, dicer, 1 do
          player.delayedAction[#player.delayedAction+1] = {}
          player.delayedAction[#player.delayedAction].action = "createExplosion"
          player.delayedAction[#player.delayedAction].timer = randNbr(15)/10
          player.delayedAction[#player.delayedAction].arg1 = "snapExplosion"
          player.delayedAction[#player.delayedAction].arg2 = player.deco[#player.deco].x
          player.delayedAction[#player.delayedAction].arg3 = player.deco[#player.deco].y
          player.delayedAction[#player.delayedAction].arg4 = 0
          player.delayedAction[#player.delayedAction].arg5 = 0 
        end
        local dicer2 = randNbr(10)
        for o = 1, dicer2, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "liveRoundMed", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart) 
        end     
      elseif(place.name == "ammoCrateSmallOpen" or place.name == "ammoCrateSmallClosed") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate1_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
        local dicer = randNbr(4)
        for o = 1, dicer, 1 do
          player.delayedAction[#player.delayedAction+1] = {}
          player.delayedAction[#player.delayedAction].action = "createExplosion"
          player.delayedAction[#player.delayedAction].timer = randNbr(15)/10
          player.delayedAction[#player.delayedAction].arg1 = "snapExplosion"
          player.delayedAction[#player.delayedAction].arg2 = player.deco[#player.deco].x
          player.delayedAction[#player.delayedAction].arg3 = player.deco[#player.deco].y
          player.delayedAction[#player.delayedAction].arg4 = 0
          player.delayedAction[#player.delayedAction].arg5 = 0 
        end
        local dicer2 = randNbr(10)
        for o = 1, dicer2, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "liveRoundSmall", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart) 
        end     
      elseif(place.name == "dragonTooth") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "dragonTooth_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 25, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bunker2_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart) 
        end 
        local clone_sfx = rockDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "obstacle") then 
        for o = 1, 6, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "tankTrapDebris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart) 
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "observationKitDeployed") then 
        for o = 1, 2 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 3 do
          local newPart = acquireParticle()
          addParticle(newPart, "greyHound_debris4", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local newPart = acquireParticle()
        addParticle(newPart, "greyHound_debris5", place.x, place.y, rad(randNbr(360)))
        table.insert(player.particles, newPart)
        local clone_sfx = radarExploSound:clone()
        clone_sfx:setVolume(stepScale(place))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "alarmKitDeployed") then 
        for o = 1, 4 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local alarmDebris = { "alarm_debris1", "alarm_debris2", "alarm_debris2", "alarm_debris3", "alarm_debris4" }
        for a = 1, #alarmDebris do
          local newPart = acquireParticle()
          addParticle(newPart, alarmDebris[a], place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local clone_sfx = radarExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "crate2" or place.name == "crate3" or place.name == "crate6") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate2_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "supplyDepot") then
        if(player.gameType == 0) then
          local lootDice = randNbr(3)
          for o = 1, lootDice, 1 do
            createLoot(place.x + (50 - randNbr(100)), place.y + (50 - randNbr(100)))
          end
        end 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "supplyDepotDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = supplyDepotDestructionSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "radarBase" or place.name == "radarBase2") then 
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "jeep_debris"..(10+randNbr(3)), place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 2 do
          local newPart = acquireParticle()
          addParticle(newPart, "jeep_debris5", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local newPart = acquireParticle()
        addParticle(newPart, "radarDebris", place.x, place.y, rad(randNbr(360)))
        table.insert(player.particles, newPart)
        local clone_sfx = radarExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "barrelWall1" or place.name == "barrelWall2") then 
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "barrelDebris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        if(place.name == "barrelWall1") then 
          for o = 1, 6, 1 do
            local newPart = acquireParticle()
            addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart)
          end 
        end
        local clone_sfx = barrelExplosionSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "wheelBarrow") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate2_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "barricade") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "barricade_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local newPart = acquireParticle()
        addParticle(newPart, "carWheel", place.x, place.y, rad(randNbr(360)))
        table.insert(player.particles, newPart)
        local clone_sfx = barricadeDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
        if(player.gameType == 1) then 
          player.mnb2BuildDestroyed = player.mnb2BuildDestroyed + 1
        end
      elseif(place.name == "palisade") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "bench_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 4, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = barricadeDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
        if(player.gameType == 1) then 
          player.mnb2BuildDestroyed = player.mnb2BuildDestroyed + 1
        end
      elseif(place.name == "barbWire") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "barbWireDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        local clone_sfx2 = _G["wireStep"..randNbr(5)]:clone()
        clone_sfx2:setVolume(stepScale(place) + 0.2)
        clone_sfx2:play() 
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "entanglement") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "entanglementDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        local clone_sfx2 = _G["wireStep"..randNbr(5)]:clone()
        clone_sfx2:setVolume(stepScale(place) + 0.2)
        clone_sfx2:play() 
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i)
      elseif(place.name == "cart" or place.name == "bigCart") then 
        deleteRelatedCover(place.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate2_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 20
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 2 do
          local newPart = acquireParticle()
          addParticle(newPart, "cartWheel", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = wagonDestroyedSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "cartBarricade") then 
        deleteRelatedCover(place.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "crate2_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 20
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "sandBag", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 2 do
          local newPart = acquireParticle()
          addParticle(newPart, "cartWheel", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = cartBarricadeDestructionSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "woodPile1") then 
        deleteRelatedCover(place.cheeseID) 
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "log", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "plankPile") then 
        deleteRelatedCover(place.cheeseID) 
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "woodPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "car") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "car_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 9.5
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 4 do
          local newPart = acquireParticle()
          addParticle(newPart, "carWheel", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for w = 1, 10 do
          local newPart = acquireParticle()
          addParticle(newPart, "car_debris"..w, place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local extraCar = { "car_debris6", "car_debris7", "car_debris8" }
        for c = 1, #extraCar do
          local newPart = acquireParticle()
          addParticle(newPart, extraCar[c], place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local clone_sfx = carExplode:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.placeables, i) 
      elseif(place.name == "tractor") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "tractor_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 9.5
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for t = 1, 4 do
          local newPart = acquireParticle()
          addParticle(newPart, "tractorDebris"..t, place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 10 do
          local newPart = acquireParticle()
          addParticle(newPart, "tractorDebris5", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 2 do
          local newPart = acquireParticle()
          addParticle(newPart, "tractorDebris6", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 5 do
          local newPart = acquireParticle()
          addParticle(newPart, "tractorDebris7", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 2 do
          local newPart = acquireParticle()
          addParticle(newPart, "tractorDebris8", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        local newPart = acquireParticle()
        addParticle(newPart, "tractorDebris9", place.x, place.y, rad(randNbr(360)))
        table.insert(player.particles, newPart)
        local clone_sfx = carExplode:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)         
      elseif(place.name == "barrel1" or place.name == "barrel2" or place.name == "bench") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = (place.name == "bench") and "bench_destroyed" or "crate2_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "hayBale" or place.name == "hayStack" or place.name == "hogBale1" or place.name == "hogBale2" or place.name == "hogBale3") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = (place.name == "hayBale") and "hayBale_destroyed" or "hayStack_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = place.rotation
        for o = 1, 15, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "hayStack_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        deleteRelatedCover(place.cheeseID)
        table.remove(player.placeables, i)
      elseif(place.name == "gift1" or place.name == "gift2" or place.name == "gift3") then
        for o = 1, 20, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "confeti", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 5 do
          local newPart = acquireParticle()
          addParticle(newPart, "santaGib3", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for o = 1, 5 do
          local newPart = acquireParticle()
          addParticle(newPart, "santaGib5", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = giftExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        local supplyLoot = {"loot_molotov", "loot_beer", "loot_medal", "loot_tracer", "loot_magnum", "loot_shovel", "loot_camo", "loot_medPack", "loot_ration", "loot_loveLetter", "loot_binos", "loot_brassKnuckles", "loot_panzerChocolate", "loot_teddyBear", "loot_panzerFaust"}
        player.lootables[#player.lootables+1] = {}
        if(randNbr(100) < 90) then 
          player.lootables[#player.lootables].name = supplyLoot[randNbr(#supplyLoot)]
        else
          player.lootables[#player.lootables].name = "side_"..getRandomAlliedGun()
        end
        player.lootables[#player.lootables].x = place.x + (randNbr(100)-50)
        player.lootables[#player.lootables].y = place.y + (randNbr(100)-50)
        screenSanity(player.lootables[#player.lootables])
        player.lootables[#player.lootables].flagged = 1
        player.lootables[#player.lootables].faction = "allied"
        player.lootables[#player.lootables].argument = ""
        player.lootables[#player.lootables].size = 10
        player.lootables[#player.lootables].life = 60
        player.lootables[#player.lootables].rotation = rad(randNbr(360))
        deleteRelatedCover(place.cheeseID)  
        table.remove(player.placeables, i) 
      elseif(place.name == "trapDoor_open" or place.name == "trapDoor_closed") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "trapDoorDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 7
        player.deco[#player.deco].rotation = 0
        for o = 1, 10, 1 do
          local newPart = acquireParticle()
          addParticle(newPart, "house_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local newPart1 = acquireParticle()
        addParticle(newPart1, "trapDoorDebris1", place.x, place.y, rad(randNbr(360)))
        table.insert(player.particles, newPart1)
        local newPart2 = acquireParticle()
        addParticle(newPart2, "trapDoorDebris2", place.x, place.y, rad(randNbr(360)))
        table.insert(player.particles, newPart2)
        local clone_sfx = carExplode:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        if(place.name == "trapDoor_closed") then
          player.groundType[#player.groundType+1] = {}
          player.groundType[#player.groundType].name = "dirt"
          player.groundType[#player.groundType].incline = 0
          player.groundType[#player.groundType].x = place.x - 34
          player.groundType[#player.groundType].y = place.y - 33
          player.groundType[#player.groundType].radius = 0
          player.groundType[#player.groundType].width = 60
          player.groundType[#player.groundType].length = 72
          player.groundType[#player.groundType].offSet = 0
          player.groundType[#player.groundType].noisy = "yes"
          player.groundType[#player.groundType].noiseRange = 300
          player.groundType[#player.groundType].slowy = "no" 
          player.groundType[#player.groundType].parts = "no"   
          player.groundType[#player.groundType].smoke = "no" 
          player.groundType[#player.groundType].water = "no"
          player.groundType[#player.groundType].cover = 45
          player.groundType[#player.groundType].midpoint = 0
          player.groundType[#player.groundType].cheeseID = player.deco[#player.deco].cheeseID
        end
        table.remove(player.placeables, i)
      elseif(place.name == "cannon") then 
        for o = 1, 9 do
          local count = (o == 1 or o == 3) and 1 or (o >= 8 and 2 or 4)
          for c = 1, count do
            local newPart = acquireParticle()
            addParticle(newPart, "cannon_debris"..o, place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart)
          end
        end
        local clone_sfx = cannonDestSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "cisternWagon") then 
        deleteRelatedCover(place.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "boxCar_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        local clone_sfx = tankExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()  
        local numberz = randNbr(5) + 5 
        for f = 1, numberz do
          createFire(place.x + (randNbr(300)-150), place.y + (randNbr(300)-150), 4)
        end
        for f = 1, 35 do
          local newPart = acquireParticle()
          addParticle(newPart, "cisternPart", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        table.remove(player.placeables, i)
      elseif(place.name == "coil1" or place.name == "coil2") then 
        deleteRelatedCover(place.cheeseID) 
        for o = 1, 15 do
          local newPart = acquireParticle()
          addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        for c = 1, 8 do
          player.deco[#player.deco+1] = {}
          player.deco[#player.deco].name = "coilDebris"..randNbr(2)
          player.deco[#player.deco].x = place.x + (randNbr(300)-150)
          player.deco[#player.deco].y = place.y + (randNbr(300)-150)
          player.deco[#player.deco].size = 3.5
          player.deco[#player.deco].rotation = rad(randNbr(360))
        end
        local clone_sfx = crateDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.placeables, i)
      elseif(place.name == "civilianTruck1") then 
        deleteRelatedCover(place.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "civilianTruckDestroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 3.5
        player.deco[#player.deco].rotation = 0
        local clone_sfx = tankExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()  
        local numberz = randNbr(5) 
        for f = 1, numberz do
          createFire(place.x + (randNbr(300)-150), place.y + (randNbr(300)-150), 4)
        end
        for f = 1, 10 do
          local newPart = acquireParticle()
          addParticle(newPart, "civilianTruckDebris1", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        local cDebris = { "civilianTruckDebris2", "civilianTruckDebris8", "civilianTruckDebris11" }
        for cd = 1, #cDebris do
          local newPart = acquireParticle()
          addParticle(newPart, cDebris[cd], player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        local cDebrisPairs = { 3, 4, 5, 6, 7, 9, 10 }
        for cd = 1, #cDebrisPairs do
          for p = 1, 2 do
            local newPart = acquireParticle()
            addParticle(newPart, "civilianTruckDebris"..cDebrisPairs[cd], player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
            table.insert(player.particles, newPart)  
          end
        end
        table.remove(player.placeables, i)
      elseif(place.name == "deadCow") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "cowSplat"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = place.rotation
        local cowParts = { "deadCowHead", "deadCowSpine", "gib_heart" }
        for cp = 1, #cowParts do
          local newPart = acquireParticle()
          addParticle(newPart, cowParts[cp], place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end
        for o = 1, 2 do
          local p1 = acquireParticle()
          addParticle(p1, "gib_eye", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, p1)
          local p2 = acquireParticle()
          addParticle(p2, "deadCowLeg1", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, p2)
          local p3 = acquireParticle()
          addParticle(p3, "deadCowLeg2", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, p3)
        end
        for o = 1, 6 do
          local p1 = acquireParticle()
          addParticle(p1, "deadCowRib", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, p1)
          local p2 = acquireParticle()
          addParticle(p2, "gib_gib", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, p2)
        end
        table.remove(player.placeables, i)
      elseif(place.name == "sandBags") then 
        deleteRelatedCover(place.cheeseID)  
        for o = 1, 15 do
          local newPart = acquireParticle()
          addParticle(newPart, "sandBag", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        table.remove(player.placeables, i)
        if(player.gameType == 1) then 
          player.mnb2BuildDestroyed = player.mnb2BuildDestroyed + 1
        end
      end 
    end
  end

  -- 3. Deco destruction (Bodies, Tobruks, Bunkers)
  for i = #player.deco, 1, -1 do
    local place = player.deco[i]
    local ddx = place.x - x
    local ddy = place.y - y
    if (ddx * ddx + ddy * ddy) < rad2 then
      if(place.name == "allied_dead" or place.name == "axis_dead" or place.name == "sarge_dead" or place.name == "para_dead" or place.name == "french_dead" or place.name == "allied_deadBBQ") then
        gib(place)
        table.remove(player.deco, i)
      elseif(place.name == "tobruk") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "tobruk_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 8
        player.deco[#player.deco].rotation = place.rotation    
        for o = 1, 15 do
          local newPart = acquireParticle()
          addParticle(newPart, "bunker2_debris", place.x, place.y, rad(randNbr(360)))
          table.insert(player.particles, newPart) 
        end  
        local clone_sfx = rockDestroyed:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.deco, i)
      elseif(place.name == "defensivePosition") then 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "defensivePosition_destroyed"
        player.deco[#player.deco].x = place.x
        player.deco[#player.deco].y = place.y
        player.deco[#player.deco].size = 8
        player.deco[#player.deco].rotation = place.rotation    
        for o = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "sandBag", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        for o = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        local clone_sfx = cartBarricadeDestructionSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        deleteRelatedCover(place.cheeseID) 
        table.remove(player.deco, i)
      end
    end
  end

  -- 4. Neutrals (Santa)
  for ii = #player.neutrals, 1, -1 do
    local santaz = player.neutrals[ii]
    if(santaz.name == "santa") then
      local sdx = santaz.x - x
      local sdy = santaz.y - y
      if (sdx * sdx + sdy * sdy) < 10000 then -- 100^2
        gibSanta(santaz)
      end
    end
  end

  -- 5. Deco secondary check (Tiles, Wells, Trains, Live Rounds)
  for ii = #player.deco, 1, -1 do
    local d = player.deco[ii]
    local ddx = d.x - x
    local ddy = d.y - y
    local distSq = ddx * ddx + ddy * ddy

    if(d.name == "tile1" or d.name == "tile2" or d.name == "tile3" or d.name == "tile4") then 
      if distSq < radHalf2 then
        for o = 1, 6 do
          local newPart = acquireParticle()
          addParticle(newPart, "darkBrick_debris", d.x, d.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        table.remove(player.deco, ii)
      end
    elseif(d.name == "well") then 
      if distSq < radHalf2 then
        deleteRelatedCover(d.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "wellDestroyed"
        player.deco[#player.deco].x = d.x
        player.deco[#player.deco].y = d.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = rad(randNbr(360))
        for o = 1, 10 do
          local newPart = acquireParticle()
          addParticle(newPart, "tombDebris", d.x, d.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 
        local clone_sfx = _G["tombDest"..randNbr(5)]:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()
        table.remove(player.deco, ii)
      end
    elseif(d.name == "trainReinforcedWagon") then 
      if distSq < radHalf2 then
        deleteRelatedCover(d.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "boxCar_destroyed"
        player.deco[#player.deco].x = d.x
        player.deco[#player.deco].y = d.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        local clone_sfx = tankExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()  
        for o = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "sandBag", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        for o = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        table.remove(player.deco, ii)
      end
    elseif(d.name == "flatBed") then 
      if distSq < rad2 then
        deleteRelatedCover(d.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "boxCar_destroyed"
        player.deco[#player.deco].x = d.x
        player.deco[#player.deco].y = d.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        local clone_sfx = tankExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()  
        for o = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        table.remove(player.deco, ii)
      end
    elseif(d.name == "boxCar") then 
      if distSq < rad2 then
        deleteRelatedCover(d.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "boxCar_destroyed"
        player.deco[#player.deco].x = d.x
        player.deco[#player.deco].y = d.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        local clone_sfx = tankExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()  
        for o = 1, 35 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        table.remove(player.deco, ii)
      end
    elseif(d.name == "trainArmored") then 
      if distSq < radHalf2 then
        deleteRelatedCover(d.cheeseID) 
        player.deco[#player.deco+1] = {}
        player.deco[#player.deco].name = "boxCar_destroyed"
        player.deco[#player.deco].x = d.x
        player.deco[#player.deco].y = d.y
        player.deco[#player.deco].size = 10
        player.deco[#player.deco].rotation = 0
        local clone_sfx = tankExploSound:clone()
        clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
        clone_sfx:play()  
        for o = 1, 35 do
          local newPart = acquireParticle()
          addParticle(newPart, "stug_debris"..randNbr(17), player.deco[#player.deco].x, player.deco[#player.deco].y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        table.remove(player.deco, ii)
      end
    elseif(string.match(d.name, "liveRoundLarge")) then 
      if distSq < radDouble2 then
        local foo = tonumber(d.name:sub(15))
        if(foo == 1) then 
          player.delayedAction[#player.delayedAction+1] = { action = "createExplosion", timer = randNbr(15)/10, arg1 = "mineExplosion", arg2 = d.x, arg3 = d.y, arg4 = 0, arg5 = 0 }
        elseif(foo == 2) then 
          player.delayedAction[#player.delayedAction+1] = { action = "createExplosion", timer = randNbr(15)/10, arg1 = "faustExplosion", arg2 = d.x, arg3 = d.y, arg4 = 0, arg5 = 0 }
        elseif(foo == 3) then 
          for o = 1, 3 do
            player.delayedAction[#player.delayedAction+1] = { action = "smokeBlast", timer = randNbr(15)/10, arg1 = d.x + (randNbr(40)-20), arg2 = d.y + (randNbr(40)-20), arg3 = 0, arg4 = 0, arg5 = 0 }
          end
        elseif(foo == 4) then 
          player.delayedAction[#player.delayedAction+1] = { action = "wpBlast", timer = randNbr(15)/10, arg1 = d.x, arg2 = d.y, arg3 = 0, arg4 = 0, arg5 = 0 }
        elseif(foo == 5) then 
          player.delayedAction[#player.delayedAction+1] = { action = "airBurst", timer = randNbr(15)/10, arg1 = d.x, arg2 = d.y, arg3 = 0, arg4 = 0, arg5 = 0 }
        end
        table.remove(player.deco, ii)
      end
    elseif(string.match(d.name, "liveRoundMed")) then 
      if distSq < radDouble2 then
        local foo = tonumber(d.name:sub(13))
        if(foo == 1) then 
          player.delayedAction[#player.delayedAction+1] = { action = "createExplosion", timer = randNbr(15)/10, arg1 = "mortarExplosion", arg2 = d.x, arg3 = d.y, arg4 = 0, arg5 = 0 }
        elseif(foo == 2) then 
          player.delayedAction[#player.delayedAction+1] = { action = "createExplosion", timer = randNbr(15)/10, arg1 = "medAPExplosion", arg2 = d.x, arg3 = d.y, arg4 = 0, arg5 = 0 }
        elseif(foo == 3) then 
          player.delayedAction[#player.delayedAction+1] = { action = "smokeBlast", timer = randNbr(15)/10, arg1 = d.x, arg2 = d.y, arg3 = 0, arg4 = 0, arg5 = 0 }
        elseif(foo == 4) then 
          local numberz = randNbr(5) + 2
          for f = 1, numberz do
            player.delayedAction[#player.delayedAction+1] = { action = "createFire", timer = randNbr(15)/10, arg1 = d.x + (randNbr(40)-20), arg2 = d.y + (randNbr(40)-20), arg3 = 0, arg4 = 0, arg5 = 0 }
          end
        elseif(foo == 5) then 
          player.delayedAction[#player.delayedAction+1] = { action = "bettyBlast", timer = randNbr(15)/10, arg1 = d.x, arg2 = d.y, arg3 = 0, arg4 = 0, arg5 = 0 }
        end
        table.remove(player.deco, ii)
      end
    elseif(string.match(d.name, "liveRoundSmall")) then 
      if distSq < radDouble2 then
        local foo = tonumber(d.name:sub(15))
        if(foo == 1) then 
          player.delayedAction[#player.delayedAction+1] = { action = "createExplosion", timer = randNbr(15)/10, arg1 = "stuartExplosion", arg2 = d.x, arg3 = d.y, arg4 = 0, arg5 = 0 }
        elseif(foo == 2) then 
          player.delayedAction[#player.delayedAction+1] = { action = "createExplosion", timer = randNbr(15)/10, arg1 = "flakExplosion", arg2 = d.x, arg3 = d.y, arg4 = 0, arg5 = 0 }
        elseif(foo == 3) then 
          local numberz = randNbr(3) + 1
          for o = 1, numberz do
            local newPart = acquireParticle()
            addParticle(newPart, "whiteSmokeBall", d.x + (randNbr(20)-10), d.y + (randNbr(20)-10), rad(randNbr(360)))
            table.insert(player.topParticles, newPart)
            player.topParticles[#player.topParticles].scale = 1
            player.topParticles[#player.topParticles].alpha = 75
            player.topParticles[#player.topParticles].expand = 1.1
          end
        elseif(foo == 4) then 
          local numberz = randNbr(2) + 1
          for f = 1, numberz do
            player.delayedAction[#player.delayedAction+1] = { action = "createFire", timer = randNbr(15)/10, arg1 = d.x + (randNbr(40)-20), arg2 = d.y + (randNbr(40)-20), arg3 = 0, arg4 = 0, arg5 = 0 }
          end
        elseif(foo == 5) then 
          player.delayedAction[#player.delayedAction+1] = { action = "miniAirBurstDetonation", timer = randNbr(15)/10, arg1 = d.x, arg2 = d.y, arg3 = 0, arg4 = 0, arg5 = 0 }
        end
        table.remove(player.deco, ii)
      end
    end
  end

  -- 6. Buildings destruction (reverse loop + squared distance)
  for ii = #player.buildings, 1, -1 do
    local place = player.buildings[ii]
    local bdx = place.x - x
    local bdy = place.y - y

    if (bdx * bdx + bdy * bdy) < rad2 then
      if(string.match(place.name, "bunker2")) then 
        if(place.name == "bunker2a") then 
          createNewBunker2(place.x, place.y, "b")
          deleteRelatedCover(place.cheeseID)
          table.remove(player.buildings, ii)
          for o = 1, 10 do
            local newPart = acquireParticle()
            addParticle(newPart, "bunker2_debris", place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart) 
          end 
          local clone_sfx = bunkerHit1:clone()
          clone_sfx:setVolume(stepScale(player.buildings[#player.buildings]))
          clone_sfx:play()  
        elseif(place.name == "bunker2b") then 
          createNewBunker2(place.x, place.y, "c")
          deleteRelatedCover(place.cheeseID)
          for o = 1, 25 do
            local newPart = acquireParticle()
            addParticle(newPart, "bunker2_debris", place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart) 
          end 
          local clone_sfx = bunkerHit2:clone()
          clone_sfx:setVolume(stepScale(player.buildings[#player.buildings]))
          clone_sfx:play()  
          table.remove(player.buildings, ii)
        else
          player.deco[#player.deco+1] = {}
          player.deco[#player.deco].name = "bunker2_destroyed"
          player.deco[#player.deco].x = place.x
          player.deco[#player.deco].y = place.y
          player.deco[#player.deco].size = 10
          player.deco[#player.deco].rotation = place.rotation 
          for o = 1, 50 do
            local newPart = acquireParticle()
            addParticle(newPart, "bunker2_debris", place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart) 
          end 
          local clone_sfx = houseDestroyed:clone()
          clone_sfx:setVolume(stepScale(player.buildings[#player.buildings]))
          clone_sfx:play()  
          deleteRelatedCover(place.cheeseID)
          table.remove(player.buildings, ii)
        end
      else
        if(place.name ~= "pillBox" or randNbr(100) > 95) then 
          deleteRelatedCover(place.cheeseID)
          player.deco[#player.deco+1] = {}
          player.deco[#player.deco].name = place.name.."_destroyed"
          player.deco[#player.deco].x = place.x
          player.deco[#player.deco].y = place.y
          player.deco[#player.deco].size = 10
          player.deco[#player.deco].rotation = place.rotation  
          if(place.name ~= "camNet" and place.name ~= "antena" and place.name ~= "telephonePost" and place.name ~= "glider") then  
            local clone_sfx = houseDestroyed:clone()
            clone_sfx:setVolume(stepScale(player.deco[#player.deco]))
            clone_sfx:play()         
            for o = 1, 100 do
              local dice = randNbr(3)
              if(place.name ~= "brestFort") then 
                if(dice == 1) then 
                  local partName = (place.name ~= "bunker2") and "house_debris" or "cinderBlock"
                  local newPart = acquireParticle()
                  addParticle(newPart, partName, place.x, place.y, rad(randNbr(360)))
                  table.insert(player.particles, newPart)
                elseif(dice == 2) then
                  local partName = (place.name == "bunker1") and "sandBag" or ((place.name == "bunker2") and "bunker2_debris" or "cinderBlock")
                  local newPart = acquireParticle()
                  addParticle(newPart, partName, place.x, place.y, rad(randNbr(360)))
                  table.insert(player.particles, newPart)  
                else 
                  if(place.name ~= "bunker2") then 
                    local newPart = acquireParticle()
                    addParticle(newPart, "bigPlank", place.x, place.y, rad(randNbr(360)))
                    table.insert(player.particles, newPart)
                  end
                end
              else
                local partName = (dice == 1) and "brestFortDebris" or ((dice == 2) and "brestWallDebris" or "bigPlank")
                local newPart = acquireParticle()
                addParticle(newPart, partName, place.x, place.y, rad(randNbr(360)))
                table.insert(player.particles, newPart) 
              end
            end
          end
          if(place.name == "bunker1") then
            for b = 1, 2 do
              local newPart = acquireParticle()
              addParticle(newPart, "corrugated", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart) 
            end
          end
          if(place.name == "mausoleum_floor") then 
            for o = 1, 20 do
              local newPart = acquireParticle()
              addParticle(newPart, "mausoleumBrick", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end           
          end
          if(place.name == "barn") then 
            for o = 1, 10 do
              local newPart = acquireParticle()
              addParticle(newPart, "barn_debris", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end   
          end
          if(place.name == "") then
            for o = 1, 20 do
              local newPart = acquireParticle()
              addParticle(newPart, "brestGun_debris", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end 
          end
          if(place.name == "camNet") then
            local clone_sfx = camDestroySound:clone()
            clone_sfx:setVolume(stepScale(place))
            clone_sfx:play()  
            for o = 1, 20 do
              local newPart = acquireParticle()
              addParticle(newPart, "plant_debris", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end 
            for o = 1, 4 do
              local newPart = acquireParticle()
              addParticle(newPart, "smallPlank", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end 
          end
          if(place.name == "glider") then
            local clone_sfx = tankExploSound:clone()
            clone_sfx:setVolume(stepScale(place))
            clone_sfx:play()  
            for o = 1, 9 do
              local newPart = acquireParticle()
              addParticle(newPart, "gliderDebris1", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end 
            local counts = { [3] = 1, [4] = 2, [5] = 6, [6] = 6, [7] = 6, [8] = 6, [9] = 6 }
            for g = 3, 9 do
              for c = 1, counts[g] do
                local newPart = acquireParticle()
                addParticle(newPart, "gliderDebris"..g, place.x, place.y, rad(randNbr(360)))
                table.insert(player.particles, newPart)
              end
            end
          end
          if(place.name == "antena") then 
            for o = 1, 4 do
              local newPart = acquireParticle()
              addParticle(newPart, "sdkfz_debris17", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end 
            for o = 1, 4 do
              local newPart = acquireParticle()
              addParticle(newPart, "opel_debris9", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart)
            end 
            local clone_sfx = smallVehicleExplosion:clone()
            clone_sfx:setVolume(stepScale(place))
            clone_sfx:play()
          end
          if(place.name == "telephonePost") then 
            local newPart = acquireParticle()
            addParticle(newPart, "telephonePostDebris1", place.x, place.y, rad(randNbr(360)))
            table.insert(player.particles, newPart)
            for o = 1, 3 do
              local newPart2 = acquireParticle()
              addParticle(newPart2, "telephonePostDebris2", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart2)
            end 
            local clone_sfx2 = _G["poleDestroyed"..randNbr(3)]:clone()
            clone_sfx2:setVolume(stepScale(place))
            clone_sfx2:play() 
          end
          if(place.name == "pillBox") then 
            for o = 1, 100 do
              local newPart = acquireParticle()
              addParticle(newPart, "bunker2_debris", place.x, place.y, rad(randNbr(360)))
              table.insert(player.particles, newPart) 
            end
          end
          if(player.gameType == 1) then 
            player.mnb2BuildDestroyed = player.mnb2BuildDestroyed + 1
          end
          table.remove(player.buildings, ii)
        else
          if(foo ~= 1) then 
            floatyText(place, "glancing blow")
            local clone_sfx2 = glancingBlow:clone()
            clone_sfx2:setVolume(gunScale(place))
            clone_sfx2:play()
          end  
        end
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- Wire and Obstacle Destruction with Squared Distances
-- ----------------------------------------------------------------------------

function destroyClosestWire(soldier)
  local tempDistSq = 999999999
  local objectAdress = 0
  for ii, place in ipairs(player.placeables) do
    if(place.name == "barbWire") then 
      local dx = soldier.x - place.x
      local dy = soldier.y - place.y
      local dSq = dx * dx + dy * dy
      if dSq < tempDistSq then 
        objectAdress = ii
        tempDistSq = dSq
      end
    end
  end
  if(objectAdress ~= 0 and player.placeables[objectAdress] and player.placeables[objectAdress].name == "barbWire") then
    player.deco[#player.deco+1] = {}
    player.deco[#player.deco].name = "barbWireDestroyed"
    player.deco[#player.deco].x = player.placeables[objectAdress].x
    player.deco[#player.deco].y = player.placeables[objectAdress].y
    player.deco[#player.deco].size = 10
    player.deco[#player.deco].rotation = rad(randNbr(360))
    deleteRelatedCover(player.placeables[objectAdress].cheeseID)
    table.remove(player.placeables, objectAdress)
  end
end

function destroyClosestEntanglement(soldier)
  local tempDistSq = 999999999
  local objectAdress = 0
  for ii, place in ipairs(player.placeables) do
    if(place.name == "entanglement") then 
      local dx = soldier.x - place.x
      local dy = soldier.y - place.y
      local dSq = dx * dx + dy * dy
      if dSq < tempDistSq then 
        objectAdress = ii
        tempDistSq = dSq
      end
    end
  end
  if(objectAdress ~= 0 and player.placeables[objectAdress] and player.placeables[objectAdress].name == "entanglement") then
    player.deco[#player.deco+1] = {}
    player.deco[#player.deco].name = "entanglementDestroyed"
    player.deco[#player.deco].x = player.placeables[objectAdress].x
    player.deco[#player.deco].y = player.placeables[objectAdress].y
    player.deco[#player.deco].size = 10
    player.deco[#player.deco].rotation = rad(randNbr(360))
    deleteRelatedCover(player.placeables[objectAdress].cheeseID)
    table.remove(player.placeables, objectAdress)
  end
end

-- ----------------------------------------------------------------------------
-- Ground Surface Identifier with Squared Distance on Radial Tiles
-- ----------------------------------------------------------------------------

function groundSurfaceTell(ticle)
  if not ticle then return "grass" end
  for u = 1, #player.groundType do
    local gt = player.groundType[u]
    if gt then 
      local inZone = false
      if (gt.width or 0) > 0 and (gt.length or 0) > 0 then 
        if ticle.x > gt.x and ticle.x < gt.x + gt.width and ticle.y > gt.y and ticle.y < gt.y + gt.length then
          inZone = true
        end
      end
      if not inZone and (gt.radius or 0) > 0 then
        local dx = ticle.x - gt.x
        local dy = ticle.y - gt.y
        if (dx * dx + dy * dy) < (gt.radius * gt.radius) then
          inZone = true
        end
      end

      if inZone then
        if gt.name == "wood" or gt.name == "metal" or gt.name == "concrete" or gt.name == "water" then
          return gt.name
        else
          return "grass"
        end
      end
    end
  end
  return "grass"
end

function createBandages(x, y)
  local dice = 4 + randNbr(6)
  for u = 1, dice do
    local newPart = acquireParticle()
    addParticle(newPart, "bandage", x, y, rad(randNbr(360)))
    table.insert(player.particles, newPart)
  end
end

function createVehicleFire(x, y)
  local dice = randNbr(4)
  for u = 1, dice do
    if(randNbr(100) < 20) then 
      createFire(x + 50 - randNbr(100), y + 50 - randNbr(100), randNbr(5))
    end
  end
  for o = 1, 30 do
    player.delayedAction[#player.delayedAction+1] = {
      action = "createFireSmokePart2",
      timer = (randNbr(15)/10) * o,
      arg1 = x, arg2 = y, arg3 = 0, arg4 = 0, arg5 = 0
    }
  end
end

-- ----------------------------------------------------------------------------
-- Bridge Destruction with Squared Distance
-- ----------------------------------------------------------------------------

function bridgeDestruction(explosion)
  if(explosion.tag == "stukaExplosion" or explosion.tag == "mortarExplosion" or explosion.tag == "bombExplosion" or explosion.tag == "howitzerExplosion" or explosion.tag == "goliathExplosion" or explosion.tag == "precisionExplosion" or explosion.tag == "b17Explosion" or explosion.tag == "v1Explosion" or explosion.tag == "tntExplosion" or explosion.tag == "artyExplosion") then 
    local bridge = getBridge()
    if(bridge and (bridge.name == "bridge" or bridge.name == "bridgeVertical")) then 
      local dx = bridge.x - explosion.x
      local dy = bridge.y - explosion.y
      if (dx * dx + dy * dy) < 40000 then -- 200^2
        if(player.bcBridge == 1) then 
          anounceStuff(bridgeExplodedTxt)
          local clone_sfx1 = breakThroughSound:clone()
          clone_sfx1:play()
          player.bcBridge = -1
        end

        local spread = (bridge.name == "bridgeVertical") and 100 or 500
        bridge.name = (bridge.name == "bridgeVertical") and "bigPlank1" or "bridgeDestroyed"

        for i = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "bigPlank", bridge.x - spread + randNbr(spread * 2), bridge.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        for i = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "bridgePart"..randNbr(3), bridge.x - spread + randNbr(spread * 2), bridge.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)  
        end
        for o = 1, 25 do
          local newPart = acquireParticle()
          addParticle(newPart, "woodPlank", bridge.x, bridge.y, rad(randNbr(360)))
          table.insert(player.particles, newPart)
        end 

        for iii = #player.groundType, 1, -1 do
          if(player.groundType[iii].cheeseID == bridge.cheeseID) then 
            player.groundType[iii].name = "water"
            player.groundType[iii].cover = 0
            player.groundType[iii].slowy = "yes"
          end
        end

        local clone_sfx2 = houseDestroyed:clone()
        clone_sfx2:setVolume(gunScale(bridge))
        clone_sfx2:play()
      end
    end
  end
end

function createLootByName(name, x, y)
  player.lootables[#player.lootables+1] = {
    name = name,
    x = x,
    y = y,
    flagged = 1,
    faction = "allied",
    argument = "",
    size = 10,
    life = 60,
    rotation = rad(randNbr(360))
  }
  screenSanity(player.lootables[#player.lootables])
end

function drawParticleList(list, isTop)
  if not list or #list == 0 then return end

  local camX = player and player.screenx or 0
  local minX = camX - 80
  local maxX = camX + 1360
  local lastAlpha = -1

  love.graphics.setColor(1, 1, 1, 1)

  for i = 1, #list do
    local p = list[i]
    -- Strict null-safety check
    if p and p.sprite and p.x and p.y then
      -- 1. Viewport Frustum Culling
      if p.x >= minX and p.x <= maxX then
        local img = _G[p.sprite]
        if img and img.getWidth then
          -- 2. State-Cached setColor
          local a = p.alpha or 255
          if a ~= lastAlpha then
            if a >= 254 then
              love.graphics.setColor(1, 1, 1, 1)
            else
              love.graphics.setColor(1, 1, 1, a / 255)
            end
            lastAlpha = a
          end

          local rot = p.innerRotation or p.rotationz or 0
          local sc = p.scale or 1
          local xo = p.xoffset or 0
          local yo = p.yoffset or 0

          if p.typez == "muzzleFlash" then
            if muzzleFlashShader then
              love.graphics.setShader(muzzleFlashShader)
              love.graphics.setBlendMode("add")
              love.graphics.draw(img, p.x, p.y, rot, sc, sc, xo, yo - 20)
              love.graphics.setShader()
              love.graphics.setColor(1, 0.9, 0.63, math.min(180, a) / 255)
              love.graphics.draw(img, p.x, p.y, rot, sc * 1.1, sc * 1.1, xo, yo - 20)
              love.graphics.setBlendMode("alpha")
              lastAlpha = -1
            else
              love.graphics.draw(img, p.x, p.y, rot, sc, sc, xo, yo - 20)
            end
          elseif p.typez == "bazookaFlash" then
            love.graphics.draw(img, p.x, p.y, rot, sc, sc, xo, yo - 20)
          elseif p.typez == "flarePart" or p.typez == "redFlarePart" then
            if randNbr(100) < 50 then
              local flareScale = randNbr(15) / 10
              love.graphics.draw(img, p.x, p.y, rad(randNbr(360)), flareScale, flareScale, xo, yo)
            end
          else
            love.graphics.draw(img, p.x, p.y, rot, sc, sc, xo, yo)
          end
        end
      end
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

-- ----------------------------------------------------------------------------
-- Self-Test & Live Benchmark: Particle System (Crash-Proof)
-- ----------------------------------------------------------------------------
function runParticleBenchmark(count, passes)
  count = count or 5000
  passes = passes or 5

  -- 1. Snapshot original game state
  local orig_particles = {}
  if player and player.particles then
    for i = 1, #player.particles do
      orig_particles[i] = player.particles[i]
    end
  end

  local orig_canvas = love.graphics.getCanvas()
  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()

  -- 2. Gather valid particle sprites
  local valid_sprites = {}
  if player and player.particles then
    for i = 1, #player.particles do
      local spr = player.particles[i] and player.particles[i].sprite
      if spr and _G[spr] and _G[spr].getWidth and not valid_sprites[spr] then
        valid_sprites[#valid_sprites + 1] = spr
        valid_sprites[spr] = true
      end
    end
  end

  local fallbacks = { "shell", "smallShell", "bigShell", "spark1", "sandBag", "bigSmoke" }
  for _, spr in ipairs(fallbacks) do
    if _G[spr] and _G[spr].getWidth and not valid_sprites[spr] then
      valid_sprites[#valid_sprites + 1] = spr
      valid_sprites[spr] = true
    end
  end

  if #valid_sprites == 0 then
    if not _G["__bench_dummy_part__"] then
      local img_data = love.image.newImageData(8, 8)
      img_data:mapPixel(function() return 1, 0.8, 0.2, 1 end)
      _G["__bench_dummy_part__"] = love.graphics.newImage(img_data)
    end
    valid_sprites[1] = "__bench_dummy_part__"
  end

  -- 3. Generate synthetic particles across a 4000px ribbon
  local sx = (player and player.screenx) or 0
  local test_particles = {}
  local on_screen_count = 0
  local minX = sx - 80
  local maxX = sx + 1360

  for i = 1, count do
    local px = sx - 1500 + ((i * 107) % 4000)
    local py = 40 + ((i * 47) % 640)
    local alpha = (i % 5 == 0) and (60 + (i % 180)) or 255

    if px >= minX and px <= maxX then
      on_screen_count = on_screen_count + 1
    end

    test_particles[i] = {
      sprite = valid_sprites[(i % #valid_sprites) + 1],
      typez = "shell",
      x = px,
      y = py,
      rotationz = ((i * 23) % 360) * (math.pi / 180),
      innerRotation = ((i * 31) % 360) * (math.pi / 180),
      scale = 0.8 + ((i % 4) * 0.1),
      alpha = alpha,
      xoffset = 2,
      yoffset = 2,
      lifeSpan = 100
    }
  end

  local culled_count = count - on_screen_count
  local culled_pct = count > 0 and (culled_count / count * 100) or 0
  local test_target = love.graphics.newCanvas(1280, 720)

  -- 4. Benchmark Vanilla Draw
  love.graphics.setCanvas(test_target)
  local calls_before_vanilla = love.graphics.getStats().drawcalls
  local t0 = love.timer.getTime()

  for p = 1, passes do
    love.graphics.clear(0, 0, 0, 0)
    for n = 1, count do
      local pt = test_particles[n]
      local img = pt and pt.sprite and _G[pt.sprite]
      if img and img.getWidth then
        love.graphics.setColor(1, 1, 1, (pt.alpha or 255) / 255)
        love.graphics.draw(img, pt.x, pt.y, pt.innerRotation or pt.rotationz or 0, pt.scale or 1, pt.scale or 1, pt.xoffset or 0, pt.yoffset or 0)
      end
    end
  end
  local vanilla_draw_ms = ((love.timer.getTime() - t0) * 1000) / passes
  local vanilla_draw_calls = math.floor((love.graphics.getStats().drawcalls - calls_before_vanilla) / passes)

  -- 5. Benchmark Optimized Draw (Frustum Culling + State Cache)
  local calls_before_optim = love.graphics.getStats().drawcalls
  local t1 = love.timer.getTime()

  for p = 1, passes do
    love.graphics.clear(0, 0, 0, 0)
    drawParticleList(test_particles, false)
  end
  local optim_draw_ms = ((love.timer.getTime() - t1) * 1000) / passes
  local optim_draw_calls = math.floor((love.graphics.getStats().drawcalls - calls_before_optim) / passes)

  -- CRUCIAL STEP: Unbind canvas from OpenGL Framebuffer BEFORE reading pixels
  love.graphics.setCanvas(orig_canvas)
  love.graphics.setBlendMode(prev_blend, prev_alpha)
  love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)

  -- 6. Safe Pixel Audit (Canvas is now safely unbound)
  local coverage_pct = 0
  local ok, img_data = pcall(function() return test_target:newImageData() end)
  if ok and img_data then
    local painted_samples = 0
    local total_samples = 0
    for sample_x = 20, 1260, 42 do
      for sample_y = 20, 700, 24 do
        total_samples = total_samples + 1
        local _, _, _, a = img_data:getPixel(sample_x, sample_y)
        if a > 0.01 then
          painted_samples = painted_samples + 1
        end
      end
    end
    coverage_pct = total_samples > 0 and (painted_samples / total_samples * 100) or 0
    img_data:release() -- Free C memory immediately
  end

  test_target:release() -- Free GPU canvas memory immediately

  -- 7. Restore game particles cleanly
  if player then
    player.particles = {}
    for i = 1, #orig_particles do
      player.particles[i] = orig_particles[i]
    end
  end

  local speedup = (optim_draw_ms > 0) and (vanilla_draw_ms / optim_draw_ms) or 0
  local msg = string.format(
    "[Particle Benchmark] %d Particles | Calls: %d -> %d | Vanilla: %.4f ms | Optim: %.4f ms | Coverage: %.1f%% | Culled: %d (%.1f%%) | Speedup: %.1fx",
    count, vanilla_draw_calls, optim_draw_calls, vanilla_draw_ms, optim_draw_ms, coverage_pct, culled_count, culled_pct, speedup
  )
  print(msg)

  -- Matching return signature for main.lua
  return optim_draw_ms, vanilla_draw_ms, speedup, culled_pct, count, vanilla_draw_calls, optim_draw_calls
end