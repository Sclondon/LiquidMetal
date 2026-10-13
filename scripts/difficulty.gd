extends RefCounted
## How hard it is: picked on the title menu (and remembered), read by the courses and the enemy
## AI. NORMAL is the game as it was tuned; CHILL and EASY slow the chasers down, make them turn
## wider and send fewer of them (most of all in the arena); HARD pushes the other way.
##   chase: times your run speed an enemy runs while behind you (endless / test area: it has to
##     beat 1 to ever catch you); arena_chase: the same in the arena, where they come at you from
##     anywhere (under 1: you can outrun them)
##   steer: how hard the AI turns toward you (lower: wider turns, easier to sidestep)
##   wave_scale / wave_cap: the arena's wave n sends ceil((n + 1) * wave_scale) enemies, at most wave_cap
##   at_once: most enemies in the arena at once; send_every: seconds between them coming in;
##     breather: seconds between waves
##   endless_enemies: most chasers at once in endless; endless_rate: chance a second of a new one
##   endless_speed: your run speed at the start of endless, and by 3000 m; gap_scale: obstacle spacing

const TIERS := [
	{ name = "CHILL", note = "slow chasers, more room", chase = 1.12, arena_chase = 0.85, steer = 1.3,
		wave_scale = 0.5, wave_cap = 6, at_once = 2, send_every = 2.2, breather = 5.0,
		endless_enemies = 1, endless_rate = 0.08, endless_speed = Vector2(12.0, 20.0), gap_scale = 1.25 },
	{ name = "EASY", note = "slower chasers, fewer of them", chase = 1.22, arena_chase = 1.05, steer = 1.8,
		wave_scale = 0.75, wave_cap = 10, at_once = 4, send_every = 1.4, breather = 3.5,
		endless_enemies = 1, endless_rate = 0.14, endless_speed = Vector2(13.0, 23.0), gap_scale = 1.1 },
	{ name = "NORMAL", note = "the full chase", chase = 1.35, arena_chase = 1.35, steer = 2.5,
		wave_scale = 1.0, wave_cap = 16, at_once = 6, send_every = 0.8, breather = 2.5,
		endless_enemies = 2, endless_rate = 0.2, endless_speed = Vector2(14.0, 26.0), gap_scale = 1.0 },
	{ name = "HARD", note = "faster, sharper, more of them", chase = 1.45, arena_chase = 1.45, steer = 3.0,
		wave_scale = 1.25, wave_cap = 20, at_once = 8, send_every = 0.6, breather = 2.0,
		endless_enemies = 3, endless_rate = 0.3, endless_speed = Vector2(15.0, 29.0), gap_scale = 0.9 },
]
const DEFAULT := 2

static var level := DEFAULT


static func tier() -> Dictionary:
	return TIERS[level]


static func tier_name() -> String:
	return TIERS[level].name


## The arena's wave n: how many it sends
static func wave_size(wave: int) -> int:
	var t := tier()
	return mini(ceili((wave + 1) * float(t.wave_scale)), t.wave_cap)


## The key bests are saved under: NORMAL keeps the old plain "run" / "wave"
static func best_key(what: String) -> String:
	return what if level == DEFAULT else "%s_%s" % [what, TIERS[level].name.to_lower()]
