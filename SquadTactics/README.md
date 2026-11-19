# Squad Tactics

Changes how the player's soldiers move and react. Needs Wayfinder; uses TrueSight when it is installed.

| Option | What it does |
|---|---|
| Smart Squad Move | A move order for two or more soldiers gives each a position near the click that suits their role: point men forward, gunners and snipers with a view, medics behind, all spaced out and in cover where there is some. Hold Shift for the game's plain order. |
| React To Contact | A soldier on a move order who sees the enemy stops, aims, fires a couple of rounds and carries on with the order. While the enemy stays in sight he stops again every few seconds. A soldier with an empty or jammed gun keeps moving. |
| Squad Size Limit | How many exposed soldiers the Germans tolerate before counter-assaults start: 6 in the game, here 6 to 32 or off. |

For other mods, the global `SquadTactics`:

| Function | Does |
|---|---|
| `SquadTactics.Move.assignSquadMoveOrder(soldiers, x, y)` | Plans a group move. Also `classifyRole(dude)`, `computeVeterancyWeight(dude)`. |
| `SquadTactics.Reaction.isActive(dude)` | Whether the soldier is stopped to fire. |
| `SquadTactics.Reaction.clear(dude)` | Ends the stop; the soldier goes on with the order. |
| `SquadTactics.squadLimit()` | The limit in use; `math.huge` when off. |

How often a moving soldier looks for the enemy, and to how many enemies it checks its line of sight, are `SquadTactics.Reaction.SCAN_INTERVAL` (0.2 s) and `SIGHT_CHECKS` (4). Rounds fired per stop are `BURST` (2), the longest stop `MAX_STOP` (5 s), and the time moving before the next stop `COOLDOWN` (3 s).

## Very large squads

Two things change when far more soldiers are under your command than the game expects:

- **The Germans' answer always ends.** The game answers an oversized squad with artillery, white phosphorus and air bursts, repeating each "while a 1 to 100 dice roll is under the squad's size". With more than 100 soldiers the roll is always under, the loop never ends and the game locks up. The chance to go on is capped at 90 in 100.
- **Groups of more than 24 are placed in a block.** Choosing a spot for each soldier compares every soldier with every candidate spot; for a few hundred soldiers that takes a second or more. A large group gets rows and columns around the click instead, soldiers on the left taking the left columns.
