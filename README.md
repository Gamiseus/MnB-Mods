# Mods for Mud and Blood

### This repo contains mods for Mud and Blood, mainly that I have made for personal use but others may find useful. The GCore and GConsole mods contain most of the things that others would find useful, and GDumper is really only useful for modders.

### All mods require the **QuarterMaster** mod loader to function! [Find it here!](https://github.com/Gamiseus/QuarterMaster)

---

### GConsole - [Download Latest](https://github.com/Gamiseus/MnB-Mods/releases/latest/download/GConsole.zip)
- A console addon for Mud and Blood/QuarterMaster. Adds some more stuff to the logging system and enables dev keybinds, but not much else. Not necessary to run the game. That's about it.
---
### GCore - [Download Latest](https://github.com/Gamiseus/MnB-Mods/releases/latest/download/GCore.zip)
- A core mod that is mainly focused on engine and base level tweaks/edits
- Currently includes features such as
    - Physics based LoS calculations, using library Box2D for raycasting
    - Multi-threading enabled at the engine level, though I haven't messed with it much yet, just a couple threads for pathfinding.
    - A log monitor, which watches the logs for spam and errors, anomolous log size increases, and notifies you in game if there's a problem
    - A system that bakes static decals in place for performance. Divides the map into canvas chunks, created lazily on demand if more chunks are necessary for the map. Once a new decal spawns (blood, craters, etc), it gets stamped onto the canvas instead of staying as it's own item. Obeys the rules set in the options for max decals by trimming out non-immune decals and rebaking, and is cleaned with the vanilla broom button. Difference is 1 draw call for the canvas (2 during scrolling if there are multiple chunks) instead of hundreds or thousands of draw calls for the individual decals.
    - A serializer for better key filtering on what is saved and what isn't. A bunch of keys that aren't necessary for saving or reloading data get filtered out, reducing file size and loading times, but mainly fixing a bug I ran into with a huge amount of soldiers, decals, and particles in a single save file, causing a crash with `main function has more than 65536 constants` errors that left the save unloadable.
    - Rewritten multithreaded pathfinding system using A* (A Star) algorithm instead of the game's vanilla pathfinding.
      - Soldiers will now avoid hazards, route around obstacles like trees and rocks instead of over them so they can maintain line of sight as best as possible. 
      - Custom terrain grid system written to define what can be walked on, and how much it costs to move through.
- Required for some mods to function properly, for now just TacticalOverhaul and GSpecialEvents. I have plans to keep consolidating core improvements and fixes in here, of which some mods will call upon rather than using vanilla implementations.
---
### GDumper - [Download Latest](https://github.com/Gamiseus/MnB-Mods/releases/latest/download/GDumper.zip)
- A simple tool to dump the game files into the qm folder in the mods directory. Will dump either all the LUA files, or the entire base game, depending on which keybind you press.
---
### GMenu - [Download Latest](https://github.com/Gamiseus/MnB-Mods/releases/latest/download/GMenu.zip)
- A menu system for Mud and Blood mods to hook if a modder wants to create their own menu in the game, or to add configurable options to the mod settings menu.
   - Works by scanning `Mods/*/config.lua` upon initialization for mod configured buttons and such.
      - Settings: Define all the usual settings things like cycle buttons (with support for cycling left *and* right), checkboxes, etc. Can use `showif` to only show a setting under certain conditions, ie if another mod is loaded or if one setting is set to something specific.
      - Menus: An automatic menu/page setup system. GMenu automatically assigns page numbers by the pages defined in the mod's config.lua, cards loaded automatically from menuButtons items and pages made from pages items. Currently can handle up to 5 cards before they end up off screen, I have to implement a multi-page/'more cards' system for more than that.
---
### GSpecialEvents - [Download Latest](https://github.com/Gamiseus/MnB-Mods/releases/latest/download/GSpecialEvents.zip)
#### **Depends on GMenu (Options menu) and GCore**
- A mod that adds a special event selector to the game, allowing a player to choose which event is loaded, or leave it at auto by calendar date, and use the mod for it's event adjustments.
   - Currently includes modifications for the Halloween event, adding configuration for setting zombie health, speed, and other stats. Also includes patches for spawning and the ai, to encourage the Germans and Zombies to fight each other as well as your own soldiers.
---
### TacticalOverhaul - [Download Latest](https://github.com/Gamiseus/MnB-Mods/releases/latest/download/TacticalOverhaul.zip)
#### **Depends on GMenu (Options menu) and GCore**
- A WIP overhaul mod that introduces a bunch of features aimed at making behavior more realistic. Kind of subjective.
   - Soldiers moved in a group no longer scatter randomly. They seek cover, maintain a little distance, look for spots with good line of sight, try to stay out of each others way and not stand in front of each other.
   - More advanced automatic placement included based on soldier's gear and type.
      - A medic will tend to stick towards the back of a group, while also moving to the most wounded person in the group. Medic movement is evaluated last to facilitate this check.
      - Close quarters weapons like shotguns encourage a soldier to move to the front of the group, seeking closer range cover to the enemy.
      - Machinegunners will look for solid cover with great sight lines.
         - Depending on squad and equipment, a rifleman may try to stick with the machinegunner, to allow for assisted reloads
      - Snipers look for spots in the rear with either cover or trees to hide in.
      - Much more. These are in progress, so it's not always perfect, but it's super useful for those who don't want to micromanage every soldier every single click, or for moving large distances and just getting them there so you can adjust their specific spots later.
   - A combat reaction system that allows soldiers to interrupt their pathfinding to react to things like newly spotted enemies, incoming fire, and hazards. They evaluate the danger based on what it is and how much of a threat it is to them specifically, can choose to do different actions like returning fire, moving to the nearest good cover away from any threats, continuing on their way, etc. Once they deem it safe or viable, they will resume pathfinding to their original destination. --- Currently very unstable and LOTS of tweaking required, as well as implementation of fallback action in case they get stuck and manual overwriting of movement commands.

---

## Contents
- All of my mods follow a set schema for `mods.json`. This will be important when the mod launcher is finished, as it will define a bunch of the stuff that the launcher will need to read for organization. Some mods with in game options menus have a `config.lua` that is loaded by GMenu. All mods **must** contain a `qm.toml` file that contains the patch instructions for the modloader to follow.

## Install
- Download the mod(s) you are interested in
- Extract the contents of the zip file(s) into the Mods folder inside your Mud and Blood directory. The end result should look like `Mods/<Modfolder>/<qm.toml file>`
- Run the game, it will automatically load all mods within the directory.
