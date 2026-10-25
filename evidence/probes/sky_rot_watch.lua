-- ============================================================================
-- sky_rot_watch.lua  -  is anything actually animating sky_orientation/rotation?
-- ============================================================================
--
-- THE QUESTION
-- Two inspections five minutes apart read the live rotation as 162 and then
-- 338 on the same nominal level. Either something animates it, or the reads
-- came from different places.
--
-- WHAT THE FILES SAY
-- sky_rot appears in exactly four files in the entire export, all of them
-- editor or lobby code:
--   core/lib/utils/dev/editor/worldholder.lua
--   core/lib/utils/dev/editor/coreworlddefinition.lua
--   core/lib/utils/dev/editor/coreenvironmentlayer.lua
--   lib/managers/menu/menuscenemanager.lua
-- Zero .environment files and zero .level files contain it.
-- playerstandard.lua has zero occurrences.
--
-- coreworlddefinition reads self._environment.sky_rot once at load and calls
-- create_global_environment_modifier. The only later writers are an editor
-- slider (coreenvironmentlayer, 0-360) and the lobby's _set_sky_rotation_angle.
-- Neither runs in a heist.
--
-- So the file evidence says NOTHING animates the rotation during a heist. That
-- makes the two readings more interesting, not less - and it means the obvious
-- explanations are the wrong ones. Most likely they came from different
-- viewports or different level loads.
--
-- WHAT THIS DOES
-- Samples the rotation on EVERY active viewport over a fixed window and prints
-- a time series. If the value drifts while you stand still, something is
-- animating it. If each viewport reports a different constant, the earlier
-- readings were from different viewports. If it is constant, the 162/338
-- difference was a level or viewport change, not animation.
--
-- READ-ONLY. Uses only calls already proven in this session:
--   managers.viewport:active_viewports()
--   viewport._env_handler
--   handler:get_value(hashed_key)
-- ============================================================================

_G.skyrotwatch = _G.skyrotwatch or {}
local W = _G.skyrotwatch

if W._loaded then return end
W._loaded = true

W.REPORT_FILE = "sky_rot_watch.txt"
W.SAMPLES     = 24        -- number of readings
W.INTERVAL    = 0.5-- seconds between readings  (24 * 0.5 = 12s window)

W.ROT_KEY     = Idstring("sky_orientation/rotation"):key()
W.ROT_STR     = "sky_orientation/rotation"

local function out(s) if log then log("[rotwatch] " .. s) end end

local function write_report(lines)
	local body = table.concat(lines, "\n")
	out(body:gsub("\n", "\n[rotwatch] "))
	local f = io.open(SavePath .. W.REPORT_FILE, "w")
	if f then f:write(body .. "\n"); f:close() end
	return body
end

-- DelayManager is nil in this build; DelayedCalls is proven and takes SECONDS.
local _seq = 0
local function later(seconds, fn)
	local ok = false
	if type(DelayedCalls) == "table" and type(DelayedCalls.Add) == "function" then
		_seq = _seq + 1
		ok = pcall(DelayedCalls.Add, DelayedCalls, "rotwatch_" .. _seq, seconds, fn)
	end
	if not ok and managers and type(managers.delayed_call) == "function" then
		ok = pcall(managers.delayed_call, managers, fn, seconds)
	end
	if not ok and managers and type(managers.add_delayed_callback) == "function" then
		_seq = _seq + 1
		ok = pcall(managers.add_delayed_callback, managers, "rotwatch_" .. _seq, fn, seconds)
	end
	if not ok then fn() end
end

local function level_id()
	return tostring(Global and Global.level_data and Global.level_data.level_id or "<none>")
end

-- ---------------------------------------------------------------------------
-- enumerate every active viewport and read its rotation
-- ---------------------------------------------------------------------------

function W.read_all()
	local rows = {}
	local mgr = managers and managers.viewport
	if not mgr then return rows, "managers.viewport is nil" end

	-- active_viewports() is listed in coreviewportmanager.lua but nothing else
	-- calls it, so it goes under pcall and a failure is reported, not guessed at.
	local ok, list = pcall(function() return mgr:active_viewports() end)
	if ok and type(list) == "table" and #list > 0 then
		for i, vp in ipairs(list) do
			local g, h = pcall(function() return vp._env_handler end)
			if g and h then
				local gv, val = pcall(function() return h:get_value(W.ROT_KEY) end)
				rows[#rows + 1] = {
					label = "active_viewports[" .. i .. "]",
					value = (gv and type(val) == "number") and val or nil,
					err   = gv and nil or tostring(val),
				}
			end
		end
	end

	-- always include first_active_viewport, whatever active_viewports returned
	local ok2, first = pcall(function() return mgr:first_active_viewport() end)
	if ok2 and first then
		local g, h = pcall(function() return first._env_handler end)
		if g and h then
			local gv, val = pcall(function() return h:get_value(W.ROT_KEY) end)
			rows[#rows + 1] = {
				label = "first_active_viewport()",
				value = (gv and type(val) == "number") and val or nil,
				err   = gv and nil or tostring(val),
			}
		end
	end

	if #rows == 0 then return rows, "no viewport exposed an _env_handler" end
	return rows, nil
end

-- ---------------------------------------------------------------------------
-- run the watch
-- ---------------------------------------------------------------------------

function W.run()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	add("=== sky rotation watch (read-only) ===")
	add("data path   = " .. W.ROT_STR)
	add("hashed key  = " .. tostring(W.ROT_KEY))
	add("samples     = " .. W.SAMPLES .. " at " .. W.INTERVAL .. "s  (" ..
		(W.SAMPLES * W.INTERVAL) .. "s window)")
	add("")

	local series = {}   -- label -> {values}
	local sample = 0

	local function tick()
		sample = sample + 1
		local rows, err = W.read_all()
		if sample == 1 then
			add("level at start = " .. level_id())
			add("")
			if err then
				add("viewport enumeration failed: " .. tostring(err))
				add("(active_viewports() may not exist in this build; the")
				add(" first_active_viewport() row below is the one that matters)")
				add("")
			end
		end

		for _, r in ipairs(rows) do
			series[r.label] = series[r.label] or {}
			table.insert(series[r.label], r.value)
		end
		series["__level__"] = series["__level__"] or {}
		table.insert(series["__level__"], level_id())

		if sample >= W.SAMPLES then
			add("level at end = " .. level_id())
			add("")
			add("--- time series ---")
			local labels = {}
			for k in pairs(series) do if k ~= "__level__" then labels[#labels + 1] = k end end
			table.sort(labels)

			if #labels == 0 then
				add("  no viewport produced a reading at any sample.")
			end

			local drifting = false
			for _, label in ipairs(labels) do
				local vals = series[label]
				local nums, nils = {}, 0
				for _, v in ipairs(vals) do
					if type(v) == "number" then nums[#nums + 1] = v else nils = nils + 1 end
				end
				add("  " .. label .. "  (" .. #nums .. " value(s), " .. nils .. " nil)")
				if #nums > 0 then
					local lo, hi = nums[1], nums[1]
					for _, v in ipairs(nums) do
						if v < lo then lo = v end
						if v > hi then hi = v end
					end
					add(string.format("     first=%.4f  last=%.4f  min=%.4f  max=%.4f  spread=%.4f",
						nums[1], nums[#nums], lo, hi, hi - lo))
					if (hi - lo) > 0.0001 then
						drifting = true
						add("     ^ DRIFTING - this value is changing on its own")
					end
					local str = {}
					for i = 1, math.min(#nums, 10) do str[#str + 1] = string.format("%.2f", nums[i]) end
					add("     first 10: " .. table.concat(str, " "))
				end
				add("")
			end

			-- did the level change under us?
			local lv = {}
			for _, l in ipairs(series["__level__"]) do if not lv[l] then lv[l] = true end end
			local nlv = 0
			for _ in pairs(lv) do nlv = nlv + 1 end
			add("distinct levels seen during the window: " .. nlv)
			add("")

			add("--- verdict ---")
			if #labels == 0 then
				add("INCONCLUSIVE - nothing could be read.")
			elseif drifting then
				add("ANIMATED. At least one viewport's rotation changed while you")
				add("stood still, so something in the game is driving it. Compare")
				add("the level log before assuming your own writes will stick.")
			elseif nlv > 1 then
				add("NOT animated, but the level changed mid-window, so the readings")
				add("are not comparable. This is the likeliest explanation for the")
				add("earlier 162 vs 338 discrepancy.")
			else
				add("NOT animated. The rotation is constant on every viewport for")
				add("the whole window, on a single level.")
				add("The earlier 162 vs 338 difference therefore came from a different")
				add("level or a different viewport, not from the game moving the sky.")
				add("Your writes will stick.")
			end
			add("")
			add("  Nothing was changed.")
			write_report(lines)
			return
		end

		later(W.INTERVAL, tick)
	end

	tick()
	return write_report(lines)
end

log("[rotwatch] loaded - samples sky rotation on every active viewport, read-only")