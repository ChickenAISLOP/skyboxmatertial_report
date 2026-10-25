-- ============================================================================
-- sky_brightness.lua  -  scale sky brightness via the ENVIRONMENT, not the material
-- ============================================================================
--
-- REVISION 2. The material route does not work.
--
-- Revision 1 wrote params_b.x through Underlay:material("sky"):set_variable().
-- It reported success every time - no error, writes incremented, errors zero -
-- and changed nothing. Measured, not assumed:
--
--   14:09:29  captured original sky intensity 0.1500
--   14:09:29  sky intensity 0.1500 -> 0.0697   (x0.46)   <- reported as written
--   14:09:30  params_b reads back 0.1500                     <- unchanged
--
-- So mat:set_variable() is a silent no-op on this material. It raises nothing,
-- which is worse than an error, because it looks like success. The material
-- object returned by Underlay:material() is evidently not the live one the
-- renderer reads.
--
-- That also settles a report claim. The README had a "Writable: yes" column for
-- params_a/params_b/color0/color2. That came from variable_exists returning
-- true - a read-only call - restated as writability. The column has been
-- retracted and this revision is the replacement route.
--
-- WHAT WORKS INSTEAD
-- The environment exposes sky intensity as a data path:
--
--   underlay_effect/sky_top/sky_intensity
--   underlay_effect/sky_bottom/sky_intensity
--
-- and it is driven through the SAME call that drives rotation:
--
--   managers.viewport:first_active_viewport()._env_handler:editor_set_value(key, v)
--
-- Rotation through that call was verified in-game: 338 -> 68 -> read back 68 ->
-- 338, dome visibly rotating. So the convention here is measured, not guessed.
--
-- SAFETY
--   first_active_viewport()  proven by the rotation probe
--   _env_handler             proven by the rotation probe
--   has_data_path_key        proven by BeardLib-Editor, EnvironmentToolEditor.lua
--   get_value / editor_set_value   proven by the rotation probe
--
-- Nothing is written until a key has been confirmed present AND read successfully.
-- ============================================================================

_G.sky_brightness = _G.sky_brightness or {}
local B = _G.sky_brightness

if B._loaded then return end
B._loaded = true

-- Candidates in preference order, best description of "brightness" first.
--
-- The prefix matters: the same key is reachable under more than one data path.
-- DisableFog writes others/sun_ray_color, so legacy flat keys live under
-- others/. Tier 2/3 keys that BLE lists live under underlay_effect/. Rather
-- than guess, detect() reports every one of these with its support flag and
-- value, and only the first supported one is actually used.
--
-- Coverage from our own decode of all 225 environments:
--   sky_intensity                51 / 225  (Tier 2 and 3 only - absent on the
--                                        174 legacy Tier 1 environments)
--   sky_top_color_scale         225 / 225  <- universal
--   sky_bottom_color_scale      225 / 225  <- universal
--
-- That is why rev2 picked others/sun_ray_color_scale on modders_devmap: the
-- real intensity key simply is not there, and the fallback it found scales the
-- SUN RAYS, which is why nothing looked different.
B.PATHS = {
	"underlay_effect/sky_top/sky_intensity",
	"underlay_effect/sky_bottom/sky_intensity",
	"sky_top/sky_intensity",
	"sky_intensity",
	"sky_top_color_scale",
	"sky_bottom_color_scale",
	"others/sky_top_color_scale",
	"others/sky_bottom_color_scale",
	"others/global_color_sky_a",
	"others/global_color_sky_b",
}

-- Keys that scale the sky's own colour rather than its brightness directly.
-- They are flagged in detect() so a silent fallback is never mistaken for the
-- real thing.
B.FALLBACK_ONLY = {
	"others/sun_ray_color_scale",
	"others/global_color_sky_a",
	"others/global_color_sky_b",
}

B.enabled    = B.enabled == true
B.multiplier = B.multiplier or 1.0

B.key        = nil      -- the hashed key actually in use
B.path       = nil      -- its string form, for logs
B.base       = nil      -- value as the level had it
B.writes     = 0
B.errors     = 0
B.last_log   = 0        -- throttle, see note()

local function out(s)
	if log then log("[bright] " .. s) end
end

-- Slider drags fire this many times a second; logging each one produced 112
-- lines in one second. Throttle to one line per distinct value change, capped.
local _seen_log = {}
local function note(s)
	local key = s:gsub("%.%d+", "N")          -- collapse numbers so real
	if _seen_log[key] then return end          -- changes still get through
	_seen_log[key] = true
	local n = 0
	for _ in pairs(_seen_log) do n = n + 1 end
	if n > 40 then _seen_log = {} end          -- and never grow without bound
	out(s)
	local f = io.open(SavePath .. "sky_brightness.log", "a")
	if f then f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. s .. "\n"); f:close() end
end

-- ---------------------------------------------------------------------------
-- key selection
-- ---------------------------------------------------------------------------

local function env_handler()
	if not (managers and managers.viewport) then return nil end
	local ok, vp = pcall(function() return managers.viewport:first_active_viewport() end)
	if not ok or not vp then return nil end
	local g, h = pcall(function() return vp._env_handler end)
	if not g or not h then return nil end
	if type(h.editor_set_value) ~= "function" then return nil end
	return h
end

-- Pick the first candidate this environment actually supports, and cache it.
function B.resolve()
	if B.key then return B.key end

	local mgr = managers and managers.viewport
	local h = env_handler()
	if not h then return nil, "no viewport _env_handler" end

	for _, p in ipairs(B.PATHS) do
		local k = Idstring(p):key()
		if mgr and type(mgr.has_data_path_key) == "function" then
			local ok, has = pcall(function() return mgr:has_data_path_key(k) end)
			if ok and has == true then
				B.key, B.path = k, p
				return k
			end
		else
			-- has_data_path_key unavailable: accept the first key that reads
			local g, v = pcall(function() return h:get_value(k) end)
			if g and type(v) == "number" then
				B.key, B.path = k, p
				return k
			end
		end
	end
	return nil, "no candidate data path is supported here"
end

-- ---------------------------------------------------------------------------
-- detection report - read-only
-- ---------------------------------------------------------------------------

function B.detect()
	local rows = {}
	-- second arg optional: a heading line with no value should not print "nil"
	local function add(k, v)
		if v == nil then
			rows[#rows + 1] = k
		else
			rows[#rows + 1] = string.format("%-42s %s", k, tostring(v))
		end
	end

	add("level", Global and Global.level_data and Global.level_data.level_id or "<none>")
	add("module_loaded", tostring(_G.sky_brightness ~= nil))
	add("material route", "mat:set_variable is a SILENT NO-OP - proven rev1")

	-- what the material route can still read, for reference
	local okmat, mat = pcall(function() return Underlay and Underlay:material(Idstring("sky")) end)
	if okmat and mat then
		for _, v in ipairs({ "params_a", "params_b", "color0", "color2" }) do
			local g, ex = pcall(function() return mat:variable_exists(Idstring(v)) end)
			if g and ex then
				local g2, val = pcall(function() return mat:get_variable(Idstring(v)) end)
				local x, y, z = 0, 0, 0
				if g2 then pcall(function() x, y, z = val.x, val.y, val.z end) end
				add("  material " .. v, g2 and string.format("%.4f, %.4f, %.4f", tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0) or "unreadable")
			else
				add("  material " .. v, "not set")
			end
		end
	else
		add("sky_material", "not found")
	end

	add("")
	add("--- environment data paths ---")
	local h = env_handler()
	add("env_handler", h and "present" or "MISSING")

	local mgr = managers and managers.viewport
	local supported = {}
	for _, p in ipairs(B.PATHS) do
		local k = Idstring(p):key()
		local sup = "?"
		if mgr and type(mgr.has_data_path_key) == "function" then
			local ok, has = pcall(function() return mgr:has_data_path_key(k) end)
			sup = not ok and ("raised - " .. tostring(has))
				or (has == true and "YES" or (has == false and "no (false)" or "nil (absent)"))
		end
		local val = ""
		if h and sup == "YES" then
			local g, v = pcall(function() return h:get_value(k) end)
			val = g and (type(v) == "number" and string.format("value = %.4f", v)
				or ("value = " .. tostring(v))) or ("read raised")
		end
		if sup == "YES" then supported[#supported + 1] = p end
		add(p, sup .. (val ~= "" and ("   " .. val) or ""))
	end

	add("")
	local k, err = B.resolve()
	if k then
		local kind = "REAL brightness control"
		for _, f in ipairs(B.FALLBACK_ONLY) do if B.path == f then kind = "FALLBACK - not sky brightness" end end
		add("CHOSEN", B.path .. "   [" .. kind .. "]")
		add("  hashed key", tostring(B.key))
	else
		add("CHOSEN", "none - " .. tostring(err))
	end
	add("base value", B.base and string.format("%.4f", B.base) or "not captured yet")
	add("supported here", #supported .. " of " .. #B.PATHS)
	if #supported > 0 then add("  list", table.concat(supported, "  ")) end
	add("enabled", tostring(B.enabled))
	add("multiplier", string.format("%.2f", B.multiplier))
	add("writes", B.writes)
	add("errors", B.errors)

	local body = table.concat(rows, "\n")
	local line = "[bright] detection\n[bright] " .. (body:gsub("\n", "\n[bright] "))
	out(line)

	local rf = io.open(SavePath .. "brightness_report.txt", "w")
	if rf then rf:write("=== brightness detection ===\n" .. body .. "\n"); rf:close() end

	return body
end

-- ---------------------------------------------------------------------------
-- the write
-- ---------------------------------------------------------------------------

function B.apply()
	local h = env_handler()
	if not h then
		note("apply refused: no viewport _env_handler")
		return false
	end

	local k, err = B.resolve()
	if not k then
		note("apply refused: " .. tostring(err))
		return false
	end

	if B.base == nil then
		local g, v = pcall(function() return h:get_value(k) end)
		if not g or type(v) ~= "number" then
			note("apply refused: could not read " .. B.path .. " (" .. tostring(v) .. ")")
			return false
		end
		B.base = v
		note(string.format("captured base %.4f from %s", v, B.path))
	end

	local target = B.base * B.multiplier
	local ok, e = pcall(function() return h:editor_set_value(k, target) end)
	if not ok then
		B.errors = B.errors + 1
		note(string.format("editor_set_value error #%d: %s", B.errors, tostring(e)))
		return false
	end

	-- Read back. The material route taught us that "no error" does not mean
	-- "written", so this is verified rather than assumed.
	local g, v = pcall(function() return h:get_value(k) end)
	if g and type(v) == "number" and math.abs(v - target) < 0.0001 then
		B.writes = B.writes + 1
		note(string.format("%s %.4f -> %.4f (x%.2f) CONFIRMED", B.path, B.base, target, B.multiplier))
		return true
	end

	B.errors = B.errors + 1
	note(string.format("write did not stick: wanted %.4f, read %s", target, g and tostring(v) or ("raised - " .. tostring(v))))
	return false
end

-- ---------------------------------------------------------------------------
-- control
-- ---------------------------------------------------------------------------

function B.restore()
	local h = env_handler()
	B.enabled = false
	if not h or not B.key or B.base == nil then return false end
	local ok = pcall(function() return h:editor_set_value(B.key, B.base) end)
	local g, v = pcall(function() return h:get_value(B.key) end)
	local good = ok and g and type(v) == "number" and math.abs(v - B.base) < 0.0001
	note(good and string.format("restored to %.4f", B.base) or "restore did not verify")
	B.base = nil
	return good
end

function B.set_enabled(on)
	B.enabled = on == true
	if B.enabled then B.apply() else B.restore() end
end

function B.set_multiplier(m)
	local v = tonumber(m)
	if not v then return end
	if v < 0 then v = 0 end
	if v > 4 then v = 4 end
	B.multiplier = v
	if B.enabled then B.apply() end
end

function B.status()
	return string.format("enabled=%s multiplier=%.2f path=%s base=%s writes=%d errors=%d",
		tostring(B.enabled), B.multiplier, tostring(B.path),
		B.base and string.format("%.4f", B.base) or "n/a", B.writes, B.errors)
end

Hooks:Add("LevelLoaded", "skybox_animated_brightness_level", function()
	B.key, B.path, B.base = nil, nil, nil
	B.writes, B.errors = 0, 0
end)

note("loaded rev2 - environment route. Material set_variable is a no-op.")