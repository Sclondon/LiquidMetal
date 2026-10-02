# Liquid Metal

A 3D auto runner for the Scareathon arcade: you are Mercury, a figure of liquid metal that runs on its own.

| Do | Touch / mouse | Keys |
| --- | --- | --- |
| Turn | tap and hold the left / right half of the screen | A / D (held) |
| Jump (a front flip) | swipe up | Space, W, Up |
| Duck (melt into a puddle) | swipe down (in the air: dive, then puddle) | S, Down |
| Dodge (sidestep 4.5 m, with a barrel roll) | swipe left / right | Left / Right arrows |
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
- `trail.gd` – the trail of little puddles left behind; splashes at the feet are a CPUParticles3D in player.gd.
- `droplets.gd` – little blobs that flop off Mercury as it moves and get pulled back in.
- `follow_cam.gd`, `hud.gd` (DASH button; TUNE panel: speed, turn rate, jump height, camera, N64 filter).
- `shaders/n64.gdshader` – the N64 look: ~400-line picture (kept light), soft bilinear upscale, 16-bit colour with dither.

## Tests (headless)

    godot --headless --path . -s res://tests/lane_bot.gd     # bot runs 5 random lanes with the controls: 0 splats
    godot --headless --path . -s res://tests/touch_test.gd   # fake touches: hold turns, swipes jump/duck/dodge
    godot --path . -s res://tests/shots.gd -- <dir>          # screenshots (needs a window)

## Web build

    godot --headless --path . --export-release "Web" build/index.html
