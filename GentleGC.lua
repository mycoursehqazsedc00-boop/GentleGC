-- GentleGC: run Lua garbage collection on a timer, before the client has to
-- allocate more space (which causes long pauses).
--
-- Changes vs. stock GentleGC (all optional, stock behavior is the fallback):
--  * Timer: uses ClassicAPI's C_Timer.NewTicker when it exists (no per-frame
--    Lua OnUpdate). Falls back to the original OnUpdate accumulator.
--  * Not in combat: a due collection is held until combat ends
--    (PLAYER_REGEN_ENABLED). Set ggc_combat = 1 to collect in combat anyway.
--  * Reports go through DEFAULT_CHAT_FRAME (stock 1.12 has no print()).
--  * /ggc, /ggc debug, /ggc status.
--
-- Confirmed (ClassicAPI docs/API.md): C_Timer.NewTicker(seconds, cb) returns a
-- handle with :Cancel(); callback errors are swallowed silently (so the
-- callback is wrapped in pcall below); collectgarbage() with no argument is
-- unchanged. NOT verified on a live client: everything in this file.

local INTERVAL = 180

local lastRun = 0
local pending = false
local backend = "none"
local ticker = nil
local elapsedAcc = 0

local function say(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GentleGC:|r " .. msg)
	end
end

local function Collect(reason)
	local before = gcinfo()
	local t1 = GetTime()
	collectgarbage()
	local t2 = GetTime()
	local after = gcinfo()
	lastRun = t2
	pending = false
	if ggc_debug then
		say(string.format("%s: %d KB -> %d KB (freed %d KB) in %.3fs [%s]",
			reason, before, after, before - after, t2 - t1, backend))
	end
end

local function InCombat()
	if ggc_combat then return false end
	return UnitAffectingCombat("player") and true or false
end

-- Called when the interval has elapsed.
local function Due(reason)
	if InCombat() then
		pending = true
		if ggc_debug then say("deferred until combat ends") end
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

local function StartTicker()
	if ticker or backend == "OnUpdate" then return end
	-- separate flags: the namespace, then the function, then a real probe
	local hasNS = type(C_Timer) == "table"
	local hasTicker = hasNS and type(C_Timer.NewTicker) == "function"
	if hasTicker then
		local ok, handle = pcall(C_Timer.NewTicker, INTERVAL, function() SafeDue("timer") end)
		if ok and handle then
			ticker = handle
			backend = "C_Timer"
			return
		end
	end
	backend = "OnUpdate"
	frame:SetScript("OnUpdate", function()
		elapsedAcc = elapsedAcc + arg1
		if elapsedAcc >= INTERVAL then
			elapsedAcc = 0
			SafeDue("timer")
		end
	end)
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then
		StartTicker()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then SafeDue("post-combat") end
	end
end)

SLASH_GGC1 = "/ggc"
SlashCmdList["GGC"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "debug" then
		if ggc_debug then ggc_debug = nil else ggc_debug = 1 end
		say("debug " .. (ggc_debug and "on" or "off"))
	elseif msg == "status" then
		say(string.format("backend=%s interval=%ds pending=%s memory=%d KB debug=%s",
			backend, INTERVAL, pending and "yes" or "no", gcinfo(), ggc_debug and "on" or "off"))
	else
		local was = ggc_debug
		ggc_debug = 1
		Collect("manual")
		ggc_debug = was
	end
end
