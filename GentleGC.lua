-- GentleGC: run Lua garbage collection on a timer, before the client has to
-- allocate more space (which causes long pauses).
--
-- Changes vs. stock GentleGC (all optional, stock behavior is the fallback):
--  * Timer: uses ClassicAPI's C_Timer.NewTicker when it exists (no per-frame
--    Lua OnUpdate). Falls back to the original OnUpdate accumulator.
--  * Not in combat: a due collection is held until combat ends
--    (PLAYER_REGEN_ENABLED). Set ggc_combat = 1 (or /ggc combat) to collect in combat anyway.
--  * Accurate pause timing via stock debugprofilestop() (ms precision).
--  * Persistent settings in GentleGCDB (/ggc debug, /ggc combat, /ggc interval, /ggc pause, /ggc threshold).
--  * ClassicAPI optional /ggc top [n] addon memory breakdown (GetAddOnMemoryUsage).
--  * Reports go through DEFAULT_CHAT_FRAME (stock 1.12 has no print()).

local DEFAULT_INTERVAL = 180
local MIN_INTERVAL = 30
local MAX_INTERVAL = 1800
local MIN_COOLDOWN = 5

local interval = DEFAULT_INTERVAL
local thresholdPct = 0
local paused = false
local dbInitialized = false

local lastRun = 0
local pending = false
local backend = "none"
local ticker = nil
local elapsedAcc = 0

local totalRuns = 0
local totalFreed = 0
local maxPauseMs = 0

local function say(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GentleGC:|r " .. msg)
	end
end

local function IsFlagOn(val)
	return val ~= nil and val ~= false and val ~= 0
end

local function InitDB()
	if dbInitialized then return end
	if type(GentleGCDB) ~= "table" then
		GentleGCDB = {}
	end
	if type(GentleGCDB.interval) == "number" and GentleGCDB.interval >= MIN_INTERVAL and GentleGCDB.interval <= MAX_INTERVAL then
		interval = math.floor(GentleGCDB.interval)
	else
		GentleGCDB.interval = interval
	end
	if type(GentleGCDB.thresholdPct) == "number" and GentleGCDB.thresholdPct >= 0 and GentleGCDB.thresholdPct <= 99 then
		thresholdPct = math.floor(GentleGCDB.thresholdPct)
	else
		GentleGCDB.thresholdPct = thresholdPct
	end
	if GentleGCDB.paused == true then
		paused = true
	else
		GentleGCDB.paused = false
	end
	if GentleGCDB.debug == true and ggc_debug == nil then
		ggc_debug = 1
	end
	if GentleGCDB.combat == true and ggc_combat == nil then
		ggc_combat = 1
	end
	dbInitialized = true
end

local function FormatMem(kb)
	if kb >= 1024 then
		return string.format("%.2f MB", kb / 1024)
	end
	return string.format("%d KB", math.floor(kb))
end

local function Collect(reason)
	local before = gcinfo()
	local hasProfile = (type(debugprofilestop) == "function")
	local p1 = hasProfile and debugprofilestop() or nil
	local t1 = GetTime()
	collectgarbage()
	local t2 = GetTime()
	local p2 = hasProfile and debugprofilestop() or nil
	local after = gcinfo()

	local elapsedMs = hasProfile and (p2 - p1) or ((t2 - t1) * 1000)
	if elapsedMs < 0 then elapsedMs = 0 end

	lastRun = t2
	pending = false
	elapsedAcc = 0

	totalRuns = totalRuns + 1
	totalFreed = totalFreed + (before - after)
	if elapsedMs > maxPauseMs then
		maxPauseMs = elapsedMs
	end

	if IsFlagOn(ggc_debug) then
		say(string.format("%s: %d KB -> %d KB (freed %d KB) in %.1fms [%s]",
			reason, before, after, before - after, elapsedMs, backend))
	end
end

local function InCombat()
	if IsFlagOn(ggc_combat) then return false end
	return UnitAffectingCombat("player") and true or false
end

-- Called when the interval has elapsed or post-combat triggers.
local function Due(reason)
	if InCombat() then
		pending = true
		if IsFlagOn(ggc_debug) then say("deferred until combat ends") end
		return
	end
	if reason ~= "manual" and lastRun > 0 and (GetTime() - lastRun) < MIN_COOLDOWN then
		pending = false
		return
	end
	Collect(reason)
end

-- Never let an error escape into a timer that would swallow it silently.
local function SafeDue(reason)
	local ok, err = pcall(Due, reason)
	if not ok then say("error: " .. tostring(err)) end
end

local frame = CreateFrame("Frame", "GentleGCFrame")

local function StopTicker()
	if ticker then
		if type(ticker.Cancel) == "function" then
			pcall(ticker.Cancel, ticker)
		end
		ticker = nil
	end
	frame:SetScript("OnUpdate", nil)
	if paused then
		backend = "paused"
	elseif backend == "C_Timer" or backend == "OnUpdate" then
		backend = "none"
	end
end

local function StartTicker()
	if paused then
		StopTicker()
		return
	end
	if ticker or backend == "OnUpdate" then return end
	-- separate flags: the namespace, then the function, then a real probe
	local hasNS = type(C_Timer) == "table"
	local hasTicker = hasNS and type(C_Timer.NewTicker) == "function"
	if hasTicker then
		local ok, handle = pcall(C_Timer.NewTicker, interval, function() SafeDue("timer") end)
		if ok and handle then
			ticker = handle
			backend = "C_Timer"
			return
		end
	end
	backend = "OnUpdate"
	elapsedAcc = 0
	frame:SetScript("OnUpdate", function()
		elapsedAcc = elapsedAcc + arg1
		if elapsedAcc >= interval then
			elapsedAcc = 0
			SafeDue("timer")
		end
	end)
end

local function ShowTopAddons(limit)
	if type(UpdateAddOnMemoryUsage) ~= "function"
		or type(GetAddOnMemoryUsage) ~= "function"
		or type(GetNumAddOns) ~= "function"
		or type(GetAddOnInfo) ~= "function" then
		say("Addon memory breakdown requires ClassicAPI (GetAddOnMemoryUsage).")
		return
	end
	UpdateAddOnMemoryUsage()
	local list = {}
	local n = GetNumAddOns()
	local i
	for i = 1, n do
		local name, title = GetAddOnInfo(i)
		local mem = GetAddOnMemoryUsage(i)
		if mem and mem > 0 then
			table.insert(list, { name = title or name or ("#" .. i), mem = mem })
		end
	end
	table.sort(list, function(a, b) return a.mem > b.mem end)
	local count = table.getn(list)
	if count == 0 then
		say("No addon memory data reported.")
		return
	end
	if limit > count then limit = count end
	say(string.format("Top %d addons by Lua memory:", limit))
	for i = 1, limit do
		say(string.format("  %d. %s - %s", i, list[i].name, FormatMem(list[i].mem)))
	end
end

local function PrintHelp()
	say("Commands:")
	say("  /ggc (or /ggc now) - collect garbage now and report")
	say("  /ggc status - show backend, memory/threshold, and session stats")
	say("  /ggc debug - toggle per-run debug reports")
	say("  /ggc combat - toggle collecting during combat")
	say("  /ggc pause - pause/resume automatic collection")
	say(string.format("  /ggc interval <%d-%d> - set timer interval in seconds (default %d)", MIN_INTERVAL, MAX_INTERVAL, DEFAULT_INTERVAL))
	say("  /ggc threshold <0|50-99> - auto-collect post-combat if memory >= % of GC threshold (0=off)")
	say("  /ggc top [n] - show top addons by Lua memory (ClassicAPI)")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" then
		if arg1 == "GentleGC" then
			InitDB()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		InitDB()
		StartTicker()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then
			SafeDue("post-combat")
		elseif thresholdPct > 0 and not paused then
			local mem, thresh = gcinfo()
			if thresh and thresh > 0 and ((mem / thresh) * 100) >= thresholdPct then
				SafeDue("threshold")
			end
		end
	end
end)

SLASH_GGC1 = "/ggc"
SLASH_GGC2 = "/gentlegc"
SlashCmdList["GGC"] = function(msg)
	InitDB()
	msg = string.gsub(msg or "", "^%s*(.-)%s*$", "%1")
	msg = string.lower(msg)

	if msg == "" or msg == "now" or msg == "collect" then
		local was = ggc_debug
		ggc_debug = 1
		Collect("manual")
		ggc_debug = was
		return
	end

	local _, _, cmd, rest = string.find(msg, "^(%S+)%s*(.*)$")
	if cmd == "debug" then
		if IsFlagOn(ggc_debug) then
			ggc_debug = nil
			GentleGCDB.debug = false
		else
			ggc_debug = 1
			GentleGCDB.debug = true
		end
		say("debug " .. (IsFlagOn(ggc_debug) and "on" or "off"))
	elseif cmd == "combat" then
		if IsFlagOn(ggc_combat) then
			ggc_combat = nil
			GentleGCDB.combat = false
		else
			ggc_combat = 1
			GentleGCDB.combat = true
		end
		say("combat collection " .. (IsFlagOn(ggc_combat) and "on" or "off"))
	elseif cmd == "pause" or cmd == "toggle" then
		paused = not paused
		GentleGCDB.paused = paused
		if paused then
			StopTicker()
			say("automatic GC paused")
		else
			StartTicker()
			say("automatic GC resumed [" .. backend .. "]")
		end
	elseif cmd == "interval" then
		local sec = tonumber(rest)
		if not sec or sec < MIN_INTERVAL or sec > MAX_INTERVAL then
			say(string.format("Usage: /ggc interval <%d-%d> (current: %ds)", MIN_INTERVAL, MAX_INTERVAL, interval))
			return
		end
		interval = math.floor(sec)
		GentleGCDB.interval = interval
		elapsedAcc = 0
		if not paused then
			StopTicker()
			StartTicker()
		end
		say(string.format("interval set to %ds [%s]", interval, backend))
	elseif cmd == "threshold" then
		local pct = tonumber(rest)
		if not pct or (pct ~= 0 and (pct < 50 or pct > 99)) then
			say(string.format("Usage: /ggc threshold <0|50-99> (current: %d%%)", thresholdPct))
			return
		end
		thresholdPct = math.floor(pct)
		GentleGCDB.thresholdPct = thresholdPct
		say(thresholdPct == 0 and "threshold auto-collect disabled" or string.format("threshold auto-collect set to %d%%", thresholdPct))
	elseif cmd == "top" then
		local limit = tonumber(rest) or 5
		if limit < 1 then limit = 1 elseif limit > 20 then limit = 20 end
		ShowTopAddons(math.floor(limit))
	elseif cmd == "status" then
		local mem, thresh = gcinfo()
		local pct = (thresh and thresh > 0) and math.floor((mem / thresh) * 100) or 0
		local lastStr = (lastRun > 0) and string.format("%ds ago", math.floor(GetTime() - lastRun)) or "never"
		say(string.format(
			"backend=%s interval=%ds paused=%s combat=%s pending=%s memory=%d/%d KB (%d%%) threshold=%s last=%s runs=%d freed=%s maxPause=%.1fms debug=%s",
			backend,
			interval,
			paused and "yes" or "no",
			IsFlagOn(ggc_combat) and "yes" or "no",
			pending and "yes" or "no",
			mem,
			thresh or 0,
			pct,
			thresholdPct > 0 and (thresholdPct .. "%") or "off",
			lastStr,
			totalRuns,
			FormatMem(totalFreed > 0 and totalFreed or 0),
			maxPauseMs,
			IsFlagOn(ggc_debug) and "on" or "off"))
	elseif cmd == "help" or cmd == "?" then
		PrintHelp()
	else
		say("Unknown command: " .. cmd)
		PrintHelp()
	end
end
