# Liquid Metal

A 3D auto runner for the Scareathon arcade: you are Mercury, a figure of liquid metal that runs on its own.

The menu has three modes:
- **ENDLESS RUN**: a lane that never ends. Every 500 m a new zone (NEON DUSK, TOXIC TIDE, ICE CIRCUIT, INFERNO,
  THE VOID) with its own colours and new obstacles (zigzags, tunnels, pillars); faster and tighter as you go.
  Score = metres + 5 per drop + 50 per enemy smashed; best saved.
- **ARENA**: a walled 90 m square with cover; waves of red enemy runners (wave n sends n + 1) come at you.
  Dash through them. One splat ends it; best wave saved.
- **TEST AREA**: the playground; enemies chase you anywhere in it, splats just rewind you.

Enemies are the same runner as you with an AI at the controls (scripts/ai_input.gd): they chase, jump,
slide and swerve. Dash (or wind up a dash) through one to blow it up; get caught otherwise and you splat.
Dashes punch left, right, then a two-handed clap; hold to charge.

Esc (or TUNE → Menu, or Start on a gamepad) goes back to the menu.

Gamepad: left stick turn, right stick look around, A / D-pad up jump, B / D-pad down duck, X dash,
LB / RB (or D-pad left / right) dodge.

| Do | Touch / mouse | Keys |
| --- | --- | --- |
| Turn | tap and hold the left / right half of the screen | A / D (held) |
| Jump (a flip; again in the air for a double jump) | swipe up | Space, W, Up |
| Duck (melt into a puddle) | swipe down (in the air: dive, then puddle) | S, Down |
| Dodge (sidestep 4.5 m, with a barrel roll) | swipe left / right | Left / Right arrows |
| Wall run (in the air, touch a wall: jump, then dodge into it; jump again to kick off) | | |
| Dash (burst of speed and a twirl, then a cooldown) | DASH button, bottom right | Shift, E |
| New course, back to the start | TUNE → New course | R |

Hitting something head-on splats you; you pull back together about a second back along your path.

## Test area (current state)

`scenes/main.tscn` builds everything in code (`scripts/main.gd`):
- `test_area.gd` – 300 m walled grid floor with a randomly generated course (new on every restart): a practice
  lane of hurdles (orange, jump), beams (cyan, duck) and half walls (magenta, dodge) in random order and spacing,
  a random field of columns, walls and slabs, a slalom, a duck tunnel and kicker ramps. Mercury drops to collect.
  Obstacles use the Tron shader (`shaders/obstacle.gdshader`).
- `player.gd` – the runner (CharacterBody3D), its moves, splat and rewind; melts into a puddle to duck.
- `mercury_model.gd` – Mercury in the game: loads `models/mercury.glb`, puts the metal shader on it, plays its `run` / `jump`.

## The character (Blender)

`art/build_mercury.py` builds Mercury (after `mercury.png`) in Blender: floating faceted parts, three horns,
a teardrop head raked back to a point, thick floating arms, long two-piece legs with knee guards, a `run` cycle of long, deep lunges
with ninja-run arms, and a `jump` leap. It saves `art/mercury.blend` (open it to tweak) and
exports `models/mercury.glb`:

    "C:/Program Files/Blender Foundation/Blender 4.3/blender.exe" -b --factory-startup --python art/build_mercury.py

If you edit the .blend by hand instead, export glTF (.glb) to `models/mercury.glb` with Animation mode "NLA Tracks".
- `runner_input.gd` – swipe / hold / keyboard → signals and a turn axis.
- `trail.gd` – the two tracks left under the feet; splashes at the feet and the landing splat are in player.gd.
- `endless.gd` – endless mode's course, built in chunks ahead and cleared behind. `menu.gd` – title and game-over.
- `droplets.gd` – little blobs that flop off Mercury as it moves and get pulled back in.
- `follow_cam.gd`, `hud.gd` (DASH button; TUNE panel: speed, turn rate, jump height, camera, N64 filter).
- `shaders/n64.gdshader` – the N64 look: ~400-line picture (kept light), soft bilinear upscale, 16-bit colour with dither.

## Tests (headless)

    godot --headless --path . -s res://tests/wallrun_test.gd  # jump + dodge into the lane wall: wall run, jump off
    godot --headless --path . -s res://tests/endless_bot.gd  # bot plays endless mode to 1500 m: no splats
    godot --headless --path . -s res://tests/arena_test.gd   # waves start, enemies close in, clearing brings the next
    godot --headless --path . -s res://tests/chase_test.gd   # an enemy spawned behind closes in and lines up

    godot --headless --path . -s res://tests/lane_bot.gd     # bot runs 5 random lanes with the controls: 0 splats
    godot --headless --path . -s res://tests/touch_test.gd   # fake touches: hold turns, swipes jump/duck/dodge
    godot --path . -s res://tests/shots.gd -- <dir>          # screenshots (needs a window)

## Web build

    godot --headless --path . --export-release "Web" build/index.html
