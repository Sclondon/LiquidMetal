class_name SandGround
extends StaticBody3D
## Sand to walk on: ground made from a height function, that takes the print
## of whatever presses into it.
##
##     var ground := SandGround.new()
##     ground.half = Vector2(128.0, 128.0)             # how far it runs each way from this node
##     ground.height = func(x: float, z: float) -> float: return dunes.height_at(x, z)
##     add_child(ground)                               # (it is made as it enters the scene)
##
## What it is made of:
## - A grid of heights, one every `cell` metres, asked of `height` once. The
##   collider is that grid and nothing finer. `height_at` reads it back.
## - A mesh that follows whoever is `focus` (the player, found by itself):
##   rings of squares, each ring twice as coarse as the one inside it, a few
##   centimetres across under his feet and metres across at the far dunes. It
##   takes its shape from the heights in its shader, so it costs nothing to
##   move, and it is one draw call.
## - Dents: a patch of fine squares round the focus, each remembering how far
##   it has been pressed down or heaped up. Boots, paws, bodies, rocks and
##   slides are stamped into it (`footprint`, `press`, ...); the shader pushes
##   the mesh down by it and lights its slopes. It softens and fills by itself,
##   slowly in still air and quickly in wind, and is forgotten beyond the patch.
## - Paint (`paint`, with a `Sand.Kind`): damp sand, packed paths, coarse and
##   pale patches; white, red and black sand; hard dirt and sandstone, which
##   take no prints, which nobody sinks into and which do not run; and snow.
##   Where two meet, each fades into the other. `give_at` is how soft the
##   ground is at a place.
## - Sand on the move (`ooze`): a lobe of it, a thick rounded mass that creeps
##   over the ground as lava does, front first, spreading and slowing, with a
##   low tongue left behind it. It is the dents that move: the ground itself
##   swells and travels, and is lit and coloured as ground.
##
## And what it does for whoever walks on it. Every figure on a `CharacterRig`
## (the group "figures") is watched: on this ground its own dust is silenced
## and sand is thrown up from its feet instead (`spray`); each footfall leaves
## a soft dent, and in loose sand a collar of it is pushed out and slumps
## round the foot; a slide or a roll leaves a trough, a sprawl the shape of a
## body; standing still it sinks a little; and on a steep face the sand under
## it gives way and oozes downhill, and carries it a little. Hounds leave paw
## prints. Anything in the group "throwable" or "sand_denting" dents it where
## it lands and furrows it where it rolls.
##
## Snow. A footprint in sand is a shallow rounded dent, with nothing of the
## boot in it: sand does not hold a shape. The crisp print, with its heel and
## sole and the lip round them, is kept for snow: set `snow` (the whole ground
## is snow: pale, crisp prints, nothing runs or is pushed out), or
## `crisp_prints` alone (sand that holds a print), or paint `Sand.Kind.SNOW`
## where it lies.
##
##     var ground := SandGround.new()
##     ground.snow = true
##
## Anything that is none of those tells the ground itself: `mark` for a
## footfall, `trail` for something that drags (see the end of this file).
##
## `cost_usec` is what a frame of all that takes here.
##
## This is the copy kept in GameCommon (godot/sand). It differs from Outside's:
## it asks for no `Player` class, and has `mark`, `trail`, `dent_cell`, `clip`,
## `ring`, `apron_roll`, `spray_colour` and `refit`, which Outside's has not.

signal built

## The dents are kept as whole numbers: this one is "not pressed", and each
## step up or down from it is `UNIT` metres.
const NEUTRAL := 128
const UNIT := 0.0005
## Steeper than this, sand that is trodden on starts to run (a slope, as rise over run).
const RUNS_AT := 0.3
## How many lobes of sand may be creeping at once, and how many of them down
## slopes at each `Sand.quality` (the rest are the small ones round his feet).
const LOBES := 16
const SLOPE_LOBES: Array[int] = [3, 4, 6]
## How many squares of the dents the lobes may be pressed into in one frame,
## at each `Sand.quality`: what bounds what they cost.
const LOBE_SQUARES: Array[int] = [300, 700, 2000]

## How far it runs each way from this node, along x and along z, metres.
@export var half := Vector2(60.0, 60.0)
## How far apart its heights are, metres. The collider is this coarse.
@export var cell := 1.0
@export var colour := Sand.COLOUR
## Whether it can be stood on. (Off: it is only drawn, over a collider the level made itself.)
@export var solid := true
## How long a footprint takes to fill in still air, and in a storm, seconds.
@export var fill_seconds := Vector2(150.0, 9.0)
## How far a figure standing still sinks in, metres, and how long it takes.
@export var sink_depth := 0.04
@export var sink_time := 1.1
## How fast a steep face carries whoever is on it downhill, metres a second
## at the angle sand lies at. 0: not at all.
@export var slope_carry := 0.6
## Snow, all of it: pale (unless `colour` has been set), prints that keep the
## shape of the boot, and nothing runs downhill or is pushed out round a foot.
@export var snow := false: set = _set_snow
## Footprints with a heel, a sole and a lip round them, as snow takes them.
## Off, a print is a soft shallow dent. (`snow` turns them on by itself.)
@export var crisp_prints := false
## Draws the ground near the eye as a curved surface through the corners of its
## grid, where it is otherwise the flat triangles the collider has: a rounded
## crest then stands against the sky as a curve and not as a line of straight
## pieces. For ground with no creases in it (see `SandDunes.rounded`): there
## the two are never more than a few centimetres apart. Set it before or after
## the ground is built.
## Which way each square of the grid is split into its two triangles, row by
## row: 0 from its first corner to the far one (as all are if this is empty), 1
## the other way. `SandDunes.splits` works out which keeps a crest that runs
## aslant from being notched. Set it before the ground is built.
var splits := PackedByteArray()
@export var curved := false:
	set(value):
		curved = value
		if _material:
			_material.set_shader_parameter(&"curve", 1.0 if curved else 0.0)
## The look its wind ripples have (`Sand.Ripples`): 0 soft waves, 1 mixed, 2
## fine forking lines, 3 none. Set it before or after the ground is built.
@export_range(0, 3) var ripples := 0:
	set(value):
		ripples = clampi(value, 0, 3)
		if _material:
			_material.set_shader_parameter(&"ripples", float(ripples))
## How far the desert is drawn past the edge of the ground (nothing can be
## stood on there), and how high that plain lies above this node: left at
## INF, as high as the edge is on the whole.
@export var beyond := 160.0
@export var apron := INF
## How far that plain rolls up and down, metres from its lowest to its highest
## (0: dead level, as round a level floor). Set it before the ground is built.
@export var apron_roll := 6.0
## Nothing is drawn past the edges of the ground: it ends there, and whatever
## the level has put round it or under it is seen. (Then `beyond` may as well be
## 0, which makes the mesh smaller.) Set it before or after the ground is built.
@export var clip := false:
	set(value):
		clip = value
		_trim()
## A disc of sand, or a ring: it is drawn no nearer the middle of the ground
## than `ring.x` metres and no further from it than `ring.y` (0, 0: all of it).
## Nothing out there is marked, and `covers` says no; the collider is still the
## whole square (turn `solid` off and give it your own if that matters). Set it
## before or after the ground is built.
@export var ring := Vector2.ZERO:
	set(value):
		ring = value
		_trim()
## How big a square of the dents is, metres. 0: as fine as `Sand.quality`
## allows (4, 2.5 or 1.5 cm), which holds the print of a boot, in a patch 10 to
## 15 m across that follows `focus`. Coarser squares hold no more than a
## furrow or a round dent, but the patch is as many times wider, and pressing
## into it as many times (squared) cheaper: at 0.1 it is 26, 51 or 102 m across,
## which is what fast things that leave trails want (see `trail`). Nothing
## narrower than two squares shows. Set it before the ground is built, or call
## `refit`.
@export var dent_cell := 0.0
## What colour the sand it throws up is, and how much so (its alpha): 0 and it
## is the colour of the ground it came from, 1 and it is all this. Black sand
## thrown up over black sand cannot be seen; dry dust off it is paler.
@export var spray_colour := Color(0.0, 0.0, 0.0, 0.0)
## Ground that goes on for ever. Given a grid of heights the same size as its
## own, that is what lies past its edges: the same square of open sand over and
## over, in every direction, for as far as anyone walks (so its last row and
## column must be its first again, and the ground's own heights must be these
## along its edges: see `SandDunes.wrap`). It is drawn, it takes prints and
## `height_at`, `give_at` and the rest answer for it; whoever made the ground
## gives it something to stand on. Left empty, the ground ends at its edges and
## a rolling plain is drawn beyond (`beyond`, `apron`). Set it before the
## ground is built; `paint_far` paints it.
var far_heights := PackedFloat32Array()
## Whether the dunes throw shadows (never on a phone: see `Sand.quality`).
@export var casts_shadow := true
## Turns `Sand.quality` down if frames are coming slowly.
@export var auto_quality := true

## How high the sand stands at (x, z), measured from this node: a function of
## two floats. Set it before the ground enters the scene, or call `build`.
var height: Callable
## What the fine part of the mesh and the dents follow. Left empty: the first
## node in the group "sand_focus"; or the figure of the player (a body whose
## script is `player.gd`, or that is in the group "player"); or the camera.
var focus: Node3D
## The sand it throws up.
var spray: SandSpray
var cost_usec := 0.0

var _columns := 0
var _rows := 0
var _heights := PackedFloat32Array()
# What has been painted: three pictures of four kinds each, in the order of
# `Sand.Kind`, a share of each at every corner of the grid.
var _kinds: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray(), PackedByteArray()]
var _kinds_stale := 0
# The same for the ground past its edges (`far_heights`), and whether there is any.
var _far_kinds: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray(), PackedByteArray()]
var _endless := false
var _kind_images: Array[Image] = []
var _kind_maps: Array[ImageTexture] = []
var _height_map: ImageTexture
var _form_map: ImageTexture
var _material: ShaderMaterial
var _drawn: MeshInstance3D
var _collider: CollisionShape3D
var _origin := Vector3.ZERO
var _quality := -1
var _slow := 0.0
var _clock := 0.0

# The dents: `_span` squares a side, each `_fine` metres across, kept as a
# torus (a place's square is its place, wrapped), in tiles of `_tile` squares.
var _span := 0
var _fine := 0.015
var _tile := 32
var _dent := PackedByteArray()
var _dent_image: Image
var _dent_map: ImageTexture
var _dent_stale := false
var _middle := Vector2i(1 << 20, 0)
# The tiles with anything in them, and how far each has been filled.
var _live := {}
var _live_list: Array[Vector2i] = []
var _cursor := 0
var _filled := 0.0

var _figures := {}
var _bodies := {}
var _hounds := {}
var _census := 0.0
# The lobes of sand that are creeping (see `ooze`), and whose turn it is.
# Who is leaving a furrow (see `trail`): where each was last, and when.
var _trails := {}
var _lobes: Array[Dictionary] = []
var _lobe_turn := 0

static var _boot: Array
static var _tread: Array
static var _paw: Array
static var _bowl: Array
static var _heap: Array
static var _lying: Array


func _ready() -> void:
	add_to_group(&"sand_grounds")
	process_priority = 20
	process_physics_priority = 20
	spray = SandSpray.new()
	add_child(spray)
	if height.is_valid() and not is_built():
		build()


func is_built() -> bool:
	return _height_map != null


# --- Making it ---

## Makes the ground: heights, collider, mesh. `heights`, if given, is the
## grid already worked out (as `SandDunes.bake` gives it: row by row, one more
## each way than there are squares); otherwise `height` is asked.
func build(heights := PackedFloat32Array()) -> void:
	_origin = global_position if is_inside_tree() else position
	_columns = maxi(int(round(half.x * 2.0 / cell)), 2)
	_rows = maxi(int(round(half.y * 2.0 / cell)), 2)
	var wide := _columns + 1
	var long := _rows + 1
	if heights.size() == wide * long:
		_heights = heights
	else:
		_heights.resize(wide * long)
		for row in long:
			for column in wide:
				# (with no `height` it is level)
				_heights[row * wide + column] = height.call(column * cell - half.x, row * cell - half.y) if height.is_valid() else 0.0
	# (ground that goes on for ever keeps what lies past its edges under its own, in each of its pictures)
	_endless = far_heights.size() == wide * long
	var deep := long * 2 if _endless else long
	var pictured := _heights
	if _endless:
		pictured = _heights.duplicate()
		pictured.append_array(far_heights)
	_height_map = ImageTexture.create_from_image(Image.create_from_data(wide, deep, false, Image.FORMAT_RF, pictured.to_byte_array()))
	_make_form()
	_size_kinds()
	_kind_images.clear()
	_kind_maps.clear()
	_material = Sand.ground_surface(Sand.SNOW if snow and colour == Sand.COLOUR else colour)
	lend(_material)
	_material.set_shader_parameter(&"form_map", _form_map)
	_material.set_shader_parameter(&"snow", 1.0 if snow else 0.0)
	_material.set_shader_parameter(&"ripples", float(ripples))
	_material.set_shader_parameter(&"curve", 1.0 if curved else 0.0)
	for i in 3:
		_kind_images.append(Image.create_from_data(wide, deep, false, Image.FORMAT_RGBA8, _kinds_pictured(i)))
		_kind_maps.append(ImageTexture.create_from_image(_kind_images[i]))
		_material.set_shader_parameter([&"kind_map", &"kind_map2", &"kind_map3"][i], _kind_maps[i])
	_kinds_stale = 0
	var plain := apron
	if plain == INF:
		plain = 0.0
		for column in wide:
			plain += (_heights[column] + _heights[(long - 1) * wide + column]) / (2.0 * wide)
	_material.set_shader_parameter(&"apron", Vector2(plain, apron_roll))
	_trim()
	if solid:
		_make_collider()
	if _drawn == null:
		_drawn = MeshInstance3D.new()
		_drawn.top_level = true
		# (its shader puts it where it is)
		_drawn.custom_aabb = AABB(Vector3.ONE * -8000.0, Vector3.ONE * 16000.0)
		add_child(_drawn)
		_drawn.global_transform = Transform3D.IDENTITY
	_make_brushes()
	_fit_quality()
	built.emit()


## Gives another material what it needs to read this ground's heights (as
## `SandWind` does, to lay its streamers along the dunes): `height_map`,
## `field` and `field_cells`, as the sand shader has them.
func lend(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"height_map", _height_map)
	material.set_shader_parameter(&"field", Vector4(_origin.x - half.x, _origin.z - half.y, cell, _origin.y))
	material.set_shader_parameter(&"field_cells", Vector2(_columns, _rows))
	material.set_shader_parameter(&"endless", 1.0 if _endless else 0.0)


func _trim() -> void:
	if _material:
		_material.set_shader_parameter(&"trim", Vector3(1.0 if clip else 0.0, ring.x, ring.y))


## Makes the mesh and the dents again, as `Sand.quality` and `dent_cell` now
## have them. Whatever was pressed in is forgotten.
func refit() -> void:
	if is_built():
		_fit_quality()
		_middle = Vector2i(1 << 20, 0)


## The material it is drawn with.
func material() -> ShaderMaterial:
	return _material


func _set_snow(value: bool) -> void:
	snow = value
	if _material:
		_material.set_shader_parameter(&"snow", 1.0 if snow else 0.0)
		if colour == Sand.COLOUR:
			_material.set_shader_parameter(&"albedo", Sand.SNOW if snow else colour)


# Room for what is painted: a share of each kind at every corner of the grid.
func _size_kinds() -> void:
	_columns = maxi(int(round(half.x * 2.0 / cell)), 2) if _columns == 0 else _columns
	_rows = maxi(int(round(half.y * 2.0 / cell)), 2) if _rows == 0 else _rows
	var size := (_columns + 1) * (_rows + 1) * 4
	for kinds in _kinds:
		if kinds.size() != size:
			kinds.resize(size)
			kinds.fill(0)
	if far_heights.size() * 4 == size:
		for kinds in _far_kinds:
			if kinds.size() != size:
				kinds.resize(size)
				kinds.fill(0)


# What is painted, as its picture has it: the ground's own, and under it what lies past its edges.
func _kinds_pictured(index: int) -> PackedByteArray:
	if not _endless:
		return _kinds[index]
	var both := _kinds[index].duplicate()
	both.append_array(_far_kinds[index])
	return both


# Which way each corner faces, how sharply the ground bends there (a crest
# is more than nothing, a crease less), and how far it lies below the ground
# round about (a hollow).
func _make_form() -> void:
	var wide := _columns + 1
	var long := _rows + 1
	var form := _form_of(_heights, false)
	if _endless:
		# What lies past the edges is worked out as ground that repeats; and the
		# ground's own outermost corners, which are the same sand (and which cannot
		# see past the edge they stand on), take theirs from it: there is no line
		# in the light where one becomes the other.
		var beyond_form := _form_of(far_heights, true)
		for ring in 3:
			for along in maxi(wide, long):
				for at: Vector2i in [Vector2i(along, ring), Vector2i(along, long - 1 - ring), Vector2i(ring, along), Vector2i(wide - 1 - ring, along)]:
					if at.x < wide and at.y < long:
						var corner := (at.y * wide + at.x) * 4
						for part in 4:
							form[corner + part] = beyond_form[corner + part]
		form.append_array(beyond_form)
	var image := Image.create_from_data(wide, long * 2 if _endless else long, false, Image.FORMAT_RGBAF, form.to_byte_array())
	image.convert(Image.FORMAT_RGBAH)
	_form_map = ImageTexture.create_from_image(image)


# The same for one grid of heights. `wraps`: it is ground that repeats, and a
# corner at its edge looks across to the far edge for what is next to it.
func _form_of(heights: PackedFloat32Array, wraps: bool) -> PackedFloat32Array:
	var wide := _columns + 1
	var long := _rows + 1
	# The ground round about: the mean over a square some way each side.
	var round_about := _smoothed(heights, wide, long, maxi(int(7.0 / cell), 2), wraps)
	var form := PackedFloat32Array()
	form.resize(wide * long * 4)
	var far := maxi(int(round(2.0 / cell)), 1)
	for row in long:
		var north := maxi(row - 1, 0)
		var south := mini(row + 1, long - 1)
		var far_north := maxi(row - far, 0)
		var far_south := mini(row + far, long - 1)
		if wraps:
			north = posmod(row - 1, _rows)
			south = posmod(row + 1, _rows)
			far_north = posmod(row - far, _rows)
			far_south = posmod(row + far, _rows)
		var deep := cell * (2 if wraps else south - north)
		north *= wide
		south *= wide
		far_north *= wide
		far_south *= wide
		for column in wide:
			var here := heights[row * wide + column]
			var west := maxi(column - 1, 0)
			var east := mini(column + 1, wide - 1)
			var far_west := maxi(column - far, 0)
			var far_east := mini(column + far, wide - 1)
			var across := cell * (east - west)
			if wraps:
				west = posmod(column - 1, _columns)
				east = posmod(column + 1, _columns)
				far_west = posmod(column - far, _columns)
				far_east = posmod(column + far, _columns)
				across = cell * 2.0
			var facing := Vector3((heights[row * wide + west] - heights[row * wide + east]) / across, 1.0,
					(heights[north + column] - heights[south + column]) / deep).normalized()
			var bend := (heights[row * wide + far_west] + heights[row * wide + far_east]
					+ heights[far_north + column] + heights[far_south + column] - 4.0 * here) / (far * cell * far * cell)
			var at := (row * wide + column) * 4
			form[at] = facing.x
			form[at + 1] = facing.z
			form[at + 2] = clampf(-bend * 2.2, -1.0, 1.0)
			form[at + 3] = clampf((round_about[row * wide + column] - here) / 2.5, -1.0, 1.0)
	return form


# Each value the mean of those within `reach` of it, along and then across.
# (`wraps`: of a grid that repeats, whose last row and column are its first again)
static func _smoothed(values: PackedFloat32Array, wide: int, long: int, reach: int, wraps := false) -> PackedFloat32Array:
	var along := PackedFloat32Array()
	along.resize(values.size())
	if wraps:
		var both_ways := PackedFloat32Array()
		both_ways.resize(values.size())
		var share := 1.0 / (reach * 2 + 1)
		for row in long:
			var sum := 0.0
			for column in range(-reach * 2, wide):
				sum += values[row * wide + posmod(column + reach, wide - 1)]
				if column > 0:
					sum -= values[row * wide + posmod(column - reach - 1, wide - 1)]
				if column >= 0:
					along[row * wide + column] = sum * share
		for column in wide:
			var sum := 0.0
			for row in range(-reach * 2, long):
				sum += along[posmod(row + reach, long - 1) * wide + column]
				if row > 0:
					sum -= along[posmod(row - reach - 1, long - 1) * wide + column]
				if row >= 0:
					both_ways[row * wide + column] = sum * share
		return both_ways
	for row in long:
		var sum := 0.0
		var count := 0
		for column in range(-reach, wide):
			var enters := column + reach
			if enters < wide:
				sum += values[row * wide + enters]
				count += 1
			var leaves := column - reach - 1
			if leaves >= 0:
				sum -= values[row * wide + leaves]
				count -= 1
			if column >= 0:
				along[row * wide + column] = sum / count
	var both := PackedFloat32Array()
	both.resize(values.size())
	for column in wide:
		var sum := 0.0
		var count := 0
		for row in range(-reach, long):
			var enters := row + reach
			if enters < long:
				sum += along[enters * wide + column]
				count += 1
			var leaves := row - reach - 1
			if leaves >= 0:
				sum -= along[leaves * wide + column]
				count -= 1
			if row >= 0:
				both[row * wide + column] = sum / count
	return both


func _make_collider() -> void:
	var wide := _columns + 1
	var faces := PackedVector3Array()
	faces.resize(_columns * _rows * 6)
	var next := 0
	for row in _rows:
		var z := row * cell - half.y
		for column in _columns:
			var x := column * cell - half.x
			var corner := row * wide + column
			var a := Vector3(x, _heights[corner], z)
			var b := Vector3(x + cell, _heights[corner + 1], z)
			var c := Vector3(x + cell, _heights[corner + wide + 1], z + cell)
			var d := Vector3(x, _heights[corner + wide], z + cell)
			# (split as `height_at` has it)
			var turned := splits.size() == _columns * _rows and splits[row * _columns + column] == 1
			faces[next] = a
			faces[next + 1] = b
			faces[next + 2] = d if turned else c
			faces[next + 3] = b if turned else a
			faces[next + 4] = c
			faces[next + 5] = d
			next += 6
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	if _collider == null:
		_collider = CollisionShape3D.new()
		add_child(_collider)
	_collider.shape = shape


# The mesh and the dents, as fine as `Sand.quality` allows.
func _fit_quality() -> void:
	_quality = Sand.quality
	var first: float = [0.125, 0.0625, 0.015625][_quality]
	var across: int = [48, 64, 96][_quality]
	_drawn.mesh = _make_mesh(first, across)
	_drawn.mesh.surface_set_material(0, _material)
	Sand.refresh()
	# (on a phone the ground casts no shadows: it would be drawn again for each of the sun's)
	_drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _quality >= 2 and casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spray.thrift = [0.5, 0.75, 1.0][_quality]
	_span = [256, 512, 1024][_quality]
	_fine = [0.04, 0.025, 0.015][_quality]
	if dent_cell > 0.0:
		_fine = dent_cell
	_tile = _span / 32
	_dent.resize(_span * _span)
	_dent.fill(NEUTRAL)
	_live.clear()
	_live_list.clear()
	_dent_image = Image.create_from_data(_span, _span, false, Image.FORMAT_R8, _dent)
	_dent_map = ImageTexture.create_from_image(_dent_image)
	_material.set_shader_parameter(&"dent_map", _dent_map)
	_material.set_shader_parameter(&"dent", Vector4(_fine, _span, 255.0 * UNIT, NEUTRAL / 255.0))


# Rings of squares: the first a whole grid `across` squares a side, each
# `first` metres; every one after it twice as coarse, the same number across,
# with a hole in the middle where the last one is, and a band of triangles
# joining it to the last one's edge. Each corner carries the side of its
# ring's squares, and whether it is one of those that sit on the ring inside.
func _make_mesh(first: float, across: int) -> ArrayMesh:
	var points := PackedVector3Array()
	var marks := PackedVector2Array()
	var corners := PackedInt32Array()
	var need := maxf(half.x, half.y) * 2.0 + beyond
	var square := first
	@warning_ignore("integer_division")
	var mid := across / 2
	var ring := 0
	while true:
		@warning_ignore("integer_division")
		var hole := 0 if ring == 0 else across / 4 + 1
		var index := {}
		for j in range(-mid, mid + 1):
			for i in range(-mid, mid + 1):
				if maxi(absi(i), absi(j)) >= hole:
					index[Vector2i(i, j)] = points.size()
					points.append(Vector3(i * square, 0.0, j * square))
					marks.append(Vector2(square, 0.0))
		for j in range(-mid, mid):
			for i in range(-mid, mid):
				if i >= -hole and i < hole and j >= -hole and j < hole:
					continue
				var a: int = index[Vector2i(i, j)]
				var c: int = index[Vector2i(i + 1, j + 1)]
				corners.append_array([a, index[Vector2i(i + 1, j)], c, a, c, index[Vector2i(i, j + 1)]])
		if ring > 0:
			# The band: the last ring's edge (in its squares, half the size of
			# these) on one side, this ring's innermost corners on the other.
			var edge := {}
			for side in 4:
				var inner: Array[int] = []
				var outer: Array[int] = []
				for k in across + 1:
					var on: Vector2i = [Vector2i(-mid + k, -mid), Vector2i(mid, -mid + k), Vector2i(mid - k, mid), Vector2i(-mid, mid - k)][side]
					if not edge.has(on):
						edge[on] = points.size()
						points.append(Vector3(on.x * square * 0.5, 0.0, on.y * square * 0.5))
						marks.append(Vector2(square, 1.0))
					inner.append(edge[on])
				for k in hole * 2 + 1:
					outer.append(index[[Vector2i(-hole + k, -hole), Vector2i(hole, -hole + k), Vector2i(hole - k, hole), Vector2i(-hole, hole - k)][side]])
				var i := 0
				var o := 0
				while i < inner.size() - 1 or o < outer.size() - 1:
					var take_inner := o >= outer.size() - 1 or (i < inner.size() - 1 and float(i + 1) / (inner.size() - 1) <= float(o + 1) / (outer.size() - 1))
					var third := inner[i + 1] if take_inner else outer[o + 1]
					var one := points[outer[o]] - points[inner[i]]
					var other := points[third] - points[inner[i]]
					# (wound the way the squares are)
					if one.z * other.x - one.x * other.z < 0.0:
						corners.append_array([inner[i], outer[o], third])
					else:
						corners.append_array([inner[i], third, outer[o]])
					if take_inner:
						i += 1
					else:
						o += 1
		if square * mid >= need:
			break
		square *= 2.0
		ring += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = marks
	arrays[Mesh.ARRAY_INDEX] = corners
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Asking it things ---

## How high the sand stands at a place in the world (as the collider has it;
## dents are not counted).
func height_at(x: float, z: float) -> float:
	if _heights.is_empty():
		return _origin.y
	var across := (x - _origin.x + half.x) / cell
	var along := (z - _origin.z + half.y) / cell
	var heights := _heights
	if _endless and (across < 0.0 or across > _columns or along < 0.0 or along > _rows):
		# (past its edges: the same square of open sand, over and over)
		heights = far_heights
		across = fposmod(across, _columns)
		along = fposmod(along, _rows)
	across = clampf(across, 0.0, _columns - 0.0001)
	along = clampf(along, 0.0, _rows - 0.0001)
	var column := int(across)
	var row := int(along)
	across -= column
	along -= row
	var corner := row * (_columns + 1) + column
	var a := heights[corner]
	var d := heights[corner + _columns + 2]
	var b := heights[corner + 1]
	var c := heights[corner + _columns + 1]
	# (each square is two triangles: split from this corner to the far one, or
	# the other way if `splits` says so)
	if splits.size() == _columns * _rows and splits[row * _columns + column] == 1:
		if across + along < 1.0:
			return a + across * (b - a) + along * (c - a) + _origin.y
		return d + (1.0 - across) * (c - d) + (1.0 - along) * (b - d) + _origin.y
	if across > along:
		return a + across * (b - a) + along * (d - b) + _origin.y
	return a + along * (c - a) + across * (d - c) + _origin.y


## Which way the sand faces at a place in the world.
func normal_at(x: float, z: float) -> Vector3:
	var reach := cell * 0.5
	return Vector3(height_at(x - reach, z) - height_at(x + reach, z), cell, height_at(x, z - reach) - height_at(x, z + reach)).normalized()


## Whether a point in the world is on this sand, or within `slack` above or below it.
func covers(point: Vector3, slack := 0.15) -> bool:
	if _heights.is_empty() or (not _endless and _past(point.x, point.z)):
		return false
	return absf(point.y - height_at(point.x, point.z)) <= slack


# Whether a place is past the ground's own edges.
func _past(x: float, z: float) -> bool:
	if ring.y > 0.0:
		var out := Vector2(x - _origin.x, z - _origin.z).length()
		if out > ring.y or out < ring.x:
			return true
	return absf(x - _origin.x) > half.x or absf(z - _origin.z) > half.y


## What has been painted at a place: a share of each of the first four of
## `Sand.Kind` (coarse, damp, packed, pale), in that order, as r, g, b, a.
## (For the others, `share_at`.)
func kind_at(x: float, z: float) -> Color:
	if _kinds[0].is_empty() or _heights.is_empty() or _past(x, z):
		return Color(0.0, 0.0, 0.0, 0.0)
	var at := _corner(x, z)
	var kinds := _kinds[0]
	return Color(kinds[at] / 255.0, kinds[at + 1] / 255.0, kinds[at + 2] / 255.0, kinds[at + 3] / 255.0)


## How much of one `Sand.Kind` has been painted at a place, 0 to 1.
func share_at(kind: int, x: float, z: float) -> float:
	if kind == Sand.Kind.SNOW and snow:
		return 1.0
	@warning_ignore("integer_division")
	if _kinds[kind / 4].is_empty() or _heights.is_empty():
		return 0.0
	@warning_ignore("integer_division")
	return _between(kind / 4, kind % 4, x, z)


## How readily the ground gives at a place: 1 is loose sand, a quarter a path
## trodden hard, and 0 hard dirt or rock, which takes no print, lets nobody
## sink into it and does not run.
func give_at(x: float, z: float) -> float:
	if _kinds[0].is_empty() or _heights.is_empty():
		return 1.0
	var hard := maxf(_between(1, 0, x, z), _between(1, 1, x, z))
	return (1.0 - 0.75 * _between(0, 2, x, z)) * (1.0 - smoothstep(0.36, 0.64, hard))


## About the colour of the ground at a place, for whatever is thrown up from it.
func colour_at(x: float, z: float) -> Color:
	var here := Sand.SNOW if snow and colour == Sand.COLOUR else colour
	if _kinds[0].is_empty() or _heights.is_empty() or _past(x, z):
		return here.lerp(Color(spray_colour, 1.0), spray_colour.a)
	var at := _corner(x, z)
	here = here.lerp(Sand.WHITE, _kinds[1][at + 2] / 255.0).lerp(Sand.RED, _kinds[1][at + 3] / 255.0)
	here = here.lerp(Sand.BLACK, _kinds[2][at] / 255.0).lerp(Sand.SNOW, _kinds[2][at + 1] / 255.0)
	here = here.lerp(here * Color(0.8, 0.755, 0.71), _kinds[0][at] / 255.0)
	here = here.lerp(Sand.DIRT, _kinds[1][at] / 255.0).lerp(Sand.SANDSTONE, _kinds[1][at + 1] / 255.0)
	here = here.lerp(here * Color(0.6, 0.57, 0.53), _kinds[0][at + 1] / 255.0)
	return here.lerp(Color(spray_colour, 1.0), spray_colour.a)


# Where in a picture of kinds the corner of the grid nearest a place is.
func _corner(x: float, z: float) -> int:
	var column := clampi(int(round((x - _origin.x + half.x) / cell)), 0, _columns)
	var row := clampi(int(round((z - _origin.z + half.y) / cell)), 0, _rows)
	return (row * (_columns + 1) + column) * 4


# One kind's share at a place, taken from the four corners round it (as the
# shader takes it: what is done to him matches what he sees).
func _between(picture: int, channel: int, x: float, z: float) -> float:
	var kinds := _kinds[picture]
	var across := (x - _origin.x + half.x) / cell
	var along := (z - _origin.z + half.y) / cell
	if _endless and (across < 0.0 or across > _columns or along < 0.0 or along > _rows):
		kinds = _far_kinds[picture]
		across = fposmod(across, _columns)
		along = fposmod(along, _rows)
	across = clampf(across, 0.0, _columns - 0.0001)
	along = clampf(along, 0.0, _rows - 0.0001)
	var column := int(across)
	var row := int(along)
	across -= column
	along -= row
	var at := (row * (_columns + 1) + column) * 4 + channel
	var below := at + (_columns + 1) * 4
	return (lerpf(lerpf(kinds[at], kinds[at + 4], across), lerpf(kinds[below], kinds[below + 4], across), along)) / 255.0


## Paints a kind of sand (`Sand.Kind`) round a place in the world (x, z): all
## of `amount` within `radius`, falling away to nothing over `feather` beyond.
## May be called before or after it is built.
func paint(kind: int, at: Vector2, radius: float, amount := 1.0, feather := 2.0) -> void:
	paint_line(kind, at, at, radius, amount, feather)


## The same along a line: `width` is how far to each side of it.
func paint_line(kind: int, from: Vector2, to: Vector2, width: float, amount := 1.0, feather := 2.0) -> void:
	_size_kinds()
	var wide := _columns + 1
	@warning_ignore("integer_division")
	var kinds := _kinds[kind / 4]
	var corner := Vector2(position.x - half.x, position.z - half.y) if not is_built() else Vector2(_origin.x - half.x, _origin.z - half.y)
	var reach := width + feather
	var low := (from.min(to) - Vector2.ONE * reach - corner) / cell
	var high := (from.max(to) + Vector2.ONE * reach - corner) / cell
	for row in range(maxi(floori(low.y), 0), mini(ceili(high.y), _rows) + 1):
		for column in range(maxi(floori(low.x), 0), mini(ceili(high.x), _columns) + 1):
			var place := corner + Vector2(column, row) * cell
			var along := to - from
			var share := clampf((place - from).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
			var far := place.distance_to(from + along * share)
			var value := int(255.0 * amount * (1.0 - smoothstep(width, reach, far)))
			var at := (row * wide + column) * 4 + kind % 4
			if value > kinds[at]:
				kinds[at] = value
	@warning_ignore("integer_division")
	_kinds_stale |= 1 << (kind / 4)


## Paints a kind over the whole ground at once: `shares` is how much of it
## lies at every corner of the grid (0..255), row by row, as `build` takes
## heights. Where more was painted already, that is kept.
func paint_all(kind: int, shares: PackedByteArray) -> void:
	_size_kinds()
	@warning_ignore("integer_division")
	var kinds := _kinds[kind / 4]
	if shares.size() * 4 != kinds.size():
		return
	var channel := kind % 4
	for i in shares.size():
		if shares[i] > kinds[i * 4 + channel]:
			kinds[i * 4 + channel] = shares[i]
	@warning_ignore("integer_division")
	_kinds_stale |= 1 << (kind / 4)


## Paints the ground past its edges (`far_heights`) as the ground itself is
## painted just now. (It is one square of sand over and over, and what is
## painted on it is painted on them all: so paint the ground with what belongs
## to the open sand, call this, and then paint the rest.)
func paint_far() -> void:
	_size_kinds()
	for i in 3:
		if _far_kinds[i].size() == _kinds[i].size():
			_far_kinds[i] = _kinds[i].duplicate()
	_kinds_stale = 7


# --- Pressing into it ---

## A footprint at a point in the world: `yaw` is which way the toe points
## (as `rotation.y`), `depth` how deep the heel goes, metres. In sand it is a
## soft dent, longer than it is wide and shallower than that; in snow (or with
## `crisp_prints`) it is the print of the boot.
func footprint(at: Vector3, yaw: float, depth: float, left: bool) -> void:
	if crisp_prints or share_at(Sand.Kind.SNOW, at.x, at.z) > 0.5:
		_stamp(_boot, Vector2(at.x, at.z), yaw, depth, 1.0, not left)
	else:
		_stamp(_tread, Vector2(at.x, at.z), yaw, depth * 1.15)


## A paw print.
func pawprint(at: Vector3, yaw: float, depth: float) -> void:
	_stamp(_paw, Vector2(at.x, at.z), yaw, depth)


## A round dent with a lip round it, `radius` across its hollow: what a rock
## makes where it lands. Stamped again and again along a line it is a trough.
func press(at: Vector3, radius: float, depth: float) -> void:
	_stamp(_bowl, Vector2(at.x, at.z), 0.0, depth, radius)


## A low heap, `radius` to its foot and `tall` high: where running sand comes to rest.
func heap(at: Vector3, radius: float, tall: float) -> void:
	_stamp(_heap, Vector2(at.x, at.z), 0.0, tall, radius)


## The print of someone lying full length, head towards `yaw`, `at` their middle.
func body_print(at: Vector3, yaw: float, depth: float) -> void:
	_stamp(_lying, Vector2(at.x, at.z), yaw, depth)


## Sets the sand at a place moving downhill, if it lies steeply enough: a
## lobe of it lets go and oozes away, and one or two more after it. `amount`
## is how hard it was disturbed (a walking step is about half, a slide 1 or
## more). Hard ground and snow do not run.
func disturb(at: Vector3, amount: float) -> void:
	var facing := normal_at(at.x, at.z)
	var steep := sqrt(maxf(1.0 - facing.y * facing.y, 0.0)) / maxf(facing.y, 0.01)
	var give := give_at(at.x, at.z)
	if steep < RUNS_AT or give < 0.2 or share_at(Sand.Kind.SNOW, at.x, at.z) > 0.5:
		return
	var much := smoothstep(RUNS_AT, 0.62, steep) * clampf(amount, 0.2, 2.0) * give
	var downhill := Vector3(facing.x, 0.0, facing.z).normalized()
	var across := Vector3(downhill.z, 0.0, -downhill.x)
	# Where it leaves from, a scoop.
	press(at + downhill * 0.1, 0.1 + 0.05 * much, 0.008 + 0.006 * much)
	# One lobe away at once, and one or two that let go a moment later, each
	# a little to one side of the last and not quite the same way.
	for k in 1 + int(much * 1.5 + randf()):
		var delay := 0.0 if k == 0 else randf_range(0.2, 1.1)
		var from := at + across * randf_range(-0.3, 0.3) * (1.0 if k > 0 else 0.3) + downhill * randf_range(0.12, 0.35)
		ooze(from, downhill.rotated(Vector3.UP, randf_range(-0.4, 0.4)), randf_range(0.22, 0.34) + 0.16 * much,
				minf(randf_range(0.12, 0.19) + 0.06 * much, 0.28), minf(0.032 + 0.012 * much, 0.055), randf_range(2.6, 3.6) + 0.8 * much, true, delay)


## Sets a lobe of loose sand creeping over the ground from `at`, the way
## `way` points: a thick rounded mass, `radius` from its middle to its edge
## and `tall` high (6 cm at the most), that sets off at `speed` metres a
## second, spreads and slows, and has stopped after `life` seconds, leaving a
## low tongue where it has been and itself where it ends. If it `runs` it
## follows the fall of the ground, goes only as fast as the slope is steep,
## and buries the prints it goes over; if not it is pushed straight out and
## comes to rest (the collar round a foot). `delay` holds it back.
func ooze(at: Vector3, way: Vector3, speed: float, radius: float, tall: float, life: float, runs := true, delay := 0.0) -> void:
	if _lobes.size() >= LOBES:
		return
	if runs:
		var running := 0
		for lobe in _lobes:
			running += 1 if lobe.runs else 0
		if running >= SLOPE_LOBES[maxi(_quality, 0)]:
			return
	var heading := Vector2(way.x, way.z)
	if heading.length() < 0.001:
		return
	_lobes.append({at = Vector2(at.x, at.z), way = heading.normalized(), speed = speed, radius = radius, tall = tall, life = life, runs = runs,
			wait = delay, age = 0.0, last = Vector2.INF, seen = 0.0, high = 0.0})


# Moves the lobes on, and presses them into the dents where they have got to.
# Each is pressed in again only when it has moved some part of a square, and
# only so many squares are pressed in a frame, the lobes taking it in turns.
func _creep(delta: float) -> void:
	var squares := LOBE_SQUARES[_quality]
	var count := _lobes.size()
	_lobe_turn += 1
	var done := false
	for k in count:
		var lobe := _lobes[(k + _lobe_turn) % count]
		if lobe.wait > 0.0:
			lobe.wait -= delta
			continue
		lobe.age += delta
		var through: float = minf(lobe.age / lobe.life, 1.0)
		var at: Vector2 = lobe.at
		var pace: float = lobe.speed
		if lobe.runs:
			# It follows the fall of the ground, and stops where that levels out.
			var facing := normal_at(at.x, at.y)
			var downhill := Vector2(facing.x, facing.z)
			var steep := downhill.length() / maxf(facing.y, 0.01)
			if steep > 0.001:
				lobe.way = (lobe.way as Vector2).lerp(downhill.normalized(), minf(3.0 * delta, 1.0)).normalized()
			pace *= (1.0 - through) * smoothstep(0.08, 0.4, steep) * give_at(at.x, at.y)
		else:
			pace *= (1.0 - through) * (1.0 - through)
		at += (lobe.way as Vector2) * pace * delta
		lobe.at = at
		var last: Vector2 = lobe.last
		var moved := at.distance_to(last) if last != Vector2.INF else 0.0
		# (pressed in again when it has moved, and as it slumps at the end)
		if (last == Vector2.INF or moved >= _fine * (0.35 if lobe.runs else 0.6) or through - lobe.seen > 0.07) and squares > 0:
			# It swells up out of the ground as it starts; it spreads as it
			# goes, and is lower for it; and as it stops it slumps, wide and low.
			var swell := smoothstep(0.0, 0.12, through)
			var radius: float = lobe.radius * (0.6 + 0.4 * swell + 0.4 * through * through)
			var tall: float = lobe.tall * swell * (1.0 - 0.6 * through * through)
			var sunk: float = maxf(lobe.high - tall, 0.0)
			squares -= _press_lobe(at, lobe.way, radius, tall, maxi(int(round((moved * 0.2 + sunk) / UNIT)), 1), lobe.runs)
			lobe.last = at
			lobe.seen = through
			lobe.high = tall
		if through >= 1.0 or (lobe.age > 0.5 and pace < 0.01):
			lobe.life = 0.0
			done = true
	if done:
		for k in range(count - 1, -1, -1):
			if _lobes[k].life <= 0.0:
				_lobes.remove_at(k)


# Presses a lobe into the dents: a round-backed mound, longer the way it is
# going than it is wide, that stands up steeply at its edge, raised wherever
# the ground is lower than it. Behind it, where it has been, and wherever it
# has sunk, the ground is let down again by `wear` steps, to a low tongue: so
# the mass travels, and is not drawn out. If it `fills` it buries whatever is
# pressed in under it; if not, it leaves a print alone. Gives back how many
# squares it looked at.
func _press_lobe(at: Vector2, way: Vector2, radius: float, tall: float, wear: int, fills: bool) -> int:
	var long := radius * 1.3
	var reach := long * (1.25 if fills else 1.12) + _fine
	var room := (_span >> 1) - _tile
	var low_x := _middle.x - room
	var high_x := _middle.x + room - 1
	var first_z := maxi(floori((at.y - reach) / _fine), _middle.y - room)
	var last_z := mini(ceili((at.y + reach) / _fine), _middle.y + room - 1)
	if first_z > last_z or at.x + reach < low_x * _fine or at.x - reach > (high_x + 1) * _fine:
		return 0
	var levels := minf(tall / UNIT, 255.0 - NEUTRAL)
	var tongue := int(levels * 0.12)
	var along_x := way.x / long
	var along_z := way.y / long
	var across_x := -way.y / radius
	var across_z := way.x / radius
	var mask := _span - 1
	var looked := 0
	for z in range(first_z, last_z + 1):
		var off_z := (z + 0.5) * _fine - at.y
		var row := (z & mask) * _span
		# (only as much of each row as lies within its reach)
		var wide := sqrt(maxf(reach * reach - off_z * off_z, 0.0))
		var first_x := maxi(floori((at.x - wide) / _fine), low_x)
		var last_x := mini(ceili((at.x + wide) / _fine), high_x)
		looked += last_x - first_x + 1
		for x in range(first_x, last_x + 1):
			var off_x := (x + 0.5) * _fine - at.x
			var along := off_x * along_x + off_z * along_z
			var across := off_x * across_x + off_z * across_z
			var out := along * along + across * across
			var index := row + (x & mask)
			var now := _dent[index] - NEUTRAL
			var wanted := int(levels * (1.0 - out) * (1.0 + 0.7 * out)) if out < 1.0 else 0
			if wanted > now:
				if fills or now > -3:
					_dent[index] = wanted + NEUTRAL
			elif now > tongue and now > wanted:
				_dent[index] = maxi(maxi(wanted, tongue), now - wear) + NEUTRAL
	_wake(floori((at.x - reach) / _fine), ceili((at.x + reach) / _fine), first_z, last_z)
	return looked


# Notes that there is something in the dents between these squares, to be
# softened and filled in time.
func _wake(first_x: int, last_x: int, first_z: int, last_z: int) -> void:
	for tile_z in range(floori(float(first_z) / _tile), floori(float(last_z) / _tile) + 1):
		for tile_x in range(floori(float(first_x) / _tile), floori(float(last_x) / _tile) + 1):
			var tile := Vector2i(tile_x, tile_z)
			if not _live.has(tile):
				_live[tile] = _filled
				_live_list.append(tile)
	_dent_stale = true


# Presses a brush into the dents: a small picture of a shape, -1 where it is
# deepest, more than nothing where sand is pushed up round it. `size` scales
# the picture, `depth` is how far -1 goes down, metres.
func _stamp(brush: Array, at: Vector2, yaw: float, depth: float, size := 1.0, mirrored := false) -> void:
	if _span == 0:
		return
	# (hard ground takes nothing; a packed path less)
	depth *= give_at(at.x, at.y)
	if depth < UNIT:
		return
	var picture: PackedFloat32Array = brush[0]
	var wide: int = brush[1]
	var long: int = brush[2]
	var grain: float = brush[3] * size
	var half_wide := wide * grain * 0.5
	var half_long := long * grain * 0.5
	var reach := sqrt(half_wide * half_wide + half_long * half_long)
	var sine := sin(yaw)
	var cosine := cos(yaw)
	# (only inside the patch that is kept)
	var room := (_span >> 1) - _tile
	var first_x := maxi(floori((at.x - reach) / _fine), _middle.x - room)
	var last_x := mini(ceili((at.x + reach) / _fine), _middle.x + room - 1)
	var first_z := maxi(floori((at.y - reach) / _fine), _middle.y - room)
	var last_z := mini(ceili((at.y + reach) / _fine), _middle.y + room - 1)
	if first_x > last_x or first_z > last_z:
		return
	var levels := depth / UNIT
	var mask := _span - 1
	var flip := -1.0 if mirrored else 1.0
	for z in range(first_z, last_z + 1):
		var off_z := (z + 0.5) * _fine - at.y
		var row := (z & mask) * _span
		for x in range(first_x, last_x + 1):
			var off_x := (x + 0.5) * _fine - at.x
			var across := (off_x * cosine - off_z * sine) * flip + half_wide
			var along := off_x * sine + off_z * cosine + half_long
			if across < 0.0 or along < 0.0:
				continue
			var column := int(across / grain)
			var line := int(along / grain)
			if column >= wide or line >= long:
				continue
			var value := picture[line * wide + column]
			if value == 0.0:
				continue
			var index := row + (x & mask)
			var now := _dent[index] - NEUTRAL
			var wanted := int(value * levels)
			if value < 0.0:
				if wanted < now:
					_dent[index] = maxi(wanted + NEUTRAL, 0)
			elif now > -3 and wanted > now:
				_dent[index] = mini(wanted + NEUTRAL, 255)
	_wake(first_x, last_x, first_z, last_z)


# Moves the patch of dents to keep the focus in the middle of it, a tile at a
# time, forgetting whatever is left behind.
func _follow(to: Vector3) -> void:
	var middle := Vector2i(roundi(to.x / (_fine * _tile)), roundi(to.z / (_fine * _tile))) * _tile
	if middle == _middle:
		return
	_middle = middle
	_material.set_shader_parameter(&"dent_at", Vector2(middle) * _fine)
	var room := (_span >> 1) - _tile
	var i := 0
	while i < _live_list.size():
		var tile := _live_list[i]
		var from_middle := tile * _tile - middle
		if from_middle.x < -room or from_middle.x >= room or from_middle.y < -room or from_middle.y >= room:
			_smooth_over(tile, 0, true)
			_live.erase(tile)
			_live_list[i] = _live_list[-1]
			_live_list.pop_back()
			_dent_stale = true
		else:
			i += 1


# The wind's work: a few tiles a frame, each softened and filled by as much
# as is due to it since it was last seen to.
func _fill(delta: float) -> void:
	var seconds := lerpf(fill_seconds.x, fill_seconds.y, clampf(Sand.wind_force, 0.0, 1.0))
	_filled += delta * (0.02 / UNIT) / maxf(seconds, 0.1)
	var budget := 2
	for look in mini(_live_list.size(), 8):
		_cursor = (_cursor + 1) % _live_list.size()
		var tile := _live_list[_cursor]
		var due := int(_filled - _live[tile])
		if due < 1:
			continue
		_live[tile] += due
		_dent_stale = true
		if not _smooth_over(tile, due, false):
			_live.erase(tile)
			_live_list[_cursor] = _live_list[-1]
			_live_list.pop_back()
			if _live_list.is_empty():
				break
		budget -= 1
		if budget == 0:
			break


# Softens one tile (each square a quarter of the way to the mean of those
# round it) and brings it `levels` nearer to flat; or just flattens it. Says
# whether anything is left in it.
func _smooth_over(tile: Vector2i, levels: int, flatten: bool) -> bool:
	var mask := _span - 1
	var from_x := tile.x * _tile
	var from_z := tile.y * _tile
	var any := false
	for j in _tile:
		var row := ((from_z + j) & mask) * _span
		if flatten:
			for i in _tile:
				_dent[row + ((from_x + i) & mask)] = NEUTRAL
			continue
		var north := ((from_z + j - 1) & mask) * _span
		var south := ((from_z + j + 1) & mask) * _span
		for i in _tile:
			var x := (from_x + i) & mask
			var here := _dent[row + x]
			var around := _dent[row + ((x + 1) & mask)] + _dent[row + ((x - 1) & mask)] + _dent[north + x] + _dent[south + x]
			if here == NEUTRAL and around == NEUTRAL * 4:
				continue
			var soft := (here * 12 + around + 8) >> 4
			if soft > NEUTRAL:
				soft = maxi(soft - levels, NEUTRAL)
			elif soft < NEUTRAL:
				soft = mini(soft + levels, NEUTRAL)
			_dent[row + x] = soft
			if soft != NEUTRAL:
				any = true
	return any


# The shapes that are pressed in: each [picture, squares wide, squares long, metres a square].
static func _make_brushes() -> void:
	if not _boot.is_empty():
		return
	# What a foot leaves in sand, which holds no shape: a shallow dent, round
	# at both ends and deepest in the middle, 15 cm by 30, toe towards +z, and
	# the sand that came out of it lying low and wide round it.
	var soft_grain := 0.0125
	var soft_wide := 28
	var soft_long := 40
	var soft := PackedFloat32Array()
	soft.resize(soft_wide * soft_long)
	for line in soft_long:
		for column in soft_wide:
			var place := Vector2(((column + 0.5) - soft_wide * 0.5) * soft_grain / 0.078, ((line + 0.5) - soft_long * 0.5) * soft_grain / 0.15)
			var out := place.length()
			if out < 1.0:
				soft[line * soft_wide + column] = -pow(1.0 - out * out, 1.3)
			elif out < 1.6:
				soft[line * soft_wide + column] = 0.13 * sin(PI * (out - 1.0) / 0.6)
	_tread = [soft, soft_wide, soft_long, soft_grain]
	# A left boot, toe towards +z, 27 cm long: a round heel, a waist, the ball
	# of the foot and a round toe; deepest under the heel and the ball, with
	# the front edge of the heel standing across it; and a lip pushed up round it.
	var grain := 0.01
	var wide := 18
	var long := 35
	var picture := PackedFloat32Array()
	picture.resize(wide * long)
	for line in long:
		var along := ((line + 0.5) * grain - long * grain * 0.5 + 0.135) / 0.27
		var half_wide := 0.0
		if along >= 0.0 and along <= 1.0:
			if along < 0.14:
				half_wide = 0.037 * sqrt(1.0 - pow((0.14 - along) / 0.14, 2.0))
			elif along < 0.3:
				half_wide = 0.037
			elif along < 0.44:
				half_wide = lerpf(0.037, 0.032, smoothstep(0.3, 0.44, along))
			elif along < 0.68:
				half_wide = lerpf(0.032, 0.05, smoothstep(0.44, 0.68, along))
			else:
				half_wide = 0.05 * sqrt(maxf(1.0 - pow((along - 0.68) / 0.32, 2.0), 0.0))
		# (the outside of the foot bows out; the inside is nearly straight)
		var middle := 0.008 * sin(clampf(along, 0.0, 1.0) * PI)
		var beyond_ends := maxf(maxf(-along, along - 1.0), 0.0) * 0.27
		for column in wide:
			var across := (column + 0.5) * grain - wide * grain * 0.5
			var outside := absf(across - middle) - half_wide
			if beyond_ends > 0.0:
				outside = sqrt(pow(maxf(absf(across - middle) - 0.02, 0.0), 2.0) + beyond_ends * beyond_ends)
			var value := 0.0
			if outside < 0.0:
				var deep := 0.6
				if along < 0.31:
					deep = 1.0
				elif along < 0.35:
					deep = 0.45
				elif along > 0.5:
					deep = lerpf(0.6, 0.92, smoothstep(0.5, 0.66, along)) * (1.0 - 0.25 * smoothstep(0.85, 1.0, along))
				value = -deep * smoothstep(0.0, 0.009, -outside)
			elif outside < 0.022:
				value = 0.16 * sin(PI * outside / 0.022)
			picture[line * wide + column] = value
	_boot = [picture, wide, long, grain]

	# A paw: a pad, and four toes in front of it.
	grain = 0.006
	wide = 16
	long = 18
	picture = PackedFloat32Array()
	picture.resize(wide * long)
	var pads: Array[Vector3] = [Vector3(0.0, -0.014, 0.021), Vector3(-0.026, 0.012, 0.011), Vector3(-0.01, 0.03, 0.011), Vector3(0.01, 0.03, 0.011), Vector3(0.026, 0.012, 0.011)]
	for line in long:
		for column in wide:
			var place := Vector2((column + 0.5) * grain - wide * grain * 0.5, (line + 0.5) * grain - long * grain * 0.5)
			var value := 0.0
			for pad in pads:
				value = minf(value, -smoothstep(0.0, 0.006, pad.z - place.distance_to(Vector2(pad.x, pad.y))))
			picture[line * wide + column] = value
	_paw = [picture, wide, long, grain]

	# A bowl one metre in radius (it is scaled to fit), and a lip round it; and a heap.
	wide = 34
	grain = 2.9 / wide
	picture = PackedFloat32Array()
	picture.resize(wide * wide)
	var mound := PackedFloat32Array()
	mound.resize(wide * wide)
	for line in wide:
		for column in wide:
			var out := Vector2((column + 0.5) * grain - 1.45, (line + 0.5) * grain - 1.45).length()
			if out < 1.0:
				picture[line * wide + column] = -pow(cos(out * PI * 0.5), 0.7)
			elif out < 1.42:
				picture[line * wide + column] = 0.32 * sin(PI * (out - 1.0) / 0.42)
			mound[line * wide + column] = pow(maxf(cos(minf(out, 1.0) * PI * 0.5), 0.0), 1.3)
	_bowl = [picture, wide, wide, grain]
	_heap = [mound, wide, wide, grain]

	# Someone lying full length, head towards +z: head, shoulders and arms, trunk, legs.
	grain = 0.015
	wide = 60
	long = 106
	picture = PackedFloat32Array()
	picture.resize(wide * long)
	for line in long:
		for column in wide:
			var place := Vector2((column + 0.5) * grain - wide * grain * 0.5, (line + 0.5) * grain - long * grain * 0.5)
			# (how far inside each part, the deepest of them)
			var inside := 0.105 - place.distance_to(Vector2(0.0, 0.6))
			# (the trunk, wider at the shoulders, with the arms lying along it)
			var wide_here := lerpf(0.15, 0.25, smoothstep(0.0, 0.42, place.y))
			inside = maxf(inside, 0.07 - Vector2(maxf(absf(place.x) - wide_here + 0.07, 0.0), maxf(absf(place.y - 0.22) - 0.2, 0.0)).length())
			inside = maxf(inside, 0.075 - Vector2(absf(absf(place.x) - 0.095), maxf(absf(place.y + 0.36) - 0.36, 0.0)).length())
			# (soft at the edges: a body is round, and does not press evenly)
			var value := -smoothstep(-0.03, 0.07, inside) * (0.8 + 0.2 * sin(place.y * 7.0 + 1.0))
			picture[line * wide + column] = value
	_lying = [picture, wide, long, grain]


# --- Each frame ---

func _process(delta: float) -> void:
	if not is_built():
		return
	var began := Time.get_ticks_usec()
	_clock += delta
	if _quality != Sand.quality:
		_fit_quality()
		_middle = Vector2i(1 << 20, 0)
	if focus == null or not is_instance_valid(focus):
		# (anything in the group "sand_focus"; or the figure of the player, who is
		# known by his script's name and not by its class, so that sand needs no Player)
		focus = get_tree().get_first_node_in_group(&"sand_focus") as Node3D
		if focus == null:
			for figure: Node3D in get_tree().get_nodes_in_group(&"figures"):
				if _is_player(figure.get_parent()):
					focus = figure
					break
	var middle := Vector3.ZERO
	if focus:
		middle = focus.global_position
	elif get_viewport().get_camera_3d():
		middle = get_viewport().get_camera_3d().global_position
	_material.set_shader_parameter(&"focus", middle)
	_follow(middle)

	for figure: Node3D in get_tree().get_nodes_in_group(&"figures"):
		_watch(figure, delta)
	_census -= delta
	if _census <= 0.0:
		_census = 0.5
		_count_heads()
		_watch_frames()
	for hound: Variant in _hounds:
		if is_instance_valid(hound):
			_watch_hound(hound)

	if not _lobes.is_empty():
		_creep(delta)
	if not _live_list.is_empty():
		_fill(delta)
	if _dent_stale:
		_dent_stale = false
		_dent_image.set_data(_span, _span, false, Image.FORMAT_R8, _dent)
		_dent_map.update(_dent_image)
	if _kinds_stale != 0:
		for i in 3:
			if _kinds_stale & (1 << i):
				_kind_images[i].set_data(_columns + 1, (_rows + 1) * (2 if _endless else 1), false, Image.FORMAT_RGBA8, _kinds_pictured(i))
				_kind_maps[i].update(_kind_images[i])
		_kinds_stale = 0
	cost_usec = lerpf(cost_usec, float(Time.get_ticks_usec() - began), 0.1)


func _physics_process(delta: float) -> void:
	if not is_built():
		return
	for body: Variant in _bodies:
		if is_instance_valid(body) and (body as Node).is_inside_tree():
			_watch_body(body, _bodies[body])
	if slope_carry > 0.0:
		for figure: Variant in _figures:
			if is_instance_valid(figure) and (figure as Node).is_inside_tree() and _figures[figure].on:
				_carry(figure, _figures[figure], delta)


# Who and what is about: looked for twice a second, not every frame.
func _count_heads() -> void:
	for group: StringName in [&"throwable", &"sand_denting"]:
		for body: Node in get_tree().get_nodes_in_group(group):
			if body is RigidBody3D and not _bodies.has(body):
				# How big it is, and how far its middle rides above what it lies on.
				var radius := 0.15
				var rise := 0.15
				for child in body.get_children():
					if child is CollisionShape3D and child.shape is SphereShape3D:
						radius = (child.shape as SphereShape3D).radius
						rise = radius
					elif child is CollisionShape3D and child.shape is BoxShape3D:
						var box := (child.shape as BoxShape3D).size
						radius = minf(minf(box.x, box.z), maxf(box.x, box.z) * 0.6) * 0.55
						rise = minf(box.x, minf(box.y, box.z)) * 0.5 if box.y > maxf(box.x, box.z) * 1.5 else box.y * 0.5
				_bodies[body] = {radius = radius, rise = rise, touching = false, last = Vector3.INF, speed = 0.0}
	for hound: Node in get_tree().get_nodes_in_group(&"hounds"):
		if hound is Node3D and not _hounds.has(hound):
			_hounds[hound] = {last = (hound as Node3D).global_position, step = 0}
	for known: Dictionary in [_bodies, _hounds, _figures]:
		for node: Variant in known.keys():
			if not is_instance_valid(node):
				known.erase(node)
	for who: Variant in _trails.keys():
		if _clock - _trails[who].seen > 2.0 or (who is Object and not is_instance_valid(who)):
			_trails.erase(who)


# Turns the quality down a step if frames have been slow for some seconds.
func _watch_frames() -> void:
	if not auto_quality or _clock < 6.0:
		return
	_slow = _slow + 0.5 if Performance.get_monitor(Performance.TIME_FPS) < 38.0 else 0.0
	if _slow >= 5.0 and Sand.quality > 0:
		_slow = 0.0
		Sand.quality -= 1


# --- Figures ---

func _watch(figure: Node3D, delta: float) -> void:
	var body := figure.get_parent() as CharacterBody3D
	if body == null:
		return
	var known: Dictionary = _figures.get(figure, {})
	if known.is_empty():
		known = {on = false, sink = 0.0, pressed = 0.0, scrape = 0.0, run = 0.0, phase = [0.0, 0.5], hooked = figure.has_signal(&"footfall"),
				sprawl = -1.0, dust = null}
		_figures[figure] = known
		if known.hooked:
			figure.connect(&"footfall", _on_footfall.bind(figure))
		if figure.has_signal(&"scraped"):
			figure.connect(&"scraped", _on_scraped.bind(figure))
		if body.has_signal(&"landed"):
			body.connect(&"landed", _on_landed.bind(figure))
		if not (&"dust_scale" in figure):
			for child in figure.get_children():
				if child is Dust:
					known.dust = child
	var at := body.global_position
	var limp: bool = body.get(&"is_limp") == true
	var on := body.is_on_floor() and not limp and covers(at, 0.14 + known.sink)
	var lump := _lump_under(at) if not limp else false
	known.on = on
	# On sand it raises sand, not dust (nor as it comes down onto it). On hard
	# ground it raises dust as it does anywhere.
	var give := give_at(at.x, at.z)
	var sandy := (on or lump or (not body.is_on_floor() and covers(at + Vector3.DOWN * 0.35, 0.5))) and give > 0.2
	if &"dust_scale" in figure:
		figure.set(&"dust_scale", 0.0 if sandy else 1.0)
	elif known.dust:
		(known.dust as Node3D).visible = not sandy

	# Standing still he settles into it, and comes out as he moves off.
	var speed := Vector3(body.velocity.x, 0.0, body.velocity.z).length()
	var still := speed < 0.25 and (on or lump) and body.is_on_floor()
	var want := 0.0
	if still:
		want = sink_depth * 3.0 if lump else sink_depth * give
	if want > known.sink:
		known.sink = lerpf(known.sink, want, 1.0 - exp(-3.0 * delta / sink_time))
	else:
		known.sink = move_toward(known.sink, want, delta * (0.25 if speed > 0.25 else 0.08))
	if &"sink" in figure:
		figure.set(&"sink", known.sink)
	# The dent to match, under each foot, as he goes down.
	if still and on and not lump and known.sink > known.pressed + 0.004:
		known.pressed = known.sink
		for foot in 2:
			footprint(_foot(figure, foot), _foot_yaw(figure, foot), known.sink + 0.008, foot == 0)
	elif not still:
		known.pressed = 0.0

	known.scrape = maxf(known.scrape - delta, 0.0)
	known.run = maxf(known.run - delta, 0.0)
	if known.sprawl >= 0.0:
		known.sprawl -= delta
		if known.sprawl < 0.0 and covers(at, 0.3):
			var facing := figure.global_basis.z
			body_print(at + Vector3(facing.x, 0.0, facing.z).normalized() * 0.5, atan2(facing.x, facing.z), 0.03)
	if not known.hooked:
		_guess_steps(figure, body, known, on, speed)


func _foot(figure: Node3D, foot: int) -> Vector3:
	if figure.has_method(&"foot_position"):
		return figure.call(&"foot_position", foot)
	return figure.global_position + figure.global_basis * Vector3(0.09 if foot == 0 else -0.09, 0.0, 0.03)


# Which way a foot points: the way he faces, turned out a little.
func _foot_yaw(figure: Node3D, foot: int) -> float:
	var facing := figure.global_basis.z
	return atan2(facing.x, facing.z) + (0.16 if foot == 0 else -0.16)


func _lump_under(at: Vector3) -> bool:
	for blob: Node in get_tree().get_nodes_in_group(&"sand_blobs"):
		if blob.has_method(&"covers") and blob.call(&"covers", at):
			return true
	return false


# A foot has come down at `at`: `weight` is about 0.3 sneaking, 0.5 walking,
# 1 running, and up to 3 for a landing.
func _on_footfall(at: Vector3, foot: int, weight: float, figure: Node3D) -> void:
	if not covers(at, 0.3):
		return
	var body := figure.get_parent() as CharacterBody3D
	var kind := kind_at(at.x, at.z)
	# (hard ground gives nothing up, and takes nothing: see `_stamp`)
	var loose := give_at(at.x, at.z)
	if loose < 0.05:
		return
	if body and body.get(&"is_crawling") == true:
		# (a knee or a hand)
		press(at, 0.05, 0.014)
		return
	var yaw := _foot_yaw(figure, foot)
	footprint(at, yaw, clampf(0.009 + 0.015 * weight, 0.01, 0.05) * (1.0 + 0.4 * kind.g), foot == 0)
	var ground_at := Vector3(at.x, height_at(at.x, at.z), at.z)
	var facing := normal_at(at.x, at.z)
	var tint := colour_at(at.x, at.z).srgb_to_linear()
	var going := Vector3(body.velocity.x, 0.0, body.velocity.z) if body else Vector3.ZERO
	var dry := loose * (1.0 - 0.5 * kind.g)
	var snowy := share_at(Sand.Kind.SNOW, at.x, at.z) > 0.5
	if weight > 1.5:
		# A landing: a ring of it.
		spray.ring(ground_at, 1.3 + 0.6 * weight, int((8.0 + 6.0 * weight) * dry), tint, 0.2 + 0.03 * weight, facing)
	elif weight > 0.4:
		# A step throws it back and up: a run more than a walk.
		var back := -going.normalized() if going.length() > 0.3 else Vector3.ZERO
		spray.kick(ground_at, back * (0.4 + 0.3 * going.length()) + Vector3.UP * (1.1 + 1.2 * weight), int((2.0 + 9.0 * (weight - 0.3)) * dry), 0.4, tint, 0.15 + 0.04 * weight, 0.0, facing)
	elif dry > 0.5:
		spray.kick(ground_at, Vector3.UP * 0.7, 1, 0.6, tint, 0.12, 0.0, facing)
	# In loose sand what the foot pushes aside swells out round it in a
	# collar, in three or four lumps, and slumps there.
	if loose > 0.6 and weight > 0.35 and not snowy and not crisp_prints:
		var soft := loose * (1.0 - 0.6 * kind.g)
		var heavy := minf(weight, 2.5)
		for k in 2 + int(heavy + randf()):
			# (most of it goes out to the sides, where the foot is longest)
			var turn := (PI * 0.5 if k % 2 == 0 else -PI * 0.5) + randf_range(-1.0, 1.0)
			var out := Vector3(sin(yaw + turn), 0.0, cos(yaw + turn))
			var edge := 1.0 / Vector2(sin(turn) / 0.078, cos(turn) / 0.15).length()
			ooze(at + out * edge * 1.05, out, (0.3 + 0.14 * heavy) * soft, randf_range(0.05, 0.07) * (0.85 + 0.25 * heavy), (0.012 + 0.007 * heavy) * soft, randf_range(0.5, 0.8), false)
	disturb(at, weight)


# He is scraping over the ground at `at`: sliding, skidding, rolling, or down on it.
func _on_scraped(at: Vector3, velocity: Vector3, amount: float, figure: Node3D) -> void:
	var known: Dictionary = _figures.get(figure, {})
	if known.is_empty() or known.scrape > 0.0 or not covers(at, 0.4):
		return
	known.scrape = 0.05
	var ground_at := Vector3(at.x, height_at(at.x, at.z), at.z)
	var loose := give_at(at.x, at.z)
	if loose < 0.05:
		return
	press(ground_at, 0.15 + 0.07 * amount, 0.016 + 0.014 * amount)
	var tint := colour_at(at.x, at.z).srgb_to_linear()
	var pace := Vector3(velocity.x, 0.0, velocity.z).length()
	if pace > 0.6:
		# A sheet of it, thrown out ahead and to the sides.
		spray.kick(ground_at, velocity * 0.45 + Vector3.UP * (0.8 + 0.25 * pace * amount), int(1.0 + 2.0 * amount * loose), 0.55, tint, 0.2, 0.0, normal_at(at.x, at.z))
	if known.run <= 0.0:
		known.run = 0.14
		disturb(at, 0.6 + amount)


# He has landed. The feet say so themselves (see `_on_footfall`); this is for
# the sprawl, which leaves the print of all of him a moment later.
func _on_landed(impact_speed: float, figure: Node3D) -> void:
	var body := figure.get_parent()
	var known: Dictionary = _figures.get(figure, {})
	if known.is_empty():
		return
	if &"landing" in body and body.get(&"landing") == _named(body, &"Landing", &"SPRAWL"):
		known.sprawl = 0.42
	if not known.hooked and covers(figure.global_position, 0.4):
		for foot in 2:
			_on_footfall(_foot(figure, foot), foot, clampf(impact_speed / 5.0, 1.0, 3.0), figure)


# For a rig that does not yet say when its feet come down: watches its gait
# go round, as it does itself, and its slides.
func _guess_steps(figure: Node3D, body: CharacterBody3D, known: Dictionary, on: bool, speed: float) -> void:
	var phases: Variant = figure.get(&"_foot_phase")
	if phases is Array and (phases as Array).size() == 2:
		for foot in 2:
			var before: float = known.phase[foot]
			known.phase[foot] = phases[foot]
			if on and speed > 0.4 and phases[foot] < before - 0.5:
				var weight := 0.3 if body.get(&"is_ducking") == true else clampf(remap(speed, 1.6, 4.4, 0.5, 1.0), 0.4, 1.2)
				_on_footfall(_foot(figure, foot), foot, weight, figure)
	if on and not figure.has_signal(&"scraped") and &"state" in body and body.get(&"state") == _named(body, &"State", &"SLIDE"):
		_on_scraped(body.global_position, body.velocity, 1.0, figure)


# A steep face gives under him: it carries him downhill a little, and goes
# on running while he stands on it.
func _carry(figure: Node3D, known: Dictionary, delta: float) -> void:
	var body := figure.get_parent() as CharacterBody3D
	var at := body.global_position
	var facing := normal_at(at.x, at.z)
	var steep := sqrt(maxf(1.0 - facing.y * facing.y, 0.0)) / maxf(facing.y, 0.01)
	var gives := smoothstep(0.47, 0.62, steep) * maxf(give_at(at.x, at.z) * 1.33 - 0.33, 0.0)
	if share_at(Sand.Kind.SNOW, at.x, at.z) > 0.5:
		gives = 0.0
	if gives <= 0.01:
		return
	var downhill := Vector3(facing.x, 0.0, facing.z).normalized()
	body.move_and_collide(downhill * slope_carry * gives * delta)
	if known.run <= 0.0:
		known.run = randf_range(0.25, 0.5)
		disturb(at + Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)), 0.5 + gives)


# --- Hounds, and whatever is thrown ---

# A hound leaves prints by where it has got to: a pair for every stretch it covers.
func _watch_hound(hound: Node3D) -> void:
	var known: Dictionary = _hounds[hound]
	var at := hound.global_position
	var moved: Vector3 = at - known.last
	moved.y = 0.0
	if moved.length() < 0.3:
		return
	known.last = at
	known.step += 1
	if not covers(at, 0.2):
		return
	var way := moved.normalized()
	var side := Vector3(way.z, 0.0, -way.x) * (0.07 if known.step % 2 == 0 else -0.07)
	var yaw := atan2(way.x, way.z)
	# (fore and hind on that side, the hind one coming down just short of the fore)
	pawprint(at + side + way * 0.28, yaw, 0.014)
	pawprint(at + side - way * 0.2, yaw, 0.012)
	if moved.length() > 0.08 and hound is CharacterBody3D and (hound as CharacterBody3D).velocity.length() > 3.0:
		var ground_at := Vector3(at.x, height_at(at.x, at.z), at.z)
		spray.kick(ground_at, -way * 1.2 + Vector3.UP * 1.0, 2, 0.5, colour_at(at.x, at.z).srgb_to_linear(), 0.12)


# A loose thing: it dents the sand where it lands and furrows it where it rolls.
func _watch_body(body: RigidBody3D, known: Dictionary) -> void:
	var at := body.global_position
	var under: float = at.y - known.rise
	var falling: float = known.speed
	known.speed = body.linear_velocity.y
	if body.freeze or (not _endless and _past(at.x, at.z)):
		known.touching = false
		return
	var ground_y := height_at(at.x, at.z)
	var touching := absf(under - ground_y) < 0.05
	var ground_at := Vector3(at.x, ground_y, at.z)
	var radius: float = known.radius
	if touching and not known.touching:
		var hard := clampf(-falling * 0.12, 0.0, 1.0)
		press(ground_at, radius * (0.75 + 0.3 * hard), minf(0.008 + 0.03 * hard, radius * 0.5))
		known.last = at
		if hard > 0.15:
			spray.ring(ground_at, 0.8 + 2.0 * hard, int(4.0 + 12.0 * hard * minf(radius / 0.12, 2.0)), colour_at(at.x, at.z).srgb_to_linear(), 0.12 + 0.1 * hard)
			disturb(ground_at, hard * 1.5)
	elif touching and at.distance_to(known.last) > radius * 0.6:
		known.last = at
		press(ground_at, radius * 0.7, minf(0.012, radius * 0.2))
		disturb(ground_at, 0.3)
	known.touching = touching


# --- Anything else that marks it ---
# (None of this is in Outside's copy: there everything that marks the sand is a
# figure on a CharacterRig, a hound or a thrown thing, and is found by its group.
# This is for a game whose bodies are none of those.)

## Something has come down on the sand at `at` (a foot, a wheel, a ball): a
## round dent `radius` across its hollow and `depth` deep, and sand thrown up
## from it, back along the way it came if `velocity` says which that is. `sand`
## is how much: 0 none, 0.5 a walking step, 1 a running one, 2 and more a
## landing, which throws a ring of it all round. Hard ground takes no dent and
## gives nothing up. Says whether it was on the sand at all (`at` may be up to
## half a metre above or below it).
##
## Call it once for each footfall. It asks nothing of the body and keeps
## nothing about it; for a shaped print use `footprint` and `spray.kick`.
func mark(at: Vector3, velocity := Vector3.ZERO, radius := 0.12, depth := 0.02, sand := 1.0) -> bool:
	if not is_built() or not covers(at, 0.5):
		return false
	var loose := give_at(at.x, at.z)
	if loose < 0.05:
		return true
	var ground_at := Vector3(at.x, height_at(at.x, at.z), at.z)
	press(ground_at, radius, depth)
	_throw_up(ground_at, velocity, sand * loose)
	return true


## A furrow. Call it every frame (or every physics tick) that something is
## dragging over the sand, with where it now touches: the ground is pressed in
## all the way from where `who` was last time to `at`, however far that is in
## one frame, so that something doing 30 m/s leaves one unbroken trough and not
## a row of dots. `who` is anything that tells one trail from another: the body
## itself, or a number. A call that comes more than a quarter of a second after
## the last, or from more than 4 m away, starts a new furrow (it had left the
## ground, or been put somewhere else); so there is nothing to call when it
## lifts off. Sand is thrown up behind it, more the faster it goes, at most a
## dozen times a second for each trail: `sand` is how much, 0 for none.
##
## What it costs is the pressing: one round stamp every `radius` * 0.6 metres
## travelled, each of about (3 * `radius` / the side of a square of the dents)
## squared steps of script. With the dents at their finest that is too much for
## anything fast; give the ground a `dent_cell` of a third to a half of `radius`.
## Away from the patch of dents round `focus` it costs almost nothing, and
## leaves nothing either.
func trail(who: Variant, at: Vector3, radius := 0.25, depth := 0.02, sand := 1.0) -> void:
	if not is_built() or not covers(at, 0.5):
		_trails.erase(who)
		return
	var known: Dictionary = _trails.get(who, {})
	var fresh: bool = known.is_empty() or _clock - known.seen > 0.25 or (known.at as Vector3).distance_to(at) > 4.0
	if fresh:
		known = {at = at, seen = _clock, owed = 0.0, thrown = -1.0}
		_trails[who] = known
		press(Vector3(at.x, height_at(at.x, at.z), at.z), radius, depth)
		return
	var from: Vector3 = known.at
	var gone := Vector3(at.x - from.x, 0.0, at.z - from.z)
	var far := gone.length()
	var pace := far / maxf(_clock - known.seen, 0.001)
	if far < 0.0001:
		known.seen = _clock
		return
	known.at = at
	known.seen = _clock
	# (only where there are dents to press: see `_follow`)
	var room := ((_span >> 1) - _tile) * _fine + radius * 2.0
	var middle := Vector2(_middle) * _fine
	if absf(at.x - middle.x) < room + far and absf(at.z - middle.y) < room + far:
		var every := maxf(radius * 0.6, _fine)
		var along: float = every - known.owed
		while along <= far:
			var place := from + gone * (along / far)
			_stamp(_bowl, Vector2(place.x, place.z), 0.0, depth, radius)
			along += every
		known.owed = far - (along - every)
	if sand > 0.0 and pace > 1.0 and _clock - known.thrown > 0.08:
		known.thrown = _clock
		var loose := give_at(at.x, at.z)
		if loose > 0.05:
			# (two handfuls or so at a time: there are only `SandSpray.COUNT` grains for everyone)
			_throw_up(Vector3(at.x, height_at(at.x, at.z), at.z), gone / far * pace, clampf(sand, 0.45, 1.4), maxi(int(round(2.0 * sand * loose)), 1))


# Sand thrown up from a point on the ground by something going at `velocity`:
# `weight` as a footfall's is (see `_on_footfall`, which this follows).
func _throw_up(ground_at: Vector3, velocity: Vector3, weight: float, handfuls := -1) -> void:
	if weight <= 0.0:
		return
	var facing := normal_at(ground_at.x, ground_at.z)
	var tint := colour_at(ground_at.x, ground_at.z).srgb_to_linear()
	var going := Vector3(velocity.x, 0.0, velocity.z)
	var pace := going.length()
	if weight > 1.5:
		spray.ring(ground_at, 1.3 + 0.6 * weight, int(8.0 + 6.0 * weight), tint, 0.2 + 0.03 * weight, facing)
	elif weight > 0.4:
		# (back and up, further the faster it is going; but sand is heavy, and
		# none of it is thrown faster than a few metres a second)
		var back := -going / pace if pace > 0.3 else Vector3.ZERO
		spray.kick(ground_at, back * minf(0.4 + 0.3 * pace, 4.5) + Vector3.UP * (1.1 + 1.2 * weight + minf(pace * 0.05, 1.0)),
				handfuls if handfuls > 0 else maxi(int(2.0 + 9.0 * (weight - 0.3)), 1), 0.4, tint, 0.15 + 0.04 * weight, 0.0, facing)
	else:
		spray.kick(ground_at, Vector3.UP * 0.7, 1, 0.6, tint, 0.12, 0.0, facing)


# Whether a body is the player: its script is called `player.gd`, or it is in
# the group "player". (Outside's copy asks `is Player`.)
static func _is_player(body: Node) -> bool:
	if body == null:
		return false
	if body.is_in_group(&"player"):
		return true
	var script := body.get_script() as Script
	return script != null and script.resource_path.get_file() == "player.gd"


# One of the named numbers a body's script has (`Player.Landing.SPRAWL`, as
# Outside's copy has it), or -1 if it has none such.
static func _named(body: Object, list: StringName, entry: StringName) -> int:
	var script := body.get_script() as Script
	while script:
		var found: Variant = script.get_script_constant_map().get(list)
		if found is Dictionary and (found as Dictionary).has(entry):
			return found[entry]
		script = script.get_base_script()
	return -1
