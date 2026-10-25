-- ============================================================================
-- sky_rot_probe.lua  -  can the sky dome rotation be driven from Lua?
-- ============================================================================
--
-- WHY THIS EXISTS
-- Report finding 5 says "no Lua-facing setter for sky_orientation/rotation".
-- That conclusion was WRONG, and this probe is the correction.
--
-- What was actually true: the sky *material* (Underlay:material("sky")) exposes
-- no rotation variable. That is a real observation. But it was the wrong layer.
-- The setter lives on the viewport's environment handler:
--
--   managers.viewport:first_active_viewport()._env_handler:editor_set_value(key, value)
--
-- BeardLib-Editor's EnvironmentLayerEditor.lua line 650 does exactly this:
--     local sky_rot_key = Idstring("sky_orientation/rotation"):key()
--     ..._env_handler:editor_set_value(sky_rot_key, item:Value())
-- and its own author left the comment "-- I guess this works".
--
-- That is not proof. This probe is.
--
-- SAFETY
-- editor_set_value / get_value / has_data_path_key are all exercised by the
-- installed DisableFog mod (Feeder.DATA_PATH_KEY, handler:get_value) and by
-- BeardLib-Editor. They are Lua-level calls into a Lua-side handler, so pcall
-- is a real safety net here - unlike the raw C++ material calls that crashed
-- the game earlier in this investigation.
--
-- The test reads the current value first and always writes it back.
-- ============================================================================

_G.skyrot = _G.skyrot or {}
local R = _G.skyrot

if R._loaded then return end
R._loaded = true

R.REPORT_FILE = "sky_rot_report.txt"
R.REVERT_FRAMES = 240          -- 4 seconds

R.ROT_KEY_STR  = "sky_orientation/rotation"
R.ROT_KEY      = Idstring(R.ROT_KEY_STR):key()

local function out(s) if log then log("[skyrot] " .. s) end end

-- Safe scheduling.
--
-- I used DelayManager:PostDelayedCallback(fn, frames) here and it crashed the
-- game: DelayManager is nil in this build. DelayedCalls is the API this mod
-- already uses successfully (lua/settings/menu.lua drives the DDS generator
-- poll with it), and it takes SECONDS, not frames.
--
-- Fall back through the other known spellings and finally to calling inline,
-- so a probe can never take the game down over a missing global again.
local _delay_seq = 0
local function later(seconds, fn)
	local ok = false
	if type(DelayedCalls) == "table" and type(DelayedCalls.Add) == "function" then
		_delay_seq = _delay_seq + 1
		ok = pcall(DelayedCalls.Add, DelayedCalls, "skyrot_" .. _delay_seq, seconds, fn)
	end
	if not ok and managers and type(managers.delayed_call) == "function" then
		ok = pcall(managers.delayed_call, managers, fn, seconds)
	end
	if not ok and managers and type(managers.add_delayed_callback) == "function" then
		_delay_seq = _delay_seq + 1
		ok = pcall(managers.add_delayed_callback, managers, "skyrot_" .. _delay_seq, fn, seconds)
	end
	if not ok then
		-- Nothing available. Run it now rather than silently dropping it.
		out("no delay API available, running callback immediately")
		fn()
	end
end

local function write_report(lines)
	local body = table.concat(lines, "\n")
	out(body:gsub("\n", "\n[skyrot] "))
	local f = io.open(SavePath .. R.REPORT_FILE, "w")
	if f then f:write(body .. "\n"); f:close() end
	return body
end

-- ---------------------------------------------------------------------------
-- locating the environment handler, tolerating the shapes the game has used
-- ---------------------------------------------------------------------------

function R.find_handler()
	local attempts = {}
	local vp = managers and managers.viewport

	if vp then
		local ok, first = pcall(function() return vp:first_active_viewport() end)
		if ok and first then
			attempts[#attempts + 1] = "first_active_viewport()"
			local ok2, h = pcall(function() return first._env_handler end)
			if ok2 and h then return h, "first_active_viewport()._env_handler", first end

			-- some builds expose vp() on the wrapper
			local ok3, inner = pcall(function() return first:vp() end)
			if ok3 and inner then
				attempts[#attempts + 1] = "first_active_viewport():vp()._env_handler"
				local ok4, h2 = pcall(function() return inner._env_handler end)
				if ok4 and h2 then return h2, "first_active_viewport():vp()._env_handler", inner end
			end
		end
	end

	-- fall back: scan every active viewport
	if vp then
		local ok, list = pcall(function() return vp:active_viewports() end)
		if ok and type(list) == "table" then
			for _, v in ipairs(list) do
				local g, h = pcall(function() return v._env_handler end)
				if g and h then return h, "active_viewports()[" .. tostring(h) .. "]._env_handler", v end
			end
		end
	end

	return nil, table.concat(attempts, ", "), nil
end

-- ---------------------------------------------------------------------------
-- inspection: read-only
-- ---------------------------------------------------------------------------

function R.inspect()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	add("=== sky rotation probe - inspection (read-only) ===")
	add("level = " .. tostring(Global and Global.level_data and Global.level_data.level_id or "<none>"))
	add("")

	local mgr = managers and managers.viewport
	add("managers.viewport = " .. type(mgr))
	if type(mgr) == "table" or type(mgr) == "userdata" then
		local names = {}
		local seen = {}
		local function absorb(t)
			if type(t) ~= "table" then return end
			for k, v in pairs(t) do
				if type(v) == "function" and not seen[tostring(k)] then
					seen[tostring(k)] = true; names[#names + 1] = tostring(k)
				end
			end
		end
		absorb(mgr)
		local ok, mt = pcall(getmetatable, mgr)
		if ok and type(mt) == "table" and type(mt.__index) == "table" then absorb(mt.__index) end
		table.sort(names)
		local rel = {}
		for _, n in ipairs(names) do
			if n:find("environment", 1, true) or n:find("env_", 1, true) then rel[#rel + 1] = n end
		end
		add("  total methods: " .. #names)
		add("  environment-related:")
		for _, n in ipairs(rel) do add("    " .. n) end
		add("")
	end

	-- the data path key
	add("--- data path key ---")
	add("  string : " .. R.ROT_KEY_STR)
	add("  hashed : " .. tostring(R.ROT_KEY))
	add("")

	-- is this environment even wired for rotation?
	add("--- does this environment support rotation? ---")
	if mgr then
		local ok, has = pcall(function() return mgr:has_data_path_key(R.ROT_KEY) end)
		add("  managers.viewport:has_data_path_key(key) = " ..
			(not ok and ("RAISED: " .. tostring(has))
				or (has == true and "YES" or (has == false and "no (false)" or "nil"))))
	end
	add("")

	-- find the handler
	local h, where, vp = R.find_handler()
	add("--- environment handler ---")
	add("  handler = " .. type(h))
	add("  found via: " .. tostring(where))
	if h then
		-- Same metatable situation as managers.worlddefinition: pairs() on the
		-- object returns nothing, the methods sit on __index.
		local seen = {}
		local function absorb(t)
			if type(t) ~= "table" then return end
			for k, v in pairs(t) do
				if type(v) == "function" and not seen[tostring(k)] then
					seen[tostring(k)] = true
				end
			end
		end
		absorb(h)
		local okm, mt = pcall(getmetatable, h)
		if okm and type(mt) == "table" then
			if type(mt.__index) == "table" then
				absorb(mt.__index)
				add("  (methods found on metatable __index)")
			end
			local mk = {}
			for k in pairs(mt) do mk[#mk + 1] = tostring(k) end
			table.sort(mk)
			add("  metatable keys: " .. table.concat(mk, ", "))
		end
		local m = {}
		for k in pairs(seen) do m[#m + 1] = k end
		table.sort(m)
		add("  methods on handler (" .. #m .. "):")
		for _, n in ipairs(m) do add("    " .. n) end
		add("  editor_set_value present: " .. tostring(type(h.editor_set_value) == "function"))
	end
	add("")

	-- Cross-check: the worlddefinition modifier id should be the hashed
	-- rotation key. If they match, the level's environment modifier really is
	-- driving sky_orientation/rotation.
	add("--- modifier id cross-check ---")
	local wdm = managers and managers.worlddefinition
	local okid, mid = pcall(function() return wdm and wdm._environment_modifier_id end)
	add("  worlddefinition._environment_modifier_id = " ..
		(okid and (tostring(mid)) or ("unreadable - " .. tostring(mid))))
	add("  hashed rotation key                 = " .. tostring(R.ROT_KEY))
	add("  MATCH: " .. tostring(okid and tostring(mid) == tostring(R.ROT_KEY)))
	add("")

	-- the level's own declared rotation, if it stores one
	local oke, envt = pcall(function() return wdm and wdm._environment end)
	if oke and type(envt) == "table" then
		local keys = {}
		for k, v in pairs(envt) do keys[#keys + 1] = string.format("%s = %s", tostring(k), tostring(v)) end
		table.sort(keys)
		add("  worlddefinition._environment = { " .. table.concat(keys, ", ") .. " }")
		add("")
	end

	-- current value
	add("--- current rotation value ---")
	local cur, err = R.read_rotation()
	if cur ~= nil then
		add("  rotation = " .. tostring(cur))
	else
		add("  unavailable: " .. tostring(err))
	end
	add("")
	add("  Nothing has been changed.")
	return write_report(lines)
end

-- ---------------------------------------------------------------------------
-- reading rotation, trying each known accessor
-- ---------------------------------------------------------------------------

function R.read_rotation()
	local tries = {}
	local found = nil
	local function try(label, fn)
		local ok, v = pcall(fn)
		tries[#tries + 1] = string.format("%s -> %s", label,
			(not ok and ("RAISED: " .. tostring(v))
				or (v == nil and "nil" or tostring(v))))
		if ok and type(v) == "number" then found = v end
		return nil
	end

	local h = R.find_handler()

	-- handler:get_value(hashed_key) is the accessor proven by DisableFog.
	-- The string form and the get_environment_value forms are NOT used:
	-- inspection showed the string form returns nil and get_environment_value
	-- raises with a nil message, which pcall cannot make safe here.
	if h then
		try("handler:get_value(rot_key)",
			function() return h:get_value(R.ROT_KEY) end)
	end

	R._last_read_tries = tries
	if found ~= nil then return found end
	return nil, table.concat(tries, "\n    ")
end

-- ---------------------------------------------------------------------------
-- the test: set rotation, read it back, restore
-- ---------------------------------------------------------------------------

function R.run()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end
	add("=== sky rotation TEST ===")

	local h, where = R.find_handler()
	add("handler = " .. type(h) .. "  via " .. tostring(where))
	if not h then
		add("no environment handler found - ABORT, nothing changed.")
		return write_report(lines)
	end

	-- the two functions this depends on must actually exist
	local have_set = type(h.editor_set_value) == "function"
	local have_get = type(h.get_value) == "function"
	add("handler.editor_set_value = " .. tostring(have_set))
	add("handler.get_value       = " .. tostring(have_get))
	if not (have_set and have_get) then
		add("required method missing - ABORT, nothing changed.")
		return write_report(lines)
	end
	add("")

	-- capture the original
	local before = nil
	local ok0, v0 = pcall(function() return h:get_value(R.ROT_KEY) end)
	if ok0 and type(v0) == "number" then
		before = v0
		add("original rotation = " .. before)
	else
		add("could not read original rotation (" .. tostring(v0) .. ")")
		add("falling back to the live worlddefinition value if present")
		local wdm = managers and managers.worlddefinition
		local oke, envt = pcall(function() return wdm and wdm._environment end)
		if oke and type(envt) == "table" and type(envt.sky_rot) == "number" then
			before = envt.sky_rot
			add("  using worlddefinition._environment.sky_rot = " .. before)
		end
	end
	add("")

	if before == nil then
		add("no original rotation to restore - ABORT, nothing changed.")
		return write_report(lines)
	end

	-- pick a visibly different angle
	local target = math.floor(before + 90) % 360
	add("target rotation   = " .. target .. "   (original + 90)")
	add("")
	add("calling handler:editor_set_value(rotation_key, " .. target .. ") ...")
	add("")

	local ok, err = pcall(function() return h:editor_set_value(R.ROT_KEY, target) end)
	add("set returned " .. (ok and "without raising" or ("RAISED: " .. tostring(err))))
	add("")

	later(0.5, function()
		local now, nerr = R.read_rotation()
		add("rotation 0.5s later: " .. (now ~= nil and tostring(now) or ("unreadable - " .. tostring(nerr))))
		if R._last_read_tries then
			add("  accessor attempts:")
			for _, t in ipairs(R._last_read_tries) do add("    " .. t) end
		end
		add("")
		if now ~= nil and math.abs(now - target) < 0.5 then
			add("RESULT: rotation now reads " .. now .. ", target was " .. target .. ".")
			add("The sky dome rotation IS writable from Lua.")
			add("Watch the sky - the clouds and sun should have swung 90 degrees.")
		elseif now ~= nil then
			add("RESULT: read " .. now .. ", expected " .. target .. " - partially applied?")
		else
			add("RESULT: could not read the value back, so this is inconclusive.")
			add("Judge by eye: did the sky visibly rotate?")
		end

		add("")
		add("restoring rotation to " .. before .. " ...")
		local ok2, err2 = pcall(function() return h:editor_set_value(R.ROT_KEY, before) end)
		add("restore " .. (ok2 and "returned without raising" or ("RAISED: " .. tostring(err2))))

		later(0.5, function()
			local fin = R.read_rotation()
			add("rotation after restore: " .. tostring(fin))
			write_report(lines)
		end)
	end)

	return write_report(lines)
end

log("[skyrot] loaded - reads and writes sky_orientation/rotation via the viewport env handler")