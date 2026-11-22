package.path = "/home/claude/tests/?.lua;" .. package.path
local H = require("harness")
local stock = dofile("/home/claude/tests/reference_stock.lua")

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and ("  -> " .. detail) or "")) end
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.05) end
local function list(t) local s = {} for i, v in ipairs(t) do s[i] = string.format("%.1f", v) end return "{" .. table.concat(s, ",") .. "}" end
local function backendOf(W) W.env.SlashCmdList.GGC("status"); return W.chat[#W.chat] end

print("== 1. Backend selection (separate probes, no merged flag) ==")
for _, c in ipairs({
  { "ok", "backend=C_Timer" }, { "nons", "backend=OnUpdate" }, { "nofn", "backend=OnUpdate" },
  { "throws", "backend=OnUpdate" }, { "nilret", "backend=OnUpdate" } }) do
  local W = H.new({ timer = c[1] }); W.fire("PLAYER_ENTERING_WORLD")
  check("timer=" .. c[1], backendOf(W):find(c[2], 1, true) ~= nil, backendOf(W))
end

print("== 2. Timing: collect every 180s ==")
for _, mode in ipairs({ "ok", "nons" }) do
  local W = H.new({ timer = mode }); W.fire("PLAYER_ENTERING_WORLD")
  W.run(1000)
  local c = W.collects
  check(mode .. ": 5 collects in 1000s", #c == 5, list(c))
  check(mode .. ": first at ~180s", c[1] and near(c[1], 180, 0.1), c[1] and tostring(c[1]))
  check(mode .. ": spacing ~180s", c[2] and near(c[2] - c[1], 180, 0.1))
end

print("== 3. Back-to-back vs reconstructed stock (same frame sequence) ==")
do
  local W = H.new({ timer = "nons" }); W.fire("PLAYER_ENTERING_WORLD")
  local S = stock(W)
  W.run(3600, 0.016, function() S.onupdate(0.016) end)
  check("fallback path == stock: same count", #W.collects == #S.collects, #W.collects .. " vs " .. #S.collects)
  local same = true
  for i = 1, #S.collects do if not near(W.collects[i], S.collects[i], 0.001) then same = false end end
  check("fallback path == stock: same timestamps", same, list(W.collects) .. " vs " .. list(S.collects))
  local W2 = H.new({ timer = "ok" }); W2.fire("PLAYER_ENTERING_WORLD"); W2.run(3600)
  -- stock resets its accumulator to 0 and so drifts ~0.01-0.1s late per cycle; the ticker does not.
  check("C_Timer path count within 1 of stock (boundary at 3600s)", math.abs(#W2.collects - #S.collects) <= 1, #W2.collects .. " vs " .. #S.collects)
  local within = true
  for i = 1, #S.collects do if not near(W2.collects[i], S.collects[i], 0.5) then within = false end end
  check("C_Timer path within 0.5s of stock for every shared collect", within, list(W2.collects) .. " vs " .. list(S.collects))
  local exact = true
  for i = 1, #W2.collects do if not near(W2.collects[i], 180 * i, 0.05) then exact = false end end
  check("C_Timer path is drift-free (n*180s)", exact)
  -- variable frame time (hitching): total time still governs
  local W3 = H.new({ timer = "nons" }); W3.fire("PLAYER_ENTERING_WORLD")
  local S3 = stock(W3)
  local i = 0
  W3.run(1000, 0.1, function() S3.onupdate(0.1) end)
  check("coarse 100ms frames: fallback == stock", #W3.collects == #S3.collects)
end

print("== 4. Combat deferral ==")
do
  local W = H.new({ timer = "ok" }); W.fire("PLAYER_ENTERING_WORLD")
  W.run(170); W.combat = true
  W.run(250) -- ticks at 180 and 360 both inside combat (t=420 now)
  check("no collect during combat", #W.collects == 0, list(W.collects))
  W.combat = false; W.fire("PLAYER_REGEN_ENABLED")
  check("exactly one collect at combat end (two ticks coalesced)", #W.collects == 1, list(W.collects))
  W.fire("PLAYER_REGEN_ENABLED")
  check("regen again with nothing pending: no extra collect", #W.collects == 1)
  W.run(200)
  check("timer keeps running after deferral", #W.collects >= 2, list(W.collects))
  local W2 = H.new({ timer = "ok" }); W2.fire("PLAYER_ENTERING_WORLD")
  W2.fire("PLAYER_REGEN_ENABLED")
  check("regen with nothing pending: no collect", #W2.collects == 0)
  local W3 = H.new({ timer = "ok" }); W3.fire("PLAYER_ENTERING_WORLD")
  W3.env.ggc_combat = 1; W3.combat = true; W3.run(185)
  check("ggc_combat=1 collects in combat (stock behavior)", #W3.collects == 1)
  local W4 = H.new({ timer = "nons" }); W4.fire("PLAYER_ENTERING_WORLD")
  W4.combat = true; W4.run(190); W4.combat = false; W4.fire("PLAYER_REGEN_ENABLED")
  check("OnUpdate path defers + resumes too", #W4.collects == 1)
end

print("== 5. Robustness ==")
do
  local W = H.new({ timer = "ok" }); W.fire("PLAYER_ENTERING_WORLD")
  W.gcError = "gc failed"; W.run(185)
  local sawErr = false
  for _, m in ipairs(W.chat) do if m:find("error: ", 1, true) then sawErr = true end end
  check("collect error is reported, not swallowed", sawErr)
  W.gcError = nil; W.run(200)
  check("ticker survives an error and collects next time", #W.collects == 1, list(W.collects))
  local E = H.new({ timer = "ok" })
  for i = 1, 50 do E.fire("PLAYER_ENTERING_WORLD") end
  check("50 loading screens -> one ticker", #E.tickers == 1, tostring(#E.tickers))
  E.run(400)
  check("50 loading screens -> still 2 collects in 400s", #E.collects == 2, list(E.collects))
  local F = H.new({ timer = "nons" })
  for i = 1, 50 do F.fire("PLAYER_ENTERING_WORLD") end
  F.run(400)
  check("OnUpdate path: 50 loading screens -> still 2 collects", #F.collects == 2, list(F.collects))
end

print("== 6. Debug output / slash commands ==")
do
  local W = H.new({ timer = "ok" }); W.fire("PLAYER_ENTERING_WORLD")
  W.run(185)
  check("debug off: timer collect prints nothing", #W.chat == 0, tostring(#W.chat))
  W.env.ggc_debug = 1; W.run(180)
  check("ggc_debug=1 (stock switch) prints a report", #W.chat == 1 and W.chat[1]:find("KB ->", 1, true) ~= nil, W.chat[1])
  check("report shows freed memory and backend", W.chat[1]:find("freed 5000 KB", 1, true) and W.chat[1]:find("[C_Timer]", 1, true))
  W.env.ggc_debug = nil; local n = #W.chat
  W.env.SlashCmdList.GGC("")
  check("/ggc collects now and reports", #W.collects == 3 and #W.chat == n + 1, list(W.collects))
  check("/ggc does not leave debug on", W.env.ggc_debug == nil)
  W.env.SlashCmdList.GGC("debug"); check("/ggc debug toggles on", W.env.ggc_debug ~= nil)
  W.env.SlashCmdList.GGC("DEBUG"); check("/ggc DEBUG toggles off (case-insens.)", W.env.ggc_debug == nil)
  W.env.SlashCmdList.GGC(nil); check("/ggc with nil msg does not error", true)
end

print("== 7. Trace (C_Timer path, combat deferral, 400s) ==")
do
  local W = H.new({ timer = "ok" }); W.env.ggc_debug = 1; W.fire("PLAYER_ENTERING_WORLD")
  W.run(179); W.combat = true; W.run(2); W.combat = false; W.now = W.now + 5; W.fire("PLAYER_REGEN_ENABLED"); W.run(200)
  for _, l in ipairs(W.trace) do print("  " .. l) end
end

print(string.format("\nRESULT: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
