-- ============================================================================
-- decal_baker.lua - High Performance Decal Canvas Baking & Cleanup System
-- Part of GCore Mod for Mud and Blood (LÖVE 11.4)
-- ============================================================================

local decal_baker = {}

local CHUNK_WIDTH = 1280
local CHUNK_HEIGHT = 720

local chunks = {}               -- col -> Canvas
local last_deco_table = nil     -- identity check
local last_deco_count = 0       -- count of stamped decals
local dim_cache = {}            -- Image -> {w, h}
local clean_timer = 0           -- periodic check timer

local PROTECTED_DECO_NAMES = {
  trench = true,
  deepCrater = true,
  dropZone = true,
  mortarPit = true,
  shellScrape = true,
  defensivePosition = true,
  pillBox = true,
  trapDoor_open = true,
  trapDoor_closed = true,
}

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
  for col, c in pairs(chunks) do
    if c then
      local prev_canvas = love.graphics.getCanvas()
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setCanvas(prev_canvas)
    end
  end
  last_deco_count = 0
end

local function stamp_range(decal_list, start_idx, end_idx)
  if not decal_list or start_idx > end_idx then return end

  -- Group decals by chunk column
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
          b[#b + 1] = { d = d, img = img, w = w, h = h, scale = scale }
        end
      end
    end
  end

  local prev_canvas = love.graphics.getCanvas()
  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  love.graphics.setColor(1, 1, 1, 1)

  for col, items in pairs(batches) do
    local c = get_or_create_chunk(col)
    love.graphics.setCanvas(c)
    local ox = col * CHUNK_WIDTH
    for j = 1, #items do
      local item = items[j]
      local d = item.d
      local lx = d.x - ox
      local ly = d.y
      local rot = d.rotation or 0
      local sc = item.scale
      love.graphics.draw(item.img, lx, ly, rot, sc, sc, item.w * 0.5, item.h * 0.5)
    end
  end

  love.graphics.setCanvas(prev_canvas)
  love.graphics.setBlendMode(prev_blend, prev_alpha)
end

function decal_baker.sync()
  if not player or not player.deco then return end

  local current_table = player.deco
  local current_count = #current_table

  if current_table ~= last_deco_table then
    -- Table reference changed (new game, save loaded, mapReset)
    last_deco_table = current_table
    decal_baker.clear_all()
    if current_count > 0 then
      stamp_range(current_table, 1, current_count)
    end
    last_deco_count = current_count
  elseif current_count < last_deco_count then
    -- Decals were removed (broom cleaner, limit trim) -> rebake
    decal_baker.clear_all()
    if current_count > 0 then
      stamp_range(current_table, 1, current_count)
    end
    last_deco_count = current_count
  elseif current_count > last_deco_count then
    -- New decals added -> stamp incrementally
    stamp_range(current_table, last_deco_count + 1, current_count)
    last_deco_count = current_count
  end
end

function decal_baker.draw()
  if not player or not player.deco then return end

  -- Synchronize canvas with current player.deco state
  decal_baker.sync()

  local cam_x = player.screenx or 0
  local col_min = math.floor((cam_x - 100) / CHUNK_WIDTH)
  local col_max = math.floor((cam_x + 1380) / CHUNK_WIDTH)

  local prev_blend, prev_alpha = love.graphics.getBlendMode()
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)

  for col = col_min, col_max do
    local c = chunks[col]
    if c then
      love.graphics.draw(c, col * CHUNK_WIDTH, 0)
    end
  end

  love.graphics.setBlendMode(prev_blend, prev_alpha)
end

function decal_baker.clean_excess()
  if not player or not player.deco then return end
  local max_decals = (player.option_maxDecals or 3) * 1000
  if #player.deco > max_decals then
    local excess = #player.deco - max_decals
    local removed = 0
    local i = 1
    while i <= #player.deco and removed < excess do
      local d = player.deco[i]
      if d and d.imunity ~= 1 and not PROTECTED_DECO_NAMES[d.name] then
        if deleteRelatedCover and d.cheeseID then
          deleteRelatedCover(d.cheeseID)
        end
        table.remove(player.deco, i)
        removed = removed + 1
      else
        i = i + 1
      end
    end
    if removed > 0 then
      decal_baker.sync()
    end
  end
end

function decal_baker.on_broom_cleaned()
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
  print("[GCore] Decal Baker initialized (Chunked Canvas Rendering & Auto-Trimming)")
end

return decal_baker
