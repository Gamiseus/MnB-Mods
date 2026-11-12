# PerfKit

Makes long battles cheaper to draw and update. It replaces none of the game's files: it swaps three drawing loops for one call each and wraps three particle functions. Every feature has a switch in Mod Settings, and with a switch off the game's own code runs.

| Feature | What happens |
|---|---|
| Bake Decals | Blood, craters and rubble are drawn once onto canvases that tile the map. A few canvases are drawn per frame instead of every decal. |
| Bake Settled Debris | A casing or piece of debris that stopped moving is taken off the game's particle list and drawn onto a canvas until its lifespan ends or the broom is used. |
| Skip Off-Screen Particles | Particles outside the view are not drawn, and the colour is only set when it changes. |

| Texture Atlas (experimental, off by default) | Small sprites are copied onto a few shared textures, and a draw of one becomes a draw of its rectangle there, so the graphics card gets fewer, larger draw calls. About 130 MB more video memory. |

F11 shows an overlay with FPS, draw calls and how much is baked. In QuarterMaster's debug mode, the mod also warns when the log is growing fast (a mod printing every frame).

## JIT code cache

The game runs on LuaJIT, which compiles the code that runs often. It keeps at most 1000 compiled pieces and 512 KB of machine code; at the limit it throws all of it away and starts again, and until the busy code is compiled again it runs several times slower. A large battle reaches that limit every few seconds.

The option **Larger JIT Code Cache** (on by default) raises the limits to 20000 pieces and 32 MB. The last line of the overlay (F11) counts how often everything was thrown away since the game started; with the option on it should stay at 0 or close to it.

## Enemies near a soldier

The game asks "how many enemies are near this soldier?" by looking at every soldier on the map, for each soldier that asks. With 3,000 soldiers that was most of a frame.

With **Faster Enemy-Nearby Checks** (on by default) the soldiers are sorted once per frame by faction and by column of the map, and a question looks only at the other factions' soldiers in the columns within reach. This covers the game's counts of soldiers near a soldier: `enemyNearby`, `friendliesCloseToTarget`, `enemyCqc`, `axisNearby`, `alliedNearby`, `alliedAround`, `alliedCloseBy`, `friendlyNearby`, `friendlyNearby2`, `soldierNearby` and `checkObstruction`. The same option makes `convertedId` look a soldier's place in the list up instead of walking it, and lets `propagandaGathering` skip its walk over every decal when no pamphlet is on the map.

The counts are the game's, with one limit: a soldier who changes sides is counted on his new side from the next frame. Soldiers added or removed, deaths and movement within the frame are all seen at once. With the option off, the game's own loops run.

Another mod that changes the counting inside these functions is bypassed while the option is on; turn the option off for such a mod. A pamphlet dropped in the very frame another decal is removed is noticed one frame later.

## Game loops made cheaper

Some of the game's own loops are patched to do the same thing with less work:

- **Fire update.** Once a second the game checked every decal's name with a pattern search, for every fire. With many fires and decals that was a hitch every second. Each name is now looked up.
- **`slowedDown`.** It asked whether a soldier has the tactical buff once per ground area; it now asks once per call.
- **Ground areas.** The game keeps trees, cover, water and buildings in one list and walks all of it to ask "is this soldier in a building?" or "is he on slow ground?". Those checks now look at the kind of area first and work out a distance only for an area that could matter. Explosion damage asked whether soldier and explosion share a building up to three times per soldier; it asks once.
- **Explosions.** Every explosion checks every soldier on the map. The explosion's own building is now worked out once per explosion (and when it is in the open, no soldier's building is looked up), and the cover-save sound is copied only for a soldier it is played for. The random numbers are drawn as before.
- **Particle removal.** The game took each expired particle out with `table.remove`, moving every particle behind it; the lower the frame rate, the more expire per frame. They are now marked and taken out together when the update returns. One visible-in-theory difference: in the game, the particle behind an expired one skipped that frame's update; it no longer does.

## Finding out what is slow

Press **Ctrl+F11** in a battle that runs badly. PerfKit measures for 10 seconds and writes `Mods/qm/perfkit-profile.txt` (the first part also goes to the log). Press it again to stop early. The report has:

- frame times: average, 99th percentile and worst;
- draw calls per frame, and how many more were merged by batching;
- per function: its own time per frame, its time including what it calls, and its calls per frame;
- the functions called too often to time, with their calls per frame;
- the slowest frame and which functions it went to, for hitches;
- how many pieces of code the JIT compiler compiled, gave up on, and how often it threw everything away.

For those 10 seconds every named function (globals, and functions in global tables such as `love.update` or `pathfinding.getSteeringTarget`) is swapped for a watched copy, then put back. The first 1.25 seconds only count calls; the functions called most are put back within two frames and left alone, and the rest are timed. Expect a short dip in frame rate when a profile starts and ends, while LuaJIT recompiles. Functions held only in a `local` are not seen; their time counts for their caller. A mod that compares a function it stored earlier with the global of the same name sees two different functions while the profile runs.

### The line sampler

The option **Line Sampler For Profiles** switches Ctrl+F11 to LuaJIT's own sampler. Its report also has single lines, local functions and the split between compiled and interpreted code. It interrupts the game from a second thread, and that has frozen the game twice: once when the sampler was stopped, once a few seconds after a profile. The report is saved before that can happen. Leave the option off unless you need lines, and restart the game after such a profile.

To judge an option, profile the same situation with it on and off; the report's first line says which options were on. The atlas helps only where draws of packed sprites follow one another, so compare draw calls and frame time with it on and off.

Not kept from GCore: the forced VSync-off, and the benchmark keys.

Known limit: baked debris is not written to save files, so settled casings are gone after loading a save. Decals are saved as before.

## For mod authors

The global `PerfKit` exists once the mod is loaded. List `perfkit` under `requires` and `load_after` in your `mod.json`.

### Adding a particle type

```lua
PerfKit.Particles.register("example_spark", {
  -- Fills in the particle. Every field starts with a neutral value (no movement, full
  -- alpha, sprite = the type name, origin at the sprite's centre, lifespan 1 second).
  setup = function(p, x, y, rotation)
    p.sprite = "muzzleSpark"       -- any global image
    p.velocity = 120
    p.drag = 4
    p.lifeSpan = 0.6
    p.fade = 6
  end,
  -- All optional:
  update = function(p, dt) end,    -- every frame while it lives
  on_death = function(p) end,      -- once, when its lifespan runs out
  draw = function(p, image) end,   -- instead of the default drawing
  top = false,                     -- true: above soldiers and trees
  live = false,                    -- true: never bake it as settled debris
})

PerfKit.Particles.spawn("example_spark", x, y, math.rad(90))
```

The game still moves, fades and removes the particle; `setup` uses the same fields as the game's own types (`velocity`, `drag`, `spin`, `fade`, `expand`, `shrink`, `lifeSpan`, `alpha`, `scale`, `trail`, `xoffset`, `yoffset`, `immunity`). Code that calls the game's `addParticle(p, "example_spark", x, y, r)` gets your type too.

| Function | Does |
|---|---|
| `PerfKit.Particles.register(typez, def)` | Adds a type. |
| `PerfKit.Particles.spawn(typez, x, y, rotation, top)` | Creates a particle of any type, the game's included, and puts it on a list. |
| `PerfKit.Particles.isRegistered(typez)` | Whether a mod registered the type. |
| `PerfKit.Particles.keepLive(typez)` | Never bake this type. Use it for a game particle your mod looks for, moves or changes after it came to rest. |
| `PerfKit.Particles.flush()` | Puts all baked debris back on `player.particles`. |
| `PerfKit.Profiler.start(seconds, label, how)`, `stop()` | Profile from code. `how` is `"timing"` (default) or `"sampling"`. `stop()` returns the report text and the file path. |
| `PerfKit.Atlas.reset()` | Rebuild the atlas. Call it after replacing image globals while the game runs. |
| `PerfKit.Decals.invalidate()` | Redraws the decal layer. Call it after changing a decal in place (moving it, swapping its image). Adding and removing decals needs nothing. |

### What is baked

A particle is treated as settled debris when it has no velocity, spin, drift, fade, growth or shrink, is not broom-immune, is not tied to a soldier (`faction` is `""` or `0`), has more than 3 seconds left, and is not one of the types the game picks up or acts on later (intel papers and maps, pamphlets, grenades, flares). If your mod scans `player.particles` for a resting particle of some type, call `keepLive` for it.
