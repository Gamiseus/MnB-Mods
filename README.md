# Mods for Mud and Blood

Mods I make for Mud and Blood. All of them need the **QuarterMaster** mod loader: [find it here](https://github.com/Gamiseus/QuarterMaster).

The old names are gone with the "G" prefix. GCore, the all-in-one core mod, is now four separate mods, so you can take the performance work without the gameplay changes. GConsole and GDumper are gone: QuarterMaster's debug mode and developer commands do their jobs. Changes are in [CHANGELOG.md](CHANGELOG.md).

| Mod | Changes gameplay? | What it does |
|---|---|---|
| [PerfKit](PerfKit/) | No | Bakes decals and settled debris onto canvases, skips off-screen particles, optional texture atlas. Has a profiler that says where the frame time goes, and a registry for mods that add particle types. Replaces no game files. |
| [SaveGuard](SaveGuard/) | No (saves only) | Leaves particles, floating text and combat litter out of save files. Fixes the `main function has more than 65536 constants` crash on load. |
| [Wayfinder](Wayfinder/) | Yes | A* pathfinding for infantry and vehicles, solved on a background thread. Units route around obstacles and hazards. |
| [TrueSight](TrueSight/) | Yes | Line of sight by ray casting against real obstacle shapes (Box2D) in place of the game's sampled check. |
| [SquadTactics](SquadTactics/) | Yes | Smart group move orders, soldiers that react to contact, and a configurable squad size limit. Needs Wayfinder; uses TrueSight when present. |
| [SeasonalEvents](SeasonalEvents/) | Yes | Pick the active special event; events are modules, including a three-way Halloween fight. |

## Download

Each mod is a zip on the [latest release](https://github.com/Gamiseus/MnB-Mods/releases/latest): `PerfKit.zip`, `SaveGuard.zip`, `Wayfinder.zip`, `TrueSight.zip`, `SquadTactics.zip`, `SeasonalEvents.zip`. Import it in the QuarterMaster launcher.

## Tests

The mods' logic is tested against stubs of the game, on the game's own LuaJIT. From this folder:

```bash
python tests/run_luajit.py tests/perfkit_test.lua
```

The same for `squad_tactics_test.lua` and `seasonal_events_test.lua`. The runner loads `../game/lua51.dll`; pass another path as a second argument. The game itself is not started.
