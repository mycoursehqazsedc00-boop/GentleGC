Gentle Garbage Collection
---
Automatically clear garbage without allocating more space, which causes long pauses for some players.

Garbage collection pauses are caused by having a lot of garbage to check and by needing to allocate space when there's too much garbage. This addon attempts to avoid the latter by clearing garbage before the game decides to allocate more space for it.
The best way to avoid the former is to turn off weighty addons you don't use often, pfquest for instance can use 100mb of addon memory while doing nothing at all.

This addon runs once every 3 minutes.

**Commands**
- `/ggc` - collect now and print a report
- `/ggc debug` - toggle a report on every automatic run (same switch as `/run ggc_debug = 1`)
- `/ggc status` - show timer backend, interval, pending state and Lua memory

**Behavior**
- If you are in combat when a run is due, it waits until combat ends. Set `ggc_combat = 1` (`/run ggc_combat = 1`) to collect in combat anyway, as the original did.
- With [ClassicAPI](https://github.com/brues-code/ClassicAPI) installed the run is scheduled with `C_Timer.NewTicker` instead of a per-frame `OnUpdate`. Without it the original `OnUpdate` timer is used. Nothing else is required.
