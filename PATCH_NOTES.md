# AutoDrive Overdrive: PropaineX edits, patch notes

Changes made on top of AutoDrive Overdrive (by chrisdfennell, based on AutoDrive by the AutoDrive Team).
Newest first. "Untested" means it has not been tried in the game yet.

## 3.10.0.0 (2026-11-07): Nexat harvester fix
*Untested in the game; Lua syntax checked, helpers tested with mock vehicles.*

- The Nexat's harvester module (nexco) sits on its carrier turned 90 degrees: the module faces the way it harvests,
  the carrier drives sideways. AutoDrive read the harvester's direction, size and side sensors from the carrier, so
  all of it was 90 degrees off. A harvester module mounted 45-135 degrees to its carrier now counts as sideways, and
  then the module's own heading is used, with the carrier's length as the rig's width. Logged once when found.
- Fixed with that: the strip in front of the harvester that waiting unloaders keep out of (and the turn zones and
  parking direction), the "unloader stuck in front of the harvester" escape check, the side sensors that pick the
  chase side, the turn-finished check, the rear-chase offset, the harvest manager's "side blocked" check and the
  clear-crop task. The Nexat gets its own sensor set facing its working direction, the side ones placed outside
  the carrier's wheel units.
- The pipe-lock tail check, wrong-side check, back-off and the gap to the combine use the Nexat's full width
  (carrier wheel units), not just the module.
- Every other harvester (self-propelled, pulled, reverse-mounted) is unchanged.

## 3.9.2.0 (2026-11-06): parking spot can be set from the map / helper screen
*Untested in the game.*

- Ctrl + right-click on the park button (P) did nothing unless you were sitting in the vehicle: the action was
  marked "own vehicle only", so from the map / helper screen or on foot the click was silently dropped (while the
  left-click "go park" was allowed and said "No parking destination assigned"). It now works from anywhere, like P.

## 3.9.1.4 (2026-11-05): no lazy arcs, cover at the combine, backing off only on tight inside corners
*Untested in the game; tested in a simulator (108 of 116 cases pass).*

- The slow, long arcs: the trailer guard straightened the wheels and held 8 km/h whenever the cab was 45 degrees off
  the trailer, i.e. in every hard turn. It now only steps in at a real fold (75 degrees) and no longer slows it.
- Trailer cover: shut until the unloader is within 50 m of the combine it unloads (it opened the moment the harvester
  called it). Road and silo trips unchanged.
- Reverse, the only time while chasing: on the inside of a real corner (the combine has turned more than 47 degrees
  toward its side, tighter than a semi can follow, and it is within 15 m) it backs straight up until there are 30 m
  between it and the combine, then goes forward at once. Logged each time. Never on lane changes.
- "Wrong side" only when actually beside the combine on the other side; from behind its tail it comes up the pipe
  side directly (no long arc).
- Ahead of the pipe spot and facing the combine's way: it eases off and lets the combine come up, instead of driving
  on and turning round through its path.

## 3.9.0.4 (2026-11-05): pipe lock: under the pipe and stay there
*Untested in the game; tested in a simulator.*

- Active unloading on a combine (not forage harvesters): the unloader now does one thing only, stay under the pipe at
  the pipe's speed. It no longer waits for turns, waits for the combine to pass, backs up, pulls forward or gives up
  because it is on the wrong side. It steers for where the pipe will be in 1.5 s (from the combine's speed and turn
  rate), so it follows lane changes and curves instead of lagging behind.
- Farther than 50 m from the combine it just drives straight to it; the pipe tracking starts inside 50 m. Its speed is
  only capped by your field speed limit setting (AutoDrive's own hidden 40 km/h chase cap is gone); it slows as it
  reaches the pipe.
- It steers at a point 12 m ahead along the combine's line (not at the spot beside it), following a smoothed
  straight line: small wobbles of the combine (under 4 deg/s) don't reach its wheels, so it drives straight instead of
  weaving; real turns are followed at once.
- On the wrong side of the combine it never cuts across it: it drops back behind the tail and comes round.
- Combine standing: it holds still under the pipe; nothing going in for 2 s -> it creeps along the trailer.
- Trailer full: it leaves to unload. Something physically in its way: it stops.
- On the inside of a corner tighter than a semi can turn it drops off and comes round forward, no reversing.
- Also: the trailer cover is only open while working a combine; shut while waiting to be called.
- Simulator (114 cases, real AutoDrive steering/speed code, bending trailer): 104 pass, never reverses. Straight,
  wobbling combine (0 steering flips/min), lane changes 10-45 deg, stop-go, speed changes, field speed limits: all pass.
  Not passing: tight inside corners (a semi can't turn that sharp: it loops round and comes back), +-30 deg S-curves
  at 6 km/h (up to 2.7 m off at the peaks), starting beside the combine facing the other way (long loop first).
  Staying under the pipe through corners lets the combine's tail touch the trailer in the simulator.

## 3.8.5.4 (2026-11-05): corners without the veer (not zipped)
*Untested in the game; tested in a simulator only.*

- Pulling forward no longer happens while chasing, so lane changes don't set it off (that veered the truck away).
  It drives straight ahead, no longer steering away from the combine.
- While the combine is flagged as turning (also about 9 s before a headland corner) the unloader drops back behind the
  combine's tail on its side, then moves back under the pipe when the flag clears.
- Pull forward only on the outside of a turn while the combine is still turning; on the inside it stands and lets
  the combine turn away. Chasing from behind: never pulls forward.
- Simulator: lane changes 10-45 deg never pull forward; outside corners stay 2.5-3.2 m clear. Still failing there:
  inside corners (clips the combine when chasing again after the turn) and lane changes of 30 deg and more.

## 3.8.4.4 (2026-11-05): pulls forward at corners, every time
*Untested.*

- The "pull forward out of the combine's tail" check only ran while chasing. At a corner the unloader had usually
  already switched to waiting for the turn (stop, or back up when close) or quit chasing because it was in front, so
  it got pinned beside the combine. Now the check runs while chasing, waiting for the turn and waiting for the
  combine to pass, and it fires at 3 m instead of 1.5 m.
- Waiting for a turn close beside the combine: it pulls forward (once per turn) instead of backing a semi up. Straight
  behind the combine it still backs up as before.
- While pulling forward the combine now counts as something in the way: if it can't move for 3 seconds it backs up.
- The game log now says each time it pulls forward (and how close the tail was) or has to back up instead.

## 3.8.3.4 (2026-11-05): lane changes followed again
*Untested.*

- 3.8.0.4 made the unloader pull forward and away as soon as the combine turned 15 degrees away from its side. A
  lane change does that too, so it drove off on lane changes. Now it doesn't look at the angle: it only pulls
  forward when the combine's rear corner on its side actually comes within 1.5 m of the truck or trailer (a corner
  swinging its tail into it). Otherwise it follows, lane changes included; past 47 degrees the normal turn handling.

## 3.8.2.4 (2026-11-05): fills the whole trailer at a standing combine
*Untested.*

- At a standing combine (Active unloading) the unloader held completely still under the pipe, even when the part of
  the trailer under the pipe was heaped full and nothing was going in. The combine waited for the trailer ("Needs to
  be unloaded") and the trailer waited for the combine.
- Now it only holds still while grain is going in. If the combine has grain, the trailer has room and nothing has
  gone in for 2 seconds, it creeps at walking pace (3 km/h) to move the emptier end of the trailer under the pipe:
  forward if the pipe is over the front half, back if it is over the rear half. It stops as soon as grain flows
  again. At the end of the trailer it tries the other way once, then waits.
- Just past its spot beside a standing combine (under 3 m), it stops instead of swinging round.

## 3.8.1.4 (2026-11-05): no more long reversing across the field
*Untested.*

- When an unloader is "stuck" it backs out. It aimed 100 m straight back and kept going (up to 30 m or 20 seconds) as
  long as its front looked blocked, and crop in front counted as blocked, so it reversed far across open field.
  Now crop doesn't count (only real objects), and it backs up 10 m at most.
- The usual way it got "stuck": it had passed the spot beside a standing combine and stood still to drop back, which
  after 15 seconds counts as stuck. Now, with the combine standing, it drives on slowly (8 km/h) and swings round to
  the spot. With the combine moving it still drops back and lets the combine come up to it.
- Backing out no longer closes the trailer cover; the cover still closes on the road as before.
- Every time it backs out, the game log now says why (failed path searches or blocked) and what it was doing.

## 3.8.0.4 (2026-11-05): out of the way at corners, cover stays open
*Untested.*

- A combine steers with its rear wheels, so in a turn its tail swings out the other way. When the combine turns away
  from the unloader's side by more than 15 degrees, the unloader beside it now pulls forward (straight on and a little
  away) by the combine's length plus 6 m, then waits for the turn and chases again. Before, it kept chasing to 47
  degrees and then tried to back a semi out, after the tail had already swung into it.
- If it can't move forward for 3 seconds (something in the way) it backs out as before.
- The combine turning toward the unloader's side (tail swings away), and an unloader straight behind: unchanged, so
  lane changes are still followed.
- Trailer cover: while working combines in the field (waiting for a call, driving to and chasing the combine, moving
  aside), the cover is kept open, checked every second. It used to be opened only when a task started, and some tasks
  (backing out of a bad spot and others) closed it, so it stayed shut partway through a field. Still only with the
  'auto trailer cover' setting on.

## 3.7.1.4 (2026-11-05): no more catch-up stops behind a moving combine
*Untested.*

- With Active unloading, a moving combine and the unloader on the same field beside or behind it, the unloader now
  goes straight into chasing. Before, it planned a route to where the pipe was (standing about 7 s each time), drove
  it, and by then the combine had moved on, so it stood and planned again: in one test 8 times in under 3 minutes,
  then a 30 second wait.
- While chasing a moving combine from the wrong side it keeps driving round to its side instead of giving up.
- Ahead of the combine, or not on its field, it still plans a route as before (chasing from in front would aim at
  the header).
- The 30 second wait after too many new routes no longer sets off the "no path within 10 s, moving aside" check (it
  did, 11 s into the wait, which stopped it once more).

## 3.7.0.4 (2026-11-05): the combine moves, the unloader moves
*Untested.*

- While chasing a combine that is moving, the unloader no longer stops because the spot behind or beside the combine
  is off to its side or behind it, or because it is far away. Before, it stood still once the spot was more than 50
  degrees off for 3 seconds or behind it, then backed away after 15 seconds, waited 8 more and only then planned a new
  route. Now it keeps driving and swings round to the spot (no tighter than a semi can turn), whether it is on the
  field, on the edge or just off it.
- A spot far behind it (20 m or more) used to set its speed to 0. Now it drives on and turns round to it; only close
  to the spot does it still drop back to line up under the pipe.
- It still stops for something in its way (collision check), and if it stands still for 60 seconds while chasing it
  backs out as before.
- A combine with Active unloading that is standing still: the unloader now drives up to the pipe and waits there,
  however far off it is. Before, a truck that had once been called to it standing counted as "at the pipe" for the
  rest of the job, so if it fell behind and the combine stopped again it waited where it was (80 s and more). That
  now only counts until the combine first drives off; after that it has to really be within 3 m of the pipe.
- Forage harvesters: unchanged.

- While chasing, the unloader used to stop and wait (or back away, for a Courseplay manoeuvre) the moment the combine
  was flagged as turning: any Courseplay manoeuvre, the game's AI turning, or the combine getting within 20 m of the
  field edge. A small veer stopped it the same as a headland turn.
- Now it notes which way the combine was pointing when that flag came on and keeps chasing. Only once the combine has
  swung more than 47 degrees from that heading does it count as a turn and use the old turn handling (stop and wait,
  back away if too close), so a 45-degree turn is still followed. If the flag clears before 47 degrees, it just keeps
  chasing.
- Only the chase is changed; the wait-for-turn handling itself is as before.

## 3.6.1.4 (2026-11-05): getting out of the way comes before planning
*Untested.*

- An unloader that is standing still planning (or waiting to plan) a route to a harvester is now also checked for being
  in a harvester's way (the 50 m strip ahead or where it turns). It used to be checked only while waiting for a call,
  so it could sit in the way while it planned.
- If it's in the way, moving out comes first, at once (no 3 second wait): it lets go of the job (the next free
  unloader on the same pins is sent, or it is called again once it's clear), drives to a clear spot, or 25 m straight
  if there is none, and waits there.
- While it drives along a route, nothing changes. Waiting for a call: still moves after 3 seconds in the way.

## 3.6.0.4 (2026-11-05): no more sitting there looking for a path
*Untested.*

When an unloader is sent to a harvester and can't find a way there within **10 seconds** (every time it plans), it
stops searching:
- **Another unloader is free on the same pins** (same first marker, e.g. both on "50 West"): it hands the job to the
  closest of them. Then, with **50% or more** in its trailer it goes to unload; with less it moves aside and waits on
  the field to be called again.
- **It's the only one:** it moves aside and plans again from there.
- "Moves aside" means: to the closest safe spot (out of the harvesters' strip and turn zones) **at least 25 m away**;
  if there's none, or no path to it within 10 seconds, it drives **25 m straight ahead** (in reverse if it can't move
  forward).
- The 10 seconds count the searching and the waits after a failed search, not the planned pauses (harvester almost
  full, not lined up, the short start delay).
- Moving out of a harvester's way (keep clear) now also gives its search 10 seconds instead of 30.

## 3.5.0.4 (2026-11-05): unloaders drive like semis when chasing
*Untested.*

Semi trucks chasing a harvester's pipe used to aim the cab straight at the spot under the pipe and steer as hard as
needed. With the spot right beside the cab or just behind it (inside the truck's turning circle) they drove in circles
or folded the trailer up (jackknifed) and got stuck. Now, while chasing with a trailer attached:
- It never steers tighter than a semi can turn (12 m radius). A spot it can't reach is no longer chased at full
  lock: it stays nearly straight, lets the harvester come by, and lines up from behind.
- Jackknife guard: if the cab gets more than 45 degrees off the trailer, it straightens the wheels and drives on at
  8 km/h or less until the trailer is back within 15 degrees.
- Driving on roads and AutoDrive routes, and rigs without a trailer: unchanged.

## 3.4.1.4 (2026-11-05): "in the harvester's way" made tighter and smarter
*Untested.*

A waiting unloader now only counts as in a harvester's way when it's:
- in the strip in front of the harvester: **50 m** ahead (was 80 m), the header width plus **5 m** on each side (was
  10 m), or
- in the headland **where the harvester is going to turn**: at the end of the field it's heading to, from its own lane
  toward the side with standing crop (it turns into the next pass). With crop on neither side, or both, both
  directions count.

No longer in the way:
- parked next to standing crop (the "within 10 m of crop" rule is gone),
- parked in the headland on the side the harvester turns away from.

When it does move, its new spot no longer has to keep away from crop or from the whole headland, only from the strip
(by 15 m) and from where the harvester turns.

## 3.4.0.4 (2026-11-05): unloader stays on when its harvester leaves
*Untested.*

- When a harvester stops working (it drives off to refuel or get repaired, its helper is switched off, or you fold
  the pipe), its unloader no longer stops where it is with AutoDrive switched off. Instead:
  - trailer 50% full or more: it drives off to unload, as with a full trailer (leaving the field first);
  - under 50%: it stays on, waits for the next call, and keeps out of the harvester's way as usual. When the
    harvester comes back and starts working, an unloader is sent again.
- A second unloader queued behind it does the same, based on its own trailer.
- With Active unloading on, an unloader is now only sent while the harvester is on a field. A Courseplay harvester
  driving on the road to or from a field doesn't get chased down the road.

## 3.3.0.4 (2026-11-05): Active unloading: chase from the start
*Untested.*

- With Active unloading on, a combine no longer waits until it reaches the "Call unloader at" (pre-call) level before
  it gets an unloader. As soon as it is working, the closest free unloader is sent to chase it, even at 0% full.
- It also keeps calling one when it is over 90% full, so a nearly full combine is chased too.
- Nothing holds it back because the pipe would be over standing crop any more (AI crop damage is off on our server).
  Before, an unloader that would chase from behind wasn't sent above 70% full, and one already coming in from behind
  waited above 85%.
- Active unloading off: unchanged, it still waits for the pre-call level.

## 3.2.1.4 (2026-11-05): no backing away from a nearly full combine (Active unloading)
*Untested.*

- 3.2.0.4 only stopped the "combine over 90% full and I'm within 25 m, back away" rule for an unloader called to a
  standing combine. A combine still driving and over 90% full still made it back away. With Active unloading on, that
  rule is now off completely.
- With Active unloading on, an unloader chasing a combine no longer gives up and goes back to waiting when the combine
  gets past 91% full. It keeps chasing, so it's under the pipe when the combine stops.
- With Active unloading on, a combine that is still driving but over 94.5% full now gets an unloader that chases it.
  Before, the unloader drove to the spot where the pipe was, as if the combine were standing.
- When a combine with Active unloading on stops and the unloader is at the pipe (within 3 m), the unloader holds still
  there, ready, and moves the moment the combine does.
- Active unloading off: unchanged.

## 3.2.0.4 (2026-11-05): Active unloading means always chasing
*Untested.*

- With Active unloading on, an unloader that reaches a standing combine no longer does a "standing unload". It goes
  straight into chase mode and holds still under the pipe while the combine stands. The moment the combine rolls, it
  rolls with it. There is no switch-over any more, so it can't miss the combine driving off (in 3.1.3.4 it sat there,
  gave up once the combine was 30 m away, looped round and came back).
- While it waits under a standing combine like this, it doesn't count as stuck, and it no longer backs away because
  the combine is over 90% full and close by.
- If the combine starts driving while the unloader is still on its way, it still switches to chasing after half a
  second (as in 3.1.3.4).
- Active unloading off, forage harvesters, a combine that is turning, and a Courseplay combine in a pocket: unchanged,
  standing unload as before.

## 3.1.3.4 (2026-11-05): chase a standing combine the moment it moves
*Untested.*

- When the unloader is sent to a combine that is standing still and the combine starts to drive, the unloader now
  switches to chasing it after half a second, whatever it is doing: still planning its way there, driving up,
  waiting for the pipe, or already unloading. It used to notice only once it had stopped under the pipe, so if the
  combine pulled away while it was coming in, it first drove to the empty spot where the pipe had been.
- It only does this once it has seen the combine standing. A combine that is still moving but nearly full is also
  sent an unloader the "standing" way (it is about to stop); that one is not chased straight away.

## 3.1.2.4 (2026-11-05): unloader stays with the combine
*Untested.*

- Under the pipe the unloader now drives at exactly the combine's speed, no faster. "Under the pipe" means within
  1 m of its place. Further back it still catches up: the combine's speed plus 1 km/h, plus 3 km/h for every metre
  beyond that 1 m.
- When it has driven up to a combine that is standing still, and the combine drives off, the unloader now starts
  following it after half a second. It used to stand still for 4 seconds first, so the combine was already several
  metres away.
- In that moment it now always follows. It used to give up and go back to waiting if its tractor or trailer was near
  standing crop.
- If a combine set to Active unloading is emptied while standing still, and the unloader still has room, it now
  stays with the combine and follows it, so it is already under the pipe when the combine fills again. It used to
  leave and wait for the next call. A full unloader still drives off to unload as before, and nothing changes for
  forage harvesters or for combines with Active unloading off.

## 3.1.1.4 (2026-11-05): unloader stays under the pipe
*Untested.*

- When the unloader chases a combine that unloads on the move, it now pushes harder to get back under the pipe.
  It aims for the combine's speed plus 1 km/h, plus 3 km/h for every metre it is short of its place (it used to be
  only 1.4 to 2 km/h per metre, so it crept up slowly and the combine kept getting away from it).
  For example, 3 m short: combine + 10 km/h (was combine + 4 km/h).
- If it gets ahead of its place, it now drops below the combine's speed and slides back, instead of overshooting.
- Your Field speed setting is still its top speed.
- Only the pipe chase works this way. Bale unloading, reversing out of a bad spot and driving clear to the field edge
  are unchanged.

## 3.1.0.4 (2026-11-05): unloader keeps out of the harvester's way
*Untested.*

- While an unloader waits on the field to be called, it checks every second whether it is standing where a harvester
  is going to drive. This counts combines and forage harvesters alike. It is in the way when it is:
  - in the strip in front of the harvester (80 m ahead, the header width plus 10 m on each side),
  - within 10 m of standing crop (where the next passes go), or
  - in the headland along the field edge where the harvester turns (20 m, or two header widths if that is more).
- If it is still in the way after 3 seconds, it drives to the nearest spot on harvested ground that is at least 15 m
  clear of all of that (it looks up to 80 m away, away from the harvester first). If there is no such spot, it goes
  15 m outside the field edge. Then it waits for a call again.
- While it moves it shows "Moving out of the harvester's way", and no harvester can call it until it has stopped.
- If it cannot get clear three times in a row, it waits 60 seconds before trying again.
- Not checked while it is driving to a combine, unloading or on its way to unload. A second unloader queued behind the
  one being filled is not checked either (the existing "Drive clear when blocked" setting still covers it).

## 3.0.2.4 (2026-11-05): longer run-up to the pipe
*Untested.*

- When the unloader drives up to a combine's pipe, the straight stretch it gets after its last turn is now 50% longer.
  The trailer has more time to line up behind the tractor instead of coming in at an angle.
  Example: a 12 m combine with an 18 m tractor and trailer: 19.8 m becomes 29.7 m. The shortest run-up goes from 7 m
  to 10.5 m.
- Forage harvesters with a fixed spout: 1.5 combine lengths instead of 1.
- Unchanged: forage harvesters that aim their spout themselves, and chasing straight behind a combine (neither has a
  run-up).
- On tight headlands the unloader may have to swing out a little further before it comes in.
