# Liquid Metal

A 3D auto runner for the Scareathon arcade: you're a blob of liquid metal that runs on its own.

| Do | Touch / mouse | Keys |
| --- | --- | --- |
| Turn | tap and hold the left / right half of the screen | A / D (held) |
| Jump | swipe up | Space, W, Up |
| Duck (melt into a puddle) | swipe down (in the air: dive, then puddle) | S, Down |
| Dodge (sidestep 3 m) | swipe left / right | Left / Right arrows |
| Back to start | TUNE → Back to start | R |

Hitting something head-on splats you; you pull back together about a second back along your path.

## Test area (current state)

`scenes/main.tscn` builds everything in code (`scripts/main.gd`):
- `test_area.gd` – 300 m walled grid floor. Practice lane straight ahead: hurdles (orange, jump),
  beams (cyan, duck), half walls (magenta, dodge). Around it: a pillar field, a cone slalom,
  a 30 m duck tunnel and kicker ramps. Mercury drops to collect (they come back).
- `player.gd` – the blob (CharacterBody3D), its moves, splat and rewind.
- `runner_input.gd` – swipe / hold / keyboard → signals and a turn axis.
- `follow_cam.gd`, `hud.gd` (TUNE panel: speed, turn rate, jump height, camera).

## Tests (headless)

    godot --headless --path . -s res://tests/lane_bot.gd     # bot runs the lane with the controls: 0 splats
    godot --headless --path . -s res://tests/touch_test.gd   # fake touches: hold turns, swipes jump/duck/dodge
    godot --path . -s res://tests/shots.gd -- <dir>          # screenshots (needs a window)

## Web build

    godot --headless --path . --export-release "Web" build/index.html
