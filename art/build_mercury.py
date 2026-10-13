# Builds Mercury (after mercury.png) in Blender and exports it for the game.
#   blender -b --factory-startup --python art/build_mercury.py
# Writes art/mercury.blend (to open and tweak by hand) and models/mercury.glb (what Godot loads).
#
# Every body part is its own floating shard with its pivot at its joint: a teardrop head (a
# round bulb for the face, drawn up and back into a short raked point, with two spikes growing out of
# it up and out in a V, all one smooth piece of armour, like a helmet; the eye a glowing V-shaped
# slit across its face), a plain kite of a chest sunk right down onto the legs, thick blade arms
# floating off the shoulders under little shoulder pads, and long two-piece legs set wide (a big
# thigh blade, then a shin blade to a point, with a guard over it from above the knee, much wider
# there, down to the toe). Faces +Y in Blender (= -Z in Godot).
#
# Animations (NLA tracks; each becomes one glTF animation across all the parts):
#   run  - 36 frames at 30 fps, looping: long, flowing strides, each a deep lunge, body
#          banking over the front leg, leaning forward, arms trailing back ninja-run style
#   land_R / land_L - the superhero landing on either hand, held, then the arm thrown back and a
#          step out into the run
#   slide - drops into a slide (lead leg out, the other folded under, leaning back) and holds it
#   jump - snaps from the push-off into a leap (knees tucked, arms swept back) and holds it
#   idle - 72 frames, looping: standing still, tall and loose, knees soft, the arms hanging a
#          little out from the sides, breathing (the chest rising, the arms floating up and down)
#          and swaying a touch from foot to foot
#   tpose - the rest pose for looking it over: standing straight, arms straight out to the sides

import math
import os

import bmesh
import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FPS = 30

# --- Scene -------------------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS


def material(name, color, metallic, roughness, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    return mat


METAL = material("Metal", (0.8, 0.82, 0.86), 1.0, 0.08)
EYE = material("Eye", (1.0, 0.08, 0.06), 0.0, 0.5, emission=(1.0, 0.08, 0.06))


def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.1
    obj.location = location
    obj.parent = parent
    scene.collection.objects.link(obj)
    return obj


def mesh_object(name, bm, location, parent, mat=METAL, smooth=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if smooth is not None:  # (None: each face as the bmesh had it)
        for poly in mesh.polygons:
            poly.use_smooth = smooth  # faceted (every face catching its own light), or smooth
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    obj.parent = parent
    scene.collection.objects.link(obj)
    return obj


# --- Shapes ------------------------------------------------------------------------------

def add_shard(bm, rings, top=None, bottom=None, offset=(0.0, 0.0, 0.0)):
    """A faceted shard along Z. rings: (z, width across X, thickness across Y), bottom to
    top, each a diamond. top / bottom: z of a point to close that end to (None: flat cap)."""
    ox, oy, oz = offset
    loops = []
    for z, w, t in rings:
        loops.append([
            bm.verts.new((ox + w / 2, oy, oz + z)),
            bm.verts.new((ox, oy + t / 2, oz + z)),
            bm.verts.new((ox - w / 2, oy, oz + z)),
            bm.verts.new((ox, oy - t / 2, oz + z)),
        ])
    for a, b in zip(loops, loops[1:]):
        for k in range(4):
            n = (k + 1) % 4
            bm.faces.new((a[k], a[n], b[n], b[k]))
    for end, loop in ((bottom, loops[0]), (top, loops[-1])):
        if end is None:
            bm.faces.new(loop)
        else:
            tip = bm.verts.new((ox, oy, oz + end))
            for k in range(4):
                bm.faces.new((loop[k], loop[(k + 1) % 4], tip))


def add_armor(bm, rings, top=None, bottom=None, offset=(0.0, 0.0, 0.0), chamfer=0.22):
    """Like add_shard, but each ring's diamond has its corners cut off (chamfer: how far along each
    edge), so it has eight facets round instead of four: armour plate rather than a crystal.
    Two rings close together with different sizes make a stepped lip, where one plate overlaps
    the next."""
    ox, oy, oz = offset
    loops = []
    for z, w, t in rings:
        corners = [(w / 2, 0.0), (0.0, t / 2), (-w / 2, 0.0), (0.0, -t / 2)]
        loop = []
        for k in range(4):
            (ax, ay), (bx, by) = corners[k], corners[(k + 1) % 4]
            for f in (chamfer, 1.0 - chamfer):
                loop.append(bm.verts.new((ox + ax + (bx - ax) * f, oy + ay + (by - ay) * f, oz + z)))
        loops.append(loop)
    sides = len(loops[0])
    for a, b in zip(loops, loops[1:]):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((a[k], a[n], b[n], b[k]))
    for end, loop in ((bottom, loops[0]), (top, loops[-1])):
        if end is None:
            bm.faces.new(loop)
        else:
            tip = bm.verts.new((ox, oy, oz + end))
            for k in range(sides):
                bm.faces.new((loop[k], loop[(k + 1) % sides], tip))


def add_blade(bm, root, tip, width, thickness, widest=0.3):
    """A flat faceted blade from root to tip: a diamond cross-section (width across, thickness
    through Y), widest a fraction of the way along, closing to points at both ends."""
    from mathutils import Vector

    root = Vector(root)
    tip = Vector(tip)
    along = (tip - root).normalized()
    across = along.cross(Vector((0, 1, 0))).normalized()
    through = across.cross(along).normalized()
    mid = root + (tip - root) * widest
    ring = [bm.verts.new(mid + d) for d in (across * width / 2, through * thickness / 2, -across * width / 2, -through * thickness / 2)]
    ends = [bm.verts.new(root), bm.verts.new(tip)]
    faces = []
    for k in range(4):
        n = (k + 1) % 4
        faces.append(bm.faces.new((ring[k], ring[n], ends[1])))
        faces.append(bm.faces.new((ring[n], ring[k], ends[0])))
    for face in faces:
        face.smooth = False
    return faces


def add_spike(bm, base, tip, radius):
    """A four-sided spike from base to tip."""
    from mathutils import Vector

    base = Vector(base)
    tip = Vector(tip)
    axis = (tip - base).normalized()
    side = axis.cross(Vector((0, 1, 0)))
    if side.length < 1e-4:
        side = axis.cross(Vector((1, 0, 0)))
    side.normalize()
    other = axis.cross(side).normalized()
    ring = [bm.verts.new(base + d * radius) for d in (side, other, -side, -other)]
    point = bm.verts.new(tip)
    for k in range(4):
        bm.faces.new((ring[k], ring[(k + 1) % 4], point))
    bm.faces.new(ring)


# --- The figure --------------------------------------------------------------------------

def add_lathe(bm, rings, top, bottom, sides=8):
    """A faceted round shape along Z: rings of (z, radius), bottom to top, closed to points at
    z = bottom and z = top."""
    loops = []
    for z, radius in rings:
        loops.append([bm.verts.new((radius * math.cos(2 * math.pi * k / sides), radius * math.sin(2 * math.pi * k / sides), z)) for k in range(sides)])
    for a, b in zip(loops, loops[1:]):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((a[k], a[n], b[n], b[k]))
    for end, loop in ((bottom, loops[0]), (top, loops[-1])):
        tip = bm.verts.new((0, 0, end))
        for k in range(sides):
            bm.faces.new((loop[k], loop[(k + 1) % sides], tip))


def add_mask(bm, outline, rim, front, back):
    """A faceted mask: an outline in the XZ plane (at y = rim) fanned to a point in front
    (the ridge down the face) and one behind, so every edge is sharp."""
    ring = [bm.verts.new((x, rim, z)) for x, z in outline]
    tip_front = bm.verts.new(front)
    tip_back = bm.verts.new(back)
    for k in range(len(ring)):
        n = (k + 1) % len(ring)
        bm.faces.new((ring[k], ring[n], tip_front))
        bm.faces.new((ring[n], ring[k], tip_back))


THIGH = 0.74  # hip to knee
SHIN = 0.84  # knee to the point of the foot
HIP_Z = THIGH + SHIN
KNEE_BALL = 0.1  # the knee's ball joint's radius
root = empty("Mercury", (0, 0, 0))
hips = empty("hips", (0, 0, HIP_Z), root)

# Chest: a kite of armour plates, a point at the waist and a point at the neck: stacked bands up
# the stomach (each lipped over the one below), broad across the chest, a ridge down the middle
# and a plate over each side of the chest
bm = bmesh.new()
add_armor(bm, [(0.05, 0.14, 0.1), (0.13, 0.26, 0.16), (0.14, 0.3, 0.19), (0.23, 0.38, 0.21), (0.24, 0.43, 0.24),
               (0.36, 0.52, 0.27), (0.45, 0.45, 0.25)], top=0.56, bottom=0.0)
add_blade(bm, (0, 0.11, 0.06), (0, 0.11, 0.52), width=0.035, thickness=0.07, widest=0.6)  # the ridge down the front
for s in (-1, 1):
    add_armor(bm, [(0.28, 0.17, 0.05), (0.42, 0.2, 0.06)], top=0.48, bottom=0.25, offset=(s * 0.12, 0.105, 0))  # chest plates
chest = mesh_object("chest", bm, (0, 0, -0.1), hips)  # (sunk right down: its point between the thighs, nearly touching them)

# Head: a helmet. A teardrop (a round bulb for the face, drawn up and back into a short point,
# raked back), with two spikes grown out of its own surface, up and out into a V, half as long as
# the teardrop; all one smooth piece (finely divided, smooth shaded), and a size up on the rest of
# him. The eye is a V-shaped slit across the face, glowing.
HEAD_SCALE = 1.35
HEAD_BOTTOM, HEAD_TOP, BULB = -0.15, 0.55, 0.17
HEAD_RAKE = math.radians(36)  # tipped well back
head_rings = []
for i in range(1, 24):
    z = HEAD_BOTTOM + (HEAD_TOP - HEAD_BOTTOM) * (1 - math.cos(math.pi * i / 24)) / 2  # (closer together at the ends)
    if z < 0.02:  # the bulb: round, centred just above its middle
        r = BULB * math.sqrt(max(0.0, 1 - ((z - 0.02) / BULB) ** 2))
    else:  # drawn out into the point
        r = BULB * (1 - ((z - 0.02) / (HEAD_TOP - 0.02)) ** 0.7)
    head_rings.append((z, r))
bm = bmesh.new()
add_lathe(bm, head_rings, top=HEAD_TOP, bottom=HEAD_BOTTOM, sides=32)
for face in bm.faces:
    face.smooth = True
k = HEAD_SCALE
bmesh.ops.scale(bm, vec=(k,) * 3, verts=bm.verts)
# Worked out in the teardrop's own space (before the rake): which way the face looks once it's
# raked back (level, straight ahead), and its up and right
from mathutils import Vector
face_fwd = Vector((0, math.cos(HEAD_RAKE), -math.sin(HEAD_RAKE)))
face_up = Vector((0, math.sin(HEAD_RAKE), math.cos(HEAD_RAKE)))
face_right = Vector((1, 0, 0))
bulb_centre = Vector((0, 0, 0.02 * k))
bulb_r = BULB * k


def on_bulb(u, v, off=0.0):
    """The point on the face's bulb u across and v up from the middle of the face (off: out from it)."""
    d = (face_fwd + face_right * (u / bulb_r) + face_up * (v / bulb_r)).normalized()
    return bulb_centre + d * (bulb_r + off)


# The spikes: a square patch of the bulb's upper sides (4 x 4 of its faces, round the vertex nearest
# the spot) pulled out up and away, in steps, narrowing to a point (so each grows smoothly out of
# the surface: one piece with it)
SPIKE_LENGTH = 0.5 * (HEAD_TOP - HEAD_BOTTOM) * k
SPIKE_STEPS = 8
for s in (-1, 1):
    root = on_bulb(s * 0.12 * k, 0.1 * k)
    out = (face_right * s * 0.85 + face_up * 0.75 - face_fwd * 0.2).normalized()
    bm.verts.ensure_lookup_table()
    centre_vert = min(bm.verts, key=lambda v: (v.co - root).length)
    inner = {f for f in centre_vert.link_faces}
    region = list({f for f in inner for v in f.verts for f in v.link_faces})
    size = 1.0
    for step in range(1, SPIKE_STEPS + 1):
        made = bmesh.ops.extrude_face_region(bm, geom=region)
        bmesh.ops.delete(bm, geom=region, context="FACES_ONLY")  # (the faces it grew from: left inside, they'd crease it)
        verts = [e for e in made["geom"] if isinstance(e, bmesh.types.BMVert)]
        region = [e for e in made["geom"] if isinstance(e, bmesh.types.BMFace)]
        bmesh.ops.translate(bm, vec=out * (SPIKE_LENGTH / SPIKE_STEPS), verts=verts)
        want = (1.0 - step / SPIKE_STEPS) ** 0.85  # how wide it is here, of its base
        centre = sum((v.co for v in verts), Vector()) / len(verts)
        bmesh.ops.scale(bm, vec=(want / size,) * 3, space=Matrix.Translation(-centre), verts=verts)
        size = max(want, 1e-3)
    bmesh.ops.pointmerge(bm, verts=verts, merge_co=sum((v.co for v in verts), Vector()) / len(verts))
for face in bm.faces:
    face.smooth = True
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
rake = Matrix.Rotation(HEAD_RAKE, 3, "X")
bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rake)
head = mesh_object("head", bm, (0, 0, 0.7), chest, smooth=None)

# The eye: one V-shaped slit across the face, glowing, set into the helmet (a thin band laid on the
# bulb's curve, sunk a little into it)
bm = bmesh.new()
SLIT_WIDE, SLIT_LOW, SLIT_HIGH, SLIT_BAND = 0.15 * k, -0.045 * k, 0.06 * k, 0.042 * k
for s in (-1, 1):
    rows = []
    for i in range(9):
        t = i / 8
        u, v = s * SLIT_WIDE * t, SLIT_LOW + (SLIT_HIGH - SLIT_LOW) * t
        band = SLIT_BAND * (1.0 - 0.5 * t)  # (tapering out to the tips)
        rows.append([bm.verts.new(on_bulb(u, v + dv, off)) for dv, off in ((band / 2, 0.006 * k), (-band / 2, 0.006 * k), (-band / 2, -0.015 * k), (band / 2, -0.015 * k))])
    for a, b in zip(rows, rows[1:]):
        for q in range(4):
            n = (q + 1) % 4
            bm.faces.new((a[q], a[n], b[n], b[q]))
    for end in (rows[0], rows[-1]):
        bm.faces.new(end)
bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rake)
mesh_object("eye_V", bm, (0, 0, 0), head, EYE)

# Arms: a thick blade each, floating free a little way off the shoulder (posed trailing
# back, ninja-run style, and bobbing on their own as he moves)
arms = {}
for s, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    add_shard(bm, [(-0.3, 0.38, 0.24), (-0.05, 0.17, 0.14)], top=None, bottom=-1.08)
    arm = mesh_object(f"arm_{tag}", bm, (s * 0.46, 0, 0.42), chest)
    arms[tag] = (arm, s)
    # A little shoulder pad capping the top of the arm (it goes where the arm goes)
    bm = bmesh.new()
    # (layered: a domed top plate over a lower one hanging out a little, a small fin along the top)
    add_armor(bm, [(-0.07, 0.37, 0.33), (0.04, 0.34, 0.3), (0.1, 0.24, 0.22)], top=0.15, bottom=-0.12, offset=(s * 0.03, 0, 0), chamfer=0.26)
    add_armor(bm, [(-0.22, 0.3, 0.27), (-0.13, 0.36, 0.31)], top=-0.07, bottom=-0.25, offset=(s * 0.07, 0, 0), chamfer=0.26)
    add_blade(bm, (s * -0.02, 0, 0.12), (s * 0.2, 0, 0.17), width=0.07, thickness=0.03, widest=0.35)
    mesh_object(f"pad_{tag}", bm, (0, 0, 0), arm)

# Legs: a big thigh blade, a gap for the knee, then a shin blade to a point. A guard on the
# front of each shin rises up past the knee.
legs = {}
for s, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    # (plated: chamfered, a lip where the hip plate overlaps it, a ridge down the front)
    add_armor(bm, [(-0.6, 0.13, 0.11), (-0.42, 0.27, 0.17), (-0.17, 0.42, 0.22), (-0.13, 0.37, 0.2), (-0.11, 0.4, 0.22),
                   (0.0, 0.19, 0.13)], top=None, bottom=-(THIGH - 0.06))
    add_blade(bm, (0, 0.085, -0.04), (0, 0.075, -(THIGH - 0.12)), width=0.03, thickness=0.06, widest=0.3)
    thigh = mesh_object(f"thigh_{tag}", bm, (s * 0.19, 0, -0.06), hips)  # (set wide)
    bm = bmesh.new()
    add_armor(bm, [(-0.55, 0.15, 0.1), (-0.17, 0.3, 0.16), (-0.06, 0.22, 0.13), (0.0, 0.14, 0.11)], top=None, bottom=-SHIN)
    add_armor(bm, [(-0.52, 0.12, 0.06), (-0.2, 0.22, 0.09)], top=-0.06, bottom=-0.66, offset=(0, -0.07, 0))  # calf plate
    # The knee: a smooth ball joint at the top of the shin (the guard covers its front)
    knee = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=KNEE_BALL)
    for face in {f for v in knee["verts"] for f in v.link_faces}:
        face.smooth = True
    # The guard down its front: from well up the thigh, widest over the knee, tapering all the way
    # down to the toe (and closing in onto the shin as it goes, meeting its point)
    shin_verts = set(bm.verts)
    add_shard(bm, [(-(SHIN - 0.1), 0.08, 0.05), (-0.42, 0.26, 0.09), (-0.02, 0.54, 0.15)], top=0.45, bottom=-(SHIN - 0.01), offset=(0, 0.12, 0))
    for v in bm.verts:
        if v not in shin_verts and v.co.z < 0.0:
            v.co.y -= 0.1 * (-v.co.z / SHIN)
    shin = mesh_object(f"shin_{tag}", bm, (0, 0, -THIGH), thigh, smooth=None)
    legs[tag] = (thigh, shin)

for obj in scene.objects:
    obj.rotation_mode = "XYZ"

# --- Animation ---------------------------------------------------------------------------

REST = {obj.name: (obj.location.copy(), obj.rotation_euler.copy()) for obj in scene.objects}
deg = math.radians
RUN_FRAMES = 36  # one long push with each leg
IDLE_FRAMES = 72  # one slow breath, in and out


def key(obj, frame, rx=None, ry=None, rz=None, x=None, z=None):
    """Key an object's pose at a frame (angles in degrees, offsets in metres from rest);
    anything not given stays at rest. ry tilts a limb out to the side."""
    location, rotation = REST[obj.name]
    obj.location = location.copy()
    obj.rotation_euler = rotation.copy()
    if rx is not None:
        obj.rotation_euler.x = deg(rx)
    if ry is not None:
        obj.rotation_euler.y = deg(ry)
    if rz is not None:
        obj.rotation_euler.z = deg(rz)
    if x is not None:
        obj.location.x = location.x + x
    if z is not None:
        obj.location.z = location.z + z
    obj.keyframe_insert("location", frame=frame)
    obj.keyframe_insert("rotation_euler", frame=frame)


def ninja_arms(frame, sway=0.0, rx=8, bob=0.0):
    # Out to the sides, trailing back only a little (rx is on top of the chest's forward lean,
    # which already tips them back, so it's near zero); bob lifts them, floating
    for tag, (arm, s) in arms.items():
        key(arm, frame, rx=rx + sway * s, ry=-s * 30, z=bob)  # -s: out, away from the body


def run_keys():
    # Lunging: every stride drops into a deep lunge (front thigh driven forward nearly level, knee
    # bent deep, the back leg straight out behind), rises, and the back leg whips through to
    # lunge next. A little push out to the side from skating is left in.
    # (swing forward, out to the side, knee bend) every 6 frames for the left leg; the right is
    # half a cycle behind, mirrored.
    stride = [
        (76, 4, -86),  # the lunge: thigh driven forward nearly level, knee deep, shin planted
        (22, 14, -42),  # rising off it, pushing back and a little out
        (-52, 20, -4),  # straight out far behind (the other leg's lunge)
        (-8, 10, -112),  # whipped through, knee folded high
    ]
    step = RUN_FRAMES // len(stride)
    for tag, side, shift in (("L", -1, 0), ("R", 1, len(stride) // 2)):
        thigh, shin = legs[tag]
        for i in range(len(stride) + 1):  # the last key repeats the first: a clean loop
            swing, out, knee = stride[(i + shift) % len(stride)]
            key(thigh, i * step, rx=swing, ry=-side * out)  # out to the side, away from the body
            key(shin, i * step, rx=knee)
    # The body rides over whichever leg is gliding: shifts and banks onto it, dips as the push
    # starts, rises as it snaps straight. The upper body leans well forward throughout (the
    # chest leans, not the hips, so the legs stay under it).
    # Hips sink deep into each lunge (the front thigh level, the back leg straight) and rise
    # between them
    for frame24, shift_x, bank, bob in ((0, -0.12, -12, -0.55), (6, 0.0, 0, -0.1), (12, 0.12, 12, -0.55),
                                      (18, 0.0, 0, -0.1), (24, -0.12, -12, -0.55)):
        frame = round(frame24 * RUN_FRAMES / 24)  # laid out on a 24-frame cycle
        # A speed skater's crouch: hips sunk low, chest folded right down over the legs, head
        # tipped well back to keep looking down the track
        key(hips, frame, ry=bank, x=shift_x, z=bob - 0.34)  # sitting low
        key(chest, frame, rx=-58, rz=-bank * 1.2)
        key(head, frame, rx=84, ry=-bank * 0.6)
    # The arms float on their own: bobbing once per push, a beat behind the body, swaying a little
    for frame in range(0, RUN_FRAMES + 1, 3):
        phase = 2 * math.pi * frame / RUN_FRAMES
        ninja_arms(frame, sway=-16 * math.cos(phase) * 0.6, rx=8 + 7 * math.sin(phase * 2 + 0.6), bob=0.07 * math.sin(phase * 2 - 1.2))


def jump_keys():
    thigh_l, shin_l = legs["L"]
    thigh_r, shin_r = legs["R"]
    # Frame 0: the push off the ground, legs long. By frame 5 it has snapped into the leap
    # (both knees tucked, one higher) and holds it; arms stay swept back.
    key(hips, 0, z=-0.06)
    key(chest, 0, rx=-26)
    key(head, 0, rx=16)
    key(thigh_l, 0, rx=20, ry=4)
    key(shin_l, 0, rx=-15)
    key(thigh_r, 0, rx=-20, ry=-4)
    key(shin_r, 0, rx=-10)
    ninja_arms(0, rx=10)
    for frame in (5, 8):
        key(hips, frame, rx=-12, z=0.05)
        key(chest, frame, rx=-30)
        key(head, frame, rx=26)
        key(thigh_l, frame, rx=88, ry=8)
        key(shin_l, frame, rx=-125)
        key(thigh_r, frame, rx=50, ry=-10)
        key(shin_r, frame, rx=-115)
        ninja_arms(frame, rx=-6)


def slide_keys():
    thigh_l, shin_l = legs["L"]
    thigh_r, shin_r = legs["R"]
    # Dropping into a slide (before melting into a puddle): low, leaning back, the lead leg shot
    # out straight in front, the other folded under, arms out wide for balance
    key(hips, 0, z=-0.2)
    key(chest, 0, rx=-12)
    key(head, 0)
    key(thigh_l, 0, rx=40)
    key(shin_l, 0, rx=-40)
    key(thigh_r, 0, rx=-10)
    key(shin_r, 0, rx=-60)
    ninja_arms(0, rx=-30)
    # Down low: the lead leg out flat along the floor, the other folded right under with its foot
    # down, leaning back, arms flung back with the hands trailing on the floor behind
    for frame in (5, 8):
        key(hips, frame, rx=18, z=-1.3)
        key(chest, frame, rx=34)  # thrown back
        key(head, frame, rx=30)  # thrown back  # still looking where it's going
        key(thigh_l, frame, rx=78)
        key(shin_l, frame, rx=0)
        key(thigh_r, frame, rx=52, ry=-14)
        key(shin_r, frame, rx=-150)
        ninja_arms(frame, rx=-62)  # arms thrown back, near straight down to the floor, hands on the floor behind


def land_keys(hand):
    # The superhero landing, on either hand ("R" or "L": the other is its mirror image): dropped onto
    # one knee, the other foot planted out in front, one hand flat on the floor, the other arm
    # flung out behind, head down. Slams in and holds (frames 0-12), then throws the down arm
    # back and steps the knee leg through into a lunge (12-22), which is where the run picks up:
    # the right leg's lunge (run frame 18) for the right hand, the left's (frame 0) for the left.
    m = 1 if hand == "R" else -1
    other = "L" if hand == "R" else "R"
    front_thigh, front_shin = legs[other]  # the foot planted ahead
    knee_thigh, knee_shin = legs[hand]  # the knee down on the floor, same side as the hand
    down_arm = arms[hand][0]
    back_arm = arms[other][0]
    for frame, sink in ((0, -1.0), (3, -1.05), (12, -1.0)):
        key(hips, frame, rx=-8, z=sink)
        key(chest, frame, rx=-48)
        key(head, frame, rx=-6)  # head down
        key(front_thigh, frame, rx=80, ry=-6 * m)
        key(front_shin, frame, rx=-100)
        key(knee_thigh, frame, rx=-25, ry=8 * m)
        key(knee_shin, frame, rx=-112)
        key(down_arm, frame, rx=58, ry=-12 * m)  # straight down to the floor
        key(back_arm, frame, rx=-55, ry=-70 * m)  # out behind
    # Up and out: the hand off the floor and thrown right back, the knee leg swinging through
    key(hips, 16, z=-0.6, ry=6 * m)
    key(chest, 16, rx=-40)
    key(head, 16, rx=30)
    key(front_thigh, 16, rx=20, ry=-10 * m)
    key(front_shin, 16, rx=-30)
    key(knee_thigh, 16, rx=35, ry=6 * m)
    key(knee_shin, 16, rx=-100)
    key(down_arm, 16, rx=-85, ry=40 * m)  # flung back
    key(back_arm, 16, rx=-20, ry=-40 * m)
    # ...into the lunge the run carries on from
    key(hips, 22, ry=12 * m, x=0.12 * m, z=-0.89)
    key(chest, 22, rx=-58, rz=-14 * m)
    key(head, 22, rx=84)
    key(knee_thigh, 22, rx=76, ry=4 * m)
    key(knee_shin, 22, rx=-86)
    key(front_thigh, 22, rx=-52, ry=-20 * m)
    key(front_shin, 22, rx=-4)
    for arm, s in arms.values():
        key(arm, 22, rx=8, ry=-s * 30)


def idle_keys():
    # Standing: upright (the chest leans only a little, the head tipped forward off its raked-back
    # rest to look ahead), knees a touch bent, weight shifting slowly from foot to foot; each
    # breath lifts the chest and floats the arms up and out, then lets them down
    for frame in range(0, IDLE_FRAMES + 1, 6):
        phase = 2 * math.pi * frame / IDLE_FRAMES
        breath = math.sin(phase)  # in on the way up
        sway = math.sin(phase + 0.9)
        key(hips, frame, ry=sway * 2.0, x=sway * 0.025, z=-0.05 + breath * 0.012)
        key(chest, frame, rx=-6 + breath * 2.5, rz=-sway * 1.5)
        key(head, frame, rx=-24 + breath * 1.5, rz=sway * 2.0)
        for tag, side in (("L", -1), ("R", 1)):
            thigh, shin = legs[tag]
            lean = sway * side  # (the leg the weight's on bends a little more)
            key(thigh, frame, rx=7 + lean * 1.5, ry=-side * 9)  # (feet set wide)
            key(shin, frame, rx=-12 - lean * 2.0)
        for tag, (arm, s) in arms.items():
            key(arm, frame, rx=6 + breath * 3.0, ry=-s * (14 + breath * 4.0), z=breath * 0.025)


def tpose_keys():
    # The T: legs straight down, a little apart; arms straight out to the sides, level; looking
    # straight ahead. (Two keys a hair apart: the glTF exporter drops an action that doesn't move.)
    for frame, d in ((0, 0.0), (30, 0.4)):
        key(hips, frame, z=d * 0.002)
        key(chest, frame, rx=d)
        key(head, frame, rx=-30 + d)
        for tag, side in (("L", -1), ("R", 1)):
            thigh, shin = legs[tag]
            key(thigh, frame, ry=-side * (9 + d))
            key(shin, frame, rx=-d)
        for tag, (arm, s) in arms.items():
            key(arm, frame, ry=-s * (90 - d))  # -s: out, away from the body


def bake(track_name, keyer, interpolation):
    animated = [o for o in scene.objects if o.type == "MESH" and not o.name.startswith(("eye_", "pad_"))]  # (pads ride on the arms)
    animated.append(hips)
    for obj in animated:
        obj.animation_data_create()
        obj.animation_data.action = bpy.data.actions.new(f"{track_name}_{obj.name}")
    keyer()
    for obj in animated:
        action = obj.animation_data.action
        for curve in action.fcurves:
            for point in curve.keyframe_points:
                # The arms' bob is keyed densely along a wave: smooth between those keys
                point.interpolation = "SINE" if obj.name.startswith("arm_") and track_name == "run" else interpolation
                point.easing = "EASE_IN_OUT"
            if track_name in ("run", "idle"):
                # A loop: cyclic curves, so the smooth (bezier) handles carry on round the seam
                curve.modifiers.new("CYCLES")
                for point in curve.keyframe_points:
                    point.handle_left_type = point.handle_right_type = "AUTO"
                curve.update()
        track = obj.animation_data.nla_tracks.new()
        track.name = track_name
        track.strips.new(track_name, int(action.frame_range[0]), action)
        obj.animation_data.action = None
    # Back to rest between actions
    for obj in scene.objects:
        obj.location, obj.rotation_euler = REST[obj.name][0].copy(), REST[obj.name][1].copy()


bake("run", run_keys, "BEZIER")  # flows on through each pose into the next (no holds)
bake("jump", jump_keys, "QUART")
bake("slide", slide_keys, "QUART")
bake("land_R", lambda: land_keys("R"), "QUART")
bake("land_L", lambda: land_keys("L"), "QUART")
bake("idle", idle_keys, "BEZIER")
bake("tpose", tpose_keys, "LINEAR")

scene.frame_start = 0
scene.frame_end = RUN_FRAMES

# --- Save --------------------------------------------------------------------------------

os.makedirs(os.path.join(ROOT, "models"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "mercury.blend"))
bpy.ops.export_scene.gltf(
    filepath=os.path.join(ROOT, "models", "mercury.glb"),
    export_format="GLB",
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_force_sampling=True,
    export_yup=True,
)
print("MERCURY BUILT")
