-- ============================================================================
-- Continuous Load Benchmark: Sustained Real-World Stress Test
-- ============================================================================

function runContinuousBenchmark(durationSeconds, particleCount, decalCount, losCount, vanillaLosFunc)
  durationSeconds = durationSeconds or 15.0 -- Sustained duration per phase (seconds)
  particleCount = particleCount or 20000
  decalCount = decalCount or 20000
  losCount = losCount or 20000
  vanillaLosFunc = vanillaLosFunc or _G.vanilla_los or _G.los

  -- --------------------------------------------------------------------------
  -- 1. Snapshot Game & Graphics State
  -- --------------------------------------------------------------------------
  local orig_particles = {}
  if player and player.particles then
    for i = 1, #player.particles do
      orig_particles[i] = player.particles[i]
    end
  end

  local orig_deco = player and player.deco
  local orig_canvas = love.graphics.getCanvas()
  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
  local sx = (player and player.screenx) or 0
  local mapW = (player and player.endLine and player.endLine > 1000) and player.endLine or 10000

  -- --------------------------------------------------------------------------
  -- 2. Build Synthetic Workloads
  -- --------------------------------------------------------------------------
  -- A. Particle Sprites
  local part_sprites = {}
  if player and player.particles then
    for i = 1, #player.particles do
      local spr = player.particles[i] and player.particles[i].sprite
      if spr and _G[spr] and _G[spr].getWidth and not part_sprites[spr] then
        part_sprites[#part_sprites + 1] = spr
        part_sprites[spr] = true
      end
    end
  end
  for _, spr in ipairs({ "shell", "smallShell", "bigShell", "spark1", "sandBag", "bigSmoke" }) do
    if _G[spr] and _G[spr].getWidth and not part_sprites[spr] then
      part_sprites[#part_sprites + 1] = spr
      part_sprites[spr] = true
    end
  end
  if #part_sprites == 0 then
    if not _G["__bench_dummy_part__"] then
      local img_data = love.image.newImageData(8, 8)
      img_data:mapPixel(function() return 1, 0.8, 0.2, 1 end)
      _G["__bench_dummy_part__"] = love.graphics.newImage(img_data)
    end
    part_sprites[1] = "__bench_dummy_part__"
  end

  local test_particles = {}
  for i = 1, particleCount do
    test_particles[i] = {
      sprite = part_sprites[(i % #part_sprites) + 1],
      typez = "shell",
      x = sx - 1500 + ((i * 107) % 4000),
      y = 40 + ((i * 47) % 640),
      rotationz = ((i * 23) % 360) * (math.pi / 180),
      innerRotation = ((i * 31) % 360) * (math.pi / 180),
      scale = 0.8 + ((i % 4) * 0.1),
      alpha = (i % 5 == 0) and (60 + (i % 180)) or 255,
      xoffset = 2,
      yoffset = 2,
      lifeSpan = 100
    }
  end

  -- B. Decal Sprites
  local decal_sprites = {}
  if player and player.deco then
    for i = 1, #player.deco do
      local name = player.deco[i].name
      if name and _G[name] and _G[name].getWidth and not decal_sprites[name] then
        decal_sprites[#decal_sprites + 1] = name
        decal_sprites[name] = true
      end
    end
  end
  for _, name in ipairs({ "kiaMask", "blood1", "blood2", "shell", "crater" }) do
    if _G[name] and _G[name].getWidth and not decal_sprites[name] then
      decal_sprites[#decal_sprites + 1] = name
      decal_sprites[name] = true
    end
  end
  if #decal_sprites == 0 then
    if not _G["__bench_dummy_decal__"] then
      local img_data = love.image.newImageData(16, 16)
      img_data:mapPixel(function() return 0.8, 0.2, 0.2, 0.8 end)
      _G["__bench_dummy_decal__"] = love.graphics.newImage(img_data)
    end
    decal_sprites[1] = "__bench_dummy_decal__"
  end

  local test_decos = {}
  for i = 1, decalCount do
    test_decos[i] = {
      name = decal_sprites[(i % #decal_sprites) + 1],
      x = sx - 100 + ((i * 79) % 1480),
      y = 30 + ((i * 43) % 660),
      rotation = ((i * 17) % 360) * (math.pi / 180),
      size = 6 + ((i * 11) % 12),
      imunity = 0
    }
  end

  -- C. LOS Raycast Pairs
  local test_rays = {}
  for i = 1, losCount do
    local x1 = ((i * 197) % mapW) + 100
    local y1 = ((i * 73) % 680) + 20
    local x2 = ((x1 + 150 + (i * 311) % 900) % mapW) + 100
    local y2 = ((i * 139) % 680) + 20
    test_rays[i] = { x1, x2, y1, y2 }
  end

  local test_target = love.graphics.newCanvas(1280, 720)

  -- Execute benchmark inside pcall so graphics/data are ALWAYS cleaned up on failure
  local ok, result = pcall(function()
    -- ------------------------------------------------------------------------
    -- 3. PHASE 1: Sustained Vanilla Load Loop
    -- ------------------------------------------------------------------------
    love.graphics.setCanvas(test_target)
    local calls_before_v = love.graphics.getStats().drawcalls
    local v_frames = 0
    local v_los_time = 0
    local v_part_time = 0
    local v_decal_time = 0
    local v_min_frame = 999999
    local v_max_frame = 0

    local t_start_v = love.timer.getTime()
    while (love.timer.getTime() - t_start_v) < durationSeconds do
      local f_t0 = love.timer.getTime()
      love.graphics.clear(0, 0, 0, 0)

      -- A. Vanilla LOS
      if vanillaLosFunc then
        local t_los = love.timer.getTime()
        for i = 1, losCount do
          local r = test_rays[i]
          vanillaLosFunc(r[1], r[2], r[3], r[4])
        end
        v_los_time = v_los_time + (love.timer.getTime() - t_los)
      end

      -- B. Vanilla Particles
      local t_part = love.timer.getTime()
      for i = 1, particleCount do
        local pt = test_particles[i]
        local img = pt and pt.sprite and _G[pt.sprite]
        if img and img.getWidth then
          love.graphics.setColor(1, 1, 1, (pt.alpha or 255) / 255)
          love.graphics.draw(img, pt.x, pt.y, pt.innerRotation or pt.rotationz or 0, pt.scale or 1, pt.scale or 1, pt.xoffset or 0, pt.yoffset or 0)
        end
      end
      v_part_time = v_part_time + (love.timer.getTime() - t_part)

      -- C. Vanilla Decals
      local t_decal = love.timer.getTime()
      for i = 1, decalCount do
        local d = test_decos[i]
        local img = _G[d.name]
        if img then
          local sc = (d.size or 10) / 10
          local w, h = img:getWidth(), img:getHeight()
          love.graphics.draw(img, d.x - sx, d.y, d.rotation or 0, sc, sc, w * 0.5, h * 0.5)
        end
      end
      v_decal_time = v_decal_time + (love.timer.getTime() - t_decal)

      local f_time = (love.timer.getTime() - f_t0) * 1000
      if f_time < v_min_frame then v_min_frame = f_time end
      if f_time > v_max_frame then v_max_frame = f_time end
      v_frames = v_frames + 1
    end

    local actual_v_dur = love.timer.getTime() - t_start_v
    local v_calls_total = love.graphics.getStats().drawcalls - calls_before_v
    local v_draw_calls = v_frames > 0 and math.floor(v_calls_total / v_frames) or 0
    local v_fps = v_frames / actual_v_dur
    local v_avg_ms = (actual_v_dur * 1000) / v_frames

    -- ------------------------------------------------------------------------
    -- 4. PHASE 2: Sustained Modded Load Loop
    -- ------------------------------------------------------------------------
    -- Unbind test canvas during baker setup so chunks bake cleanly
    love.graphics.setCanvas(orig_canvas)

    local bake_ms = 0
    if decal_baker then
      if not player then player = {} end
      player.deco = test_decos
      local tb0 = love.timer.getTime()
      decal_baker.force_rebake()
      decal_baker.sync()
      bake_ms = (love.timer.getTime() - tb0) * 1000
    end

    if los_physics and los_physics.sync then
      los_physics.sync()
    end

    -- Explicitly rebind test target for modded rendering
    love.graphics.setCanvas(test_target)
    local calls_before_opt = love.graphics.getStats().drawcalls
    local opt_frames = 0
    local opt_los_time = 0
    local opt_part_time = 0
    local opt_decal_time = 0
    local opt_min_frame = 999999
    local opt_max_frame = 0

    local t_start_opt = love.timer.getTime()
    while (love.timer.getTime() - t_start_opt) < durationSeconds do
      local f_t0 = love.timer.getTime()
      love.graphics.clear(0, 0, 0, 0)

      -- A. Box2D LOS
      if los_physics and los_physics.checkLOS then
        local t_los = love.timer.getTime()
        for i = 1, losCount do
          local r = test_rays[i]
          los_physics.checkLOS(r[1], r[2], r[3], r[4])
        end
        opt_los_time = opt_los_time + (love.timer.getTime() - t_los)
      end

      -- B. Frustum Culled Particles
      if drawParticleList then
        local t_part = love.timer.getTime()
        drawParticleList(test_particles, false)
        opt_part_time = opt_part_time + (love.timer.getTime() - t_part)
      end

      -- C. Baked Decal Blit
      if decal_baker and decal_baker.draw then
        local t_decal = love.timer.getTime()
        decal_baker.draw()
        opt_decal_time = opt_decal_time + (love.timer.getTime() - t_decal)
      end

      local f_time = (love.timer.getTime() - f_t0) * 1000
      if f_time < opt_min_frame then opt_min_frame = f_time end
      if f_time > opt_max_frame then opt_max_frame = f_time end
      opt_frames = opt_frames + 1
    end

    local actual_opt_dur = love.timer.getTime() - t_start_opt
    local opt_calls_total = love.graphics.getStats().drawcalls - calls_before_opt
    local opt_draw_calls = opt_frames > 0 and math.floor(opt_calls_total / opt_frames) or 0
    local opt_fps = opt_frames / actual_opt_dur
    local opt_avg_ms = (actual_opt_dur * 1000) / opt_frames

    -- ------------------------------------------------------------------------
    -- 5. Calculate Metrics
    -- ------------------------------------------------------------------------
    local throughput_speedup = (v_fps > 0) and (opt_fps / v_fps) or 0
    local v_part_ms = (v_part_time * 1000) / v_frames
    local v_decal_ms = (v_decal_time * 1000) / v_frames
    local v_los_ms = (v_los_time * 1000) / v_frames

    local opt_part_ms = (opt_part_time * 1000) / opt_frames
    local opt_decal_ms = (opt_decal_time * 1000) / opt_frames
    local opt_los_ms = (opt_los_time * 1000) / opt_frames

    local part_speedup = (opt_part_ms > 0) and (v_part_ms / opt_part_ms) or 0
    local decal_speedup = (opt_decal_ms > 0) and (v_decal_ms / opt_decal_ms) or 0
    local los_speedup = (opt_los_ms > 0) and (v_los_ms / opt_los_ms) or 0

    print("================================================================================")
    print(string.format("[CONTINUOUS BENCHMARK] Sustained Load over %.1fs each", durationSeconds))
    print(string.format("  * SUSTAINED FPS    : %.1f FPS (Vanilla) -> %.1f FPS (Optimized) | Throughput: %.1fx", v_fps, opt_fps, throughput_speedup))
    print(string.format("  * FRAMES PROCESSED : %d frames vs %d frames", v_frames, opt_frames))
    print(string.format("  * AVG FRAME TIME   : %.2f ms -> %.2f ms | Calls: %d -> %d/frame", v_avg_ms, opt_avg_ms, v_draw_calls, opt_draw_calls))
    print(string.format("  * FRAME SPIKES     :"))
    print(string.format("      Vanilla : min %.2f ms | max %.2f ms (spike: +%.2f ms)", v_min_frame, v_max_frame, v_max_frame - v_avg_ms))
    print(string.format("      Modded  : min %.2f ms | max %.2f ms (spike: +%.2f ms)", opt_min_frame, opt_max_frame, opt_max_frame - opt_avg_ms))
    print(string.format("  * SUBSYSTEM BREAKDOWN (per frame):"))
    print(string.format("      Particles (%d) : %.2f ms -> %.2f ms (%.1fx)", particleCount, v_part_ms, opt_part_ms, part_speedup))
    print(string.format("      Decals (%d)    : %.2f ms -> %.2f ms (%.1fx) [Bake: %.1f ms]", decalCount, v_decal_ms, opt_decal_ms, decal_speedup, bake_ms))
    print(string.format("      LOS Rays (%d)  : %.2f ms -> %.2f ms (%.1fx)", losCount, v_los_ms, opt_los_ms, los_speedup))
    print("================================================================================")

    return {
      duration = durationSeconds,
      vFrames = v_frames,
      optFrames = opt_frames,
      vFps = v_fps,
      optFps = opt_fps,
      throughputSpeedup = throughput_speedup,
      vAvgMs = v_avg_ms,
      optAvgMs = opt_avg_ms,
      vCalls = v_draw_calls,
      optCalls = opt_draw_calls,
      vMinMs = v_min_frame,
      vMaxMs = v_max_frame,
      optMinMs = opt_min_frame,
      optMaxMs = opt_max_frame,
      particleCount = particleCount,
      decalCount = decalCount,
      losCount = losCount,
      bakeMs = bake_ms,
      vPartMs = v_part_ms,
      optPartMs = opt_part_ms,
      partSpeedup = part_speedup,
      vDecalMs = v_decal_ms,
      optDecalMs = opt_decal_ms,
      decalSpeedup = decal_speedup,
      vLosMs = v_los_ms,
      optLosMs = opt_los_ms,
      losSpeedup = los_speedup
    }
  end)

  -- --------------------------------------------------------------------------
  -- 6. Clean State Restoration
  -- --------------------------------------------------------------------------
  love.graphics.setCanvas(orig_canvas)
  love.graphics.setBlendMode(prev_blend, prev_alpha)
  love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
  test_target:release()

  if player then
    player.particles = {}
    for i = 1, #orig_particles do
      player.particles[i] = orig_particles[i]
    end
    player.deco = orig_deco
  end

  if decal_baker then
    decal_baker.clear_all()
    if orig_deco and #orig_deco > 0 then
      decal_baker.force_rebake()
      decal_baker.sync()
    end
  end

  if not ok then
    error(result)
  end

  return result
end