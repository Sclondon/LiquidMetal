# Liquid Metal: notes for Claude

A Godot 4.7 3D auto runner for the Scareathon arcade. You play Mercury, a figure made of liquid metal.
The design doc covers what the game is and why: https://claude.ai/code/artifact/62a45f20-c913-4028-b4b6-cd79283da87d
README.md covers the controls, modes and tests for players.

## Layout

The whole scene is built in code. `scenes/main.tscn` is just `scripts/main.gd`.

- `main.gd`: the modes (`start_endless`, `start_arena`, `start_test`, `show_menu`, `restart`), the score, the bests, and the sky per zone.
  - Exported vars: `start_mode` ("menu" / "endless" / "arena" / "test"), `enemies`, `use_pads`.
- `player.gd`: the runner (CharacterBody3D). It holds every move: turn, jump, double jump, flips, duck/slide/puddle, dodge, wall run, dash punches with charge, splat and rewind.
  - Signals: `splatted`, `smashed`, `dashed`, `boosted`, `drops_changed`.
  - **The player and the enemies use this same script.** Enemies call `make_enemy()` and sit on collision layer 2 with mask 1. The player's mask is 1|2.
- Input nodes: `runner_input.gd` (touch, keys, gamepad) and `ai_input.gd` (enemies: chase, ray feelers, lane_plan).
  - Both expose the same signals and API: `jump`, `duck`, `dodge(dir)`, `dash`, `turn`, `look`, `duck_held()`, `dash_held()`. Keep them in sync.
- `mercury_model.gd`: Mercury in-game. It loads `models/mercury.glb`, applies the liquid-metal shader, and plays the NLA anims (`run`, `jump`, `slide`, `land_R`, `land_L`).
  - Each part has a spring "jiggle" child.
  - Stride/pump timing, world-space punch aim, and an elastic arm stretch (`_ext`).
- Courses:
  - `endless.gd`: chunks ahead, cleared behind, with zones every 500 m (the `ZONES` and `ZONE_KINDS` tables).
  - `arena.gd`: a 90 m walled square. Wave n sends n+1 enemies, at most 6 at once.
  - `test_area.gd`: the playground.
  - Each course exposes `lane_plan` (read by the bots and the AI), `start_position` and `runner`.
- Effects: `droplets.gd` (blobs that fly off and rejoin), `trail.gd` (foot tracks), `boost_pad.gd`, `follow_cam.gd`.
- UI: `ui_theme.gd` (StyleBoxFlat glass/neon theme), `menu.gd` (title + game over), `hud.gd` (stats panel, banners, round DASH button, TUNE panel).
- `shaders/`:
  - `liquid_metal`: chrome faked with a painted horizon. Params: collapse, ball_radius, splash, real_reflection.
  - `puddles`: smooth-union SDF discs on a plane, with a clip rect.
  - `obstacle` (Tron edges), `grid_floor`, `boost_pad`, `n64` (post filter).
- `art/build_mercury.py`: Blender script → `art/mercury.blend` + `models/mercury.glb`.

## Commands

Godot (Steam):

    "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

Run the headless tests from this folder with `--headless --path . -s res://tests/<name>.gd`:

| Test | What a pass looks like |
| --- | --- |
| `lane_bot` | 5 random lanes, 0 splats |
| `endless_bot` | reaches ~2100 m / zone 5 |
| `touch_test` | 6 PASS |
| `pad_test` | 5 PASS |
| `wallrun_test` | 2 PASS |
| `chase_test` | PASS |
| `arena_test` | 3 PASS |

- Screenshot scripts (`shots`, `model_shots`, `liquid_shots`, `slide_shots`, `crash_shots`, `wall_shots`, `enemy_shots`, `ui_shots`, `menu_shots`) need a window. Run them without `--headless` and pass `-- <out dir>`.
- After changing a script, check that it parses by running a test. `--check-only` trips on autoloads/class names.

Rebuild the character (Blender 4.3):

    "C:/Program Files/Blender Foundation/Blender 4.3/blender.exe" -b --factory-startup --python art/build_mercury.py

- The run is 36 frames with bezier cyclic curves. The lunges sit at 0.0 s (left leg) and 0.6 s (right leg).
- The glTF exporter drops a perfectly static action, so every track needs some motion.
- Arm `ry = -s*angle` swings the arms outward.

Web build and publish (GitHub Pages serves `build/` from Sclondon/LiquidMetal):

    godot --headless --path . --export-release "Web" build/index.html
    git -c credential.helper='!gh auth git-credential' push

## Conventions

- Only push when the user asks. Commit messages start with `Liquid Metal: ...`.
- No Python on this machine. Avoid `rm` in commands; overwrite files or use fresh output dirs instead.
- For multi-line edits, write a `.cjs` script to `$CLAUDE_JOB_DIR/tmp` and run it with node. Inline `node -e` and heredocs break on quotes.
- Type GDScript vars explicitly (`var x: float = ...`) wherever inference fails, for example values from Dictionaries or untyped arrays.
- Tests must set `main.start_mode`, plus `main.enemies = false` and `main.use_pads = false` unless they test those. A stuck gamepad axis would otherwise steer the bot.
- Bests (`user://bests.cfg`) are saved only from real play: `start_mode == "menu"`, no SceneTree script, and not running in the editor. Never let a test write them.
- The web export uses gl_compatibility, which turns the ReflectionProbe black. `can_reflect()` gates live reflections to desktop.
- Comments in code are plain-English `##` docs at the top of each script plus short inline notes. Match that style.
- The Godot editor, if open, can overwrite edits to open scripts. Re-check files after editing.

## Arcade cart

The game is a secret cart in scarbone98/scareathon-v3, unlocked by typing LIQUID into WaysideOS (`src/pages/Arcade/unlocks.ts`).
After a game push, bump the cache-buster in `LIQUID_METAL_URL` (`...?v=<short commit>`) and push that repo too.
