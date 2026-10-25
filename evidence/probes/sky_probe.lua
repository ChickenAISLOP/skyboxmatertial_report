-- ============================================================================
-- sky_probe.lua  -  read-only diagnostic probe for PAYDAY 2 skybox internals
-- ============================================================================
--
-- REVISION 2. Revision 1 crashed the game.
--
-- What went wrong: it called material:get_variable("color0") with a Lua string
-- instead of an Idstring. The native function dereferences that argument as a
-- pointer, so it faulted with an access violation. pcall cannot trap that --
-- pcall only catches Lua errors, and a bad native pointer dies inside the C
-- layer before control returns to the VM.
--
-- Rule applied throughout revision 2:
--
--     Only ever call a native function using an argument convention that some
--     other mod is already calling successfully at runtime. Inspect freely;
--     invoke sparingly.
--
-- Every call below is copied from a pattern that
-- mods/environment editor/env.lua executes in this same game:
--
--     local mat = Underlay:material(Idstring("sky"))
--     if mat:variable_exists(Idstring("color0")) then
--         local v = mat:get_variable(Idstring("color0"))
--         mat:set_variable(Idstring("color0"), v)
--     end
--
-- The gate is variable_exists(). Calling get_variable blind is what crashed v1.
--
-- Install: lua/sky_probe.lua + a "lib/setups/gamesetup" hook in mod.txt.
-- Output : sky_probe_report.txt in the BLT save folder.
-- ============================================================================

_G.sky_probe = _G.sky_probe or {}
local P = _G.sky_probe

if P._loaded then return end
P._loaded = true

P.OUTPUT_FILE = "sky_probe_report.txt"

-- The five inputs the dome_sky shader declares. color1 is the one no vanilla
-- sky ever sets.
local DOME_KEYS = {
	{ name = "params_a", note = "range / offset / curve" },
	{ name = "params_b", note = "sky intensity / sun intensity" },
	{ name = "color0",   note = "gradient top" },
	{ name = "color1",   note = "GRADIENT MIDDLE - never set by vanilla" },
	{ name = "color2",   note = "gradient bottom" },
}

-- Additional names the Environment Editor already proves are live on this
-- material. Included so the probe doubles as a check that env.lua's own
-- assumptions still hold on the current build.
local EDITOR_KEYS = {
	{ name = "color0_scale" },
	{ name = "color2_scale" },
	{ name = "ambient_color" },
	{ name = "ambient_falloff_scale" },
	{ name = "fog_start_color" },
	{ name = "fog_far_low_color" },
	{ name = "fog_min_range" },
	{ name = "fog_max_range" },
	{ name = "fog_max_density" },
}

-- ---------------------------------------------------------------------------
-- output
-- ---------------------------------------------------------------------------

local function fmt(v)
	if v == nil then return "<nil>" end
	local t = type(v)
	if t == "string" then return string.format("%q", v) end
	if t == "number" then return string.format("%.6g", v) end
	if t == "boolean" then return tostring(v) end
	if t == "table" or t == "userdata" then
		-- Vector3 exposes x/y/z. Reading fields off a userdata is safe; it is
		-- calling native functions with wrong arguments that is not.
		local ok, a, b, c = pcall(function() return v.x, v.y, v.z end)
		if ok and (type(a) == "number" or type(b) == "number" or type(c) == "number") then
			return string.format("Vector3(%.4f, %.4f, %.4f)", tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0)
		end
		return "<" .. t .. ">"
	end
	return "<" .. t .. ">"
end

function P.write(lines)
	local body = table.concat(lines, "\n")
	if log then log("[sky_probe] " .. body:gsub("\n", "\n[sky_probe] ")) end
	local path = SavePath .. P.OUTPUT_FILE
	local f = io.open(path, "w")
	if f then
		f:write(body .. "\n")
		f:close()
	elseif log then
		log("[sky_probe] FAILED to write " .. path)
	end
	return body
end

-- ---------------------------------------------------------------------------
-- proven-safe readers
-- ---------------------------------------------------------------------------

-- Returns mat, err. Only calls what env.lua calls.
local function get_sky_material()
	local ok, loaded = pcall(function()
		if Underlay and type(Underlay.loaded) == "function" then return Underlay:loaded() end
	end)
	if not ok or not loaded then return nil, "Underlay not loaded" end
	ok, mat = pcall(function() return Underlay:material(Idstring("sky")) end)
	if not ok then return nil, "Underlay:material raised" end
	if not mat then return nil, "no sky material" end
	return mat, nil
end

-- Gate then read. Returns value, state where state is one of:
--   "ok" | "absent" (variable_exists returned false) | "unreadable"
local function read_var(mat, name)
	local ok, exists = pcall(function() return mat:variable_exists(Idstring(name)) end)
	if not ok then return nil, "variable_exists raised" end
	if not exists then return nil, "absent" end
	local ok2, v = pcall(function() return mat:get_variable(Idstring(name)) end)
	if not ok2 then return nil, "get_variable raised" end
	return v, "ok"
end

-- ---------------------------------------------------------------------------
-- structure inspection - no native calls, only type() checks
-- ---------------------------------------------------------------------------

-- Walks one level of a table and reports what is there. Reading keys and
-- calling type() cannot fault.
local function describe(label, obj, out)
	if obj == nil then
		out[#out + 1] = string.format("  %-26s <absent>", label)
		return
	end
	out[#out + 1] = string.format("  %-26s type=%s", label, type(obj))
	if type(obj) == "table" then
		local keys = {}
		for k in pairs(obj) do
			keys[#keys + 1] = tostring(k)
			if #keys >= 40 then break end
		end
		table.sort(keys)
		out[#out + 1] = string.format("  %-26s fields: %s", "", table.concat(keys, ", "))
	end
end

-- Enumerates method names on a table OR on userdata.
--
-- pairs() returns nothing for userdata, which is why rev3 printed empty method
-- lists for vp / post_processor / modifier. For userdata the method table lives
-- on the metatable, usually under __index. Reading the metatable and walking it
-- is plain table inspection -- it invokes nothing.
local function collect_methods(obj, out)
	local seen = {}
	local function absorb(t)
		if type(t) ~= "table" then return end
		for k, v in pairs(t) do
			if type(v) == "function" then seen[tostring(k)] = true end
		end
	end

	if type(obj) == "table" then
		absorb(obj)
	elseif type(obj) == "userdata" then
		local ok, mt = pcall(getmetatable, obj)
		if not ok or type(mt) ~= "table" then
			out[#out + 1] = "    <no readable metatable>"
			return nil
		end
		local idx = mt.__index
		if type(idx) == "table" then
			absorb(idx)
		elseif type(idx) == "function" then
			-- __index is a function: names live in its upvalues, which is far
			-- too invasive to walk. Report the facts and stop.
			out[#out + 1] = "    __index is a function (C or closure) - names not enumerable"
			out[#out + 1] = "    metatable keys: " .. (function()
				local n = {}
				for k in pairs(mt) do n[#n + 1] = tostring(k) end
				table.sort(n)
				return table.concat(n, ", ")
			end)()
			return nil
		else
			out[#out + 1] = "    __index is " .. type(idx)
		end
	end

	local names = {}
	for k in pairs(seen) do names[#names + 1] = k end
	table.sort(names)
	return names
end

local function list_methods(label, obj, out, limit)
	out[#out + 1] = string.format("  %s  (type=%s):", label, type(obj))
	local names = collect_methods(obj, out)
	if names == nil then return end
	if #names == 0 then
		out[#out + 1] = "    <none found>"
		return
	end
	for i = 1, math.min(#names, limit or 120) do
		out[#out + 1] = "    " .. names[i]
	end
	if #names > (limit or 120) then
		out[#out + 1] = string.format("    ... and %d more", #names - (limit or 120))
	end
end

-- Proven-safe environment chain, copied from
-- mods/environment editor/env.lua, which calls all three every frame:
--   managers.viewport:first_active_viewport()  ->  :vp()
--   :get_post_processor_effect("World", Idstring("deferred"))
--   :modifier(Idstring("apply_ambient"))       ->  :material()
-- Returns whatever it can reach, plus a note on where it stopped.
local function reach_environment()
	local res = {}
	local ok, mgr = pcall(function() return managers.viewport end)
	if not ok or not mgr or type(mgr.first_active_viewport) ~= "function" then
		res.err = "managers.viewport unavailable"
		return res
	end
	ok, res.viewport = pcall(function() return mgr:first_active_viewport() end)
	if not ok or not res.viewport then
		res.err = "no active viewport"
		return res
	end
	if type(res.viewport.vp) == "function" then
		ok, res.vp = pcall(function() return res.viewport:vp() end)
		if not ok then res.vp = nil end
	end
	if res.vp and type(res.vp.get_post_processor_effect) == "function" then
		ok, res.processor = pcall(function()
			return res.vp:get_post_processor_effect("World", Idstring("deferred"))
		end)
		if not ok then res.processor = nil end
	end
	if res.processor and type(res.processor.modifier) == "function" then
		ok, res.modifier = pcall(function() return res.processor:modifier(Idstring("apply_ambient")) end)
		if not ok then res.modifier = nil end
	end
	if res.modifier and type(res.modifier.material) == "function" then
		ok, res.env_material = pcall(function() return res.modifier:material() end)
		if not ok then res.env_material = nil end
	end
	return res
end

-- ---------------------------------------------------------------------------
-- the dump
-- ---------------------------------------------------------------------------

function P.dump()
	local out = {}
	local function add(s) out[#out + 1] = s end

	add("=== PAYDAY 2 sky probe (rev 4, read-only) ===")
	add("heist           = " .. tostring(Global and Global.level_data and Global.level_data.level_id or "<none>"))
	add("underlay_loaded = " .. tostring(Underlay and type(Underlay.loaded) == "function" and Underlay:loaded()))
	add("")

	-- --- 1. dome material, proven-safe --------------------------------------
	add("--- dome_sky material (variable_exists gate + get_variable) ---")
	local mat, err = get_sky_material()
	if not mat then
		add("  unavailable: " .. tostring(err))
		add("  Enter an outdoor heist. Interior levels have no sky dome.")
	else
		for _, k in ipairs(DOME_KEYS) do
			local v, state = read_var(mat, k.name)
			local text
			if state == "ok" then
				text = fmt(v)
			elseif state == "absent" then
				text = "<absent - not set on this sky>"
			else
				text = "<" .. state .. ">"
			end
			add(string.format("  %-12s %-30s", k.name, text))
		end
		add("")
		add("  color1 verdict: see the line above.")
		add("    absent -> the shader input is real but unset; set_variable would")
		add("                likely be accepted and is worth a controlled test.")
		add("    a value -> already populated at runtime, read it and compare with")
		add("               the static config (static says every sky ships 1 1 1).")
		add("")
		add("--- keys the Environment Editor also uses (sanity check) ---")
		for _, k in ipairs(EDITOR_KEYS) do
			local v, state = read_var(mat, k.name)
			add(string.format("  %-24s %s", k.name,
				state == "ok" and fmt(v) or ("<" .. state .. ">")))
		end
	end
	add("")

	-- --- 2. live environment objects, inspection only -----------------------
	add("--- environment globals (rev2 found all of these absent) ---")
	for _, g in ipairs({ "CoreSky", "EnvironmentHandler", "EnvironmentManager" }) do
		describe(g, rawget(_G, g), out)
	end
	describe("managers.environment", managers and managers.environment, out)
	add("  -> none of them are globals. The live route is via the viewport.")
	add("")

	local env = reach_environment()
	if env.err then
		add("  viewport chain unavailable: " .. tostring(env.err))
		add("  Run inside a heist, not the main menu.")
	else
		describe("viewport", env.viewport, out)
		describe("vp", env.vp, out)
		describe("post_processor", env.processor, out)
		describe("modifier(apply_ambient)", env.modifier, out)
		describe("env material", env.env_material, out)
	end
	add("")

	-- --- 3. method inventory on the live objects ----------------------------
	add("--- methods on vp (names only, nothing invoked) ---")
	list_methods("vp", env.vp, out, 200)
	add("")
	add("--- methods on post_processor (names only) ---")
	list_methods("post_processor", env.processor, out, 200)
	add("")
	add("--- methods on modifier (names only) ---")
	list_methods("modifier", env.modifier, out, 200)
	add("")
	add("--- fields on vp (any name containing rot/sky/orient/under) ---")
	if type(env.vp) == "table" then
		local hits = {}
		for k in pairs(env.vp) do
			local s = tostring(k):lower()
			if s:find("rot", 1, true) or s:find("sky", 1, true)
				or s:find("orient", 1, true) or s:find("under", 1, true) then
				hits[#hits + 1] = tostring(k)
			end
		end
		table.sort(hits)
		if #hits == 0 then
			add("    <none>")
		else
			for _, h in ipairs(hits) do add("    " .. h) end
		end
	else
		add("    <vp is not a table>")
	end
	add("")

	-- --- 4. rotation-shaped names across every object we can reach ----------
	add("--- rotation/sky/orientation-shaped names, all objects ---")
	local WANT = { "rot", "sky", "orient", "underlay", "sun" }
	local function scan(label, obj)
		local names = collect_methods(obj, {})
		if not names then return end
		local hits = {}
		for _, n in ipairs(names) do
			local low = n:lower()
			for _, w in ipairs(WANT) do
				if low:find(w, 1, true) then hits[#hits + 1] = n; break end
			end
		end
		if #hits > 0 then
			table.sort(hits)
			add("  " .. label .. ":")
			for _, h in ipairs(hits) do add("      " .. h) end
		end
	end
	scan("viewport", env.viewport)
	scan("vp", env.vp)
	scan("post_processor", env.processor)
	scan("modifier", env.modifier)
	add("  (fields, not just methods)")
	if type(env.viewport) == "table" then
		local fh = {}
		for k in pairs(env.viewport) do
			local low = tostring(k):lower()
			for _, w in ipairs(WANT) do
				if low:find(w, 1, true) then fh[#fh + 1] = tostring(k) .. "  type=" .. type(env.viewport[k]); break end
			end
		end
		table.sort(fh)
		if #fh == 0 then add("    <none>") else for _, h in ipairs(fh) do add("    " .. h) end end
	end
	add("")

	-- --- 5. viewport._env_handler ------------------------------------------
	add("--- viewport._env_handler (the name rev2 looked for as a global) ---")
	local vpt = env.viewport
	if type(vpt) == "table" and vpt._env_handler ~= nil then
		local h = vpt._env_handler
		add("  type(_env_handler) = " .. type(h))
		if type(h) == "function" then
			add("  it is a method, not a cached instance.")
			add("  NOT called. If it is called, the return value is the")
			add("  EnvironmentHandler that CoreSky/EnvironmentHandler were")
			add("  assumed to be, and it should expose get_value/set_value.")
		elseif type(h) == "userdata" or type(h) == "table" then
			add("  it is a cached instance.")
			list_methods("_env_handler", h, out, 120)
			local names = collect_methods(h, {})
			if names then
				local hits = {}
				for _, n in ipairs(names) do
					local low = n:lower()
					if low:find("rot", 1, true) or low:find("sky", 1, true)
						or low:find("orient", 1, true) or low:find("value", 1, true) then
						hits[#hits + 1] = n
					end
				end
				table.sort(hits)
				if #hits > 0 then
					add("  rotation/value-shaped:")
					for _, h2 in ipairs(hits) do add("      " .. h2) end
				end
			end
		end
	else
		add("  <not present on this viewport>")
	end
	add("")

	-- --- 4. what to do with the above ---------------------------------------
	add("--- next step ---")
	add("  Everything above is read from objects that the Environment Editor")
	add("  already calls every frame, so the chain is proven safe to touch.")
	add("")
	add("  If the method lists contain anything rotation-shaped -- set_rotation,")
	add("  set_yaw_pitch_roll, set_sky_orientation, an underlay or orientation")
	add("  setter on vp -- that is the real route to sky_orientation/rotation.")
	add("  Nothing here has been called. Pick one name from the list above and")
	add("  it can be tried in isolation next.")
	add("")
	add("=== end ===")

	return P.write(out)
end

function sky_probe_dump() return P.dump() end

-- Auto-dump. PAYDAY 2 has no dependable console, so do not require one.
local DUMP_DELAYS = { 0, 400, 1500 }

local function try_dump(tag)
	local ok, err = pcall(function() P.dump() end)
	if not ok and log then log("[sky_probe] dump failed (" .. tostring(tag) .. "): " .. tostring(err)) end
end

-- Safe scheduling. DelayManager is nil in this build and indexing it takes the
-- game down; DelayedCalls is what lua/settings/menu.lua already uses. Falls
-- back through the other known spellings, then runs inline rather than
-- dropping the dump.
local _dump_seq = 0
local function later(seconds, fn)
	local ok = false
	if type(DelayedCalls) == "table" and type(DelayedCalls.Add) == "function" then
		_dump_seq = _dump_seq + 1
		ok = pcall(DelayedCalls.Add, DelayedCalls, "sky_probe_" .. _dump_seq, seconds, fn)
	end
	if not ok and managers and type(managers.delayed_call) == "function" then
		ok = pcall(managers.delayed_call, managers, fn, seconds)
	end
	if not ok and managers and type(managers.add_delayed_callback) == "function" then
		_dump_seq = _dump_seq + 1
		ok = pcall(managers.add_delayed_callback, managers, "sky_probe_" .. _dump_seq, fn, seconds)
	end
	if not ok then fn() end
end

Hooks:Add("LevelLoaded", "sky_probe_level_loaded", function()
	-- seconds, not frames
	local delays = { 0.0, 6.7, 25.0 }
	for i = 1, #delays do
		later(delays[i], function() try_dump("LevelLoaded+" .. i) end)
	end
end)

log("[sky_probe] rev4 loaded - read-only, auto-dumps on LevelLoaded")