-- RECONSTRUCTED model of stock GentleGC (OnUpdate accumulator, 180s, collectgarbage).
-- Reconstructed from the behavior I read earlier; not a verbatim copy.
return function(W)
  local acc, collects = 0, {}
  return {
    onupdate = function(dt)
      acc = acc + dt
      if acc >= 180 then acc = 0; collects[#collects + 1] = W.now end
    end,
    collects = collects,
  }
end
