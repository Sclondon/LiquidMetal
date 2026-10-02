# Builds Mercury (after mercury.png) in Blender and exports it for the game.
#   blender -b --factory-startup --python art/build_mercury.py
# Writes art/mercury.blend (to open and tweak by hand) and models/mercury.glb (what Godot loads).
#
# Every body part is its own floating shard with its pivot at its joint: head (three horns,
# the middle one biggest), chest, pelvis, shoulder spikes, blade arms, and two-piece legs
# (a big thigh blade, then a shin blade to a point) so the knees can fold for big strides.
# Faces +Y in Blender (= -Z in Godot, the way the runner goes).
#
# Animations (NLA tracks; each becomes one glTF animation across all the parts):
#   run  - 16 frames at 30 fps, looping: big snappy strides, arms pumping against the legs
#   jump - snaps from the push-off into a leap (one knee tucked up, the other leg trailing,
#          arms flung back) and holds it

import math
import os

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FPS = 30
RUN_FRAMES = 16

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


def mesh_object(name, bm, location, parent, mat=METAL):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False  # faceted: every face catches its own light
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

HIP_Z = 1.26
root = empty("Mercury", (0, 0, 0))
hips = empty("hips", (0, 0, HIP_Z), root)

bm = bmesh.new()
add_shard(bm, [(0.0, 0.26, 0.17)], top=0.1, bottom=-0.15)
pelvis = mesh_object("pelvis", bm, (0, 0, 0), hips)

# Chest: a kite, a point at the waist, widest across the shoulders
bm = bmesh.new()
add_shard(bm, [(0.42, 0.52, 0.26), (0.5, 0.34, 0.18)], top=None, bottom=0.0)
chest = mesh_object("chest", bm, (0, 0, 0.17), hips)

# Head: a diamond with three horns, the middle one biggest, swept up
bm = bmesh.new()
add_shard(bm, [(0.06, 0.27, 0.21), (0.16, 0.15, 0.14)], top=None, bottom=-0.11)
add_spike(bm, (0, 0, 0.14), (0, -0.04, 0.72), 0.06)
for s in (-1, 1):
    add_spike(bm, (s * 0.06, 0, 0.12), (s * 0.27, -0.03, 0.43), 0.04)
head = mesh_object("head", bm, (0, 0, 0.67), chest)
for s in (-1, 1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.085, 0.02, 0.022), verts=bm.verts)
    eye = mesh_object(f"eye_{'L' if s < 0 else 'R'}", bm, (s * 0.045, 0.1, 0.075), head, EYE)
    eye.rotation_euler = (0, s * 0.45, -s * 0.35)  # angled into a V

# Spikes off the back of the shoulders
for s in (-1, 1):
    bm = bmesh.new()
    add_spike(bm, (0, 0, 0), (s * 0.24, -0.14, 0.34), 0.055)
    mesh_object(f"shoulder_{'L' if s < 0 else 'R'}", bm, (s * 0.28, -0.04, 0.47), chest)

# Arms: a long blade each, hanging from just off the shoulder
ARM_SWEEP = math.radians(32)
arms = {}
for s, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    add_shard(bm, [(-0.2, 0.17, 0.1), (-0.04, 0.07, 0.06)], top=None, bottom=-0.86)
    arm = mesh_object(f"arm_{tag}", bm, (s * 0.34, 0, 0.44), chest)
    arms[tag] = (arm, s)

# Legs: a big thigh blade, a gap for the knee, then a shin blade to a point
legs = {}
for s, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    add_shard(bm, [(-0.42, 0.15, 0.13), (-0.12, 0.42, 0.22), (0.0, 0.17, 0.13)], top=None, bottom=-0.53)
    thigh = mesh_object(f"thigh_{tag}", bm, (s * 0.14, 0, -0.06), hips)
    bm = bmesh.new()
    add_shard(bm, [(-0.15, 0.32, 0.17), (0.0, 0.13, 0.11)], top=None, bottom=-0.62)
    shin = mesh_object(f"shin_{tag}", bm, (0, 0, -0.58), thigh)
    legs[tag] = (thigh, shin)

for obj in scene.objects:
    obj.rotation_mode = "XYZ"

# --- Animation ---------------------------------------------------------------------------

REST = {obj.name: (obj.location.copy(), obj.rotation_euler.copy()) for obj in scene.objects}
deg = math.radians


def arm_rest(side):
    return -side * ARM_SWEEP  # rotating about Y sweeps the blade out from the body


def key(obj, frame, rx=None, rz=None, z=None, ry=None):
    """Key an object's pose at a frame; anything not given stays at rest."""
    location, rotation = REST[obj.name]
    obj.location = location.copy()
    obj.rotation_euler = rotation.copy()
    if rx is not None:
        obj.rotation_euler.x = deg(rx)
    if ry is not None:
        obj.rotation_euler.y = ry
    if rz is not None:
        obj.rotation_euler.z = deg(rz)
    if z is not None:
        obj.location.z = location.z + z
    obj.keyframe_insert("location", frame=frame)
    obj.keyframe_insert("rotation_euler", frame=frame)


def run_keys():
    half = RUN_FRAMES // 2
    # One leg's stride, a pose every 4 frames: reach forward, plant, drive back, then fold the
    # knee high and whip it through. The right leg is half a cycle behind.
    stride = [(68, -12), (22, -6), (-52, -28), (8, -125)]
    for tag, shift in (("L", 0), ("R", 2)):
        thigh, shin = legs[tag]
        for i in range(5):
            hip, knee = stride[(i + shift) % 4]
            key(thigh, i * 4, rx=hip)
            key(shin, i * 4, rx=knee)
    # Arms pump against the legs: back as that side's leg reaches, forward and up as it drives
    for tag, (arm, s) in arms.items():
        swings = (-58, 70) if tag == "L" else (70, -58)
        for i, frame in enumerate((0, half, RUN_FRAMES)):
            key(arm, frame, rx=swings[i % 2], ry=arm_rest(s))
    # The body drops on each footfall and springs up off it, leaning in, hips swinging with the legs
    for frame, bob, twist in ((0, 0.0, 10), (2, -0.1, 6), (5, 0.07, -2), (8, 0.0, -10), (10, -0.1, -6), (13, 0.07, 2), (16, 0.0, 10)):
        key(hips, frame, rx=-14, rz=twist, z=bob)
        key(chest, frame, rz=-twist * 1.6)
    for frame, nod in ((0, 0), (3, -9), (6, 4), (8, 0), (11, -9), (14, 4), (16, 0)):
        key(head, frame, rx=nod)


def jump_keys():
    thigh_l, shin_l = legs["L"]
    thigh_r, shin_r = legs["R"]
    # Frame 0: the push off the ground, legs long. By frame 5 it has snapped into the leap
    # (one knee driven up, the other leg trailing, arms flung back) and holds it.
    key(hips, 0, rx=-8, z=-0.04)
    key(chest, 0)
    key(head, 0, rx=-6)
    key(thigh_l, 0, rx=25)
    key(shin_l, 0, rx=-15)
    key(thigh_r, 0, rx=-25)
    key(shin_r, 0, rx=-10)
    for tag, (arm, s) in arms.items():
        key(arm, 0, rx=40, ry=arm_rest(s))
    for frame in (5, 8):
        key(hips, frame, rx=-22, z=0.05)
        key(chest, frame, rx=-6)
        key(head, frame, rx=10)
        key(thigh_l, frame, rx=85)
        key(shin_l, frame, rx=-120)
        key(thigh_r, frame, rx=-40)
        key(shin_r, frame, rx=-55)
        for tag, (arm, s) in arms.items():
            key(arm, frame, rx=-75, ry=arm_rest(s) * 1.6)


def bake(track_name, keyer, interpolation):
    animated = [o for o in scene.objects if o.type == "MESH" and not o.name.startswith(("eye_", "shoulder_", "pelvis"))]
    animated.append(hips)
    for obj in animated:
        obj.animation_data_create()
        obj.animation_data.action = bpy.data.actions.new(f"{track_name}_{obj.name}")
    keyer()
    for obj in animated:
        action = obj.animation_data.action
        for curve in action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = interpolation
                point.easing = "EASE_IN_OUT"
        track = obj.animation_data.nla_tracks.new()
        track.name = track_name
        track.strips.new(track_name, int(action.frame_range[0]), action)
        obj.animation_data.action = None
    # Back to rest between actions
    for obj in scene.objects:
        obj.location, obj.rotation_euler = REST[obj.name][0].copy(), REST[obj.name][1].copy()


bake("run", run_keys, "QUART")  # quick moves between held poses: snappy
bake("jump", jump_keys, "QUART")

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
