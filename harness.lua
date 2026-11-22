-- Mock 1.12 client for GentleGC. Runs under Lua 5.3 (texlua): logic/trace tests only,
-- NOT a proof of Lua 5.0 compatibility.
local H = {}

function H.new(opts)
  opts = opts or {}
  local W = { now = 0, combat = false, mem = 20000, collects = {}, chat = {}, trace = {}, tickers = {}, frames = {} }
  local env = {}
  setmetatable(env, { __index = function(_, k)
    local v = ({ string = string, table = table, math = math, type = type, pcall = pcall, tostring = tostring })[k]
    return v
  end })
  local function T(msg) W.trace[#W.trace + 1] = string.format("[%8.3f] %s", W.now, msg) end
  W.T = T

  env.GetTime = function() return W.now end
  env.gcinfo = function() return W.mem, W.mem * 2 end
  env.collectgarbage = function()
    if W.gcError then error(W.gcError) end
    W.collects[#W.collects + 1] = W.now
    T("collectgarbage()")
    W.mem = W.mem - 5000 -- each collect frees 5000 KB
  end
  env.UnitAffectingCombat = function() return W.combat and 1 or nil end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) W.chat[#W.chat + 1] = m; T("chat: " .. m) end }
  env.CreateFrame = function(_, name)
    local f = { scripts = {}, events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:SetScript(n, fn) self.scripts[n] = fn; T("SetScript " .. n) end
    W.frames[#W.frames + 1] = f
    return f
  end
  env.SlashCmdList = {}

  if opts.timer == "ok" then
    env.C_Timer = { NewTicker = function(sec, cb)
      local t = { sec = sec, cb = cb, next = W.now + sec, cancelled = false }
      function t:Cancel() self.cancelled = true end
      W.tickers[#W.tickers + 1] = t
      T("C_Timer.NewTicker(" .. sec .. ")")
      return t
    end }
  elseif opts.timer == "nons" then
    -- no C_Timer
  elseif opts.timer == "nofn" then
    env.C_Timer = {}
  elseif opts.timer == "throws" then
    env.C_Timer = { NewTicker = function() error("boom") end }
  elseif opts.timer == "nilret" then
    env.C_Timer = { NewTicker = function() return nil end }
  end

  local chunk = assert(loadfile("/home/claude/GentleGC/GentleGC.lua", "t", env))
  chunk()
  W.env = env
  W.frame = W.frames[1]

  function W.fire(e) env.event = e; W.frame.scripts.OnEvent() end
  -- advance the simulated clock in frames of dt, running tickers (C_Timer walks per frame) and OnUpdate
  function W.run(seconds, dt, hook)
    dt = dt or 0.016
    local stop = W.now + seconds
    while W.now < stop - 1e-9 do
      W.now = W.now + dt
      if hook then hook(W.now) end
      for _, t in ipairs(W.tickers) do
        if not t.cancelled and W.now >= t.next then
          t.next = t.next + t.sec
          pcall(t.cb) -- C_Timer swallows errors, like the real one
        end
      end
      if W.frame.scripts.OnUpdate then
        env.arg1 = dt
        W.frame.scripts.OnUpdate()
      end
    end
  end
  return W
end

return H
