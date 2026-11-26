# GentleGC (Patched for WoW 1.12 / Turtle WoW)

> Run Lua garbage collection on a combat-aware timer before the client hits its allocation threshold and causes long stop-the-world pauses.

> [!WARNING]
> **Not needed if you use `WeirdUtils.dll`:** [WeirdUtils](https://codeberg.org/MarcelineVQ/WeirdUtils/) (`weirdperformance`) already replaces the stock Lua 5.0 allocator and stop-the-world garbage collector with an incremental/generational collector (~9ms chunks). If you have `WeirdUtils.dll` installed, you do **not** need this addon.

## Client Mods Used
| Mod | Purpose in this addon | Required? |
|---|---|---|
| ClassicAPI | `C_Timer.NewTicker` (zero `OnUpdate` overhead) and `GetAddOnMemoryUsage` (`/ggc top`) | Optional |

*(The addon works without any client mods; it falls back to a lightweight `OnUpdate` accumulator when `ClassicAPI` is absent.)*

## Features
- **Scheduled Garbage Collection:** Collects Lua garbage every 180 seconds by default (configurable from `30` to `1800` seconds).
- **Combat Deferral:** Holds due collections while in combat and runs them once on `PLAYER_REGEN_ENABLED` (can be overridden with `/ggc combat` or `ggc_combat = 1`).
- **Accurate Pause Profiling:** Measures real GC pause duration in milliseconds using stock `debugprofilestop()`.
- **Threshold Guard (Optional):** Can automatically collect post-combat when Lua memory reaches a configurable percentage of `gcinfo()`'s GC threshold (`/ggc threshold <50-99>`).
- **Addon Memory Inspector (ClassicAPI):** `/ggc top [n]` lists the top memory-consuming addons to help identify what is causing GC pauses.
- **Persistent Settings:** Saves `debug`, `combat`, `interval`, `paused`, and `thresholdPct` in `GentleGCDB`.

## What Was Added / Improved
- **Fixed:** Trimmed leading/trailing whitespace and added explicit command matching in `/ggc` so typos or `/ggc status ` no longer trigger an unintended `collectgarbage()` pause.
- **Fixed:** Replaced frame-cached `GetTime()` delta (which always reported `0.000s` in-game) with `debugprofilestop()` for accurate millisecond pause reporting.
- **Fixed:** Guarded `ggc_debug = 0` / `ggc_combat = 0` so `0` is treated as off rather than Lua-truthy.
- **Added:** `SavedVariables: GentleGCDB` persistence, `/ggc combat`, `/ggc pause`, `/ggc interval <sec>`, `/ggc threshold <pct>`, `/ggc top [n]` (ClassicAPI), `/ggc help`, and `/gentlegc` alias.
- **Improved:** `/ggc status` now displays memory vs. GC threshold (`KB / threshold KB (%)`), last run time, total runs, total freed memory, and max pause time.

## Usage
- `/ggc` or `/ggc now` — Run `collectgarbage()` immediately and print a report.
- `/ggc status` — Show timer backend, interval, combat/pause state, memory vs. GC threshold, and session stats.
- `/ggc debug` — Toggle per-run debug reports (also synced with `ggc_debug = 1`).
- `/ggc combat` — Toggle collecting during combat (also synced with `ggc_combat = 1`).
- `/ggc pause` — Pause or resume automatic collection.
- `/ggc interval <30-1800>` — Change collection interval in seconds (default `180`).
- `/ggc threshold <0|50-99>` — Auto-collect post-combat if memory reaches `%` of GC threshold (`0` disables).
- `/ggc top [n]` — Show top `n` (default `5`) addons by Lua memory (requires ClassicAPI).
- `/ggc help` — Print command list.

## Credits & License
- Original addon: Weird Vibes (`GentleGC` v1.0)
- License: Same as original addon.
