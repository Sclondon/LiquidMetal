@tool
class_name SandDunes
extends RefCounted
## Dunes as the wind makes them, as a height any level can ask for:
##
##     var dunes := SandDunes.new()
##     dunes.wind = Vector2(1.0, 0.3)            # the way it blows, over the ground (x, z)
##     dunes.add_barchan(Vector2(40, 10), 46.0, 6.0)
##     dunes.add_ridge(Vector2(-80, -60), Vector2(-60, 70), 8.0)
##     dunes.scatter(Rect2(-120, -120, 240, 240), 14)      # or let it place them
##     var y := dunes.height_at(x, z)
##
## Every dune is one line on the ground, its brink: the edge the sand is blown
## up to and falls from. Upwind of it the back of the dune rises gently, an S
## in outline; downwind the slip face falls away at the angle sand lies at
## (`REPOSE`), exactly, because it is the heap you get by pouring sand along
## that line. A barchan is a brink bent into a crescent, its horns downwind
## and running out to nothing; a transverse ridge is a long one lying across
## the wind and wandering a little. Between dunes the floor is nearly level.
##
## And three more: a barchanoid ridge (`add_barchanoid`), which is crescents
## joined horn to horn in a scalloped line across the wind; a star dune
## (`add_star`), which is arms running out from a peak, where the wind comes
## from all round by turns; and a whole field of any of them (`field`), set out
## as the wind sets them out: in rows across it, each row a dune's length and
## some flat ground behind the last, the dunes of one row standing in the gaps
## of the row before, big dunes far apart and small ones close. `sharp` is how
## much of a crease the crest is.
##
## `height_at` is a plain function of place: the same answer every time, no
## state, so a level can call it for its mesh, its collider and anything it
## sets down. `bake` fills a whole grid at once and is much quicker than
## asking point by point.

## The angle a slip face stands at.
const REPOSE := deg_to_rad(32.0)
## The back of a dune is this many times as long as the dune is high (its
## steepest part is then about 12 degrees).
const BACK := 7.0
## A dune is no higher than this share of half its width, so that its ends
## can run out to nothing without standing steeper than sand does.
const SQUAT := 0.36

## The way the wind blows, over the ground (x, z). Set it before adding dunes.
var wind := Vector2(1.0, 0.0):
	set(value):
		wind = value.normalized() if value.length() > 0.001 else Vector2(1.0, 0.0)
## How far the floor between the dunes rolls, up and down, metres; and across
## what distance.
var floor_roll := 0.18
var floor_span := 23.0
## A different number gives a different floor, and different dunes from `scatter`.
var seed := 1
## How sharp the crest of a dune is, 0..1. At 0 its back rounds over to level
## at the brink, as a worn dune's does; at 1 it is still climbing when it gets
## there (at about 8 degrees, having been 11 at its steepest), and the brink is
## a crease. Set it before adding dunes.
var sharp := 0.0
## Whether the back of a dune is as long at its ends as in its middle. It was
## not: the back was seven times as long as the dune was high at each place
## along it, so where a dune ran out at its end its back shrank to nothing
## too, and the end was a steep-sided wedge. With this on a dune ends as a low
## long tongue, and its ends are raised over a longer way. Set it before adding
## dunes. (A field of dunes turns it on; dunes scattered as they were have it off.)
var long_backs := false
## Where a dune stands lower than this (metres) its lee side is not a slip
## face but a gentler slope, the gentler the lower: as the horn of a dune is,
## which is too low for sand to pile up and let go. 0: every lee side is a
## slip face, however low. A slip face a metre high is under two metres long,
## which a grid of heights two and a half metres apart draws as teeth; give
## this about one and a third times the side of a square. Set it before adding dunes.
var soft_below := 0.0

## The ways a field of dunes can be set out (see `field`). (New ones go on the
## end: levels keep these as numbers.)
enum Field { SCATTERED, BARCHANS, TRANSVERSE, BARCHANOID, STARS, MIXED }

# Each dune: [frame, brink, heights, bounds]. It is measured in a frame of its
# own: `along` the wind and `across` it, from a point of its own. The brink is
# how far downwind it lies at each of a row of places evenly spaced across the
# wind, and `heights` how high it stands at each. `frame` is the point (x, z),
# the wind (x, z), where across the wind the row starts, how far apart its
# places are, and how far a slip face can reach from the brink.
var _dunes: Array = []


## A crescent dune with the middle of its brink at `at`: `width` from horn to
## horn across the wind, `height` at the middle. `horns` is how far downwind
## the tips reach, as a share of the width; `lean` makes one longer than the
## other. Says how high it really is (it is made lower if it would be too
## squat to stand).
func add_barchan(at: Vector2, width: float, height: float, horns := 0.55, lean := 0.0) -> float:
	var brink := PackedFloat32Array()
	var heights := PackedFloat32Array()
	# (with `long_backs` the brink is in shorter pieces: each piece has a flat of slip
	# face under it, and flats five metres wide show where the light turns to shade)
	var count := clampi(int(width / 2.5), 16, 72) if long_backs else 16
	height = minf(height, SQUAT * width * 0.5)
	for i in count + 1:
		var out := float(i) / count * 2.0 - 1.0
		# (an arc: nearly straight across the wind in the middle, and swept
		# round to run with it at the horns)
		brink.append(horns * width * 1.4 * (1.0 - sqrt(1.0 - 0.92 * out * out)) * (1.0 + lean * out))
		heights.append(height * pow(1.0 - out * out, 1.4))
	_add(at, -width * 0.5, width / count, brink, heights)
	return height


## A long dune across the wind, its brink running from `from` to `to` (which
## should lie more or less across the wind) and wandering up and down wind by
## `sway`, as a share of its length. It is highest in its middle part and
## runs out at each end. `wobble` is any number: another gives another line.
func add_ridge(from: Vector2, to: Vector2, height: float, sway := 0.05, wobble := 0) -> float:
	var across := Vector2(-wind.y, wind.x)
	if (to - from).dot(across) < 0.0:
		var swap := from
		from = to
		to = swap
	var width := (to - from).dot(across)
	var slant := (to - from).dot(wind)
	var count := maxi(int(width / (2.5 if long_backs else 5.0)), 6)
	var brink := PackedFloat32Array()
	var heights := PackedFloat32Array()
	height = minf(height, SQUAT * width * 0.5)
	var taper := clampf(height / 0.34 / width, 0.08, 0.5)
	if long_backs:
		taper = clampf(height * 6.0 / width, 0.12, 0.5)
	for i in count + 1:
		var share := float(i) / count
		var wander := _noise(share * 3.1 + wobble * 7.3, wobble * 1.7 + 0.5) - 0.5 + 0.5 * (_noise(share * 7.7 + wobble * 3.1, wobble * 5.1) - 0.5)
		brink.append(slant * share + wander * sway * width * 2.0)
		var ends := smoothstep(0.0, taper, share) * smoothstep(0.0, taper, 1.0 - share)
		heights.append(height * ends * (0.78 + 0.44 * _noise(share * 4.3 + wobble * 2.3, 9.0 + wobble)))
	_add(from, 0.0, width / count, brink, heights)
	return height


## A ridge of crescents joined horn to horn, across the wind from `from` to
## `to`: each bowed upwind in its middle, where it is highest, with a low
## saddle and a point downwind where it meets the next. `horns` is how far
## downwind the points reach, as a share of one crescent's width.
func add_barchanoid(from: Vector2, to: Vector2, height: float, horns := 0.4, wobble := 0) -> float:
	var across := Vector2(-wind.y, wind.x)
	if (to - from).dot(across) < 0.0:
		var swap := from
		from = to
		to = swap
	var width := (to - from).dot(across)
	var slant := (to - from).dot(wind)
	# How many crescents, and where each ends: none quite as wide as the next.
	var links := maxi(int(round(width / maxf(height * 8.5, 6.0))), 2)
	var ends := PackedFloat32Array([0.0])
	for i in range(1, links):
		ends.append((i + (_hash(wobble * 31 + i, 77) - 0.5) * 0.5) / links)
	ends.append(1.0)
	var count := maxi(int(width / (2.5 if long_backs else 3.5)), links * 6)
	var brink := PackedFloat32Array()
	var heights := PackedFloat32Array()
	height = minf(height, SQUAT * width / links * 0.8)
	var link := 0
	for i in count + 1:
		var share := float(i) / count
		while link < links - 1 and share > ends[link + 1]:
			link += 1
		var span := (ends[link + 1] - ends[link]) * width
		var out := (share - ends[link]) / (ends[link + 1] - ends[link]) * 2.0 - 1.0
		var tall := height * (0.72 + 0.5 * _hash(wobble * 13 + link, 5))
		var saddle := 0.4 + 0.25 * _hash(wobble * 7 + link, 19)
		# (a wave, not arcs that meet in a point: the crest runs round each join in a curve)
		brink.append(slant * share + horns * span * 0.3 * (1.0 - cos(PI * out)) + (_noise(share * 2.3 + wobble * 3.7, 1.5) - 0.5) * span * 0.5)
		var end := clampf(height * 6.0 / width, 0.5 / links, 0.5) if long_backs else 0.5 / links
		var run_out := smoothstep(0.0, end, share) * smoothstep(0.0, end, 1.0 - share)
		heights.append(tall * (saddle + (1.0 - saddle) * pow(1.0 - out * out, 1.2)) * run_out)
	_add(from, 0.0, width / count, brink, heights)
	return height


## A star dune with its peak at `at`: `arms` crests run out from it, each
## bending a little, `radius` to their tips. One side of each arm is a slip
## face and the other a gentle back, so an arm can be walked up to the peak.
## Says how high it really is.
func add_star(at: Vector2, radius: float, height: float, arms := 3, wobble := 0) -> float:
	height = minf(height, radius * 0.2)
	var lines: Array = []
	var turned := _hash(wobble * 17 + 3, 41) * TAU
	for arm in arms:
		var angle := turned + (arm + (_hash(wobble * 5 + arm, 23) - 0.5) * 0.5) * TAU / arms
		var curl := (_hash(wobble * 11 + arm, 59) - 0.5) * 1.3
		var long := radius * (0.7 + 0.3 * _hash(wobble * 3 + arm, 7))
		var line := PackedVector2Array()
		for k in 6:
			var share := k / 5.0
			line.append(at + Vector2(cos(angle + curl * share), sin(angle + curl * share)) * long * share)
		lines.append(line)
	var reach := radius * 1.3
	_dunes.append([PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), Rect2(at - Vector2.ONE * reach, Vector2.ONE * reach * 2.0), [at, radius, height, lines]])
	return height


## Sets out a field of dunes over `area` as the wind does: in rows across it.
## `kind` is which (`Field`): crescents, long ridges, ridges of linked
## crescents, stars, or all of them, each where it belongs (crescents where
## the sand is thin, ridges where there is more). `heights` is the lowest and
## the highest; `flat` (0..1) how much level ground lies between one row and
## the next; `thick` how thickly they stand (1: as many as their size calls
## for). The same numbers and the same `seed` always give the same field.
## Says how many dunes it made.
func field(area: Rect2, kind: int, heights := Vector2(2.5, 8.0), flat := 0.35, thick := 1.0) -> int:
	if thick <= 0.0 or kind == Field.SCATTERED:
		return 0
	var across := Vector2(-wind.y, wind.x)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)]:
		var lies := Vector2(corner.dot(wind), corner.dot(across))
		low = low.min(lies)
		high = high.max(lies)
	var made := 0
	var row := 0
	var along := low.x - heights.y * 3.0 * _hash(seed, 911)
	while along < high.x and row < 400:
		# (the dunes of a row are much of a size, and the size drifts from row to row)
		var size := lerpf(heights.x, heights.y, clampf(_noise(row * 0.7 + seed * 5.3, seed * 1.9) * 1.5 - 0.25, 0.0, 1.0))
		var length := size * BACK + size / tan(REPOSE)
		var side := low.y - length * 2.0 * _hash(seed * 3 + row, 131)
		var place := 0
		while side < high.y and place < 400:
			var key := seed * 7919 + row * 613 + place * 37
			var tall := size * (0.82 + 0.36 * _hash(key, 1))
			var sort := kind
			if kind == Field.MIXED:
				# (which sort grows here: it changes across the field, not dune by dune)
				var middle := wind * along + across * side
				var sand := _noise(middle.x / 95.0 + seed * 2.1, middle.y / 95.0 - seed * 0.7) + (_hash(key, 2) - 0.5) * 0.25
				# (no stars among them: a star is a peak, and a sea of dunes is long calm lines)
				sort = Field.BARCHANS if sand < 0.3 else (Field.BARCHANOID if sand < 0.62 else Field.TRANSVERSE)
			var width: float
			match sort:
				Field.BARCHANS:
					width = tall * lerpf(7.5, 10.5, _hash(key, 4))
				Field.TRANSVERSE:
					width = tall * lerpf(10.0, 15.0, _hash(key, 4))
				Field.BARCHANOID:
					width = tall * lerpf(12.0, 18.0, _hash(key, 4))
				_:
					width = tall * lerpf(8.0, 10.0, _hash(key, 4))
			var gap := width * (0.08 + (0.25 + flat * 1.3) * _hash(key, 5)) / thick
			var at := wind * (along + (_hash(key, 6) - 0.5) * length * 0.5) + across * (side + width * 0.5)
			if area.has_point(at):
				var lie := across.rotated((_hash(key, 7) - 0.5) * 0.3)
				match sort:
					Field.BARCHANS:
						add_barchan(at, width, tall, lerpf(0.4, 0.68, _hash(key, 8)), (_hash(key, 9) - 0.5) * 0.7)
					Field.TRANSVERSE:
						add_ridge(at - lie * width * 0.5, at + lie * width * 0.5, tall, lerpf(0.03, 0.08, _hash(key, 8)), key & 0xffff)
					Field.BARCHANOID:
						add_barchanoid(at - lie * width * 0.5, at + lie * width * 0.5, tall, lerpf(0.3, 0.5, _hash(key, 8)), key & 0xffff)
					_:
						add_star(at, width * 0.5, tall * 1.25, 3 + int(_hash(key, 8) * 2.99), key & 0xffff)
				made += 1
			side += width + gap
			place += 1
		along += length * (0.5 + flat * 1.7) / sqrt(thick)
		row += 1
	return made


## The same dunes, made lower wherever `share` says: it is given a place on a
## dune's brink (Vector2) and how far the dune reaches up wind and down from
## it, and says how much of its height the dune may keep there, 0..1. For
## running dunes out to nothing at ground that has to stay clear, without
## moving any of them.
func lowered(share: Callable) -> SandDunes:
	var kept := without(func(_bounds: Rect2) -> bool: return false)
	var across := Vector2(-wind.y, wind.x)
	for index in kept._dunes.size():
		var dune: Array = (kept._dunes[index] as Array).duplicate()
		if dune.size() > 4:
			var star: Array = (dune[4] as Array).duplicate()
			star[2] = float(star[2]) * float(share.call(star[0], float(star[1]), float(star[1])))
			dune[4] = star
		else:
			var frame: PackedFloat32Array = dune[0]
			var brink: PackedFloat32Array = dune[1]
			var heights: PackedFloat32Array = (dune[2] as PackedFloat32Array).duplicate()
			var at := Vector2(frame[0], frame[1])
			var blows := Vector2(frame[2], frame[3])
			var keeps := PackedFloat32Array()
			for i in heights.size():
				keeps.append(float(share.call(at + across * (frame[4] + frame[5] * i) + blows * brink[i], heights[i] * BACK + 1.5, heights[i] / tan(REPOSE))) if heights[i] > 0.0 else 1.0)
			# It runs out over some way, as the end of a dune does, and not in a
			# step: first each place keeps no more than those near it do, then
			# the line of them is evened out.
			var reach := maxi(int(ceil(12.0 / frame[5])), 1)
			for turn in 2:
				var evened := keeps.duplicate()
				for i in keeps.size():
					var least := 1.0
					var sum := 0.0
					var count := 0
					for j in range(maxi(i - reach, 0), mini(i + reach, keeps.size() - 1) + 1):
						least = minf(least, keeps[j])
						sum += keeps[j]
						count += 1
					evened[i] = least if turn == 0 else sum / count
				keeps = evened
			var whole := 0.0
			var left := 0.0
			for i in heights.size():
				whole += heights[i]
				heights[i] *= keeps[i]
				left += heights[i]
			# (and a dune with most of it gone is not left as a stump)
			if left < whole * 0.2:
				heights.fill(0.0)
			dune[2] = heights
		kept._dunes[index] = dune
	return kept


## Places `count` dunes in `area` by chance: barchans, big and small, and (a
## share `ridges` of them) ridges. `keep_clear`, given a place (Vector2) and a
## reach, says whether a dune may not stand there. `heights` is the lowest and
## the highest. Says how many it found room for.
func scatter(area: Rect2, count: int, heights := Vector2(2.5, 8.0), keep_clear := Callable(), ridges := 0.3) -> int:
	var random := RandomNumberGenerator.new()
	random.seed = seed * 7919 + 13 + _dunes.size()
	var across := Vector2(-wind.y, wind.x)
	var placed := 0
	for attempt in count * 60:
		if placed >= count:
			break
		var at := area.position + Vector2(random.randf(), random.randf()) * area.size
		var height := lerpf(heights.x, heights.y, random.randf())
		var ridge := random.randf() < ridges
		var width := height * (random.randf_range(11.0, 18.0) if ridge else random.randf_range(7.0, 10.0))
		var horns := random.randf_range(0.42, 0.65)
		# (the ground it stands on: its back upwind, its horns and slip face downwind)
		var back := height * BACK
		var front := height / tan(REPOSE) + (0.0 if ridge else horns * width)
		var middle := at + wind * (front - back) * 0.5
		var room := maxf(width, back + front) * 0.5
		if keep_clear.is_valid() and keep_clear.call(middle, room):
			continue
		var crowded := false
		var wanted := Rect2(middle - Vector2.ONE * room * 0.62, Vector2.ONE * room * 1.24)
		for dune: Array in _dunes:
			var bounds: Rect2 = dune[3]
			if bounds.grow(-minf(bounds.size.x, bounds.size.y) * 0.19).intersects(wanted):
				crowded = true
				break
		if crowded:
			continue
		if ridge:
			var lie := across.rotated(random.randf_range(-0.25, 0.25))
			add_ridge(at - lie * width * 0.5, at + lie * width * 0.5, height, 0.05, placed + seed + _dunes.size())
		else:
			add_barchan(at, width, height, horns, random.randf_range(-0.3, 0.3))
		placed += 1
	return placed


## For ground that is to go on for ever as the same square of dunes over and
## over: every dune that reaches past an edge of `square` is put in again a
## whole square away, so that it comes in at the far edge where it went out at
## this one. Baked over the square, the last row and column are then the first
## again, and the squares meet with no seam. Call it when all the dunes are in.
func wrap(square: Rect2) -> void:
	for index in _dunes.size():
		var dune: Array = _dunes[index]
		var bounds: Rect2 = dune[3]
		if square.encloses(bounds):
			continue
		for down in range(-1, 2):
			for along in range(-1, 2):
				var by := Vector2(along, down) * square.size
				var moved := Rect2(bounds.position + by, bounds.size)
				if by == Vector2.ZERO or not moved.intersects(square):
					continue
				var again := dune.duplicate()
				again[3] = moved
				if dune.size() > 4:
					var star: Array = (dune[4] as Array).duplicate()
					star[0] = (star[0] as Vector2) + by
					var lines: Array = []
					for line: PackedVector2Array in star[3]:
						var shifted := PackedVector2Array()
						for point in line:
							shifted.append(point + by)
						lines.append(shifted)
					star[3] = lines
					again[4] = star
				else:
					var frame: PackedFloat32Array = (dune[0] as PackedFloat32Array).duplicate()
					frame[0] += by.x
					frame[1] += by.y
					again[0] = frame
				_dunes.append(again)


## How high the sand stands at a place.
func height_at(x: float, z: float) -> float:
	var height := 0.0
	var at := Vector2(x, z)
	for dune: Array in _dunes:
		if (dune[3] as Rect2).has_point(at):
			height = maxf(height, _star_height(dune[4], x, z) if dune.size() > 4 else _dune_height(dune[0], dune[1], dune[2], x, z))
	return height + floor_at(x, z)


## The floor between the dunes alone.
func floor_at(x: float, z: float) -> float:
	if floor_roll <= 0.0:
		return 0.0
	return floor_roll * (_noise(x / floor_span + seed * 3.7, z / floor_span - seed * 1.3) * 2.0 - 1.0)


## The heights of a whole grid at once, row by row: `columns` by `rows`
## corners, `cell` apart, the first at `origin`. Without `floor` it is the
## dunes alone: nought wherever there is none.
func bake(origin: Vector2, cell: float, columns: int, rows: int, floor := true) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(columns * rows)
	for dune: Array in _dunes:
		var bounds: Rect2 = dune[3]
		var frame: PackedFloat32Array = dune[0]
		var brink: PackedFloat32Array = dune[1]
		var tall: PackedFloat32Array = dune[2]
		var first_column := maxi(int(ceil((bounds.position.x - origin.x) / cell)), 0)
		var last_column := mini(int(floor((bounds.end.x - origin.x) / cell)), columns - 1)
		var first_row := maxi(int(ceil((bounds.position.y - origin.y) / cell)), 0)
		var last_row := mini(int(floor((bounds.end.y - origin.y) / cell)), rows - 1)
		for row in range(first_row, last_row + 1):
			var z := origin.y + row * cell
			for column in range(first_column, last_column + 1):
				var height := _star_height(dune[4], origin.x + column * cell, z) if dune.size() > 4 else _dune_height(frame, brink, tall, origin.x + column * cell, z)
				if height > heights[row * columns + column]:
					heights[row * columns + column] = height
	if floor_roll > 0.0 and floor:
		for row in rows:
			for column in columns:
				heights[row * columns + column] += floor_at(origin.x + column * cell, origin.y + row * cell)
	return heights


## A grid of heights (as `bake` gives it) with every sharp thing in it rounded
## over: each corner becomes the mean of those round it, weighted 1, 2, 1 along
## and then across, `passes` times (each pass rounds over about 0.7 of a
## square more). A crest that is a crease cannot be drawn with a grid: it comes
## out as teeth wherever it runs aslant to the squares. Rounded over two squares
## or so it is a clean line from any side. With `wraps` the grid is one that
## repeats (its last row and column are its first again: see `wrap`), and it is
## rounded across its edges as it is everywhere else, so that it still repeats.
static func rounded(heights: PackedFloat32Array, columns: int, rows: int, passes := 2, wraps := false) -> PackedFloat32Array:
	var from := heights
	for pass_no in passes:
		var along := PackedFloat32Array()
		along.resize(from.size())
		for row in rows:
			var first := row * columns
			if wraps:
				along[first] = (from[first + columns - 2] + from[first] * 2.0 + from[first + 1]) * 0.25
				along[first + columns - 1] = along[first]
			else:
				along[first] = (from[first] * 3.0 + from[first + 1]) * 0.25
				along[first + columns - 1] = (from[first + columns - 1] * 3.0 + from[first + columns - 2]) * 0.25
			for at in range(first + 1, first + columns - 1):
				along[at] = (from[at - 1] + from[at] * 2.0 + from[at + 1]) * 0.25
		var both := PackedFloat32Array()
		both.resize(from.size())
		for at in range(columns, columns * (rows - 1)):
			both[at] = (along[at - columns] + along[at] * 2.0 + along[at + columns]) * 0.25
		for column in columns:
			var last := (rows - 1) * columns + column
			if wraps:
				both[column] = (along[last - columns] + along[column] * 2.0 + along[column + columns]) * 0.25
				both[last] = both[column]
			else:
				both[column] = (along[column] * 3.0 + along[column + columns]) * 0.25
				both[last] = (along[last] * 3.0 + along[last - columns]) * 0.25
		from = both
	return from


## For a grid of heights with no creases in it: which way to split each of its
## squares into two triangles, row by row (one fewer each way than there are
## corners). 0 is from a square's first corner to the far one; 1 the other way.
## Split all one way, a rounded crest that runs along the other diagonal is
## notched at every square, by a hand's breadth: this picks, for each square,
## the diagonal whose middle is nearer where a curved surface through the
## corners round about would be.
static func splits(heights: PackedFloat32Array, columns: int, rows: int) -> PackedByteArray:
	var turned := PackedByteArray()
	turned.resize((columns - 1) * (rows - 1))
	for row in range(1, rows - 2):
		for column in range(1, columns - 2):
			var at := row * columns + column
			var one := (heights[at] + heights[at + columns + 1]) * 0.5
			var other := (heights[at + 1] + heights[at + columns]) * 0.5
			if absf(one - other) < 0.01:
				continue
			# (the middle of the curved surface: nine sixteenths of the corners next
			# to it each way, less a sixteenth of those beyond)
			var inner := one + other
			var beside := heights[at - columns] + heights[at - columns + 1] + heights[at - 1] + heights[at + 2] 					+ heights[at + columns - 1] + heights[at + columns + 2] + heights[at + columns * 2] + heights[at + columns * 2 + 1]
			var beyond := heights[at - columns - 1] + heights[at - columns + 2] + heights[at + columns * 2 - 1] + heights[at + columns * 2 + 2]
			var middle := (162.0 * inner - 9.0 * beside + beyond) / 256.0
			if absf(other - middle) < absf(one - middle):
				turned[row * (columns - 1) + column] = 1
	return turned


## The same dunes, less those `drop` says yes to: it is given the ground each
## covers (a Rect2). For keeping dunes off places without disturbing the rest.
func without(drop: Callable) -> SandDunes:
	var kept := SandDunes.new()
	kept.wind = wind
	kept.floor_roll = floor_roll
	kept.floor_span = floor_span
	kept.seed = seed
	kept.sharp = sharp
	kept.long_backs = long_backs
	kept.soft_below = soft_below
	for dune: Array in _dunes:
		if not drop.call(dune[3]):
			kept._dunes.append(dune)
	return kept


## The ground each dune covers.
func bounds() -> Array[Rect2]:
	var all: Array[Rect2] = []
	for dune: Array in _dunes:
		all.append(dune[3])
	return all


func _add(at: Vector2, first: float, gap: float, brink: PackedFloat32Array, heights: PackedFloat32Array) -> void:
	var across := Vector2(-wind.y, wind.x)
	var highest := 0.0
	var upwind := 1.0e9
	var downwind := -1.0e9
	for i in brink.size():
		highest = maxf(highest, heights[i])
		downwind = maxf(downwind, brink[i] + heights[i] / tan(REPOSE))
	var back := highest * BACK + 1.5 if long_backs else 0.0
	for i in brink.size():
		upwind = minf(upwind, brink[i] - (back if long_backs else heights[i] * BACK + 1.5))
	var reach := maxf(highest, soft_below) / tan(REPOSE)
	for i in brink.size():
		if soft_below > 0.0 and heights[i] > 0.0:
			downwind = maxf(downwind, brink[i] + soft_below / tan(REPOSE))
	var last := first + gap * (brink.size() - 1)
	var bounds := Rect2(at + across * first + wind * upwind, Vector2.ZERO)
	for corner: Vector2 in [Vector2(first, downwind), Vector2(last, upwind), Vector2(last, downwind)]:
		bounds = bounds.expand(at + across * corner.x + wind * corner.y)
	_dunes.append([PackedFloat32Array([at.x, at.y, wind.x, wind.y, first, gap, reach, sharp, back, soft_below]), brink, heights, bounds.grow(1.0)])


# One dune's height at a place. Upwind of the brink it is the dune's back;
# downwind, the highest of the heaps that would stand if sand were poured
# along each stretch of the brink.
static func _dune_height(frame: PackedFloat32Array, brink: PackedFloat32Array, heights: PackedFloat32Array, x: float, z: float) -> float:
	var from_x := x - frame[0]
	var from_z := z - frame[1]
	var along := from_x * frame[2] + from_z * frame[3]
	var gap := frame[5]
	var place := (from_z * frame[2] - from_x * frame[3] - frame[4]) / gap
	var last := brink.size() - 1
	if place <= 0.0 or place >= last:
		return 0.0
	var index := int(place)
	var part := place - index
	var edge := brink[index] + (brink[index + 1] - brink[index]) * part
	if along <= edge:
		var height := heights[index] + (heights[index + 1] - heights[index]) * part
		# (the back is as long as the dune's own height calls for, or, if it has
		# `long_backs`, as its highest part does)
		var out := (edge - along) / (frame[8] if frame[8] > 0.0 else height * BACK + 1.5)
		if out >= 1.0:
			return 0.0
		if frame[7] > 0.0:
			# (a sharper crest: the back is still climbing where it meets the brink)
			var up := 1.0 - out
			return height * up * up * (3.0 - frame[7] - (2.0 - frame[7]) * up)
		return height * (1.0 - out * out * (3.0 - 2.0 * out))
	var steep := tan(REPOSE)
	var span := int(frame[6] / gap) + 1
	var best := 0.0
	var across := place * gap
	for i in range(maxi(index - span, 0), mini(index + span, last - 1) + 1):
		# (the nearest point of this stretch of the brink)
		var run := brink[i + 1] - brink[i]
		var off_across := across - i * gap
		var off_along := along - brink[i]
		var share := clampf((off_across * gap + off_along * run) / (gap * gap + run * run), 0.0, 1.0)
		off_across -= gap * share
		off_along -= run * share
		var tall := heights[i] + (heights[i + 1] - heights[i]) * share
		# (a low part of a dune has a gentler lee side: see `soft_below`)
		var heap := tall - steep * (1.0 if tall >= frame[9] else maxf(tall / frame[9], 0.3)) * sqrt(off_across * off_across + off_along * off_along)
		if heap > best:
			best = heap
	return best


# A star dune's height at a place: the highest of what its arms make of it.
# To one side of an arm's crest the sand lies at the angle it slips at; to the
# other it falls away gently.
static func _star_height(star: Array, x: float, z: float) -> float:
	var at := Vector2(x, z)
	var height: float = star[2]
	var steep := tan(REPOSE)
	var best := 0.0
	for line: PackedVector2Array in star[3]:
		var last := line.size() - 1
		for i in last:
			var run := line[i + 1] - line[i]
			var share := clampf((at - line[i]).dot(run) / maxf(run.length_squared(), 0.0001), 0.0, 1.0)
			var crest := height * pow(1.0 - (i + share) / last, 1.5)
			if crest <= best:
				continue
			var off := at - (line[i] + run * share)
			var far := off.length()
			var tall: float
			if run.x * off.y - run.y * off.x > 0.0:
				tall = crest - steep * far
			else:
				var up := 1.0 - far / (crest * 5.0 + 1.0)
				tall = crest * up * up * (2.0 - up) if up > 0.0 else 0.0
			if tall > best:
				best = tall
	return best


static func _hash(x: int, z: int) -> float:
	var n := (x * 374761393 + z * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


# Smooth noise, 0..1.
static func _noise(x: float, z: float) -> float:
	var whole_x := floori(x)
	var whole_z := floori(z)
	var part_x := x - whole_x
	var part_z := z - whole_z
	part_x = part_x * part_x * (3.0 - 2.0 * part_x)
	part_z = part_z * part_z * (3.0 - 2.0 * part_z)
	return lerpf(lerpf(_hash(whole_x, whole_z), _hash(whole_x + 1, whole_z), part_x),
			lerpf(_hash(whole_x, whole_z + 1), _hash(whole_x + 1, whole_z + 1), part_x), part_z)
