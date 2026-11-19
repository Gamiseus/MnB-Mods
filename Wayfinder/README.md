# Wayfinder

A* pathfinding for infantry and vehicles on a 16 px grid. Units route around solid objects, buildings, trees, wire, fire and known mines. Paths are solved on a background thread. This changes how units move.

What the grid is made of, from the game's own objects:

- **Solid objects** (those whose collision is on, see above), by the size of their sprites, scaled and turned as the game draws them: dragon's teeth, hedgehogs, barricades, barrel and breastwork walls, fences, palisades, cars, carts, trucks, tractors, wagons, cannons, radar bases, stacks and piles, hay, crates, barrels, wheelbarrows and tombs. A soldier's width round each is kept clear, so paths do not brush them.
- **Buildings** can be entered; paths lead through one only when going round is far longer.
- **Rocks** are walkable, as in the game (soldiers can stand on them); vehicles go round.
- **Wire and entanglements** are costly; soldiers who can cut wire go through.
- **Trees, mud, water and slopes** cost a little more; **fires** and **known mines** a lot.

In the game itself soldiers can walk over anything, so nobody is left stuck: a soldier held back by an object for a moment gets a new path from where he stands, and one still held back after 2 seconds steps across. When objects close off a destination completely, a soldier walks the best path there is and then crosses the rest.

Options (Mod Settings): Pathfinding, Pathfinding For Your Soldiers, Infantry Collision, Path Through Buildings, Fine Tuned Collisions, Safer Destinations, Solve Paths In The Background. Shift+F9 shows the grid.

Collision options:

- **Infantry Collision** (on): solid objects stop soldiers, who walk round them. Off, soldiers can cross anything, as in the game; paths still prefer to go round.
- **Fine Tuned Collisions**: a submenu with one switch per kind of object: Dragon's Teeth, Hedgehogs And Obstacles, Barricades, Low Walls, Fences, Palisades, Vehicles And Wagons, Cannons, Radar Bases, Stacks And Piles, Hay, Crates And Barrels, Tombs. On, that kind stops soldiers; off, they can cross it, and paths cross it only when going round is longer. Low Walls and Fences are off by default: maps lay them in lines across the field as cover to climb over. Vehicles go round every kind.
- **Path Through Buildings** (on): paths may lead through a building when walking round it is far longer. Off, soldiers only enter the building they start in or are sent to.

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
| `SOLID_PLACEABLES` | The solid objects by the game's placeable names, each with its sprite's solid box at size 10. |
| `COLLISION_KINDS` | The kinds of solid object, each with its option alias, default and placeable names. |
| `collides(name)` | Whether a placeable of that name stops soldiers, by the options. |

The grid's settings are fields on `pathfinding`: `CELL_SIZE` (16 px), `BODY_RADIUS` (8 px kept clear round solid objects), `MARGIN_COST`, `VAULT_COST` (an object soldiers may cross), `BUILDING_COST` (a building cell on a path through it), `CORRIDOR_MAX_COST`, `MAX_EXPANSIONS`, `NEAREST_SEARCH`, `UNSTICK_REPLAN` (0.4 s) and `UNSTICK_PASS` (2 s).

The mod keeps its state on units in `pathQueue`, `_pfGoalX`, `_pfGoalY` and `_pfRecheckTimer`.
