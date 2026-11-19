# Wayfinder

A* pathfinding for infantry and vehicles on a 32 px grid. Units route around trees, rocks, buildings, wire, fire and known mines. Paths are solved on a background thread. This changes how units move.

Options (Mod Settings): Pathfinding, Pathfinding For Your Soldiers, Safer Destinations, Solve Paths In The Background. Shift+F9 shows the grid.

Your soldiers go where you send them when you want them to:

- **Pathfinding For Your Soldiers** off: your soldiers walk straight to the spot, as in the game, with no detour and no shifted destination. The enemy and allied AI still use pathfinding.
- **Direct Move** (hold X while giving a move order, rebindable under Keybinds, Wayfinder tab): that order is walked straight, through wire or anything else in the way. The next order given without the key uses pathfinding again.

Fires are given a wide berth: as far out as the game burns a soldier (a fire's size times 75 px, up to 150 px), plus a margin.

For other mods, the global `pathfinding`:

| Function | Does |
|---|---|
| `requestPathAsync(unit, startX, startY, goalX, goalY)` | Queues a path on the worker thread; the result is stored in `unit.pathQueue`. |
| `computePath(startX, startY, goalX, goalY, unit)` | Solves a path now, on the game's thread. |
| `findSafeDestination(wx, wy, unit)` | The nearest safe, walkable point. |
| `isWalkableWorld(wx, wy, unit, allowBuildingId)` | Whether a point can be walked on. |
| `needsDetour(x1, y1, x2, y2, unit)` | Whether a straight line is blocked. |
| `markDirty()`, `invalidateHazards()` | Rebuild the grid; also drop every unit's path. |
| `movesDirect(unit)` | Whether the unit walks its order straight (a player's soldier with the option off, or on a Direct Move order). |
| `fireRadius(fire)` | How far from a fire units are kept. |

The mod keeps its state on units in `pathQueue`, `_pfGoalX`, `_pfGoalY` and `_pfRecheckTimer`.
