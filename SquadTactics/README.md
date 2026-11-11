# Squad Tactics

Changes how the player's soldiers move and react. Needs Wayfinder; uses TrueSight when it is installed.

| Option | What it does |
|---|---|
| Smart Squad Move | A move order for two or more soldiers gives each a position near the click that suits their role: point men forward, gunners and snipers with a view, medics behind, all spaced out and in cover where there is some. Hold Shift for the game's plain order. |
| React To Contact | A soldier on a move order who meets the enemy stops to return fire or runs for nearby cover, then carries on with the order when the area is clear. Veterans fire first. Halt (H) cancels the order for good. |
| Squad Size Limit | How many exposed soldiers the Germans tolerate before counter-assaults start: 6 in the game, here 6 to 32 or off. |

For other mods, the global `SquadTactics`:

| Function | Does |
|---|---|
| `SquadTactics.Move.assignSquadMoveOrder(soldiers, x, y)` | Plans a group move. Also `classifyRole(dude)`, `computeVeterancyWeight(dude)`. |
| `SquadTactics.Reaction.isActive(dude)` | Whether the soldier is reacting to contact. |
| `SquadTactics.Reaction.clear(dude)` | Ends the reaction and forgets the interrupted order. |
| `SquadTactics.squadLimit()` | The limit in use; `math.huge` when off. |

How often a soldier looks for threats, and to how many enemies it checks its line of sight, are `SquadTactics.Reaction.SCAN_INTERVAL` (0.2 s) and `SIGHT_CHECKS` (4).
