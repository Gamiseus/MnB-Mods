# Seasonal Events

Choose which of the game's special events is active, whatever the date: Auto (by the calendar), None, or one by name. The choice is in Mod Settings and applies while playing.

Halloween has its own options and becomes a three-way fight:

- zombies attack Germans as well as Allies, and Germans fight back (each can be switched off);
- the dead rise again as zombies: those killed by a zombie, or every casualty;
- zombie health, speed, damage, where they spawn and how often.

The other events run exactly as the game has them.

## Adding an event from another mod

```lua
SpecialEvents.register("Example", {
  onLoad = function(core) print("Example event on") end,
  isHostile = function(dude, target, core) return dude.faction ~= target.faction end,
  onUpdate = function(dt, core) end,
})
```

A module is a table with any of `onLoad`, `onUnload`, `isHostile`, `onDeath`, `onUpdate`, `onCqcHit`, `spawnZombies`, `getZombieSpeed`, `onZombieIdle` and `waveSpawnChance`. Anything it leaves out behaves as in the game. `seasonal_events.lua` lists what each receives.

| Function | Does |
|---|---|
| `SpecialEvents.register(name, module)` | Adds or replaces an event module. |
| `SpecialEvents.getActiveEvent()` | The running event, `""` for none. |
| `SpecialEvents.getSelectedEvent()`, `setSelectedEvent(name)` | The player's choice. |
| `SpecialEvents.isHostile(a, b)` | Whether two units are enemies under the running event. Also the global `isHostileTo`. |
