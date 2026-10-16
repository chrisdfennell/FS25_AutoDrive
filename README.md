# AutoDrive Overdrive

[![CI](https://github.com/chrisdfennell/FS25_AutoDrive/actions/workflows/ci.yml/badge.svg)](https://github.com/chrisdfennell/FS25_AutoDrive/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/chrisdfennell/FS25_AutoDrive?label=release)](https://github.com/chrisdfennell/FS25_AutoDrive/releases/latest)

AutoDrive Overdrive is an unofficial edition of [AutoDrive](https://github.com/Stephan-S/FS25_AutoDrive) for Farming Simulator 25, by the AutoDrive Team (Stephan-S, Axel32019, TyKonKet and [many contributors](credits.txt)), released under the [MIT licence](LICENSE).
It is based on AutoDrive 3.0.1.4 and adds route editor improvements, waypoint actions, a route check with fixes, a route preview on the map, a fleet overview with send-to and driver statistics, best price unloading and work schedules. For the official mod and its support, see the original README below.

## Download
Get **FS25_AutoDrive.zip** from the [latest release](https://github.com/chrisdfennell/FS25_AutoDrive/releases/latest) and put it into your mods folder (`Documents/My Games/FarmingSimulator2025/mods`), replacing the official AutoDrive zip.
Keep the file name: the mod only loads as `FS25_AutoDrive.zip`, and that is also what keeps your savegames, routes and settings working.

Versions are `<AutoDrive version>-od.<build>`, e.g. `3.0.1.4-od.1` is the first Overdrive build based on AutoDrive 3.0.1.4. The version shows in the header of the AutoDrive HUD.

## What Overdrive adds

### Undo and redo in the route editor
With the editor turned on, **Ctrl+Z** undoes and **Ctrl+Y** redoes your last change to the route network.

**What can be undone**
- creating, deleting and moving waypoints
- connections (one-way, two-way, reverse, curves) and the side road setting, including the section tools
- creating, renaming and deleting targets, and moving them between folders
- creating, renaming, deleting and recolouring folders
- recorded drives
- generated field points (Ctrl+Shift+F)
- routes loaded with the routes manager: one Ctrl+Z brings back the previous network
- routes added by placeables with prepared AutoDrive routes

**How it behaves**
- One action is one undo step. Deleting a selection, changing a whole section, a curve, a recorded drive or a field's points is undone in one go. Moving the same waypoint several times within 10 seconds also counts as one step.
- The message says what was undone or redone, e.g. `Undone: waypoint deleted, target "Silo" deleted (3 more to undo, 1 to redo)`.
- Undo and redo icons in the HUD header (editor mode only) are greyed out when there is nothing to undo or redo.
- After an undo or redo, the affected waypoints flash for a few seconds: green = added or restored, yellow = changed, magenta = removed. A moved waypoint also shows a line from its previous position. If the change is out of sight, a pointer from your vehicle shows the direction.
- **Preview:** hold **Left Alt + Z**, or right click the undo icon, to see what the next undo would change, without changing anything.
- **While recording**, Ctrl+Z removes the last ~10 m of recorded points and the recording continues from the highlighted point. After the recording is stopped, one Ctrl+Z removes the whole drive.
- **Multiplayer:** the history is kept on the server and each player undoes their own edits. An older own edit can be undone even if others edited afterwards, as long as their edits don't depend on it; otherwise the message names the player who changed the network in the meantime. Diagnostic lines starting with `[AD Undo]` are written to the game log in multiplayer.
- The history holds the last 100 steps and lasts until the game is closed or the savegame is left. A few changes outside the editor clear it, e.g. switching on the road network debug markers or placing the colour selection points; a message then tells you why.

### Target folders
- **Sub folders:** folders can contain folders (shown indented in the target list, e.g. "Farm" › "Silos"). A sub folder is only listed when its parent folders are expanded.
- In editor mode, each folder in the target list has icons to **add a sub folder**, **rename** it (sub folders and targets move along) and **change its colour**. Clicking the colour square cycles through 12 colours and back to the default. The folder name is shown in its colour.
- Folder colours are saved with the savegame and included in route exports of the routes manager.
- In editor mode, each target in the list has a rename icon, to rename any target directly from the list.

### Waypoint editing
- **Move waypoints by dragging:** hold **Left Shift** and drag a waypoint with the left mouse button. A short click without moving still toggles the side road setting as before. The key can be changed ("AD: Hold + left mouse drag to move waypoint").
- **Deleting a waypoint** removes all targets on it, not only the first one, and every connection pointing to it. Before, a second target or a reverse connection could be left pointing at the next waypoint.

### Tidy-up tools
Select a waypoint with a left click, point the mouse at another waypoint on the same route and press:
- **Ctrl+Alt+J** to even out the spacing: the waypoints stay on the route, at equal distances
- **Ctrl+Alt+K** to straighten: the waypoints are lined up between the two waypoints
- **Ctrl+Alt+U** to smooth: kinks and zig-zags of e.g. a recorded drive are rounded off

The route between the two waypoints is the shortest chain of connections. Only waypoints between them are moved, both end points stay where they are, and connections, targets and side road settings don't change. Heights follow the ground. Each tidy-up is one undo step.

### Route check
**Ctrl+Alt+N** checks the whole route network and lists the problems, nearest first:
- targets that can't be reached from the rest of the network, or from which there is no way back
- one-way traps: parts of the network you can drive into but not out of
- dead ends (waypoints without a way on, unless a target is on them)
- loose waypoints without any connection
- waypoints on top of each other (less than 0.3 m apart)

**Show** (or a double click) marks the problem with a pulsing red beacon. If it is out of sight, a red arrow at your vehicle points the way. The check only reads the network, it changes nothing until you press **Fix**: a loose waypoint is deleted, two waypoints on top of each other are merged into one (the connections of both are kept; the one with a target stays), and a dead end is connected one-way to the nearest waypoint within 30 m that does not lead to it. Each fix is one undo step, the list is checked again right after. Unreachable targets and one-way traps need a decision about the route, use **Show** to find them. It also looks at things the road network debug markers can't see, like whole parts of the network that can't be left, and it doesn't add debug targets to your map.

### Fleet overview
**Ctrl+Alt+I** (in a vehicle or on foot) lists every AutoDrive vehicle of your farm: name, mode, destination, load, fuel, work schedule and what it is doing. A stopped vehicle shows its latest warning or error from the notifications. **Enter vehicle** takes you to it, **Start / stop** starts or stops its job.

**Send to:** double click a vehicle and choose a destination: the vehicle switches to "drive to" with that destination and starts, without you getting in. The list updates every second.

**Statistics** switches the list to the driver statistics, counted while AutoDrive drives the vehicle: distance, time driving, time standing and waiting (with its share of the total), deliveries, the amount unloaded, the crops hauled most and their estimated value at today's best selling price. The button cycles through total, today, the last 7 in-game days and back to the status. A delivery is counted when the vehicle's load goes down by at least 500 l (or a quarter of a smaller trailer) and then stays. In this view, **Reset statistics** sets the selected vehicle back to zero. The numbers are saved with the savegame.

### Waypoint actions
In the editor, point the mouse at a waypoint (or select one) and press:
- **Ctrl+Alt+W**: vehicles wait there (each press: 5, 10, 20, 30, 60, 120, 300 seconds, off)
- **Ctrl+Alt+H**: vehicles sound the horn there
- **Ctrl+Alt+L**: vehicles switch the lights on there, off there, or leave them (each press)

Waypoints with actions get an orange marker with the actions written above it. Every change is one undo step. The actions are stored in the waypoint data, so they are saved, exported with the routes manager and sent to all players. The official AutoDrive ignores them.

### Route preview
**Ctrl+Alt+P** shows the route from the vehicle to its destination, and for pickup and deliver also on to the unload target (second colour): as a line in the world, on the minimap and on the big map (ESC > Map), where you can zoom out and see the whole route. A message gives distance and estimated drive time for each part. Press again to hide it.

### Best price unloading
New vehicle setting **Best price unloading**. When the vehicle is loaded and sets off to unload, it picks the target in the unload target's folder whose selling point pays the most for the load right now, and tells you where it goes. Put all the selling points you want to use as targets into one folder, and choose one of them as the unload target. Targets without a selling point within 60 m are left out. Works with pickup and deliver and with unload. It needs "use folders" and does nothing while target rotation for unloading is on. The target must be in a folder, not in "All".

### Work schedule
New vehicle settings **Start work at** and **Stop work at** (in-game hours, `--:--` = off).
- At the start hour the driver starts its job, with the mode and targets set in the HUD.
- At the stop hour, pickup and deliver finishes the round it is on (loading and unloading) and then drives to its park position, if one is set. Other modes stop right away.
- Skipping time (sleeping) counts: the later of the two hours that were skipped decides.

### Key bindings
| Action | Default key |
|---|---|
| Undo route edit | Ctrl + Z |
| Redo route edit | Ctrl + Y |
| Preview the next undo (hold) | Left Alt + Z |
| Move waypoint (hold, then drag with the left mouse button) | Left Shift |
| Even out waypoint spacing | Ctrl + Alt + J |
| Straighten route | Ctrl + Alt + K |
| Smooth route | Ctrl + Alt + U |
| Route check | Ctrl + Alt + N |
| Fleet overview | Ctrl + Alt + I |
| Waypoint action: wait | Ctrl + Alt + W |
| Waypoint action: horn | Ctrl + Alt + H |
| Waypoint action: lights | Ctrl + Alt + L |
| Route preview | Ctrl + Alt + P |

All key bindings can be changed in the game's control settings. Like AutoDrive's other keys, they work while you sit in a vehicle; the fleet overview also works on foot.

### Notes
- The mod keeps the name `FS25_AutoDrive`, so it replaces the official AutoDrive mod: install either one, not both. Savegames, routes and settings of the official version keep working.
- In multiplayer, all players need the same version of the mod.
- The new texts are translated into all languages of the mod. Corrections from native speakers are welcome.
## For developers
Every push and pull request runs the [CI workflow](.github/workflows/ci.yml):
- a Lua 5.1 syntax check, the Lua version the game uses
- static checks: XML files, translation placeholders, every script loaded by `register.lua` exists ([tools/ci_checks.py](tools/ci_checks.py))
- static checks also make sure every text the code uses exists in English, and that the mod's startup check accepts its title
- the tests ([tools/tests](tools/tests)): undo / redo, route check, tidy-up tools, work schedule, best price and fleet overview. They run the mod code outside the game with stubs for the game API
- a test build of the mod zip, attached to the workflow run

Run the same locally with `pip install lupa`, then `python tools/ci_checks.py` and `python tools/tests/run_all.py`.

**Releasing:** push a tag like `v3.0.1.4-od.2`, or start the [Release workflow](.github/workflows/release.yml) from the Actions tab and enter the version (with "dry run" it only builds). The workflow runs all checks, builds `FS25_AutoDrive.zip` with [tools/build_mod.py](tools/build_mod.py), writes the release notes and publishes the release. The version must start with the version in `modDesc.xml`.

The mod zip contains `drawing`, `gui`, `scripts`, `sounds`, `textures`, `translations`, `icon_AutoDrive.dds`, `modDesc.xml`, `register.lua`, `LICENSE` and `credits.txt`. The `tools` and `.github` folders are for development and not part of the mod.

---

# Original AutoDrive README

FS25 version of the AutoDrive mod

### Latest Release: 3.0.1.4
Direct Download: https://github.com/Stephan-S/FS25_AutoDrive/releases/latest/download/FS25_AutoDrive.zip

## Discord Server:
For help & support, feel free to join us on Discord: 
https://discord.gg/2XfnM59DFy

### For a little thank you
If you like our work, feel free to buy us a coffee (of which we drink quite a lot :D )  
For now, there is no general link for the team, so each contributer can post his/her preferred donation link here :-)  
But remember, this is absolutely not required. We value any issues and feature requests the same!  
And to all who do donate: Thank you very much :-)

#### Stephan (Founder):
https://www.paypal.me/StephanSchlosser

#### Iwan1803 (Community Manager, Supporter & Tester):
https://iwan1803.de/urls/tip

#### Axel & Tommo (Modder)

#### Willi (Supporter & Tester)

## Placeable Crossings and Reversing (separate mods)
Direct Download: https://github.com/Williwillswisse/AD_XandT-intersections/releases/latest/download/FS25_AutoDrive_XT_Intersection.zip <br/>
Direct Download: https://github.com/Williwillswisse/AD_xCrossing/releases/latest/download/FS25_AutoDrive_xCrossing.zip <br/>
Direct Download: https://github.com/Williwillswisse/AD_T_intersection/releases/latest/download/FS25_AutoDrive_T_intersection.zip <br/>
Direct Download: https://github.com/Williwillswisse/AD_reverseToMarker/releases/latest/download/FS25_AutoDrive_reverseToMarker.zip <br/>
Repository: https://github.com/Williwillswisse

## Placeables with already prepared AD routes (separate mods)
A growing number of ingame placeables, e.g. buildings, silos, productions and so on with integrated AD routes. <br/>
Download: https://hof-hirschfeld.de/category/autodrive/

## Course Editor
The course editor is now maintained by @KillBait and can be found here:
https://github.com/KillBait/AutoDrive_Course_Editor
