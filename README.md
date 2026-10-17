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

**Double click a vehicle** for its menu: **Send to...** (choose a destination: the vehicle switches to "drive to" with that destination and starts, without you getting in), **Load products...**, **Unload products...** and **Enter vehicle**. The list updates every second.

**Statistics** switches the list to the driver statistics, counted while AutoDrive drives the vehicle: distance, time driving, time standing and waiting (with its share of the total), deliveries, the amount unloaded, the crops hauled most and their estimated value at today's best selling price. The button cycles through total, today, the last 7 in-game days and back to the status. A delivery is counted when the vehicle's load goes down by at least 500 l (or a quarter of a smaller trailer) and then stays. In this view, **Reset statistics** sets the selected vehicle back to zero. The numbers are saved with the savegame.

**Fleet on the map:** the big map (ESC > Map) shows every AutoDrive vehicle of your farm as a coloured square with its name: green driving, yellow switched on but standing, red stopped with a problem, grey idle. Switch it off in the user settings (**Fleet on the map**).

### Waypoint panel
In the editor, **left-click a waypoint** to select it: a panel opens next to the AutoDrive HUD with everything about that waypoint, as buttons:
- **Target:** its name with **Rename** and **Remove**, or **Create** a target right on this waypoint
- **Side road:** no / yes
- **Connections:** every neighbouring waypoint with the kind of connection (out, in, both ways, reverse out, reverse in). Click it to switch to the next kind; pointing at it draws a line to that waypoint
- **Actions:** wait (each click: next time), horn, lights, unlock load
- **Speed zone** for this waypoint, and **Zone on road** for the whole road it is on, up to the next junctions in both directions (the number of waypoints is shown)

Every click is one undo step and works in multiplayer like the keys. The panel stays while the waypoint is selected; **X**, clicking the waypoint again, or connecting it to another waypoint closes it. It moves to the left of the HUD when there is no room on the right. Switch it off in the user settings (**Waypoint panel**).

### Waypoint actions
In the editor, point the mouse at a waypoint (or select one) and press:
- **Ctrl+Alt+W**: vehicles wait there (each press: 5, 10, 20, 30, 60, 120, 300 seconds, off)
- **Ctrl+Alt+H**: vehicles sound the horn there
- **Ctrl+Alt+L**: vehicles switch the lights on there, off there, or leave them (each press)
- **Ctrl+Alt+B**: unlock load: the tension belts of the vehicle and its trailers open there (like the lock load key), and close again before the vehicle drives on. The vehicle has to stop there: use it on the selling target, or add a wait on the same waypoint

### Speed zones
In the editor, click a waypoint to select it, point the mouse at another waypoint further along the same route and press:
- **Ctrl+Alt+1**: 15 km/h zone
- **Ctrl+Alt+2**: 30 km/h zone
- **Ctrl+Alt+3**: 50 km/h zone
- **Ctrl+Alt+0**: remove the zone

All waypoints of the route between the two get the zone (or just the one waypoint you select or point at). Vehicles never drive faster than the zone on it, and brake in time before it, so they enter at the zone speed. Use them for yards, villages, bridges or a tight farm gate. Zone waypoints get a small coloured ball (15 red, 30 orange, 50 blue); the speed is written above the first waypoint of a zone. One undo step per key press. Like the waypoint actions, zones are saved with the routes and sent to all players.

Waypoints with actions get an orange marker with the actions written above it. Every change is one undo step. The actions are stored in the waypoint data, so they are saved, exported with the routes manager and sent to all players. The official AutoDrive ignores them.

### Route preview
**Ctrl+Alt+P** shows the route from the vehicle to its destination, and for pickup and deliver also on to the unload target (second colour): as a line in the world, on the minimap and on the big map (ESC > Map), where you can zoom out and see the whole route. A message gives distance and estimated drive time for each part. Press again to hide it.

### Unload products
Choose what is unloaded at the unload target, the rest stays on board:
- **Per vehicle:** "unload only these products". Open it with **Ctrl+Alt+F** in the vehicle, with the button left of the unload target list in the HUD (pickup and deliver and unload mode), or in the fleet overview: double click a vehicle > **Unload products...**. The list shows what is on board (also pallets of Universal Autoload); click products to select them, **All products** removes the limit. The choice is saved with the vehicle and shown in the fleet overview.
- **Per target:** "this target takes only these products". In the editor, point at a waypoint with a target and press **Ctrl+Alt+F**. The list shows what the unloading points next to the target (within 60 m) take. Saved with the routes of the savegame; a renamed target keeps its list.

**Pallets (Universal Autoload):** the list shows the pallets on board. When AutoDrive unloads at the target, only the pallets of the chosen products are set down, the others stay on the trailer and are strapped again. This needs the vehicle setting **"Autoload: Unload Position"** on left, behind or right: with "center" Universal Autoload only opens the belts, and a selling point then takes every pallet it accepts (the dialog shows a hint). Best price counts the pallets too. AutoDrive's "what to load" list in the HUD shows what is on board first, with the amount and a loaded-trailer icon.

A trailer only tips if its product is allowed by the vehicle, by the target, and by best price "each product". A stop with something left on board is done when nothing has been tipped for 3 seconds. Best price only plans with the products the vehicle unloads and only at targets that take them. This works per trailer (or per compartment that tips on its own).

### Load products (pallets)
Choose which pallets the vehicle picks up with **Universal Autoload**. Open it with **Ctrl+Alt+G** in the vehicle, with the HUD button for the automatic pickup target (pickup and deliver and load mode, while that upstream feature is off), or in the fleet overview: double click a vehicle > **Load products...**. The list shows the products of the pallets within 60 m of the vehicle or of its load target, with how many there are; click products to select them, **All products** removes the limit.

When AutoDrive loads, Universal Autoload then picks up only pallets of the chosen products and leaves the others. Pallets you put on by hand or with a forklift are always accepted, and nothing changes while you drive yourself. The choice is saved with the vehicle and sent to all players. Bulk loading (silos, piles) is not affected.

### Best price unloading
New vehicle setting **Best price unloading**, for pickup and deliver and for unload. Put all the selling points you want to use as targets into one folder and choose one of them as the unload target. When the vehicle is loaded and sets off to unload, it compares the current prices of the selling points next to these targets (within 60 m) and tells you where it goes:
- **One stop (whole load):** the target where everything on board together brings the most. Products that selling point does not buy stay on board.
- **Each product (several stops), maximum profit:** the product worth the most goes first, to the target that pays the most for it. At each stop only the products that get their best price there are unloaded; everything else stays on board, even if that selling point would buy it for less. Then pickup and deliver drives on to the next target for what is left, until nothing sellable is left (at most 5 stops). This works per trailer (or per tipping compartment): a trailer with a product for another stop simply stays closed. In unload mode there is only one stop, so it works like one stop.

The vehicle's own tanks (diesel, DEF, ...) are never counted as load. A stop is done when the selling point takes nothing more, so a vehicle never waits forever for a product the point does not buy. It needs "use folders", does nothing while target rotation for unloading is on, and the target must be in a folder, not in "All".

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
| Waypoint action: unlock load | Ctrl + Alt + B |
| Speed zone 15 / 30 / 50 km/h, remove | Ctrl + Alt + 1 / 2 / 3 / 0 |
| Unload products (vehicle, or the target under the mouse in the editor) | Ctrl + Alt + F |
| Load products (pallets) | Ctrl + Alt + G |
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

The mod zip contains `drawing`, `gui`, `scripts`, `sounds`, `textures`, `translations`, `icon_AutoDrive.dds`, `modDesc.xml`, `register.lua`, `LICENSE` (as `LICENSE.txt`) and `credits.txt`. The `tools` and `.github` folders are for development and not part of the mod.

GIANTS' mod checks allow at most 128 files in a mod and Lua files of at most 0.5 MB, so the build joins the scripts that `register.lua` loads into `scripts/OverdriveBundle1.lua`, `OverdriveBundle2.lua`, ... (same order, each file in its own `do ... end` block, each bundle below 450 KB) and the zip's `register.lua` loads them one after another; the scripts the game loads itself as specializations stay separate. The source tree is unchanged. The build writes `FS25_AutoDrive.bundlemap.txt` next to the zip to find the source file of a bundle line in an error message.

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
