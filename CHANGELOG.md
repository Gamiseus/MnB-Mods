# Mods changelog

One changelog for every mod in this folder, grouped by mod. Each mod has its own version, `Major.Minor.Patch`, with the same meaning as QuarterMaster's:

- **Major**: the mod is redone from the ground up.
- **Minor**: large update; things behave noticeably differently.
- **Patch**: fixes and small changes that keep behaviour.

## PerfKit

### 1.4.0

- `alliedFrontLine` reads the front from the per-frame sorting instead of walking every soldier; with no flagged Allied soldier the game's own function answers
- `numberOfOGs`, asked before every shot, counts the award holders once per frame and again when an award is given
- `closestflaggedEnemy` tries the nearest enemy first: same answer, a fraction of the sight checks
- a machine gunner's target search no longer builds a debug text for every enemy out of range
- settled debris: chunks that come due together are redrawn one per frame instead of all in one
- profile report: the six most common particle types, the settled debris count, and the graphics card, processor threads and window size
- `PerfKit.Near.alliedFront`, `closestFlagged`, `originals`, `awardGiven`; `PerfKit.Particles.MAX_REDRAWS`

### 1.3.1

- release zip holds a single `PerfKit/` folder again (v2.0's zips had the files loose)
- marked as conflicting with GCore: installed together, the two break each other
- the per-frame sorting also answers `axisNearby`, `alliedNearby`, `alliedAround`, `alliedCloseBy`, `friendlyNearby`, `friendlyNearby2`, `soldierNearby` and `checkObstruction`
- `convertedId` looks a soldier's place up instead of walking the list; the place is checked before use
- `propagandaGathering` does nothing when no pamphlet is on the map
- `PerfKit.Near.countOf`, `countOwn`, `countAll`, `indexOf`, `decalNamed`

### 1.3.0

- faster enemy-nearby checks (option, on by default): `enemyNearby`, `friendliesCloseToTarget` and `enemyCqc` count from a per-frame sorting of the soldiers by faction and map column instead of walking every soldier
- a soldier who changes sides is counted on his new side one frame later; everything else as the game counts
- explosions: the explosion's building is worked out once, not once per soldier; in the open no soldier's building is looked up
- explosions: the cover-save sound is copied only when it plays, not for every soldier on the map
- `PerfKit.Near.count(soldier, radius, each)`, `PerfKit.buildingOf`, `PerfKit.laterSound`

### 1.2.1

- profiler no longer halves the frame rate: calls are only counted during calibration, and the most-called functions are put back after two frames and left alone
- building checks (`getOccupantBuildingId`, `insideBuilding`) and `slowedDown` look at the kind of ground area before working out a distance
- explosion damage asks once per soldier whether soldier and explosion share a building, not up to three times

### 1.2.0

- larger JIT code cache (option, on by default): 20000 traces and 32 MB instead of LuaJIT's 1000 and 512 KB, so big battles stop throwing compiled code away
- expired particles are removed in one pass after the game's update instead of one `table.remove` each; a particle behind an expired one no longer skips a frame
- overlay (F11): JIT line with traces compiled, given up, and times everything was thrown away
- profiler: the particle update's parts are listed separately (`PerfKit.Particles.gameUpdate`, `settle`, `expire`); report label says which JIT cache was in use
- `PerfKit.Particles.kill(list, i, particle)`, `runSwept(list, fn, dt)`

### 1.1.1

- fixed the once-a-second hitch with many fires and decals: the game's fire update looks each decal name up instead of pattern-searching it per fire
- `slowedDown` asks for the tactical buff once per call instead of once per ground area; same result
- profiler: calibration lasts at least 1.25 s, so once-a-second work is seen
- profiler: report names the slowest frame and the functions it went to

### 1.1.0

- profiler rewritten: times every named function on the game's own thread; no second thread, so it cannot freeze the game
- report: own and total time per frame, calls per frame, functions called too often to time, JIT compile and flush counts, measuring cost
- LuaJIT's line sampler kept as an option, off by default (froze the game again while left idle); report says to restart afterwards
- `PerfKit.Profiler.start(seconds, label, how)`

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

### 1.0.1

- release zip holds a single `SaveGuard/` folder again (v2.0's zips had the files loose)
- marked as conflicting with GCore: installed together, the two break each other

### 1.0.0

- new mod, from GCore's serializer, unchanged

## Wayfinder

### 1.0.1

- release zip holds a single `Wayfinder/` folder again (v2.0's zips had the files loose)
- marked as conflicting with GCore: installed together, the two break each other
- path requests no longer copy a cost grid to the worker each time; the grid is sent once per rebuild and the worker works out each unit's costs

### 1.0.0

- new mod, from GCore's pathfinding
- normal movement uses the background solver (option)
- safe-destination check once per order, and its option now works
- worker thread stops on quit
- answers for an old destination are dropped

## TrueSight

### 1.0.1

- release zip holds a single `TrueSight/` folder again (v2.0's zips had the files loose)
- marked as conflicting with GCore: installed together, the two break each other

### 1.0.0

- new mod, from GCore's line of sight
- obstacle world rebuilt on change or every 10 frames, not every frame

## SquadTactics

### 2.0.1

- release zip holds a single `SquadTactics/` folder again (v2.0's zips had the files loose)
- marked as conflicting with TacticalOverhaul: installed together, the two break each other
- fixed the game locking up with more than 100 soldiers under the player's command: the Germans' answer to an oversized squad looped while a 1-100 roll was under the squad's size; the chance is capped at 90
- groups of more than 24 soldiers are placed in a plain block; placing 420 spot by spot took about a second
- log line before placing a group of 50 or more

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

### 2.0.1

- release zip holds a single `SeasonalEvents/` folder again (v2.0's zips had the files loose)
- marked as conflicting with GSpecialEvents: installed together, the two break each other

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
