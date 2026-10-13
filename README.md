# Liquid Metal

A 3D auto runner for the Scareathon arcade: you are Mercury, a figure of liquid metal that runs on its own.

The menu has four modes, and a difficulty:
- **ENDLESS RUN**: a lane that never ends. Every 500 m a new zone (NEON DUSK, TOXIC TIDE, ICE CIRCUIT, INFERNO,
  THE VOID) with its own colours and new obstacles (zigzags, tunnels, pillars); faster and tighter as you go.
  Score = metres + 5 per drop + 50 per enemy smashed; best saved.
- **ARENA**: an online battle room. Everyone who opens it is in the same walled 140 m square, fighting for
  the most mass before the 3-minute round ends: run over drops to grow, dash through other runners to burst them
  (or run into one much smaller), and get burst or hit a wall and you spill your mass and come back small. Bots fill
  empty seats; with no server it is bots only. Most mass you have held is saved.
- **TEST AREA**: the playground; enemies chase you anywhere in it (TUNE → Enemies switches them off),
  splats just rewind you.
- **MODEL VIEWER**: Mercury running on the spot, the camera circling it: drag (or the right stick) to orbit,
  wheel / pinch / LB-RB to zoom, a speed slider (0: it stands, breathing), buttons for every move and a T-POSE.
- **Difficulty** (press it to step through, or left / right): CHILL, EASY, NORMAL, HARD. Easier tiers have
  slower chasers that turn wider, and fewer of them (in endless and the test area: on CHILL they're slower
  than you); HARD is faster, sharper and more. Endless speed and obstacle spacing follow it too. Bests are
  kept per difficulty (scripts/difficulty.gd has the numbers).

Enemies are the same runner as you with an AI at the controls (scripts/ai_input.gd): they chase, jump,
slide and swerve. Dash (or wind up a dash) through one to blow it up; get caught otherwise and you splat.
Dashes slash: the left blade, the right, then an X with both; hold to charge.

Esc (or TUNE → Menu, or Start on a gamepad) goes back to the menu.

Gamepad: left stick turn, right stick orbits the camera (all the way round; let go and it swings back
behind), A / D-pad up jump, B / D-pad down duck, X dash, LB / RB (or D-pad left / right) dodge, left
trigger brake.

| Do | Touch / mouse | Keys |
| --- | --- | --- |
| Turn | tap and hold the left / right half of the screen | A / D (held) |
| Jump (a flip; again in the air for a double jump) | swipe up | Space, W, Up |
| Duck (melt into a puddle) | swipe down (in the air: dive, then puddle) | S, Down |
| Dodge (sidestep 4.5 m, with a barrel roll) | swipe left / right | Left / Right arrows |
| Wall run (in the air, touch a wall: jump, then dodge into it; jump again to kick off) | | |
| Dash (burst of speed and a slash, then a cooldown) | DASH button, bottom right | Shift, E |
| Brake (slow down, to a stop: it stands) | hold both halves of the screen | Q (held) |
| New course, back to the start | TUNE → New course | R |

Hitting something head-on splats you; you pull back together about a second back along your path.

## Test area (current state)

`scenes/main.tscn` builds everything in code (`scripts/main.gd`):
- `test_area.gd` – 300 m walled grid floor with a randomly generated course (new on every restart): a practice
  lane of hurdles (orange, jump), beams (cyan, duck) and half walls (magenta, dodge) in random order and spacing,
  a random field of columns, walls and slabs, a slalom, a duck tunnel and kicker ramps. Mercury drops to collect.
  Obstacles use the Tron shader (`shaders/obstacle.gdshader`).
- `player.gd` – the runner (CharacterBody3D), its moves, splat and rewind; melts into a puddle to duck.
- `mercury_model.gd` – Mercury in the game: loads `models/mercury.glb`, puts the metal shader on it, plays its
  `run` / `jump` / `slide` / `land_*` / `idle` / `tpose`, and the dash's slash (with its trail).

## The character (Blender)

`art/build_mercury.py` builds Mercury (after `mercury.png`) in Blender: floating faceted parts, a smooth
teardrop helmet (two spikes growing out of it in a V, a glowing V slit for the eye), plated armour, thick floating blade arms under little shoulder pads, wide-set two-piece legs with ball-joint knees (in the game, chrome tube muscles join the parts),
with guards from the knee to the toe, a `run` cycle of long, deep lunges with ninja-run arms, a `jump` leap, a
`slide`, superhero landings, a breathing `idle` and a `tpose`. It saves `art/mercury.blend` (open it to tweak)
and exports `models/mercury.glb`:

    "C:/Program Files/Blender Foundation/Blender 4.3/blender.exe" -b --factory-startup --python art/build_mercury.py

If you edit the .blend by hand instead, export glTF (.glb) to `models/mercury.glb` with Animation mode "NLA Tracks".
- `runner_input.gd` – swipe / hold / keyboard → signals and a turn axis.
- `trail.gd` – the two tracks left under the feet; splashes at the feet and the landing splat are in player.gd.
- `endless.gd` – endless mode's course, built in chunks ahead and cleared behind. `menu.gd` – title and game-over.
- `droplets.gd` – little blobs that flop off Mercury as it moves and get pulled back in.
- `follow_cam.gd`, `hud.gd` (DASH button; TUNE panel: speed, turn rate, jump height, camera, N64 filter,
  the test area's enemies). `viewer.gd` – the model viewer. `difficulty.gd` – the difficulty tiers.
- `shaders/n64.gdshader` – the N64 look: ~400-line picture (kept light), soft bilinear upscale, 16-bit colour with dither.
- `shaders/sky.gdshader` – the sky: the zone's colours, a low striped sun down the lane, a skyline, stars.
- `shaders/grid_floor.gdshader` – brushed-metal floor plates in glowing seams. `shaders/puddles.gdshader` – the
  liquid splats, melted together and standing up off the floor (or wall) in 3D.

## Tests (headless)

    godot --headless --path . -s res://tests/wallrun_test.gd  # jump + dodge into the lane wall: wall run, jump off
    godot --headless --path . -s res://tests/endless_bot.gd  # bot plays endless mode to 2100 m: no splats
    godot --headless --fixed-fps 60 --path . -s res://tests/arena_test.gd   # the battle room with bots: drops, bursts, respawns, rounds
    tools/arena_net_test.sh <scareathon-v3>/server           # two copies in one room on a local server
    godot --headless --path . -s res://tests/chase_test.gd   # an enemy spawned behind closes in and lines up

    godot --headless --path . -s res://tests/lane_bot.gd     # bot runs 5 random lanes with the controls: 0 splats
    godot --headless --path . -s res://tests/touch_test.gd   # fake touches: hold turns, swipes jump/duck/dodge
    godot --path . -s res://tests/shots.gd -- <dir>          # screenshots (needs a window)
    godot --path . -s res://tests/slash_shots.gd -- <dir>    # the three slashes, in the model viewer
    godot --path . -s res://tests/idle_shots.gd -- <dir>     # standing idle and the T-pose, in the model viewer

## Web build

    godot --headless --path . --export-release "Web" build/index.html
