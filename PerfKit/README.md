# PerfKit

Makes long battles cheaper to draw and update. It replaces none of the game's files: it swaps three drawing loops for one call each and wraps three particle functions. Every feature has a switch in Mod Settings, and with a switch off the game's own code runs.

| Feature | What happens |
|---|---|
| Bake Decals | Blood, craters and rubble are drawn once onto canvases that tile the map. A few canvases are drawn per frame instead of every decal. |
| Bake Settled Debris | A casing or piece of debris that stopped moving is taken off the game's particle list and drawn onto a canvas until its lifespan ends or the broom is used. |
| Skip Off-Screen Particles | Particles outside the view are not drawn, and the colour is only set when it changes. |

| Texture Atlas (experimental, off by default) | Small sprites are copied onto a few shared textures, and a draw of one becomes a draw of its rectangle there, so the graphics card gets fewer, larger draw calls. About 130 MB more video memory. |

F11 shows an overlay with FPS, draw calls and how much is baked. In QuarterMaster's debug mode, the mod also warns when the log is growing fast (a mod printing every frame).

## Finding out what is slow

Press **Ctrl+F11** in a battle that runs badly. PerfKit measures for 10 seconds and writes `Mods/qm/perfkit-profile.txt` (the first part also goes to the log). Press it again to stop early. The report has:

- frame times: average, 99th percentile and worst;
- draw calls per frame, and how many more were merged by batching;
- where the time went by kind: compiled Lua, interpreted Lua, engine calls (drawing, audio, physics), garbage collection;
- the functions and lines that used the most time, and the hottest call paths.

After the first profile the sampler stays switched on and idle, which costs a fraction of a percent until the game is closed. Switching it off froze the game, so PerfKit no longer does.

To judge an option, profile the same situation with it on and off; the report's first line says which options were on. The atlas helps only where draws of packed sprites follow one another, so compare draw calls and the "engine" share with it on and off.

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
| `PerfKit.Profiler.start(seconds, label)`, `stop()` | Profile from code. `stop()` returns the report text and the file path. |
| `PerfKit.Atlas.reset()` | Rebuild the atlas. Call it after replacing image globals while the game runs. |
| `PerfKit.Decals.invalidate()` | Redraws the decal layer. Call it after changing a decal in place (moving it, swapping its image). Adding and removing decals needs nothing. |

### What is baked

A particle is treated as settled debris when it has no velocity, spin, drift, fade, growth or shrink, is not broom-immune, is not tied to a soldier (`faction` is `""` or `0`), has more than 3 seconds left, and is not one of the types the game picks up or acts on later (intel papers and maps, pamphlets, grenades, flares). If your mod scans `player.particles` for a resting particle of some type, call `keepLive` for it.
