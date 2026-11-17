# FROSTLINE: Last Train to Haven

*Bad Ideas Works · Game of the Week #1 · Theme: survival on a train*

You are the last crew member on the last train. 100 km of frozen wasteland lie between
eight passengers and Haven. Keep the fires burning, keep the train moving, and keep the
raiders off.

## How to play

| Key | Action |
| --- | --- |
| A / D or arrows | Move |
| W / S at a gap between cars | Climb ladders |
| Space | Jump |
| S on a roof | Duck (under bridges and tunnels) |
| E | Shovel coal, feed the furnace or stove, pull the brake, use a bandage |
| J or left click | Swing your wrench |
| P / Esc | Pause |
| F11 | Fullscreen |

### The loop
- **Furnace** (engine cab): fuel = speed. A fast train outruns the raider sleds.
- **Stove** (passenger car): if it goes out, the car freezes and passengers die.
- Both eat coal from the **tender**, and coal runs out.
- **Coal depots** (green ticks on the route bar) refill the tender, but only below 35 km/h.
  Pull the brake lever in the cab, then release it afterwards. Slowing down lets the raiders catch up.
- **Low bridges and tunnels**: get off the roof or hold S to duck. Raiders on the roof don't duck.
- **Raiders**
  - Yellow scarf: coal thief, steals from the tender.
  - Green scarf: snatcher, kidnaps passengers.
  - Red scarf: saboteur, uncouples cars. Losing the passenger car ends the run.
  - Purple, big: brute, hunts you.
- Stay warm: roofs are freezing; the engine cab and the heated passenger car warm you up.
- The caboose has a medkit with 3 bandages.

## Tech
- Engine: [LÖVE 11.5](https://love2d.org) (Lua). All graphics and sounds are procedural, so there are no asset files.
- `build.sh` fuses the game into a Windows exe. GitHub Actions builds it plus a web version and
  publishes both to GitHub Pages.
- Headless smoke test (a bot plays two full runs): `love game --autotest`.
