extends Node3D
## What the Crystaliens built round their colosseum. Two things went into it. The Crystal Palace:
## iron and glass in the same bay over and over, round-headed arches in two storeys with fans of
## glazing bars, and great barrel-vaulted transepts with a wheel window in the end of each. And the
## painted cities of Ralph McQuarrie and of the Dune that Jodorowsky never made (Moebius, Foss,
## Giger): towers too big to be reasonable, swelling and tapering, banded in bright colours, mushroom
## caps and collars on them, ribs like a carcass's sweeping up the outside, and saucers of light
## hanging over it all. Drawn only (nothing here is run into); colosseum.gd owns one.
##   - the arcade: `BAYS` bays round the top of the stands, two storeys, as two multimeshes (iron,
##     glass); a crystal finial on every pier
##   - the canopy: a rafter from every pier of the arcade up and in to a great ring truss hung
##     over the arena (two rings, braced), with rings of purlins tying the rafters together and
##     glass over the stands; the middle, over the sand, is open to the sky
##   - four transepts on the compass points: a barrel vault running out from the arcade, glass
##     between iron hoops, a wheel window in its inner end
##   - the ribs: great curved fins from the ground outside up over the arcade
##   - the towers beyond, turned on a lathe from a few profiles, striped (shaders/tower.gdshader)
##   - three saucers hanging in the air, lit underneath, drifting

const Crystal := preload("res://scripts/crystal.gd")
const BAYS := 48
const STOREY := 11.0 # the lower arches' height; the upper storey is two thirds of it
const IRON := Color(0.06, 0.07, 0.1)
const GLASS := Color(0.5, 0.85, 1.0)

## Where the arcade stands: how far out from the middle of the arena, and how high its foot is
var out := 88.0
var foot := 17.0

var _iron := StandardMaterial3D.new()
var _glass := ShaderMaterial.new()
var _rng := RandomNumberGenerator.new()
var _saucers: Array[Node3D] = []
var _clock := 0.0


func _ready() -> void:
	_rng.seed = 1851
	_iron.albedo_color = IRON
	_iron.metallic = 0.7
	_iron.roughness = 0.35
	_glass.shader = preload("res://shaders/crystal.gdshader")
	_glass.set_shader_parameter("horizon", GLASS)
	_glass.set_shader_parameter("sky_top", GLASS.darkened(0.8))
	_glass.set_shader_parameter("clarity", 0.85)
	_build_arcade()
	_build_canopy()
	_build_transepts()
	_build_ribs()
	_build_towers()
	_build_saucers()


func _process(delta: float) -> void:
	_clock += delta
	for k in _saucers.size():
		var saucer := _saucers[k]
		var home: Vector3 = saucer.get_meta("home")
		saucer.position = home + Vector3(sin(_clock * 0.11 + k * 2.0) * 9.0, sin(_clock * 0.23 + k) * 2.5, cos(_clock * 0.09 + k * 1.3) * 9.0)
		saucer.rotation.y = _clock * (0.05 + 0.02 * k)


# --- Pieces of iron and glass ---------------------------------------------------------------

## A straight bar from a to b, `thick` square
func _bar(tool: SurfaceTool, a: Vector3, b: Vector3, thick: float) -> void:
	var along := b - a
	if along.length() < 0.001:
		return
	var up := Vector3.UP if absf(along.normalized().y) < 0.95 else Vector3.RIGHT
	var side := along.cross(up).normalized() * thick * 0.5
	var over := side.cross(along).normalized() * thick * 0.5
	var corners: Array[Vector3] = [a - side - over, a + side - over, a + side + over, a - side + over, b - side - over, b + side - over, b + side + over, b - side + over]
	for face in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [0, 3, 2, 1], [4, 5, 6, 7]]:
		var centre := (a + b) * 0.5
		_quad(tool, centre, corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]])


## A flat four-cornered piece, facing away from `centre`
func _quad(tool: SurfaceTool, centre: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var p: Vector3 = tri[0]
		var q: Vector3 = tri[1]
		var r: Vector3 = tri[2]
		if (q - p).cross(r - p).dot((p + q + r) / 3.0 - centre) > 0.0:
			var swap := q
			q = r
			r = swap
		tool.add_vertex(p)
		tool.add_vertex(q)
		tool.add_vertex(r)


## A round-headed arch in the x/y plane, `wide` across and `tall` to its crown, standing on y = 0
## about x = 0: its two legs and the half round over them, as bars; with `fan` glazing bars
## radiating from the middle of its springing line
func _arch(tool: SurfaceTool, wide: float, tall: float, thick: float, fan: int, at := Transform3D.IDENTITY) -> void:
	var radius := wide * 0.5
	var spring := tall - radius # (where the round begins)
	_bar(tool, at * Vector3(-radius, 0.0, 0.0), at * Vector3(-radius, spring, 0.0), thick)
	_bar(tool, at * Vector3(radius, 0.0, 0.0), at * Vector3(radius, spring, 0.0), thick)
	_bar(tool, at * Vector3(-radius, spring, 0.0), at * Vector3(radius, spring, 0.0), thick * 0.6)
	var steps := 12
	for k in steps:
		var a := PI * k / steps
		var b := PI * (k + 1) / steps
		_bar(tool, at * Vector3(cos(a) * radius, spring + sin(a) * radius, 0.0), at * Vector3(cos(b) * radius, spring + sin(b) * radius, 0.0), thick)
	for k in range(1, fan):
		var a := PI * k / fan
		_bar(tool, at * Vector3(0.0, spring, 0.0), at * Vector3(cos(a) * radius, spring + sin(a) * radius, 0.0), thick * 0.4)
	# (and a smaller half round inside the fan, as its hub)
	for k in 6:
		var a := PI * k / 6.0
		var b := PI * (k + 1) / 6.0
		_bar(tool, at * Vector3(cos(a) * radius * 0.3, spring + sin(a) * radius * 0.3, 0.0), at * Vector3(cos(b) * radius * 0.3, spring + sin(b) * radius * 0.3, 0.0), thick * 0.4)


## The glass in such an arch: one sheet filling it
func _arch_glass(tool: SurfaceTool, wide: float, tall: float, at := Transform3D.IDENTITY) -> void:
	var radius := wide * 0.5
	var spring := tall - radius
	var centre := at * Vector3(0.0, spring, -5.0)
	_quad(tool, centre, at * Vector3(-radius, 0.0, 0.0), at * Vector3(radius, 0.0, 0.0), at * Vector3(radius, spring, 0.0), at * Vector3(-radius, spring, 0.0))
	var steps := 12
	for k in steps:
		var a := PI * k / steps
		var b := PI * (k + 1) / steps
		var p := at * Vector3(0.0, spring, 0.0)
		var q := at * Vector3(cos(a) * radius, spring + sin(a) * radius, 0.0)
		var r := at * Vector3(cos(b) * radius, spring + sin(b) * radius, 0.0)
		_quad(tool, centre, p, q, r, r)


func _begin() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	return tool


func _show(tool: SurfaceTool, material: Material, parent: Node = self) -> MeshInstance3D:
	tool.generate_normals()
	var view := MeshInstance3D.new()
	view.mesh = tool.commit()
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(view)
	return view


# --- The arcade ----------------------------------------------------------------------------

func _build_arcade() -> void:
	var wide := TAU * out / BAYS
	var upper := STOREY * 0.66
	# One bay, facing -Z (in toward the arena once it's turned to face the middle)
	var iron := _begin()
	_arch(iron, wide - 0.5, STOREY, 0.42, 8)
	_arch(iron, wide - 0.5, upper, 0.3, 6, Transform3D(Basis.IDENTITY, Vector3(0.0, STOREY + 0.5, 0.0)))
	# The cornices between and over the storeys, and the pier the arches stand against
	for y in [STOREY + 0.25, STOREY + upper + 0.75]:
		_bar(iron, Vector3(-wide * 0.5, y, 0.0), Vector3(wide * 0.5, y, 0.0), 0.6)
	_bar(iron, Vector3(-wide * 0.5, 0.0, 0.1), Vector3(-wide * 0.5, STOREY + upper + 1.0, 0.1), 0.7)
	iron.generate_normals()
	var glass := _begin()
	_arch_glass(glass, wide - 0.5, STOREY)
	_arch_glass(glass, wide - 0.5, upper, Transform3D(Basis.IDENTITY, Vector3(0.0, STOREY + 0.5, 0.0)))
	glass.generate_normals()
	var finial := Crystal.shard(0.45, 3.4, 0.3)
	for part in [[iron.commit(), _iron, 0.0], [glass.commit(), _glass, 0.0], [finial, _glass, STOREY + upper + 2.4]]:
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = part[0]
		many.instance_count = BAYS
		for k in BAYS:
			var angle := (k + 0.5) * TAU / BAYS
			var facing := Basis(Vector3.UP, -angle + PI / 2.0)
			var place := Vector3(cos(angle) * out, foot + float(part[2]), sin(angle) * out)
			if float(part[2]) > 0.0:
				place += facing * Vector3(-wide * 0.5, 0.0, 0.0) # (the finial: on the pier, not mid-bay)
			many.set_instance_transform(k, Transform3D(facing, place))
		var view := MultiMeshInstance3D.new()
		view.multimesh = many
		view.material_override = part[1]
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(view)


# --- The canopy ----------------------------------------------------------------------------

## Every pier of the arcade carries a rafter: it bows up and in to a ring truss hung over the
## arena, so nothing ends in the air. Purlins ring the rafters at thirds; glass covers the outer
## two thirds (over the stands); the ring's middle is open.
func _build_canopy() -> void:
	var top := foot + STOREY * 1.66 + 1.0
	var ring_out := out * 0.62 # (over the arena's wall, about)
	var ring_up := top + 15.0
	var iron := _begin()
	var glass := _begin()
	var steps := 6
	var rafters: Array = [] # each: its points from the pier in to the ring
	for k in BAYS:
		var angle := k * TAU / BAYS
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var points: Array[Vector3] = []
		for s in steps + 1:
			var t := float(s) / steps
			# (rising quickly off the pier, levelling out toward the ring)
			points.append(outward * lerpf(out, ring_out, t) + Vector3.UP * lerpf(top, ring_up, sin(t * PI * 0.5)))
		rafters.append(points)
		for s in steps:
			_bar(iron, points[s], points[s + 1], lerpf(0.8, 0.45, float(s) / steps))
		# A strut down from the rafter's shoulder to the pier's head, so it's braced
		_bar(iron, outward * out + Vector3.UP * (top - 4.0), points[1], 0.35)
	for k in BAYS:
		var here: Array = rafters[k]
		var next: Array = rafters[(k + 1) % BAYS]
		# The ring truss: an upper ring where the rafters land, a lower one a little in and down,
		# and bracing between them
		var lower_here: Vector3 = (here[steps] as Vector3) * Vector3(0.9, 0.0, 0.9) + Vector3.UP * (ring_up - 5.0)
		var lower_next: Vector3 = (next[steps] as Vector3) * Vector3(0.9, 0.0, 0.9) + Vector3.UP * (ring_up - 5.0)
		_bar(iron, here[steps], next[steps], 1.1)
		_bar(iron, lower_here, lower_next, 0.8)
		_bar(iron, here[steps], lower_here, 0.5)
		_bar(iron, here[steps], lower_next, 0.35)
		# Purlins, and the glass between the rafters out over the stands
		for s in [2, 4]:
			_bar(iron, here[s], next[s], 0.4)
		for s in 4:
			_quad(glass, ((here[s] as Vector3) + (next[s + 1] as Vector3)) * 0.5 + Vector3.DOWN * 30.0, here[s], next[s], next[s + 1], here[s + 1])
	_show(iron, _iron)
	_show(glass, _glass)


# --- The transepts ---------------------------------------------------------------------------

func _build_transepts() -> void:
	var radius := 17.0
	var length := 34.0
	var spring := foot + STOREY * 1.66 + 1.0 # (their vaults spring from the arcade's top)
	for k in 4:
		var angle := k * TAU / 4.0
		# x across the vault, z outward along it
		var place := Transform3D(Basis(Vector3.UP, -angle - PI / 2.0), Vector3(cos(angle), 0.0, sin(angle)) * (out - 1.0) + Vector3.UP * spring)
		var iron := _begin()
		var glass := _begin()
		# Hoops along it, a ridge and purlins joining them, glass between
		var hoops := 6
		var steps := 14
		for h in hoops + 1:
			var z := length * h / hoops
			for s in steps:
				var a := PI * s / steps
				var b := PI * (s + 1) / steps
				var p := Vector3(cos(a) * radius, sin(a) * radius, z)
				var q := Vector3(cos(b) * radius, sin(b) * radius, z)
				_bar(iron, place * p, place * q, 0.55)
				if h < hoops:
					var z2 := length * (h + 1) / hoops
					_quad(glass, place * Vector3(0.0, -20.0, (z + z2) * 0.5), place * p, place * q, place * Vector3(q.x, q.y, z2), place * Vector3(p.x, p.y, z2))
		for s in range(0, steps + 1, 2):
			var a := PI * s / steps
			_bar(iron, place * Vector3(cos(a) * radius, sin(a) * radius, 0.0), place * Vector3(cos(a) * radius, sin(a) * radius, length), 0.4)
		# Its legs down to the stands, and the wheel window in the end that looks into the arena
		for side in [-1.0, 1.0]:
			for h in hoops + 1:
				var z := length * h / hoops
				_bar(iron, place * Vector3(side * radius, 0.0, z), place * Vector3(side * radius, -STOREY * 1.66 - 1.0, z), 0.6)
		for end in [0.0, length]:
			var spokes := 16
			for s in spokes + 1:
				var a := PI * s / spokes
				_bar(iron, place * Vector3(0.0, 0.0, end), place * Vector3(cos(a) * radius, sin(a) * radius, end), 0.3)
			for ring in [0.35, 0.68]:
				for s in steps:
					var a := PI * s / steps
					var b := PI * (s + 1) / steps
					_bar(iron, place * Vector3(cos(a) * radius * ring, sin(a) * radius * ring, end), place * Vector3(cos(b) * radius * ring, sin(b) * radius * ring, end), 0.3)
			for s in steps:
				var a := PI * s / steps
				var b := PI * (s + 1) / steps
				_quad(glass, place * Vector3(0.0, 0.0, end - 9.0 if end == 0.0 else end - 9.0), place * Vector3(0.0, 0.0, end), place * Vector3(cos(a) * radius, sin(a) * radius, end), place * Vector3(cos(b) * radius, sin(b) * radius, end), place * Vector3(cos(b) * radius, sin(b) * radius, end))
			_bar(iron, place * Vector3(-radius, 0.0, end), place * Vector3(radius, 0.0, end), 0.6)
		_show(iron, _iron)
		_show(glass, _glass)


# --- The ribs --------------------------------------------------------------------------------

## Great fins from the ground outside, up and over to the arcade's top: a carcass's ribs
func _build_ribs() -> void:
	var tool := _begin()
	var count := 24
	for k in count:
		var angle := (k + 0.5) * TAU / count
		if k % 6 == 2 or k % 6 == 3:
			continue # (the transepts stand here)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var top := outward * (out + 1.0) + Vector3.UP * (foot + STOREY * 1.66 + 3.0)
		var ground := outward * (out + 46.0) + Vector3.UP * -2.0
		var bulge := outward * (out + 40.0) + Vector3.UP * (foot + STOREY * 2.6)
		var last := ground
		var steps := 14
		for s in range(1, steps + 1):
			var t := float(s) / steps
			var point := ground.lerp(bulge, t).lerp(bulge.lerp(top, t), t)
			# (thick at the root, fine where it comes down on the arcade)
			_bar(tool, last, point, lerpf(3.2, 0.7, t))
			last = point
		# A spine of smaller bars off its back, like a fish's
		for s in range(3, steps - 1, 3):
			var t := float(s) / steps
			var point := ground.lerp(bulge, t).lerp(bulge.lerp(top, t), t)
			_bar(tool, point, point + outward * 4.0 + Vector3.UP * 5.0, 0.5)
	_show(tool, _iron)


# --- The towers ------------------------------------------------------------------------------

## A shape turned on a lathe: profile is (how far out, how high) from the bottom up
func _turned(profile: Array, sides := 20) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in sides:
		var a := k * TAU / sides
		var b := (k + 1) * TAU / sides
		for p in profile.size() - 1:
			var p0: Vector2 = profile[p]
			var p1: Vector2 = profile[p + 1]
			var a0 := Vector3(cos(a) * p0.x, p0.y, sin(a) * p0.x)
			var b0 := Vector3(cos(b) * p0.x, p0.y, sin(b) * p0.x)
			var a1 := Vector3(cos(a) * p1.x, p1.y, sin(a) * p1.x)
			var b1 := Vector3(cos(b) * p1.x, p1.y, sin(b) * p1.x)
			var centre := Vector3(0.0, (p0.y + p1.y) * 0.5, 0.0)
			# (smooth round it, creased where the profile turns)
			tool.set_smooth_group(p)
			_quad(tool, centre, a0, b0, b1, a1)
	tool.generate_normals()
	return tool.commit()


func _build_towers() -> void:
	# (how far out, how high), as fractions of each tower's girth and height
	var shapes := [
		# The needle: a swelling foot, a long taper, a collar, a bulb, a point
		[Vector2(1.0, 0.0), Vector2(1.25, 0.06), Vector2(0.8, 0.14), Vector2(0.55, 0.5), Vector2(0.9, 0.53), Vector2(0.9, 0.56), Vector2(0.45, 0.6), Vector2(0.38, 0.78), Vector2(0.7, 0.84), Vector2(0.5, 0.9), Vector2(0.0, 1.0)],
		# The mushroom: a stem, a wide cap with a lip, a dome on it
		[Vector2(0.7, 0.0), Vector2(0.45, 0.2), Vector2(0.4, 0.68), Vector2(1.6, 0.76), Vector2(1.7, 0.8), Vector2(1.2, 0.84), Vector2(0.9, 0.93), Vector2(0.0, 1.0)],
		# The hive: stepped rings narrowing, each with an overhang
		[Vector2(1.3, 0.0), Vector2(1.3, 0.18), Vector2(1.45, 0.2), Vector2(1.0, 0.22), Vector2(1.0, 0.42), Vector2(1.15, 0.44), Vector2(0.75, 0.46), Vector2(0.75, 0.66), Vector2(0.9, 0.68), Vector2(0.5, 0.7), Vector2(0.4, 0.9), Vector2(0.0, 1.0)],
		# The urn: narrow foot, great belly, narrow neck, a flared mouth
		[Vector2(0.5, 0.0), Vector2(0.6, 0.1), Vector2(1.3, 0.32), Vector2(1.35, 0.45), Vector2(0.6, 0.7), Vector2(0.5, 0.86), Vector2(1.0, 0.95), Vector2(0.9, 1.0), Vector2(0.0, 1.0)],
	]
	var meshes: Array[ArrayMesh] = []
	for shape in shapes:
		meshes.append(_turned(shape))
	var finial := Crystal.shard(0.5, 1.0, 0.3)
	for k in 13:
		var angle: float = k * TAU / 13.0 + _rng.randf_range(-0.12, 0.12)
		var away := _rng.randf_range(150.0, 250.0)
		var tall := _rng.randf_range(70.0, 190.0)
		var girth := _rng.randf_range(9.0, 20.0)
		var tower := MeshInstance3D.new()
		tower.mesh = meshes[k % meshes.size()]
		tower.position = Vector3(cos(angle) * away, -4.0, sin(angle) * away)
		tower.scale = Vector3(girth, tall, girth)
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/tower.gdshader")
		material.set_shader_parameter("band_a", Crystal.COLORS[k % Crystal.COLORS.size()])
		material.set_shader_parameter("band_b", Crystal.COLORS[(k * 3 + 2) % Crystal.COLORS.size()])
		material.set_shader_parameter("seed", float(k) * 3.7)
		material.set_shader_parameter("tall", tall)
		tower.material_override = material
		tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tower)
		# A crystal on its point
		var top := MeshInstance3D.new()
		top.mesh = finial
		top.position = tower.position + Vector3.UP * (tall + girth * 0.5)
		top.scale = Vector3(girth * 0.5, girth * 1.6, girth * 0.5)
		var crystal := ShaderMaterial.new()
		crystal.shader = preload("res://shaders/crystal.gdshader")
		crystal.set_shader_parameter("horizon", Crystal.COLORS[(k * 2 + 1) % Crystal.COLORS.size()])
		top.material_override = crystal
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(top)


# --- The saucers ----------------------------------------------------------------------------

func _build_saucers() -> void:
	var hull := _turned([Vector2(0.0, -0.1), Vector2(0.45, -0.12), Vector2(1.0, 0.0), Vector2(0.95, 0.03), Vector2(0.4, 0.1), Vector2(0.3, 0.2), Vector2(0.0, 0.24)], 28)
	var light := _turned([Vector2(0.0, -0.105), Vector2(0.43, -0.125), Vector2(0.0, -0.13)], 28)
	for k in 3:
		var angle := k * TAU / 3.0 + 0.6
		var saucer := Node3D.new()
		var home := Vector3(cos(angle) * 60.0, 70.0 + k * 14.0, sin(angle) * 60.0)
		saucer.set_meta("home", home)
		saucer.position = home
		saucer.scale = Vector3.ONE * (16.0 + k * 5.0)
		var body := MeshInstance3D.new()
		body.mesh = hull
		body.material_override = _iron
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		saucer.add_child(body)
		var under := MeshInstance3D.new()
		under.mesh = light
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Crystal.COLORS[(k * 2) % Crystal.COLORS.size()].lerp(Color.WHITE, 0.4)
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		under.material_override = glow
		under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		saucer.add_child(under)
		add_child(saucer)
		_saucers.append(saucer)
