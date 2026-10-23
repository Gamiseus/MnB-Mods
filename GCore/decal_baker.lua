-- ============================================================================
-- decal_baker.lua - High Performance Decal Canvas Baking & Cleanup System
-- Part of GCore Mod for Mud and Blood (LÖVE 11.4)
-- ============================================================================

local decal_baker = {}
local broomer_hooked = false

local CHUNK_WIDTH = 1280
local CHUNK_HEIGHT = 720

local chunks = {}               -- col -> Canvas
local last_deco_table = nil     -- identity check
local last_deco_count = 0       -- count of stamped decals
local dim_cache = {}            -- Image -> {w, h}
local clean_timer = 0           -- periodic check timer
local needs_full_rebake = false

-- A decal is immune if the engine marked it with imunity/immunity == 1
local function is_immune(d)
  if not d then return true end
  return (d.imunity == 1 or d.immunity == 1)
end

local function get_image_dims(img)
  local dims = dim_cache[img]
  if not dims then
    dims = { img:getWidth(), img:getHeight() }
    dim_cache[img] = dims
  end
  return dims[1], dims[2]
end

local function get_or_create_chunk(col)
  local c = chunks[col]
  if not c then
    c = love.graphics.newCanvas(CHUNK_WIDTH, CHUNK_HEIGHT)
    chunks[col] = c
  end
  return c
end

function decal_baker.clear_all()
  local prev_canvas = love.graphics.getCanvas()
  for col, c in pairs(chunks) do
    if c then
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
    end
  end
  love.graphics.setCanvas(prev_canvas)
  last_deco_count = 0
end

local function stamp_range(decal_list, start_idx, end_idx)
  if not decal_list or start_idx > end_idx then return end

  local batches = {}

  for i = start_idx, end_idx do
    local d = decal_list[i]
    if d and d.name then
      local img = _G[d.name]
      if img and img.getWidth then
        local w, h = get_image_dims(img)
        local scale = (d.size or 10) / 10
        local radius = math.max(w, h) * scale * 0.5
        local col_min = math.floor((d.x - radius) / CHUNK_WIDTH)
        local col_max = math.floor((d.x + radius) / CHUNK_WIDTH)

        for col = col_min, col_max do
          local b = batches[col]
          if not b then
            b = {}
            batches[col] = b
          end
          -- Store only the index, not a new table!
          b[#b + 1] = i
        end
      end
    end
  end

  local prev_canvas = love.graphics.getCanvas()
  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()

  -- CRUCIAL: Push the graphics stack and reset to origin so camera
  -- translations/scaling never leak onto the canvas.
  love.graphics.push()
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)

  for col, indices in pairs(batches) do
    local c = get_or_create_chunk(col)
    love.graphics.setCanvas(c)
    local ox = col * CHUNK_WIDTH
    for j = 1, #indices do
      local d = decal_list[indices[j]]
      local img = _G[d.name]
      local w, h = get_image_dims(img)
      local sc = (d.size or 10) / 10
      local lx = d.x - ox
      local ly = d.y
      local rot = d.rotation or 0
      love.graphics.draw(img, lx, ly, rot, sc, sc, w * 0.5, h * 0.5)
    end
  end

  love.graphics.setCanvas(prev_canvas)
  love.graphics.pop() -- Restore the previous camera transform
  love.graphics.setBlendMode(prev_blend, prev_alpha)
  love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function decal_baker.force_rebake()
  needs_full_rebake = true
end

function decal_baker.sync()
  if not player or not player.deco then return end

  local current_table = player.deco
  local current_count = #current_table

  if current_table ~= last_deco_table or needs_full_rebake then
    needs_full_rebake = false
    last_deco_table = current_table
    decal_baker.clear_all()
    if current_count > 0 then
      stamp_range(current_table, 1, current_count)
    end
    last_deco_count = current_count
  elseif current_count < last_deco_count then
    -- Decals removed -> wipe and re-render existing
    decal_baker.clear_all()
    if current_count > 0 then
      stamp_range(current_table, 1, current_count)
    end
    last_deco_count = current_count
  elseif current_count > last_deco_count then
    -- New decals appended -> stamp only the new slice
    stamp_range(current_table, last_deco_count + 1, current_count)
    last_deco_count = current_count
  end
end

function decal_baker.draw()
  if not player or not player.deco then return end

  decal_baker.sync()

  local cam_x = player.screenx or 0
  local col_min = math.floor((cam_x - 100) / CHUNK_WIDTH)
  local col_max = math.floor((cam_x + 1380) / CHUNK_WIDTH)

  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)

  -- Check if the engine has already translated the coordinate space.
  -- If (0, 0) transforms to (0, 0), the engine draws in screen coordinates,
  -- so we manually offset by cam_x. If it translates, draw at world x.
  local tx, _ = love.graphics.transformPoint(0, 0)
  local draw_offset_x = (math.abs(tx) < 0.001) and -cam_x or 0

  for col = col_min, col_max do
    local c = chunks[col]
    if c then
      love.graphics.draw(c, (col * CHUNK_WIDTH) + draw_offset_x, 0)
    end
  end

  love.graphics.setBlendMode(prev_blend, prev_alpha)
  love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)
end

function decal_baker.clean_excess()
  if not player or not player.deco then return end
  local max_decals = (player.option_maxDecals or 3) * 1000

  if #player.deco > max_decals then
    local excess = #player.deco - max_decals
    local removed = 0
    local kept = {}

    -- Keep immune decals and the newest non-immune decals
    for i = 1, #player.deco do
      local d = player.deco[i]
      if is_immune(d) or removed >= excess then
        kept[#kept + 1] = d
      else
        removed = removed + 1
      end
    end

    if removed > 0 then
      player.deco = kept
      decal_baker.force_rebake()
      decal_baker.sync()
    end
  end
end

-- Call this when the player clicks the broom
function decal_baker.on_broom_cleaned()
  decal_baker.force_rebake()
  decal_baker.sync()
end

function decal_baker.update(dt)
  clean_timer = clean_timer + (dt or 0)
  if clean_timer >= 2.0 then
    clean_timer = 0
    decal_baker.clean_excess()
  end
end

function decal_baker.init()
  chunks = {}
  last_deco_table = nil
  last_deco_count = 0
  dim_cache = {}
  needs_full_rebake = true

  -- Hook broomerButton so the canvas refreshes immediately when clicked
  if broomerButton and not broomer_hooked then
    local orig_broomerButton = broomerButton
    broomerButton = function(...)
      local res = orig_broomerButton(...)
      decal_baker.on_broom_cleaned()
      return res
    end
    broomer_hooked = true
  end

  print("[GCore] Decal Baker initialized")
end

-- ----------------------------------------------------------------------------
-- Self-Test & Live Benchmark
-- ----------------------------------------------------------------------------
function decal_baker.runBenchmark(count, passes)
  count = count or 30000000
  passes = passes or 5

  local orig_deco = player and player.deco
  local orig_canvas = love.graphics.getCanvas()
  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  local prev_r, prev_g, prev_b, prev_a = love.graphics.getColor()

  -- 1. Gather valid decal sprites
  local valid_names = {}
  if player and player.deco then
    for i = 1, #player.deco do
      local name = player.deco[i].name
      if name and _G[name] and _G[name].getWidth and not valid_names[name] then
        valid_names[#valid_names + 1] = name
        valid_names[name] = true
      end
    end
  end

  local fallbacks = { "kiaMask", "blood1", "blood2", "shell", "crater" }
  for _, name in ipairs(fallbacks) do
    if _G[name] and _G[name].getWidth and not valid_names[name] then
      valid_names[#valid_names + 1] = name
      valid_names[name] = true
    end
  end

  if #valid_names == 0 then
    if not _G["__bench_dummy_decal__"] then
      local img_data = love.image.newImageData(16, 16)
      img_data:mapPixel(function() return 0.8, 0.2, 0.2, 0.8 end)
      _G["__bench_dummy_decal__"] = love.graphics.newImage(img_data)
    end
    valid_names[1] = "__bench_dummy_decal__"
  end

  -- 2. Generate synthetic decals across the active viewport
  local sx = (player and player.screenx) or 0
  local test_decos = {}
  for i = 1, count do
    test_decos[i] = {
      name = valid_names[(i % #valid_names) + 1],
      x = sx - 100 + ((i * 79) % 1480),
      y = 30 + ((i * 43) % 660),
      rotation = ((i * 17) % 360) * (math.pi / 180),
      size = 6 + ((i * 11) % 12),
      imunity = 0
    }
  end

  local test_target = love.graphics.newCanvas(1280, 720)

  -- 3. Benchmark Vanilla: Draw calls & render time
  love.graphics.setCanvas(test_target)
  local calls_before_vanilla = love.graphics.getStats().drawcalls
  local t0 = love.timer.getTime()
  for p = 1, passes do
    love.graphics.clear(0, 0, 0, 0)
    for n = 1, count do
      local d = test_decos[n]
      local img = _G[d.name]
      if img then
        local sc = (d.size or 10) / 10
        local w, h = img:getWidth(), img:getHeight()
        love.graphics.draw(img, d.x - sx, d.y, d.rotation or 0, sc, sc, w * 0.5, h * 0.5)
      end
    end
  end
  local vanilla_draw_ms = ((love.timer.getTime() - t0) * 1000) / passes
  local vanilla_draw_calls = math.floor((love.graphics.getStats().drawcalls - calls_before_vanilla) / passes)

  -- 4. Benchmark Baker: Bake Time
  if not player then player = {} end
  player.deco = test_decos

  local t_bake0 = love.timer.getTime()
  decal_baker.force_rebake()
  decal_baker.sync()
  local bake_time_ms = (love.timer.getTime() - t_bake0) * 1000

  -- 5. Pixel Audit: Verify the canvas is actually holding painted pixels
  local active_col = math.floor((sx + 640) / CHUNK_WIDTH)
  local sampled_chunk = chunks[active_col] or chunks[0]
  local painted_samples = 0
  local total_samples = 0

  if sampled_chunk then
    local img_data = sampled_chunk:newImageData()
    -- Sample a grid of 900 points across the canvas
    for sample_x = 20, 1260, 42 do
      for sample_y = 20, 700, 24 do
        total_samples = total_samples + 1
        local _, _, _, a = img_data:getPixel(sample_x, sample_y)
        if a > 0.01 then
          painted_samples = painted_samples + 1
        end
      end
    end
  end
  local coverage_pct = total_samples > 0 and (painted_samples / total_samples * 100) or 0

  -- 6. Benchmark Baker: Draw calls & blit time
  local calls_before_baker = love.graphics.getStats().drawcalls
  local t1 = love.timer.getTime()
  for p = 1, passes do
    love.graphics.clear(0, 0, 0, 0)
    decal_baker.draw()
  end
  local baker_draw_ms = ((love.timer.getTime() - t1) * 1000) / passes
  local baker_draw_calls = math.floor((love.graphics.getStats().drawcalls - calls_before_baker) / passes)

  -- 7. Restore game state -- Comment this out if you want to keep the test decals after the benchmark just to see if the crazy metrics are real.
  player.deco = orig_deco
  decal_baker.clear_all()
  if orig_deco and #orig_deco > 0 then
    decal_baker.force_rebake()
    decal_baker.sync()
  end

  love.graphics.setCanvas(orig_canvas)
  love.graphics.setBlendMode(prev_blend, prev_alpha)
  love.graphics.setColor(prev_r, prev_g, prev_b, prev_a)

  local speedup = (baker_draw_ms > 0) and (vanilla_draw_ms / baker_draw_ms) or 0
  local msg = string.format(
    "[Decal Baker Benchmark] %d Decals | Calls: %d -> %d | Vanilla: %.3f ms | Baker: %.3f ms | Coverage: %.1f%% | Bake: %.3f ms",
    count, vanilla_draw_calls, baker_draw_calls, vanilla_draw_ms, baker_draw_ms, coverage_pct, bake_time_ms
  )
  print(msg)

  return baker_draw_ms, vanilla_draw_ms, speedup, bake_time_ms, count, coverage_pct, vanilla_draw_calls, baker_draw_calls
end

return decal_baker