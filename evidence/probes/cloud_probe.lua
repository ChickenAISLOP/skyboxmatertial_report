-- ============================================================================
-- cloud_probe.lua  -  can the scrolling cloud layers be driven from Lua?
-- ============================================================================
--
-- THE FINDING THIS BUILDS ON
-- sky_1945_sunset_clouds is the only one of the 38 skies with scrolling clouds.
-- Its material_config declares FOUR materials, not one:
--
--   <material name="sky" render_template="dome_sky">        params_a/b, color0, color2
--   <material name="clouds_top"    ...DIFFUSE0_UVANIM...> uv0_speed = 0 -0.006 0
--   <material name="clouds_02"     ...DIFFUSE0_UVANIM...> uv0_speed = 0.005 0 0
--   <material name="clouds_02_slow" ...DIFFUSE0_UVANIM...> uv0_speed = 0.003 0 0
--
-- The other 32 skies declare exactly one material, "sky".
--
-- So the clouds are SEPARATE dome materials. That is why every earlier probe
-- missed them: Underlay:material(Idstring("sky")) returns only the sky dome,
-- and the cloud scroll lives on a different object entirely. This is Option B
-- in the report - the one rotation cannot substitute for, because rotating the
-- dome counter-rotates clouds baked into the composite.
--
-- IMPORTANT: these skies already animate. The three uv0_speed values are
-- non-zero, so Overkill's engine is scrolling them today with no mod at all.
-- What a mod adds is CONTROL of the speed, not the motion.
--
-- SAFETY
-- Read-only by default. variable_exists and get_variable are the exact calls
-- the existing probes already make, and this mod has never crashed on them.
--
-- The write path deliberately avoids constructing a Vector3 - that constructor
-- has no verified precedent here - and instead mutates the value object handed
-- back by get_variable, so the argument handed to set_variable is the same
-- object the engine already produced.
-- ============================================================================

_G.cloudprobe = _G.cloudprobe or {}
local C = _G.cloudprobe

if C._loaded then return end
C._loaded = true

C.REPORT_FILE = "cloud_report.txt"

-- Material names from every sky config in the export. Only sky_1945_sunset_clouds
-- declares more than the first; the rest are included so the probe reports
-- honestly on whichever level it is run in.
C.MATERIALS = { "sky", "clouds_top", "clouds_02", "clouds_02_slow" }

-- Variables to look for on each material.
C.VARS = { "uv0_speed", "intensity", "params_a", "params_b", "color0", "color1", "color2" }

local function out(s) if log then log("[cloud] " .. s) end end

local function write_report(lines)
	local body = table.concat(lines, "\n")
	out(body:gsub("\n", "\n[cloud] "))
	local f = io.open(SavePath .. C.REPORT_FILE, "w")
	if f then f:write(body .. "\n"); f:close() end
	return body
end

-- DelayManager is nil in this build and indexing it crashed the game. DelayedCalls
-- is what lua/settings/menu.lua uses and takes SECONDS.
local _seq = 0
local function later(seconds, fn)
	local ok = false
	if type(DelayedCalls) == "table" and type(DelayedCalls.Add) == "function" then
		_seq = _seq + 1
		ok = pcall(DelayedCalls.Add, DelayedCalls, "cloud_" .. _seq, seconds, fn)
	end
	if not ok and managers and type(managers.delayed_call) == "function" then
		ok = pcall(managers.delayed_call, managers, fn, seconds)
	end
	if not ok and managers and type(managers.add_delayed_callback) == "function" then
		_seq = _seq + 1
		ok = pcall(managers.add_delayed_callback, managers, "cloud_" .. _seq, fn, seconds)
	end
	if not ok then fn() end
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function fmt(v)
	local x, y, z = nil, nil, nil
	local ok = pcall(function() x, y, z = v.x, v.y, v.z end)
	if not ok then return "<not a vector>" end
	return string.format("%.6f, %.6f, %.6f", tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
end

function C.underlay_ready()
	return Underlay and type(Underlay.loaded) == "function" and Underlay:loaded()
end

-- Read every material we know about and every variable we know about. Read-only.
function C.survey()
	local out_t = {}
	out_t.underlay_loaded = C.underlay_ready()
	out_t.materials = {}

	if not out_t.underlay_loaded then return out_t end

	for _, name in ipairs(C.MATERIALS) do
		local entry = { name = name, found = false, vars = {} }
		local ok, mat = pcall(function() return Underlay:material(Idstring(name)) end)
		if ok and mat then
			entry.found = true
			for _, v in ipairs(C.VARS) do
				local g1, ex = pcall(function() return mat:variable_exists(Idstring(v)) end)
				if g1 and ex then
					local g2, val = pcall(function() return mat:get_variable(Idstring(v)) end)
					if g2 then
						local ty = type(val)
						entry.vars[v] = (ty == "number") and tostring(val) or fmt(val)
					else
						entry.vars[v] = "<unreadable: " .. tostring(val) .. ">"
					end
				end
			end
		else
			entry.error = tostring(mat)
		end
		out_t.materials[#out_t.materials + 1] = entry
	end
	return out_t
end

-- ---------------------------------------------------------------------------
-- inspection: read-only
-- ---------------------------------------------------------------------------

function C.inspect()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	add("=== cloud layer probe - inspection (read-only) ===")
	add("level = " .. tostring(Global and Global.level_data and Global.level_data.level_id or "<none>"))
	add("")

	local s = C.survey()
	add("Underlay loaded = " .. tostring(s.underlay_loaded))
	add("")

	local cloud_found = 0
	for _, m in ipairs(s.materials) do
		if m.found then
			local has_uv = false
			for v in pairs(m.vars) do if v == "uv0_speed" then has_uv = true end end
			if has_uv then cloud_found = cloud_found + 1 end
			add(string.format("  %-18s FOUND%s", m.name, has_uv and "   <-- has uv0_speed" or ""))
			local keys = {}
			for k in pairs(m.vars) do keys[#keys + 1] = k end
			table.sort(keys)
			for _, k in ipairs(keys) do
				add(string.format("      %-12s %s", k, m.vars[k]))
			end
		else
			add(string.format("  %-18s absent (%s)", m.name, tostring(m.error)))
		end
	end
	add("")

	if cloud_found > 0 then
		add("RESULT: " .. cloud_found .. " material(s) expose uv0_speed.")
		add("These skies ALREADY scroll their clouds - the speeds above are non-zero")
		add("in the stock config, so the motion ships with the game.")
		add("The TEST button measures whether the speed is writable at runtime.")
	else
		add("RESULT: no uv0_speed here.")
		add("Either this level does not use sky_1945_sunset_clouds, or the cloud")
		add("materials are not reachable through Underlay:material().")
		add("Environments that use it: pd2_env_auc_ext, pd2_env_auc_int,")
		add("pd2_env_chew_2, pd2_env_mex_sunset")
	end
	add("")
	add("  Nothing has been changed.")
	return write_report(lines)
end

-- ---------------------------------------------------------------------------
-- the test: change one component of uv0_speed, read it back, restore
-- ---------------------------------------------------------------------------

function C.run()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end
	add("=== cloud layer TEST ===")

	if not C.underlay_ready() then
		add("Underlay not loaded - ABORT, nothing changed.")
		return write_report(lines)
	end

	-- find the first material that actually has uv0_speed
	local target_name, mat
	for _, name in ipairs(C.MATERIALS) do
		local ok, m = pcall(function() return Underlay:material(Idstring(name)) end)
		if ok and m then
			local g, ex = pcall(function() return m:variable_exists(Idstring("uv0_speed")) end)
			if g and ex then target_name, mat = name, m; break end
		end
	end

	if not mat then
		add("no material exposes uv0_speed in this level - ABORT, nothing changed.")
		add("Try pd2_env_mex_sunset, pd2_env_chew_2, pd2_env_auc_ext or pd2_env_auc_int.")
		return write_report(lines)
	end
	add("target material = " .. target_name)
	add("")

	-- capture the original
	local okr, orig = pcall(function() return mat:get_variable(Idstring("uv0_speed")) end)
	if not okr or orig == nil then
		add("could not read uv0_speed - ABORT, nothing changed.")
		add("  " .. tostring(orig))
		return write_report(lines)
	end
	add("original uv0_speed = " .. fmt(orig))
	add("")

	-- mutate one component on the object the engine handed us, rather than
	-- constructing a Vector3, which has no verified precedent in this mod
	local x0, y0, z0 = orig.x, orig.y, orig.z
	local new_x = -(tonumber(x0) or 0)          -- flip the sign of the x speed
	local setok, seterr = pcall(function() orig.x = new_x end)
	add("mutating the returned value: " ..
		(setok and ("x " .. tostring(x0) .. " -> " .. tostring(new_x))
			or ("RAISED: " .. tostring(seterr))))
	add("")

	add("calling mat:set_variable(uv0_speed, that value) ...")
	local okw, werr = pcall(function() return mat:set_variable(Idstring("uv0_speed"), orig) end)
	add("set " .. (okw and "returned without raising" or ("RAISED: " .. tostring(werr))))
	add("")

	later(1.0, function()
		local oka, now = pcall(function() return mat:get_variable(Idstring("uv0_speed")) end)
		add("uv0_speed 1s later = " .. (oka and fmt(now) or ("unreadable - " .. tostring(now))))
		add("")
		if oka and now then
			local nx = tonumber(now.x) or 0
			if math.abs(nx - new_x) < 0.00001 then
				add("RESULT: the write took. Cloud scroll speed is drivable from Lua.")
				add(">>> WATCH THE SKY - the cloud layers should visibly change speed")
				add("    or direction.")
			else
				add("RESULT: read back " .. tostring(nx) .. ", expected " .. tostring(new_x))
				add("    - the write did not take, or something overwrote it.")
			end
		else
			add("RESULT: could not read back, inconclusive. Judge by eye.")
		end

		add("")
		add("restoring x to " .. tostring(x0) .. " ...")
		local okr2, rerr = pcall(function() orig.x = x0 end)
		if okr2 then
			local okw2, werr2 = pcall(function()
				return mat:set_variable(Idstring("uv0_speed"), orig)
			end)
			add("restore " .. (okw2 and "returned without raising" or ("RAISED: " .. tostring(werr2))))
		else
			add("restore RAISED: " .. tostring(rerr))
		end

		later(0.5, function()
			local okf, fin = pcall(function() return mat:get_variable(Idstring("uv0_speed")) end)
			add("uv0_speed after restore = " .. (okf and fmt(fin) or "unreadable"))
			write_report(lines)
		end)
	end)

	return write_report(lines)
end

log("[cloud] loaded - read-only survey of sky_1945_sunset_clouds cloud materials")