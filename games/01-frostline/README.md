# FROSTLINE: Last Train to Haven

*Bad Ideas Works · Games of the Week · Week 1 · Theme: survival on a train*

You are the last crew member on the last train. 100 km of frozen wasteland lie between
eight passengers and Haven. Keep the fires burning, keep the train moving, keep the
raiders off... and survive whatever waits near the end of the line.

## Controls

| Keyboard | Gamepad | Action |
| --- | --- | --- |
| A / D or arrows | Left stick / D-pad | Move |
| W / S at a gap between cars | Up / Down | Climb ladders |
| Space | A | Jump |
| S on a roof | Down | Duck (under bridges and tunnels) |
| E | B | Shovel, feed the fires, brake, dig, stomp fires, trade, heal... |
| J or left click | X | Swing your wrench / throw dynamite |
| Esc / P | Start | Pause (shows your passengers and their perks) |
| F11 | | Fullscreen |

## How to survive
- **Furnace** (engine cab): fuel = speed. A fast train outruns the raider sleds.
- **Stove** (passenger car): if it goes out, the car freezes and passengers die.
- Both eat coal from the **tender**, and coal runs out.
- **Coal depots** (green ticks on the route bar) refill the tender, but only below 35 km/h:
  pull the brake lever in the cab, then release it afterwards. While you're stopped, visit the
  **trader** in the cargo car and spend **scrap** (dropped by raiders) on upgrades.
- **Passengers** all have names and perks: Ivo the mechanic, Gran Olga's soup, Doc Amara,
  Pip who shouts where raiders land, Sergei the old soldier, Lena the lookout, Bruno the stoker,
  and Mr. Whiskers (unimpressed). Lose someone and you lose their perk.
- **Raiders**: yellow scarf steals coal, green snatches passengers, red uncouples cars
  (losing the passenger car ends the run), big purple ones hunt you. An alarm sounds when a
  saboteur starts working.
- **Hazards**: low bridges and tunnels (duck!), car fires, damaged track (brake or derail),
  wolf packs at night, fevers (bring medicine from the caboose), avalanches (outrun them or dig
  out the buried gap), blizzards.
- **Story**: a short intro, Marisol from Haven Control on the radio, passengers who chat and react,
  four favours with real rewards (Ivo's engine tuning, Gran Olga's soup pot, Pip's toy train,
  Doc Amara's bandages), and epilogues that depend on who survived.
- **The finale**: near Haven, the **Iron Jaw** attacks. Cut its chains with your wrench before
  they drag the train to a stop, and throw dynamite from the cargo car to bring it down.
- Your best score is saved. Beat it.

## Tech
- Engine: [LÖVE 11.5](https://love2d.org) (Lua). All graphics, sound effects and the adaptive
  soundtrack are procedural. The only assets are two free fonts: Permanent Marker (Apache 2.0)
  and Lato (SIL Open Font License), with their licenses in `src/assets/fonts/`.
- Settings and high scores are stored in LÖVE's save folder (`settings.txt`).
- Dev tools: `love src --autotest [--runs=3] [--start=80] [--god] [--shots]` lets a bot play
  full runs; `love src --scenes` screenshots menus and hazards; `love src --loadtime`.
