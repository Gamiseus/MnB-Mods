-- perfkit_atlas.lua
-- An automatic texture atlas.
--
-- The game keeps every sprite in its own texture, so nearly every draw is its own GPU
-- call. Here the small sprites are copied side by side onto a few large textures (pages),
-- and love.graphics.draw is wrapped: a draw of a packed sprite becomes a draw of its
-- rectangle on a page. Draws that follow one another from the same page are then merged
-- by LÖVE into one GPU call.
--
-- The game and other mods keep using the original images; nothing else changes. Sprites
-- that are not packed (large ones, ones loaded later) are drawn as before.
--
-- Whether this helps depends on how often text, shaders or unpacked sprites come between
-- two packed ones. Turn it on, then compare the draw calls in the overlay (F11) or run the
-- profiler with it on and off.

local Atlas = {}

-- Sprites larger than this on either side stay out.
Atlas.MAX_SPRITE = 256
-- Page size; lowered to what the graphics card allows.
Atlas.PAGE_SIZE = 4096
Atlas.MAX_PAGES = 6
-- Pixels of the sprite's own edge repeated around it, so a rotated or scaled sprite never
-- picks up its neighbour.
Atlas.PADDING = 1

local map = {}          -- image -> { tex = page canvas, quad = Quad, kx, ky = shown size over pixels }
local pages = {}
local packed = 0
local built = false
local enabled = false
local shaderOn = false
local origDraw, origSetShader, wrapper, shaderWrapper

local function isImage(v)
  return type(v) == "userdata" and type(v.typeOf) == "function" and v:typeOf("Image")
end

-- The real pixel size and the display scale of an image. QuarterMaster may show an image
-- at another size than its pixels; then getWidth() reports the displayed size.
local function rawInfo(img)
  local sprites = QM and QM.Sprites
  if sprites and sprites.rawSize then
    local w, h = sprites.rawSize(img)
    local kx, ky = sprites.scaleOf(img)
    return w, h, kx or 1, ky or kx or 1
  end
  return img:getWidth(), img:getHeight(), 1, 1
end

local function collect()
  local list, seen = {}, {}
  for name, v in pairs(_G) do
    if isImage(v) and not seen[v] then
      seen[v] = true
      local w, h, kx, ky = rawInfo(v)
      if w <= Atlas.MAX_SPRITE and h <= Atlas.MAX_SPRITE and w > 0 and h > 0 then
        list[#list + 1] = { img = v, w = w, h = h, kx = kx, ky = ky, name = tostring(name) }
      end
    end
  end
  -- Tallest first, then by name so the layout is the same every run.
  table.sort(list, function(a, b)
    if a.h ~= b.h then return a.h > b.h end
    return a.name < b.name
  end)
  return list
end

-- Shelf packing: rows of sprites, each row as tall as its first (tallest) sprite.
local function layout(list, size)
  local pad = Atlas.PADDING
  local page, x, y, rowH = 1, 0, 0, 0
  local placed = 0
  for i = 1, #list do
    local s = list[i]
    local w, h = s.w + 2 * pad, s.h + 2 * pad
    if x + w > size then
      x, y, rowH = 0, y + rowH, 0
    end
    if y + h > size then
      page, x, y, rowH = page + 1, 0, 0, 0
    end
    if page > Atlas.MAX_PAGES then break end
    s.page, s.x, s.y = page, x + pad, y + pad
    x = x + w
    if h > rowH then rowH = h end
    placed = i
  end
  return placed, math.min(page, Atlas.MAX_PAGES)
end

local function render(list, placed, npages, size)
  local g = love.graphics
  local prevCanvas = g.getCanvas()
  local prevShader = g.getShader()
  local pr, pg, pb, pa = g.getColor()
  local pBlend, pAlpha = g.getBlendMode()
  local sx0, sy0, sw0, sh0 = g.getScissor()
  g.push()
  g.origin()
  g.setShader()
  g.setColor(1, 1, 1, 1)
  -- Copy pixels as they are: no blending and no alpha multiplication, so a page holds
  -- the same colour values as the images and is drawn exactly like them.
  g.setBlendMode("replace", "premultiplied")

  local draw = origDraw or g.draw
  local pad = Atlas.PADDING
  for p = 1, npages do
    local canvas = g.newCanvas(size, size)
    pages[p] = canvas
    g.setCanvas(canvas)
    g.setScissor()
    g.clear(0, 0, 0, 0)
    for i = 1, placed do
      local s = list[i]
      if s.page == p then
        g.setScissor(s.x - pad, s.y - pad, s.w + 2 * pad, s.h + 2 * pad)
        -- Shifted copies fill the padding with the sprite's edge pixels; the last copy,
        -- unshifted, is the sprite itself.
        for dy = -pad, pad do
          for dx = -pad, pad do
            if dx ~= 0 or dy ~= 0 then draw(s.img, s.x + dx, s.y + dy) end
          end
        end
        draw(s.img, s.x, s.y)
        map[s.img] = { tex = canvas, quad = g.newQuad(s.x, s.y, s.w, s.h, size, size), kx = s.kx, ky = s.ky }
      end
    end
  end

  g.setScissor()
  g.setCanvas(prevCanvas)
  g.pop()
  g.setShader(prevShader)
  g.setBlendMode(pBlend, pAlpha)
  g.setColor(pr, pg, pb, pa)
  if sx0 then g.setScissor(sx0, sy0, sw0, sh0) end
end

--- Throws the pages away. The next frame with the atlas on builds them again.
function Atlas.reset()
  for k in pairs(map) do map[k] = nil end
  for i, c in ipairs(pages) do
    if c.release then c:release() end
    pages[i] = nil
  end
  packed = 0
  built = false
end

--- Builds the pages from every small image the game holds in a global.
function Atlas.build()
  Atlas.reset()
  local limit = love.graphics.getSystemLimits().texturesize or Atlas.PAGE_SIZE
  local size = math.min(Atlas.PAGE_SIZE, limit)
  local list = collect()
  local placed, npages = layout(list, size)
  if placed > 0 then render(list, placed, npages, size) end
  packed = placed
  built = true
  print(string.format("[PerfKit] Atlas: %d of %d small sprites on %d page(s) of %d px (%.0f MB)",
    placed, #list, #pages, size, #pages * size * size * 4 / 1048576))
  return placed
end

-- love.graphics.draw(image, x, y, r, sx, sy, ox, oy, kx, ky) for a packed image.
local function drawWrapped(a, x, y, r, sx, sy, ox, oy, kx, ky)
  if enabled and not shaderOn then
    local e = map[a]
    -- Only the plain form; draws with a Quad or a Transform pass through.
    if e and type(x) ~= "userdata" then
      local ex, ey = e.kx, e.ky
      if ex ~= 1 or ey ~= 1 then
        -- QuarterMaster shows this image at another size than its pixels: scale the page
        -- rectangle the same way, and give the origin in the image's own pixels.
        sx = sx or 1
        sy = (sy or sx) * ey
        sx = sx * ex
        return origDraw(e.tex, e.quad, x or 0, y or 0, r or 0, sx, sy, (ox or 0) / ex, (oy or 0) / ey, kx, ky)
      end
      if sx == nil then
        return origDraw(e.tex, e.quad, x, y, r)
      end
      return origDraw(e.tex, e.quad, x, y, r, sx, sy, ox, oy, kx, ky)
    end
  end
  return origDraw(a, x, y, r, sx, sy, ox, oy, kx, ky)
end

local function install()
  if wrapper then return end
  origDraw = love.graphics.draw
  origSetShader = love.graphics.setShader
  wrapper = function(a, x, y, r, sx, sy, ox, oy, kx, ky)
    -- A draw with fewer arguments must stay one: LÖVE tells its forms apart by count.
    if x == nil then return origDraw(a) end
    return drawWrapped(a, x, y, r, sx, sy, ox, oy, kx, ky)
  end
  -- A shader may read texture coordinates, which differ on a page: leave those draws alone.
  shaderWrapper = function(s, ...)
    shaderOn = s ~= nil
    return origSetShader(s, ...)
  end
  love.graphics.draw = wrapper
  love.graphics.setShader = shaderWrapper
end

--- Turns the atlas on or off. Called every frame with the setting; the first frame with
--- it on builds the pages.
function Atlas.setEnabled(on)
  on = on and true or false
  if on and not built then
    install()
    shaderOn = love.graphics.getShader() ~= nil
    Atlas.build()
  elseif not on and built then
    Atlas.reset()
  end
  enabled = on and packed > 0
end

function Atlas.stats()
  return { enabled = enabled, sprites = packed, pages = #pages }
end

Atlas._map = map       -- for tests
Atlas._layout = layout -- for tests

return Atlas
