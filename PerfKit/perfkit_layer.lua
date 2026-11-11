-- perfkit_layer.lua
-- A baked layer: static sprites are drawn once into canvases ("chunks") that tile the map
-- from left to right, and the chunks are drawn each frame instead of the sprites.
--
-- Used by the decal baker and the settled-debris baker. Neither knows about canvases; they
-- hand the layer a list of items and a function that describes how to draw one.

local floor, max, abs = math.floor, math.max, math.abs

local Layer = {}
Layer.__index = Layer

-- Chunk size. The map is 720 high; the margin keeps sprites that hang over the top or the
-- bottom edge whole.
Layer.CHUNK_W = 1280
Layer.MARGIN_Y = 128
Layer.CHUNK_H = 720 + 2 * Layer.MARGIN_Y

function Layer.new()
  return setmetatable({ chunks = {}, buckets = {}, used = {} }, Layer)
end

--- The chunk columns a sprite touches. `reach` is how far it extends from (x, y).
function Layer.columns(x, reach)
  return floor((x - reach) / Layer.CHUNK_W), floor((x + reach) / Layer.CHUNK_W)
end

--- How far a sprite can reach from its position, whatever its rotation and origin.
function Layer.reach(w, h, sx, sy, ox, oy)
  local rx = max(abs(ox), abs(w - ox)) * abs(sx)
  local ry = max(abs(oy), abs(h - oy)) * abs(sy)
  return math.sqrt(rx * rx + ry * ry) + 1
end

function Layer:chunk(col)
  local c = self.chunks[col]
  if not c then
    c = love.graphics.newCanvas(Layer.CHUNK_W, Layer.CHUNK_H)
    self.chunks[col] = c
  end
  return c
end

function Layer:clear(col)
  local c = self.chunks[col]
  if not c then return end
  local prev = love.graphics.getCanvas()
  love.graphics.setCanvas(c)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setCanvas(prev)
end

--- Drops every canvas. The next bake creates the ones it needs.
function Layer:reset()
  for col, c in pairs(self.chunks) do
    if c.release then c:release() end
    self.chunks[col] = nil
  end
end

--- Draws items[first..last] into the chunks they touch.
-- describe(item) returns: image, x, y, rotation, sx, sy, ox, oy, alpha (0..1)
-- or nil to skip the item. With `only`, a table of columns, other chunks are left alone.
-- Returns the number of items drawn.
function Layer:bake(items, first, last, describe, only)
  if last < first then return 0 end
  local buckets, used = self.buckets, self.used
  local nused = 0

  -- Pass 1: sort item indexes by chunk, so each canvas is bound once.
  for i = first, last do
    local img, x, _, _, sx, sy, ox, oy = describe(items[i])
    if img then
      local w, h = img:getDimensions()
      local c0, c1 = Layer.columns(x, Layer.reach(w, h, sx, sy, ox, oy))
      for col = c0, c1 do
        if not only or only[col] then
          local b = buckets[col]
          if not b then
            b = { n = 0 }
            buckets[col] = b
          end
          if b.n == 0 then
            nused = nused + 1
            used[nused] = col
          end
          b.n = b.n + 1
          b[b.n] = i
        end
      end
    end
  end
  if nused == 0 then return 0 end

  -- Pass 2: draw. Every piece of graphics state touched is put back afterwards.
  local g = love.graphics
  local prevCanvas = g.getCanvas()
  local prevShader = g.getShader()
  local pr, pg, pb, pa = g.getColor()
  local pBlend, pAlphaMode = g.getBlendMode()
  local sx0, sy0, sw0, sh0 = g.getScissor()
  g.push()
  g.origin()
  g.setScissor()
  g.setShader()
  g.setBlendMode("alpha")

  local drawn = 0
  local lastAlpha = -1
  for u = 1, nused do
    local col = used[u]
    local b = buckets[col]
    g.setCanvas(self:chunk(col))
    local offx = col * Layer.CHUNK_W
    for j = 1, b.n do
      local img, x, y, r, sx, sy, ox, oy, a = describe(items[b[j]])
      if img then
        a = a or 1
        if a ~= lastAlpha then
          g.setColor(1, 1, 1, a)
          lastAlpha = a
        end
        g.draw(img, x - offx, y + Layer.MARGIN_Y, r, sx, sy, ox, oy)
        drawn = drawn + 1
      end
      b[j] = nil
    end
    b.n = 0
    used[u] = nil
  end

  g.setCanvas(prevCanvas)
  g.pop()
  g.setShader(prevShader)
  g.setBlendMode(pBlend, pAlphaMode)
  g.setColor(pr, pg, pb, pa)
  if sx0 then g.setScissor(sx0, sy0, sw0, sh0) end
  return drawn
end

--- Draws the chunks in view. Call it where the game draws in map coordinates.
function Layer:draw(camX)
  local g = love.graphics
  local c0 = floor(camX / Layer.CHUNK_W)
  local c1 = floor((camX + 1280) / Layer.CHUNK_W)
  local pr, pg, pb, pa = g.getColor()
  local pBlend, pAlphaMode = g.getBlendMode()
  -- A canvas holds premultiplied colour.
  g.setBlendMode("alpha", "premultiplied")
  g.setColor(1, 1, 1, 1)
  for col = c0, c1 do
    local c = self.chunks[col]
    if c then
      g.draw(c, col * Layer.CHUNK_W, -Layer.MARGIN_Y)
    end
  end
  g.setBlendMode(pBlend, pAlphaMode)
  g.setColor(pr, pg, pb, pa)
end

return Layer
