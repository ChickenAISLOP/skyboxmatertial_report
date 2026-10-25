-- ============================================================================
-- env_swap_test.lua  rev4  -  does an environment swap actually change the sky?
-- ============================================================================
--
-- WHY REV3
-- rev1 proved _set_environment is callable but changed nothing visible: all six
-- candidates returned DB:has=false, so it fell through to core/environments/
-- default, which was probably already active. It also captured no original, so
-- the revert never armed.
--
-- rev2 fixed the paths (environments/<dir>/<name>, all verified YES) and added
-- the raw-field dump. That dump answered the revert question:
--
--     managers.worlddefinition._environment = { sky_rot = 53 }
--
-- _environment holds environment MODIFIER values, not the environment name. The
-- level's own environment path is not readable from Lua through worlddefinition,
-- so there is no way to capture the original that way.
--
-- BUT managers.viewport exposes what we actually need:
--
--     game_default_environment   -> self._env_manager.game_default_environment
--     default_environment_path   -> a path
--     set_override_environment   -> (environment_path, blend_duration, ...)
--
-- game_default_environment is a guaranteed-valid restore target. That replaces
-- the impossible "capture the original" with "restore to the game default", which
-- is safe and needs no guessing.
--
-- set_override_environment also takes a blend duration, which _set_environment
-- does not - so it can cross-fade rather than snap.
--
-- SAFETY
-- No installed mod calls set_override_environment, so rev3 probes it under pcall
-- and tries each known argument shape, reporting which one worked. It refuses to
-- run at all unless a restore target has been confirmed to exist in the DB.
-- ============================================================================

_G.env_swap = _G.env_swap or {}
local E = _G.env_swap

if E._loaded then return end
E._loaded = true

E.REPORT_FILE = "env_swap_report.txt"
E.BLEND_SECONDS = 2.0

-- Real environment paths from the decoded export. Full DB form:
-- environments/<dir>/<name>, matching the on-disk <name>.environment layout.
-- Ordered so the first available one is maximally different from a night sky.
E.CANDIDATES = {
	"environments/env_0200_night_moon_stars/env_0200_night_moon_stars",
	"environments/env_1930_sunset_heavy_clouds/env_1930_sunset_heavy_clouds",
	"environments/env_2003_dusk_blue/env_2003_dusk_blue",
	"environments/env_1945_sunset/env_1945_sunset",
	"core/environments/default",
}

local function out(s) if log then log("[env_swap] " .. s) end end

-- Safe scheduling. DelayManager is nil in this build and indexing it crashed the
-- game during the rotation probe. DelayedCalls is what lua/settings/menu.lua uses,
-- and it takes SECONDS.
local _delay_seq = 0
local function later(seconds, fn)
	local ok = false
	if type(DelayedCalls) == "table" and type(DelayedCalls.Add) == "function" then
		_delay_seq = _delay_seq + 1
		ok = pcall(DelayedCalls.Add, DelayedCalls, "env_swap_" .. _delay_seq, seconds, fn)
	end
	if not ok and managers and type(managers.delayed_call) == "function" then
		ok = pcall(managers.delayed_call, managers, fn, seconds)
	end
	if not ok and managers and type(managers.add_delayed_callback) == "function" then
		_delay_seq = _delay_seq + 1
		ok = pcall(managers.add_delayed_callback, managers, "env_swap_" .. _delay_seq, fn, seconds)
	end
	if not ok then fn() end
end

local function write_report(lines)
	local body = table.concat(lines, "\n")
	out(body:gsub("\n", "\n[env_swap] "))
	local f = io.open(SavePath .. E.REPORT_FILE, "w")
	if f then f:write(body .. "\n"); f:close() end
	return body
end

-- ---------------------------------------------------------------------------
-- sky material snapshot - the direct measurement
-- ---------------------------------------------------------------------------

function E.snapshot()
	if not (Underlay and type(Underlay.loaded) == "function" and Underlay:loaded()) then
		return nil, "Underlay not loaded"
	end
	local ok, mat = pcall(function() return Underlay:material(Idstring("sky")) end)
	if not ok or not mat then return nil, "no sky material" end

	local snap = {}
	for _, k in ipairs({ "params_a", "params_b", "color0", "color1", "color2" }) do
		local g1, ex = pcall(function() return mat:variable_exists(Idstring(k)) end)
		if g1 and ex then
			local g2, v = pcall(function() return mat:get_variable(Idstring(k)) end)
			if g2 then
				local vx, vy, vz = nil, nil, nil
				pcall(function() vx, vy, vz = v.x, v.y, v.z end)
				snap[k] = string.format("%.4f,%.4f,%.4f", vx or 0, vy or 0, vz or 0)
			else
				snap[k] = "<unreadable>"
			end
		else
			snap[k] = "<absent>"
		end
	end
	return snap, nil
end

local KEYS = { "params_a", "params_b", "color0", "color1", "color2" }

-- ---------------------------------------------------------------------------
-- finding a restore target
-- ---------------------------------------------------------------------------

local function env_exists(path)
	if type(path) ~= "string" or path == "" then return false, "not a string" end
	local ok, has = pcall(function() return DB:has("environment", path) end)
	if not ok then return false, "raised: " .. tostring(has) end
	if has == true then return true, "YES" end
	if has == false then return false, "no (false)" end
	return false, "nil (not found)"
end

local function show(v)
	if type(v) == "string" then return string.format("%q", v) end
	if v == nil then return "nil" end
	return tostring(v)
end

-- Walk managers.viewport for anything usable as a way back to a known environment.
function E.find_restore()
	local mgr = managers and managers.viewport
	local tries = {}
	if not mgr then return nil, nil, { "managers.viewport is nil" } end

	local function record(label, v)
		tries[#tries + 1] = string.format("  %-46s = %s", label, show(v))
	end

	-- 1. the viewport manager's own accessors
	local accessors = {
		{ "game_default_environment()", function() return mgr:game_default_environment() end },
		{ "default_environment()",       function() return mgr:default_environment() end },
	}
	for _, a in ipairs(accessors) do
		local ok, v = pcall(a[2])
		record(a[1], ok and v or ("RAISED: " .. tostring(v)))
		if ok and type(v) == "string" and v ~= "" then
			local ex, why = env_exists(v)
			if ex then return v, "managers.viewport:" .. a[1], tries end
			tries[#tries + 1] = "      -> not in DB: " .. tostring(why)
		end
	end

	-- 2. the env handler / env manager underneath the viewport
	local handler = E._handler
	if type(handler) == "table" then
		for _, f in ipairs({ "default_environment_path", "default_environment",
		                     "_default_environment", "environment_path", "_environment_path" }) do
			local ok, v = pcall(function() return handler[f] end)
			record("_env_handler." .. f, ok and v or ("RAISED: " .. tostring(v)))
			if ok and type(v) == "string" and v ~= "" then
				local ex, why = env_exists(v)
				if ex then return v, "_env_handler." .. f, tries end
				tries[#tries + 1] = "      -> not in DB: " .. tostring(why)
			end
		end
	end

	return nil, nil, tries
end

-- ---------------------------------------------------------------------------
-- swapping
-- ---------------------------------------------------------------------------

-- Apply an environment.
--
-- REVISION 4 - set_override_environment was removed.
--
-- Rev3 tried managers.viewport:set_override_environment(path, blend) and it
-- access-violated inside PackageManager:_script_data, reached via BeardLib's
-- FileManager:Process at line 46. Two causes, one of them mine:
--
--   1. I guessed the argument shape. The constant pool shows
--      set_override_environment(environment_path, blend_duration, ...) with more
--      arguments after blend_duration. Passing two can leave the native side
--      reading an argument that was never supplied. This is exactly the mistake
--      this project already made once with SizeCode, and pcall cannot catch it.
--
--   2. No installed mod calls set_override_environment, so there was no
--      precedent proving the convention.
--
-- What is left is worlddefinition:_set_environment(path), which was called
-- successfully in rev1 without raising and without crashing, and which is the
-- same call the Day & Night mod uses. Rev4 no longer guesses anything.
function E.apply(path)
	local wd = managers and managers.worlddefinition
	if type(wd) ~= "table" or type(wd._set_environment) ~= "function" then
		return false, nil, { "  worlddefinition._set_environment is not available" }
	end

	local attempts = {}
	local ok, err = pcall(function() return wd:_set_environment(path) end)
	attempts[#attempts + 1] = string.format("  %-46s %s", "worlddefinition:_set_environment(path)",
		ok and "returned without raising" or ("RAISED: " .. tostring(err)))
	if ok then return true, "worlddefinition:_set_environment(path)", attempts end

	return false, nil, attempts
end

-- ---------------------------------------------------------------------------
-- inspection (read-only)
-- ---------------------------------------------------------------------------

function E.inspect()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	add("=== environment swap inspection rev4 (read-only) ===")
	add("level = " .. tostring(Global and Global.level_data and Global.level_data.level_id or "<none>"))

	local mgr = managers and managers.viewport
	add("managers.viewport = " .. type(mgr))
	if type(mgr) == "table" then
		local has = {}
		local function absorb(t)
			if type(t) ~= "table" then return end
			for k, v in pairs(t) do
				if type(v) == "function" and not has[tostring(k)] then has[tostring(k)] = true end
			end
		end
		absorb(mgr)
		local ok, mt = pcall(getmetatable, mgr)
		if ok and type(mt) == "table" and type(mt.__index) == "table" then absorb(mt.__index) end
		local rel = {}
		for k in pairs(has) do if k:find("environment", 1, true) then rel[#rel + 1] = k end end
		table.sort(rel)
		add("  environment methods: " .. table.concat(rel, ", "))
	end
	add("")

	add("--- viewport + env handler ---")
	E._handler = nil
	local vp = nil
	if mgr then
		local ok, first = pcall(function() return mgr:first_active_viewport() end)
		if ok and first then
			vp = first
			local g, h = pcall(function() return first._env_handler end)
			if g and h then E._handler = h end
		end
	end
	add("  active viewport  = " .. type(vp))
	add("  _env_handler     = " .. type(E._handler))
	add("")

	add("--- restore target search ---")
	local restore, source, tries = E.find_restore()
	for _, t in ipairs(tries) do add(t) end
	add("")
	add("  RESTORE TARGET = " .. tostring(restore))
	add("  from           = " .. tostring(source))
	add("")

	add("--- candidates ---")
	for _, name in ipairs(E.CANDIDATES) do
		local ex, why = env_exists(name)
		add(string.format("  %-62s %s", name, why))
	end
	add("")

	add("--- live sky material, before any change ---")
	local snap, err = E.snapshot()
	if snap then
		for _, k in ipairs(KEYS) do add(string.format("  %-10s %s", k, snap[k])) end
	else
		add("  unavailable: " .. tostring(err))
	end
	add("")
	add("  Nothing has been changed.")
	if not restore then
		add("  !! No restore target found, so TEST will ABORT.")
	end
	return write_report(lines)
end

-- ---------------------------------------------------------------------------
-- the test
-- ---------------------------------------------------------------------------

function E.run()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end
	add("=== environment swap TEST (rev4) ===")

	local mgr = managers and managers.viewport
	if not mgr then
		add("managers.viewport is nil - ABORT.")
		return write_report(lines)
	end

	-- capture the handler for the restore search
	if not E._handler then
		local ok, first = pcall(function() return mgr:first_active_viewport() end)
		if ok and first then
			local g, h = pcall(function() return first._env_handler end)
			if g and h then E._handler = h end
		end
	end

	add("--- restore target ---")
	local restore, source, tries = E.find_restore()
	for _, t in ipairs(tries) do add(t) end
	add("")
	if not restore then
		add("No restore target exists in the DB - ABORT, nothing changed.")
		add("Restarting the level would still restore, but the test refuses to")
		add("run without a way back it can verify.")
		return write_report(lines)
	end
	add("RESTORE TARGET = " .. restore .. "   (from " .. tostring(source) .. ")")
	add("")

	-- choose a candidate that differs from the restore target
	local target
	for _, name in ipairs(E.CANDIDATES) do
		if name ~= restore then
			local ex = env_exists(name)
			if ex then target = name; break end
		end
	end
	if not target then
		add("no candidate environment exists in DB - ABORT, nothing changed.")
		return write_report(lines)
	end

	local before = E.snapshot()
	if before then
		add("--- sky material BEFORE ---")
		for _, k in ipairs(KEYS) do add(string.format("  %-10s %s", k, before[k])) end
		add("")
	end

	add("target = " .. target)
	add("(no blend on this call - the change is immediate)")
	add("")
	add("applying ...")
	local ok, how, attempts = E.apply(target)
	for _, a in ipairs(attempts) do add(a) end
	add("")
	if not ok then
		add("every application route failed - nothing changed.")
		return write_report(lines)
	end
	add("applied via: " .. how)
	add("")
	add(">>> WATCH THE SKY NOW.")
	add("")

	later(E.BLEND_SECONDS + 0.5, function()
		local after, aerr = E.snapshot()
		add("--- sky material AFTER ---")
		local changed = false
		if after then
			for _, k in ipairs(KEYS) do
				local mark = ""
				if before and before[k] ~= after[k] then mark = "   <-- CHANGED"; changed = true end
				add(string.format("  %-10s %s%s", k, after[k], mark))
			end
		else
			add("  unavailable: " .. tostring(aerr))
		end
		add("")
		if changed then
			add("RESULT: the dome material changed. The swap reached the sky.")
		else
			add("RESULT: dome material identical before/after.")
			add("The call did not alter the dome material. Judge by eye whether")
			add("lighting, fog or the sky texture changed.")
		end
		add("")
		add("restoring to " .. restore .. " ...")
		local ok2, how2, att2 = E.apply(restore)
		for _, a in ipairs(att2) do add("  " .. a) end
		add("restore via: " .. tostring(how2))
		write_report(lines)
	end)

	return write_report(lines)
end

log("[env_swap] rev4 loaded - uses only worlddefinition:_set_environment")