# AutoDrive Overdrive

[![CI](https://github.com/chrisdfennell/FS25_AutoDrive/actions/workflows/ci.yml/badge.svg)](https://github.com/chrisdfennell/FS25_AutoDrive/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/chrisdfennell/FS25_AutoDrive?label=release)](https://github.com/chrisdfennell/FS25_AutoDrive/releases/latest)

AutoDrive Overdrive is an unofficial edition of [AutoDrive](https://github.com/Stephan-S/FS25_AutoDrive) for Farming Simulator 25, by the AutoDrive Team (Stephan-S, Axel32019, TyKonKet and [many contributors](credits.txt)), released under the [MIT licence](LICENSE).
It is based on AutoDrive 3.0.1.4 and adds route editor improvements. For the official mod and its support, see the original README below.

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

### Key bindings
| Action | Default key |
|---|---|
| Undo route edit | Ctrl + Z |
| Redo route edit | Ctrl + Y |
| Preview the next undo (hold) | Left Alt + Z |
| Move waypoint (hold, then drag with the left mouse button) | Left Shift |

All key bindings can be changed in the game's control settings.

### Notes
- The mod keeps the name `FS25_AutoDrive`, so it replaces the official AutoDrive mod: install either one, not both. Savegames, routes and settings of the official version keep working.
- In multiplayer, all players need the same version of the mod.
- The new texts are translated into all languages of the mod. Corrections from native speakers are welcome.
## For developers
Every push and pull request runs the [CI workflow](.github/workflows/ci.yml):
- a Lua 5.1 syntax check, the Lua version the game uses
- static checks: XML files, translation placeholders, every script loaded by `register.lua` exists ([tools/ci_checks.py](tools/ci_checks.py))
- the undo / redo tests ([tools/tests](tools/tests)), which run the mod code outside the game with stubs for the game API
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
