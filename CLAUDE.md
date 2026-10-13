# Liquid Metal: notes for Claude

A Godot 4.7 3D auto runner for the Scareathon arcade. You play Mercury, a figure made of liquid metal.
The setting (the user's, 2026-10-12): the black sand moon of the Crystaliens, a people who build everything out of crystal. **No neon / Tron look**: no glowing grids or wireframe edges. The arena is their colosseum; the endless run is a ring road round the moon.
The design doc covers what the game is and why: https://claude.ai/code/artifact/62a45f20-c913-4028-b4b6-cd79283da87d
README.md covers the controls, modes and tests for players.

## Layout

The whole scene is built in code. `scenes/main.tscn` is just `scripts/main.gd`.

- `main.gd`: the modes (`start_endless`, `start_arena`, `start_test`, `start_viewer`, `show_menu`, `restart`), the score, the bests (per difficulty), and the sky and key light per zone.
  - Exported vars: `start_mode` ("menu" / "endless" / "arena" / "test" / "viewer"), `enemies`, `use_pads`.
- `difficulty.gd`: the tiers (CHILL / EASY / NORMAL / HARD) as a table of numbers, a static `level` (picked on the menu, saved), `wave_size()` and `best_key()`. NORMAL is the old tuning; tests always play it.
- `viewer.gd`: the model viewer. Mercury runs on the spot (pulled back every physics step) while it orbits the camera; its buttons fire the runner input's signals.
- `player.gd`: the runner (CharacterBody3D). It holds every move: turn, jump, double jump, flips, duck/slide/puddle, dodge, wall run, brake, dash slashes with charge, splat and rewind. Landing keeps its speed. Real reflections (a live probe) are on for the player, off for enemies.
  - Signals: `splatted`, `smashed`, `dashed`, `boosted`, `drops_changed`.
  - **The player and the enemies use this same script.** Enemies call `make_enemy()` and sit on collision layer 2 with mask 1. The player's mask is 1|2.
- Input nodes: `runner_input.gd` (touch, keys, gamepad) and `ai_input.gd` (enemies: chase, ray feelers, lane_plan).
  - Both expose the same signals and API: `jump`, `duck`, `dodge(dir)`, `dash`, `turn`, `look`, `brake`, `duck_held()`, `dash_held()`. Keep them in sync.
- `mercury_model.gd`: Mercury in-game. It loads `models/mercury.glb`, applies the liquid-metal shader, and plays the NLA anims (`run`, `jump`, `slide`, `land_R`, `land_L`, `idle`, `tpose`; `force_pose` holds one).
  - Each part has a spring "jiggle" child. The shoulder pads (`pad_L/R`) and eyes are reparented onto the arm / head jiggles.
  - Tube muscles (`TUBES`: neck, shoulders, hips, knees) are rebuilt every frame in an ImmediateMesh between the parts' jiggles (attach points in Blender coordinates), hidden when he goes to jelly or melts.
  - Stride/pump timing, and the dash's slash aimed in world space (`_slash` sweeps once over `SLASH_TIME`; `PUNCHES` in player.gd: L, R, then the X with both), with a fading trail.
- Courses:
  - `endless.gd`: chunks ahead, cleared behind, with zones every 500 m (the `ZONES` and `ZONE_KINDS` tables). The world round the lane is `ring_world.gd`: the ring road (a 90 m band of sand 1500 m out from the moon) and the moon, kept abreast of the runner because the lane itself is straight. The lane's ordinary walls are drawn as 1.1 m kerbs (`KERB`) but collide at full height.
  - `colosseum.gd`: the arena's shell: round wall (72 straight lengths, for wall runs), stands, a multimesh crowd of Crystaliens (`cheer()`), spires, and the floor (`set_floor(pit)`; its `ground` is the shared SandGround, drawn only: the collider is made here).
  - `crystal.gd`: crystal meshes (`shard`, `part` for a Crystalien runner's body parts, `spectator`) and the Crystaliens' colours.
  - `arena.gd`: the online battle room (agar.io style): a round colosseum, 70 m radius, where everyone fights for the most mass. The room picks a layout ("mode") each round: `open`, `blocks`, `movers` (blocks sliding on the round's clock) or `pit` (fall in and you're lost). The bots are Crystaliens (`player.gd` `crystal = true`: Mercury's skeleton with a crystal for each part); other players are Mercury. Drops add mass, a dash through another runner bursts it (so does running into one 1.3x smaller), a burst runner spills 60% of its mass as drops and comes back at 10. Rounds are 3 minutes. Bots fill the room to 6 runners.
    - The room itself (mass, drops, who burst whom, the clock) is `arena_net.gd` (the site's server: `server/liquidMetal/arena.js` + `server/routes/liquidMetal.js` in scareathon-v3, at `/liquid-metal/ws`) or, when that can't be reached, `arena_room.gd` (the same rules run in the game, bots only). **The rules live in both `arena.js` and `arena_room.gd`: change them together.** The message list is at the top of `arena_net.gd`.
    - Each game moves its own runner and sends its state 15 times a second (`player.gd` `net_state` / `net_apply`, 11 bytes). Other players' runners are puppets (`make_puppet`). The bots are real runners with `bot_input.gd` at the controls, run by whichever game the server names (`bots` message); the rest see them as puppets.
    - In the room nobody collides with anybody (layer 2, mask 1): `arena.gd` works out hits and drop pickups by distance and claims them from the room; the first claim wins.
    - `--server=<url>` / `?server=` points at another server, `--offline` / `?offline` skips it. Tests that start straight into the arena play the local room unless given `--server`.
  - `test_area.gd`: the playground.
  - Each course exposes `lane_plan` (read by the bots and the AI), `start_position` and `runner`.
- Effects: `droplets.gd` (blobs that fly off and rejoin), `trail.gd` (foot tracks), `boost_pad.gd`, `follow_cam.gd`.
- UI: `ui_theme.gd` (StyleBoxFlat glass/neon theme), `menu.gd` (title + game over), `hud.gd` (stats panel, banners, round DASH button, TUNE panel).
- `shaders/`:
  - `liquid_metal`: chrome faked with a painted horizon. Params: collapse, ball_radius, splash, real_reflection.
  - `puddles`: smooth-union SDF discs on a subdivided plane, lifted into a 3D bead by vertex displacement, with a clip rect. The player sets its colours for enemies (red).
  - `sky` (custom sky: gradient, stars; `space` = 1 for the moon: stars all the way down, a plain star for a sun, no skyline; `ring` = 1 draws the ring overhead), `obstacle` (cut crystal: every block, wall and obstacle), `crystal` (shards and Crystaliens), `crowd`, `moon`, `pit`, `black_sand` (the test area's floor only), `boost_pad`, `n64` (post filter). `grid_floor` is no longer used.
- Sand: `scripts/sand*.gd` and `dust.gd` are the shared component **GameCommon `godot/sand`** (from Outside), installed with `sh /c/Projects/GameCommon/kit.sh install godot/sand .`. Read its README there before changing them; `kit.sh diff` shows what this game has changed (nothing so far).
- `art/build_mercury.py`: Blender script → `art/mercury.blend` + `models/mercury.glb`.

## State after 2026-10-12/13 (read with the layout above; some lines there are older)

- **Endless** is the whole top of the ring now (56 m wide, no lane walls): breaks to fall into, crystal formations to jump / duck / dodge, crystals that fall from the sky and stay (`crystal_fall.gd`), aurora rings for boosts (`boost_pad.gd`, used by the arena too), companion ring bands and a moon with an atmosphere shell lit by three suns (`ring_world.gd`, `moon_air` / `ring_band` shaders). `plan` lists what's laid; `lane_plan` is empty. Tests: `endless_bot` (2000 m, no splats) and `ring_test` (7 checks; "an enemy keeps off the edge" fails more often than not since the merge with the dash wall and wants looking at), both with `--fixed-fps 60`.
- **Arena**: the layout changes every 45 s inside a round as well (`layout` message, 3.5 s warning; stones sink and rise through the sand). The dash leaves a standing wall of metal (`metal_wall.gd`) that bursts anyone else who runs into it (`died` with `how: "trail", by`). The crowd reacts (`colosseum.gd`: cheer / wave / flash / gasp). Stones are crystal formations over box colliders. `palace.gd` is the architecture round the colosseum (Crystal Palace + McQuarrie / Jodorowsky's Dune, the user's references).
- **Crystaliens** (bots) shatter into shards, have no droplets or puddles, and leave sprouting crystals (`crystal_trail.gd`). Mercury's puddles run back into him when they go (`_resorb`), and as a puddle he slows to a stop.
- **Sky**: `sky.gdshader` paints the fixed deep sky and three suns; `sky_show.gd` / `sky_show.gdshader` is the animated layer (comets, supernovae, a turning figure, aurora, motes) on a ball round the camera.
- **Story**: `cinematic.gd` plays behind the title menu, round and round (`show_menu` → `_stage_story`; `_end_story` / `halt` when a mode starts). There is no STORY button and no "story" mode. Long-lens shots climbing Mercury from his feet to his face, cut with glimpses; a few lowercase words. `tests/story_shots.gd` captures one round.
- **Menu (2026-10-13, the user's)**: two options only, ENDLESS and ARENA. No difficulty picker: the game is always NORMAL (`difficulty.gd` still holds the table; nothing sets `level`). TEST AREA and MODEL VIEWER show only with the dev toggle (`?dev`, `--dev`, or the ` key on the title).
- **DASH** is a half-round of liquid metal across the whole bottom of the screen (`shaders/dash_dome.gdshader`, `hud.gd` `is_over_dash`). Its touches are taken in `runner_input.gd` so a second finger can dash while one steers. The dash wall (`metal_wall.gd`) is a thin blade drawn along a smooth curve.
- **Font**: Audiowide (`fonts/`, OFL), slanted, standing in for Resbaloso (the user's reference, commercial); `fonts/Resbaloso.ttf` is used instead if it's ever added.
- **Endless (2026-10-13)**: things are set closer (`GAP_EASY` / `GAP_HARD`); `split` and `fork` are long breaks along the ring that part it into paths; crystals come down as shards, boulders, bars (jump) and rows (`crystal_fall.gd` `kind` / `spec`); the enemies are Crystaliens that spawn ahead and come head on before chasing (`ai_input.gd` `head_on`); `war.gd` draws the fleets, the crossing pairs and the ship that strafes down the ring to loose each lot of crystals.
- Crystal shaders read the screen (`hint_screen_texture`) and use `depth_draw_always`; without that, crystals draw over each other in the wrong order.

## Commands

Godot (Steam):

    "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

Run the headless tests from this folder with `--headless --path . -s res://tests/<name>.gd`:

| Test | What a pass looks like |
| --- | --- |
| `lane_bot` | 5 random lanes, 0 splats |
| `endless_bot` | reaches 2100 m / zone 5, no splats (it steers itself back to the lane's middle) |
| `touch_test` | 6 PASS |
| `pad_test` | 5 PASS |
| `wallrun_test` | 2 PASS |
| `chase_test` | PASS |
| `arena_test` | 7 PASS (the local room; run it with `--fixed-fps 60` so its 45 s round goes quickly) |
| `modes_test` | 3 PASS (pit, movers, open; `--fixed-fps 60`) |
| `tools/arena_net_test.sh <scareathon-v3>/server` | 9 PASS: two copies of the game in one room on a local server (`tools/dev_relay.mjs`; needs `npm ci` in that server folder) |

- `touch_test` fails its two hold-to-turn checks under `--fixed-fps 60`; run it without.

- Screenshot scripts (`shots`, `model_shots`, `liquid_shots`, `slide_shots`, `crash_shots`, `wall_shots`, `enemy_shots`, `ui_shots`, `menu_shots`, `slash_shots`, `idle_shots`, `arena_shots`, `colosseum_shots` (`-- <out dir> <mode>`), `ring_shots`) need a window. The viewer ones are the easiest close-ups of Mercury. Run them without `--headless` and pass `-- <out dir>`.
- After changing a script, check that it parses by running a test. `--check-only` trips on autoloads/class names.

Rebuild the character (Blender 4.3):

    "C:/Program Files/Blender Foundation/Blender 4.3/blender.exe" -b --factory-startup --python art/build_mercury.py

- The run is 36 frames with bezier cyclic curves. The lunges sit at 0.0 s (left leg) and 0.6 s (right leg). `idle` (72 frames) loops the same way.
- The head (a helmet: the teardrop with its two spikes extruded out of its own surface, one smooth mesh) is the only smooth-shaded part; the eye is one V-slit mesh (`eye_V`). Each shin carries a smooth ball joint at the knee (`KNEE_BALL`). Chest, thighs, shins and shoulder pads use `add_armor` (chamfered, eight-facet plates with stepped lips); the arm blades and knee guards keep the plain `add_shard` blade look on purpose. After a rebuild, run `--headless --import` so Godot picks the new .glb up.
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
