# Wayfinder

A* pathfinding for infantry and vehicles on a 32 px grid. Units route around trees, rocks, buildings, wire, fire and known mines. Paths are solved on a background thread. This changes how units move.

Options (Mod Settings): Pathfinding, Safer Destinations, Solve Paths In The Background. Shift+F9 shows the grid.

For other mods, the global `pathfinding`:

| Function | Does |
|---|---|
| `requestPathAsync(unit, startX, startY, goalX, goalY)` | Queues a path on the worker thread; the result is stored in `unit.pathQueue`. |
| `computePath(startX, startY, goalX, goalY, unit)` | Solves a path now, on the game's thread. |
| `findSafeDestination(wx, wy, unit)` | The nearest safe, walkable point. |
| `isWalkableWorld(wx, wy, unit, allowBuildingId)` | Whether a point can be walked on. |
| `needsDetour(x1, y1, x2, y2, unit)` | Whether a straight line is blocked. |
| `markDirty()`, `invalidateHazards()` | Rebuild the grid; also drop every unit's path. |

The mod keeps its state on units in `pathQueue`, `_pfGoalX`, `_pfGoalY` and `_pfRecheckTimer`.
