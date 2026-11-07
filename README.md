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

### A new look
The HUD looks like CourseCorrect's panel: a dark rounded panel with a soft shadow and a green line along the top, the title in bold with the mode, time and task in grey, every button on a rounded chip that lights up under the mouse and turns green when it is on (start / stop, editor, recording, yes / no settings, loop counter), and the target lists as rounded fields; an opened list is a panel of its own with the row under the mouse highlighted. The waypoint panel, the selection menu and the route-check count match. Everything works as before. The HUD colours in the settings still apply (background, the line along the top = header colour, texts); colours never changed by a player move to the new ones. It also draws a little faster: button images, the header text and the list names are only worked out again when they change.

### Overdrive tab in the settings
All settings Overdrive adds have their own tab in the AutoDrive settings window (speedometer icon), so the other tabs are the same as in AutoDrive:
- **This vehicle:** Best price unloading, While tipping, Drive clear when blocked, Drive through obstructions (No AI Collisions), Start work at, Stop work at, Pipe Offset Front/Back, Refuel at. Shown only while you sit in a vehicle; they are saved on that vehicle, and "Make default" works as on the vehicle tab.
- **You:** Waypoint panel, Ticker at the bottom, Fleet on the map. Only for you; the server keeps them per player.

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
- **Multiplayer:** the history is kept on the server and each player undoes their own edits, also on a dedicated server. An older own edit can be undone even if others edited afterwards, as long as their edits don't depend on it; otherwise the message names the player who changed the network in the meantime. Diagnostic lines starting with `[AD Undo]` are written to the game log in multiplayer.
- The history holds the last 100 steps and lasts until the game is closed or the savegame is left. A few changes outside the editor clear it, e.g. switching on the road network debug markers or placing the colour selection points; a message then tells you why.

### Target folders
- **Sub folders:** folders can contain folders (shown indented in the target list, e.g. "Farm" › "Silos"). A sub folder is only listed when its parent folders are expanded.
- In editor mode, each folder in the target list has icons to **add a sub folder**, **rename** it (sub folders and targets move along) and **change its colour**. Clicking the colour square cycles through 12 colours and back to the default. The folder name is shown in its colour.
- Folder colours are saved with the savegame and included in route exports of the routes manager.
- In editor mode, each target in the list has a rename icon, to rename any target directly from the list.

### Waypoint editing
- **Move waypoints by dragging:** hold **Left Shift** and drag a waypoint with the left mouse button. The waypoint goes where the mouse points at the road or the ground, at its height, also on hills and slopes. A short click without moving still toggles the side road setting as before. The key can be changed ("AD: Hold + left mouse drag to move waypoint").
- **Select several waypoints:** hold **Ctrl + Shift** and drag a box with the left mouse button: every waypoint in it is selected. **Ctrl + Shift + click** a waypoint to add it to or take it out of the selection (while something is selected, **Ctrl + click** does the same, like in Windows). When you let go of the keys, a menu opens at the mouse: **Move** (the waypoints follow the mouse, click to put them down), **Put on the ground**, **Side road** on / off, **Direction** (one-way and tidy up Even / Straight / Smooth when the selection is one unbranched line; two-way and flip for every connection between selected waypoints), **Delete** and **Deselect**. Each action is one undo step. A click outside the menu closes it and clears the selection. Shortcuts: **Alt + click** a selected waypoint deletes them all; dragging one of them (Left Shift + left drag, or right / middle drag) moves them all. With nothing selected, Ctrl + click and Ctrl + Shift + click on the ground do what they did before.
- **Route problems where they are:** while the editor is on, AutoDrive checks the route network by itself a moment after every change and marks each problem on the spot: a tall beacon (orange: dead end or loose waypoint; red: trap, or a target that can not be reached or left) with its text above it, the number of problems and the distance to the nearest one under the HUD, an arrow towards it when it is out of sight, and squares on the big map. Setting "Route problems in the editor" on the Overdrive tab.
- **Unloader that keeps missing the combine:** after 8 new paths in a row without getting lined up with the combine, it stands still for 30 seconds and says why, and which two settings to check for long trucks and trailers, instead of driving circles. Each new path is written to the log.
- **Unloader never cuts through the crop to the combine:** with Avoid Fruit on, an unloader driving up to a combine's pipe first searches further for a way, may leave the field border (Restrict to Field) as before, but no longer gives up on avoiding fruit. If there is no way around the crop it stands still and shows "No way around the crop to the combine, waiting", then plans again a few seconds later (the combine may move or the harvested area grow). Written to the log once. Chasing the combine is as before.
- **Construction screen:** while landscaping (painting, shaping the ground), the left mouse button belongs to the brush: AutoDrive shows the routes but does not select, connect, create or drag waypoints with it there.
- **Deleting a waypoint** removes all targets on it, not only the first one, and every connection pointing to it. Before, a second target or a reverse connection could be left pointing at the next waypoint.

### Tidy-up tools
Select a waypoint with a left click, point the mouse at another waypoint on the same route and press:
- **Ctrl+Alt+J** to even out the spacing: the waypoints stay on the route, at equal distances
- **Ctrl+Alt+K** to straighten: the waypoints are lined up between the two waypoints
- **Ctrl+Alt+U** to smooth: kinks and zig-zags of e.g. a recorded drive are rounded off. Waypoints only move sideways out of a kink, never along the route, also next to long connections

The same tools are in the **waypoint panel** for the whole road a waypoint is on, without pointing at a second waypoint.

The route between the two waypoints is the shortest by distance. Only waypoints between them are moved, both end points stay where they are, and connections, targets and side road settings don't change. Heights follow the ground. Each tidy-up is one undo step.

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

**Fleet on the map:** the big map (ESC > Map) shows every AutoDrive vehicle of your farm as a coloured square with its name: green driving, yellow switched on but standing, red stopped with a problem, grey idle. Switch it off on the Overdrive tab of the settings (**Fleet on the map**).

### Waypoint panel
In the editor, **left-click a waypoint** to select it: a panel opens next to the AutoDrive HUD with everything about that waypoint, as buttons:
- **Target** (first, right under the waypoint number): its name in orange with **Rename...** and **Remove**, or **No target** with **Add target...**: a text box opens, type the name and press Enter, and the target is put on this waypoint
- **Height:** **-0.5** / **+0.5** move the waypoint down or up by half a metre a click (only the height changes; Ctrl+Z puts it back, quick clicks undo together)
- **Delete waypoint** (red, under the height and distance): deletes the waypoint like the editor's delete, with the targets on it and all connections to it; one Ctrl+Z brings it all back
- **Vehicles** (on a target): **Drive here** sends the vehicle you are in to this target (drive to, and it starts); **Send vehicle** lists the AutoDrive vehicles of your farm, nearest first (busy ones are marked), and sends the one you pick
- **Park here**: **Yes** makes this target the vehicle's parking place (where it goes when its job is done, like AutoDrive's park button: for the selected implement if one is selected); **No** removes it. On a waypoint without a target, **Park here** creates a target named "Park" plus the vehicle's name and makes it the parking place
- **Side road:** no / yes for this waypoint
- **Connections:** every neighbouring waypoint with the kind of connection (out, in, both ways, reverse out, reverse in). Click it to switch to the next kind, **X** removes the connection; pointing at a row draws a line to that waypoint
- **Actions:** wait (each click: next time), horn, lights, unlock load
- **Speed zone** for this waypoint

**Road** is the stretch the waypoint is on, up to the next junction in both directions (the number of waypoints is shown):
- **Speed zone** and **Side road** for the whole road
- **Direction:** **One-way** (the way most of it already goes), **Two-way**, or **Flip** to turn it round. The junctions at both ends are connected the same way; their other roads stay as they are
- **Tidy up:** **Even**, **Straight** or **Smooth**, like Ctrl+Alt+J / K / U, without pointing at a second waypoint. The junctions stay where they are

Every click is one undo step and works in multiplayer like the keys. The panel stays while the waypoint is selected, also while you move the mouse onto it; **X**, clicking the waypoint again, or connecting it to another waypoint closes it. It moves to the left of the HUD when there is no room on the right. Switch it off on the Overdrive tab of the settings (**Waypoint panel**).

### Ticker at the bottom
A bar along the bottom edge of the screen scrolls, like a news ticker:
- first the numbers for the whole server: how many vehicles AutoDrive drives right now (and how many of them wait), how many Courseplay drives, and how many the game's own helpers drive
- every AutoDrive vehicle of your farm that is switched on, with what it is doing (the line from its HUD, e.g. "Drive to unload point")
- **why it waits** when it stands, worked out by the server: waiting in line to unload, at a waypoint (seconds left), giving way to another vehicle (its name), blocked by something ahead, loading (litres), waiting for more load (litres still free), tipping (litres left), tipping but nothing comes out (for how long), at the unload point with load on board, or just standing (for how long)
- AutoDrive vehicles that stopped because of a problem, for as long as they stand: errors in **red**, warnings in yellow
- Courseplay vehicles of your farm with their Courseplay info texts: errors (no path found, stuck, blocked, out of fuel, broken, ...) in **red**, things to look after (fuel low, needs filling / unloading, waiting for rain) in yellow, the rest in white
- the AutoDrive messages of the last 3 minutes (warnings in yellow, errors in red). The pop-ups at the top stay as they are.

It is **off until you switch it on**: AutoDrive settings, Overdrive tab, **Ticker at the bottom**. Each player chooses for themselves (the server keeps the choice per player). When on, it is hidden in menus and when the game's HUD is off; otherwise it is always there (with the numbers), even when nothing drives.

Every wait reason and every Courseplay info comes with a short hint in grey on what it means or what to check (e.g. "Blocked: the obstacle detection sees something in front: a vehicle, object or person").

### Error messages that say what to check
AutoDrive's error and warning messages tell what happened, with what, and what to look at. They are in all 18 languages, and the server writes each one to its log.txt as `[AD] ...`, so you can read them there later. For example:
- **Can't calculate a path**: the target and how far the vehicle is from the route network. AutoDrive also tells the two cases apart:
  - the nearest waypoint has no route to the target: check the arrows there, or run Route check;
  - no drivable way to the network: buildings, fences, trees, vehicles or steep ground are in the way.
- **Can't reach** a target: the waypoint it starts from. It may stand on the other lane of a one-way road.
- **Got stuck**: the next waypoint, how far away it is, the speed, and what blocks it (the other vehicle's name).
- **No refuel station**: each fuel it needs with the tank level, and how many stations with that fuel were found. A target has to be within 15 m of the pump.
- **No workshop**: the damaged units with their damage, and how many workshops were found.
- **No park destination**: which tool it is missing for. The park target is saved for each tool.
- **Wrong mode to take over from Courseplay or the helper**: the current mode, and which modes work.
- **AI helper still active**: whether Courseplay or the game's helper drives the vehicle.
- **Can't start the helper**: not on a field, or the game's reason.
- **Bunker silo**:
  - the shovel: lists what is attached;
  - no bunker in reach: it must be within 100 m;
  - nothing to load: names the product;
  - no trailer: what a trailer needs to be picked.
- **Recording two roads stopped**: why (both offsets the same, or reversing).
- **A mode started without its targets**: says so, instead of doing nothing.
- **Leaving the field without a route to the unload target**: says it.
- **Universal Autoload version not supported**: one warning per session.

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

**Strapped pallets and bales:** pallets and bales held by the game's tension belts (strapped with L) count as load, on ordinary trailers and also on Universal Autoload vehicles for the pallets Autoload did not load itself (put on by forklift): AutoDrive sees them as soon as the belts are fastened, and a strapped load counts as full, so in pickup and deliver strapping it (L) is the sign that the truck can go. Best price and the unload products list see these products too. At the unload target AutoDrive releases from the belts **only the pallets and bales of the products it sells there** (with best price "each product": the ones that get their best price at this stop), one by one, wherever they sit on the trailer; the belts stay closed and everything else stays locked, and a locked pallet cannot be sold. It waits while the selling point takes them (until all released ones are sold, 5 seconds after the last sale, at most 60 seconds). Whatever is still left is locked again, and drives on to the next stop, until everything is sold at its best price. Set it and forget it: load and strap the trucks any way you like. The target has to be placed so that the trailers stand in the selling point's pallet area. Tractors or machines on a low-loader never count and are never released.

A trailer only tips if its product is allowed by the vehicle, by the target, and by best price "each product". A stop with something left on board is done when nothing has been tipped for 3 seconds. Best price only plans with the products the vehicle unloads and only at targets that take them. This works per trailer (or per compartment that tips on its own).

### Load products (pallets)
Choose which pallets the vehicle picks up with **Universal Autoload**. Open it with **Ctrl+Alt+G** in the vehicle, with the HUD button for the automatic pickup target (pickup and deliver and load mode, while that upstream feature is off), or in the fleet overview: double click a vehicle > **Load products...**. The list shows the products of the pallets within 60 m of the vehicle or of its load target, with how many there are; click products to select them, **All products** removes the limit.

When AutoDrive loads, Universal Autoload then picks up only pallets of the chosen products and leaves the others. Pallets you put on by hand or with a forklift are always accepted, and nothing changes while you drive yourself. The choice is saved with the vehicle and sent to all players. Bulk loading (silos, piles) is not affected.

### Best price unloading
New vehicle setting **Best price unloading**, for pickup and deliver and for unload. Put all the selling points you want to use as targets into one folder and choose one of them as the unload target. When the vehicle is loaded and sets off to unload, it compares the current prices of the selling points next to these targets (within 60 m) and tells you where it goes:
- **One stop (whole load):** the target where everything on board together brings the most. Products that selling point does not buy stay on board.
- **Each product (several stops), maximum profit:** the product worth the most goes first, to the target that pays the most for it. At each stop only the products that get their best price there are unloaded; everything else stays on board, even if that selling point would buy it for less. Then pickup and deliver drives on to the next target for what is left, until nothing sellable is left (at most 5 stops). This works per trailer (or per tipping compartment): a trailer with a product for another stop simply stays closed. In unload mode there is only one stop, so it works like one stop.

A selling point counts only for the target nearest to where it is unloaded: a factory with a loading and an unloading section can have a target at each, and only the one at the unloading section gets its price (if that target does not take the product, see unload products, the next nearest does).

The vehicle's own tanks (diesel, DEF, ...) are never counted as load. A stop is done when the selling point takes nothing more, so a vehicle never waits forever for a product the point does not buy. It needs "use folders", does nothing while target rotation for unloading is on, and the target must be in a folder, not in "All".

### Refuel at
New per-vehicle choice **Refuel at**, on the Overdrive tab and next to Auto Refuel on the vehicle tab: **Nearest** (default) or one of the targets at a refuel point for the vehicle's fuels. It is used for the refuel button, for auto refuel during AutoDrive's jobs and when Courseplay hands a vehicle over to refuel. It is stored as the target's name, so editing the network does not change it. If the chosen target is gone, has no refuel point with fuel for the vehicle, or the farm has no access, the vehicle refuels at the nearest one and the log (and a message) says why.

Nearest is now measured along the routes instead of in a straight line (straight line if the network gives no route), and a refuel point of the vehicle's own farm wins if it is at most 1.5 times as far as the nearest one.

Other mods: `AutoDrive.getRefuelDestination(vehicle)` gives the target name (`""` = Nearest), `AutoDrive.setRefuelDestination(vehicle, name)` sets it (synced in multiplayer), `AutoDrive.getRefuelDestinationChoices(vehicle)` lists the names that can be chosen.

### Pipe offset front/back
New vehicle setting for combine unloaders, **Pipe Offset Front/Back** (setting `pipeZOffset`, -5 m to +5 m in 0.25 m steps, default 0). Pipe Offset moves the unloader out from the combine or in; this one moves its place beside the combine forward (+, towards the combine's front) or back (-), to fill a long trailer evenly or to keep the cab clear of a wide header. It is used for the place it drives to and the place it keeps while unloading, not when it chases behind the combine (Follow distance does that) and not for auto-aiming choppers or sugarcane harvesters. On the vehicle tab next to Pipe Offset and on the Overdrive tab. Other mods can set it like any vehicle setting (`AutoDrive.setSettingState`, then `AutoDriveUpdateSettingsEvent.sendEvent(vehicle)`).

### Drive clear when blocked
New vehicle setting for combine unloaders, **Drive clear when blocked** (off by default). When the unloader
- stands in front of a harvester driven by a helper (AutoDrive's harvester helper or Courseplay) for 6 seconds, with both standing still, or
- is stuck against another vehicle (where AutoDrive would otherwise reverse),

it switches off its collisions with other vehicles (its trailers too; the ground, buildings and trees still count), drives through to the nearest field edge and a few metres past it, waits there until no other vehicle is near, switches its collisions back on and carries on with its job. Collisions only come back when nothing overlaps, otherwise the physics would throw the vehicles apart; if AutoDrive is stopped during the escape they come back by themselves once the unloader is clear. A message tells you when a driver does this, and it happens at most every 90 seconds per vehicle.

### Drive through obstructions (with No AI Collisions)
The **No AI Collisions** mod (by PropaineX) lets a helper that has been stopped by an obstruction for 2 seconds switch its collisions off and drive through it. With that mod loaded, the Overdrive tab of the settings shows **Drive through obstructions (No AI Collisions)**, right below Drive clear when blocked (without the mod the row is hidden):
- **Yes** (default): the mod decides, as before.
- **No**: the mod leaves this vehicle alone, and it waits like AutoDrive normally does. Useful for a long unloader that the mod would otherwise push into its own combine.

AutoDrive only publishes the choice as `vehicle.ad.allowDriveThrough` (on the root vehicle; nil counts as yes). No AI Collisions has to read it; a version that doesn't simply ignores the setting.

### While tipping
New vehicle setting **While tipping**, **Stand still** by default (since od.37, also for vehicles saved before):
- **Drive through** (as AutoDrive always did): in a bunker silo or on a heap the vehicle drives slowly through while tipping, to spread the load along the silo.
- **Stand still:** once the vehicle stands for tipping it gets no throttle at all (no drive request to the gearbox), the handbrake, and the full brake on the vehicle **and every trailer** (AutoDrive's normal hold gives a touch of throttle and only brakes the truck, so a heavy trailer tipping backwards could push it along). Everything is released as soon as the load stops running: the trailer is empty or the tipping place takes nothing more.
  - **Silo pit / tip trigger, truck with trailer:** the vehicle does not drive on while one of its units is open and the load is running, also when AutoDrive lost track of which unit tips (it used to creep on with the grain still flowing). When nothing has come out for 1.5 seconds it drives on as usual, e.g. to bring the trailer over the pit.
  - **Bunker silo / heap (tipping onto the ground):** the vehicle stops at the first place where it can tip and stays there. It waits up to 30 seconds for the load to start running (the tipper body rises first). Once it ran, when nothing comes out for 6 seconds (the heap is as high as it gets), it moves on slowly until the load runs again, and stops again. Reversing into a silo works as before.

On the ground this only works where AutoDrive knows the vehicle tips onto the ground: a bunker silo or a heap area. The server log shows a line `[AD] <driver>: tipping on the ground (bunker silo / heap), setting stand still` (or `drive through`) when it starts.

### Work schedule
New vehicle settings **Start work at** and **Stop work at** (in-game hours, `--:--` = off).
- At the start hour the driver starts its job, with the mode and targets set in the HUD.
- At the stop hour, pickup and deliver finishes the round it is on (loading and unloading) and then drives to its park position, if one is set. Other modes stop right away.
- Skipping time (sleeping) counts: the later of the two hours that were skipped decides.

### Longer run-up to the pipe
When a combine unloader drives up to a combine's pipe, the straight stretch it gets after its last turn is 50% longer than in AutoDrive (`runUpFactor = 1.5` in `PathFinderModule:startPathPlanningToPipe`), so the trailer has time to line up behind the tractor instead of coming in at an angle. Combines: half the combine's length plus 0.765 x the tractor-and-trailer length, now x 1.5, at least 10.5 m (was 7 m); for a 12 m combine and an 18 m rig that is 29.7 m instead of 19.8 m. Choppers with a fixed pipe: 1.5 combine lengths instead of 1. Auto-aiming choppers and chasing straight behind a combine have no run-up and are unchanged. On tight headlands the unloader may swing out a little further before it comes in.

### Keep out of the harvester's way
While a combine unloader waits on the field to be called, it checks every second whether it stands where a working harvester (combine or chopper, within 200 m) is going to drive:
- in the strip in front of the harvester: 50 m ahead, its working width plus 5 m on each side (`AHEAD_LENGTH`, `AHEAD_MARGIN`), or
- where the harvester will turn: the headland band (20 m, or two working widths if that is more) at the end of the field it is heading to, from its own lane toward the side with standing crop; crop on neither or both sides counts both ways (`getTurnZone`).

Parking next to standing crop, or in the headland on the side the harvester turns away from, is fine.

After 3 seconds in the way it drives with the pathfinder to the nearest spot on harvested ground that is at least 15 m clear of the strip and clear of where the harvesters turn (tried from 15 to 80 m away, directions away from the harvesters first, no other vehicles there), parked along the working direction; if there is none, 15 m outside the field edge. Then it waits for a call again. While it moves it shows *Moving out of the harvester's way* and is not on the harvest manager's list of free unloaders, so no harvester calls it halfway. After a move it checks again after 15 seconds; after three failed moves in a row it waits 60 seconds. It is not checked while the unloader drives to a combine, unloads or drives off to unload, nor for a second unloader queued behind the active one (Drive clear when blocked covers that). Code: `scripts/Manager/UnloaderClear.lua` (`ADUnloaderClear`, called from `CombineUnloaderMode:monitorTasks`), `scripts/Tasks/MoveClearOfHarvesterTask.lua`.

### Staying under the pipe
When a combine unloader chases a combine that unloads on the move, it pushes harder to get back under the pipe. Within 1 m of its place it drives exactly the combine's speed, no faster; further back it aims for the combine's speed + 1 km/h + 3 km/h for every metre beyond that (within 20 m; AutoDrive used 1.4 km/h per metre under 7 m and 2 km/h per metre under 20 m, so it crept up slowly and the combine kept getting away). Once past its place it drops below the combine's speed and slides back instead of overshooting. Field speed stays its top speed. Only the pipe chase uses this (`chaseCatchUp` argument of `ADSpecialDrivingModule:driveToPoint`, passed by `FollowCombineTask:followChasePoint`; numbers `CATCH_UP_GAIN`, `CATCH_UP_LEAD`, `UNDER_PIPE_DISTANCE`); bale unloading, reversing from a bad location and the escape to the field edge drive as before.

### Driving like a semi while chasing
While chasing a harvester's pipe (`driveToPoint` with `chaseCatchUp`) with a trailer of 4 m or more attached, the unloader never steers tighter than `TRAILER_TURN_RADIUS` (12 m): pure pursuit, the angle to the spot is capped at asin(distance / 24 m), so a spot inside its turning circle is no longer chased at full lock (it drove in circles or jackknifed). Jackknife guard: cab more than `JACKKNIFE_ANGLE` (45 deg) off the trailer -> wheels straight, at most 8 km/h, until under 15 deg. Code: `ADSpecialDrivingModule:limitTrailerSteering`.

### Unloading a standing combine
When an unloader is sent to a combine that stands still (`EmptyHarvesterTask`) and the combine starts to drive, the unloader switches to chasing it after half a second (`FOLLOW_AFTER`), whatever it is doing: planning its way there, driving up, waiting for the pipe or unloading. AutoDrive only checked this while unloading, stood still for 4 seconds first, and gave up (back to waiting for a call) when the unloader was next to crop. It only counts once the combine has been seen standing, because a moving combine that is nearly full is also sent an unloader this way. If a combine set to **Active unloading** is emptied while standing and the unloader still has room, it stays with the combine and follows it instead of going back to waiting for the next call (not for choppers, not while the combine turns or stands in a Courseplay pocket).

### Active unloading: always chasing
With **Active unloading** on, a combine unloader is always in chase mode (`FollowCombineTask`), never a standing unload. When it reaches a standing combine it goes straight into chase mode (`EmptyHarvesterTask:startUnloading`, flag `standingCall`) and holds still under the pipe while the combine stands (also whenever it is within 3 m of its chase point). The moment the combine rolls, it rolls with it, with no hand-over to miss. It also gets an unloader from the start: with Active unloading on, `ADHarvestManager.isHarvesterActive` ignores the pre-call level and the 90 % cut-off, so the closest free unloader is sent as soon as the combine works; the rear chase no longer holds back for the pipe over crop (above 70 % / 85 %) either. The three "combine nearly full" give-ups are off with Active unloading: FollowCombineTask's "over 90 % and within 25 m, reverse", CatchCombinePipeTask's "over 91 %, wait for a call", and CombineUnloaderMode sending a moving combine over 94.5 % a standing-style unloader. Active unloading off, choppers, a turning combine and a Courseplay combine in a pocket: unchanged.

### When the harvester leaves
When a harvester stops working (off to refuel or repair, helper off, pipe folded), `ADHarvestManager:fireUnloader` no longer stops its unloader with AutoDrive switched off. `CombineUnloaderMode:onHarvesterLeft` sends it off to unload if its trailer is at least 50 % full (`LEAVE_UNLOAD_LEVEL`), or else back to waiting for a call. A queued second unloader does the same. With Active unloading on, a harvester only gets an unloader while it is on a field.

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
