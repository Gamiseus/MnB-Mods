local pairs, ipairs, tostring, type, concat, dump, floor, format = pairs, ipairs, tostring, type, table.concat, string.dump, math.floor, string.format

-- Pure visual/UI effects that are safe to discard without affecting gameplay or map terrain
local ALWAYS_TRANSIENT_KEYS = {
	particles = true,
	topParticles = true,
	rainParticles = true,
	explosions = true,
	damageCue = true,
	bubbleCue = true,
	tipCue = true,
	iconCue = true,
	uiCue = true,
	textCue = true,
	xpBubble = true,
	clouds = true,
	bubbles = true,
	fluffBalls = true
}

-- Substrings in deco names that represent combat litter (casings, blood) rather than map cover (dirt, mud, trenches)
local DECAL_BLOAT_PATTERNS = {
	"casing",
	"shell",
	"blood",
	"splat",
	"gore"
}

local function is_combat_decal(name)
	if type(name) ~= "string" then return false end
	local lower = name:lower()
	for _, pat in ipairs(DECAL_BLOAT_PATTERNS) do
		if lower:find(pat, 1, true) then
			return true
		end
	end
	return false
end

local function getchr(c)
	return "\\" .. c:byte()
end

local function make_safe(text)
	return ("%q"):format(text):gsub('\n', 'n'):gsub("[\128-\255]", getchr)
end

local oddvals = {[tostring(1/0)] = '1/0', [tostring(-1/0)] = '-1/0', [tostring(-(0/0))] = '-(0/0)', [tostring(0/0)] = '0/0'}
local function write(t, memo, rev_memo)
	local ty = type(t)
	if ty == 'number' then
		t = format("%.17g", t)
		return oddvals[t] or t
	elseif ty == 'boolean' or ty == 'nil' then
		return tostring(t)
	elseif ty == 'string' then
		return make_safe(t)
	elseif ty == 'table' or ty == 'function' then
		if not memo[t] then
			local index = #rev_memo + 1
			memo[t] = index
			rev_memo[index] = t
		end
		return '_[' .. memo[t] .. ']'
	else
		error("Trying to serialize unsupported type " .. ty)
	end
end

local kw = {['and'] = true, ['break'] = true, ['do'] = true, ['else'] = true,
	['elseif'] = true, ['end'] = true, ['false'] = true, ['for'] = true,
	['function'] = true, ['goto'] = true, ['if'] = true, ['in'] = true,
	['local'] = true, ['nil'] = true, ['not'] = true, ['or'] = true,
	['repeat'] = true, ['return'] = true, ['then'] = true, ['true'] = true,
	['until'] = true, ['while'] = true}

local function write_key_value_pair(k, v, memo, rev_memo, name)
	if type(k) == 'string' and k:match '^[_%a][_%w]*$' and not kw[k] then
		return (name and name .. '.' or '') .. k ..'=' .. write(v, memo, rev_memo)
	else
		return (name or '') .. '[' .. write(k, memo, rev_memo) .. ']=' .. write(v, memo, rev_memo)
	end
end

local function is_cyclic(memo, sub, super)
	local m = memo[sub]
	local p = memo[super]
	return m and p and m < p
end

local function write_table_ex(t, memo, rev_memo, srefs, name)
	if type(t) == 'function' then
		return '_[' .. name .. ']=loadstring' .. make_safe(dump(t))
	end
	local m = {}
	local mi = 1
	for i = 1, #t do
		local v = t[i]
		if v == t or is_cyclic(memo, v, t) then
			srefs[#srefs + 1] = {name, i, v}
			m[mi] = 'nil'
			mi = mi + 1
		else
			m[mi] = write(v, memo, rev_memo)
			mi = mi + 1
		end
	end

	local is_player_root = (name == 0) and (t.mnb2Experience ~= nil or t.experience ~= nil or t.gameType ~= nil or t.gameState ~= nil)

	for k,v in pairs(t) do
		if type(k) ~= 'number' or floor(k) ~= k or k < 1 or k > #t then
			-- 1. Strip visual-only tables (particles, floating text)
			if is_player_root and type(k) == 'string' and type(v) == 'table' and ALWAYS_TRANSIENT_KEYS[k] then
				m[mi] = (k:match '^[_%a][_%w]*$' and not kw[k]) and (k .. '={}') or ('[' .. write(k, memo, rev_memo) .. ']={}')
				mi = mi + 1

			-- 2. Clean combat decals (blood/casings) from deco while preserving all map terrain (mud, dirt, trenches)
			elseif is_player_root and k == "deco" and type(v) == "table" then
				local clean_deco = {}
				for _, item in ipairs(v) do
					if type(item) == "table" and not is_combat_decal(item.name) then
						clean_deco[#clean_deco + 1] = item
					end
				end
				m[mi] = write_key_value_pair(k, clean_deco, memo, rev_memo)
				mi = mi + 1

			elseif v == t or k == t or is_cyclic(memo, v, t) or is_cyclic(memo, k, t) then
				srefs[#srefs + 1] = {name, k, v}
			else
				m[mi] = write_key_value_pair(k, v, memo, rev_memo)
				mi = mi + 1
			end
		end
	end
	return '_[' .. name .. ']={' .. concat(m, ',') .. '}'
end

return function(t)
	local memo = {[t] = 0}
	local rev_memo = {[0] = t}
	local srefs = {}
	local result = {}

	-- 1: recursively descend the table structure
	local n = 0
	while rev_memo[n] do
		result[n + 1] = write_table_ex(rev_memo[n], memo, rev_memo, srefs, n)
		n = n + 1
	end

	-- 2: reverse order
	for i = 1, n*.5 do
		local j = n - i + 1
		result[i], result[j] = result[j], result[i]
	end

	-- 3: add all cyclic references
	for i, v in ipairs(srefs) do
		n = n + 1
		result[n] = write_key_value_pair(v[2], v[3], memo, rev_memo, '_[' .. v[1] .. ']')
	end

	-- 4: return main table
	if result[n]:sub(1, 5) == '_[0]=' then
		result[n] = 'return ' .. result[n]:sub(6)
	else
		result[n + 1] = 'return _[0]'
	end

	-- 5: concatenate
	result = concat(result, '\n')
	return n > 1 and 'local _={}\n' .. result or result
end