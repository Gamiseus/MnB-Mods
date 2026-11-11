# Mods changelog

One changelog for every mod in this folder, grouped by mod. Each mod has its own version, `Major.Minor.Patch`, with the same meaning as QuarterMaster's:

- **Major**: the mod is redone from the ground up.
- **Minor**: large update; things behave noticeably differently.
- **Patch**: fixes and small changes that keep behaviour.

## PerfKit

### 1.0.1

- fixed game freezing when a profile finished: the report is saved first and the sampler is left on, idle, instead of being stopped
- profiler: second and later profiles reuse the running sampler

### 1.0.0

- new mod, from GCore's performance parts; replaces no game files
- decal baking: tracked by identity, redraws only the chunk that changed
- settled debris baked until it expires or the broom is used
- off-screen particles skipped; colour set only when it changes
- particle registry: `PerfKit.Particles.register`, `spawn`, `keepLive`
- profiler (Ctrl+F11): 10 seconds, report in `Mods/qm/perfkit-profile.txt`
- texture atlas (option, off by default)
- overlay (F11): FPS, draw calls, baked counts, atlas
- log growth warning in debug mode
- dropped from GCore: whole-file particle system, forced VSync off, benchmark keys

## SaveGuard

### 1.0.0

- new mod, from GCore's serializer, unchanged

## Wayfinder

### 1.0.0

- new mod, from GCore's pathfinding
- normal movement uses the background solver (option)
- safe-destination check once per order, and its option now works
- worker thread stops on quit
- answers for an old destination are dropped

## TrueSight

### 1.0.0

- new mod, from GCore's line of sight
- obstacle world rebuilt on change or every 10 frames, not every frame

## SquadTactics

### 2.0.0

- rewritten; was TacticalOverhaul
- contact reactions moved from a 550-line patch into `combat_reaction.lua`
- threat scan about 5 times a second per moving soldier, sight checks to the 4 nearest enemies only; none while standing still
- reaction state kept beside the soldier, not saved
- move orders: two one-line hooks around the game's own code, no copied game code
- fixed crash with Squad Size Limit set to OFF
- added option: React To Contact
- needs Wayfinder; uses TrueSight when present

## SeasonalEvents

### 2.0.0

- rewritten; was GSpecialEvents
- settings come from Mod Settings only; `saveSpecialEvents.lua` no longer used
- changing the event in Mod Settings applies while playing
- `SpecialEvents.register(name, module)` for other mods
- hostility check no longer wrapped in `pcall` on every call
- fixed zombie speed option being applied twice
- fixed "Auto" falling back to Halloween without a calendar
- removed empty Xmas, Remembrance and general modules (those events run as the game has them)
- no longer needs GCore

## Removed

- GCore: split into PerfKit, SaveGuard, Wayfinder and TrueSight
- GConsole, GDumper: replaced by QuarterMaster's debug mode and developer commands
