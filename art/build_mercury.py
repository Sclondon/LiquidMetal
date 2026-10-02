# Builds Mercury (after mercury.png) in Blender and exports it for the game.
#   blender -b --factory-startup --python art/build_mercury.py
# Writes art/mercury.blend (to open and tweak by hand) and models/mercury.glb (what Godot loads).
#
# Every body part is its own floating shard with its pivot at its joint: a sharp mask for a
# head with the spikes growing out of it (three horns, the middle one biggest), chest, pelvis,
# shoulder spikes, blade arms, and long two-piece legs (a big thigh blade, then a shin blade to
# a point, with a guard rising above the knee). Faces +Y in Blender (= -Z in Godot).
#
# Animations (NLA tracks; each becomes one glTF animation across all the parts):
#   run  - 24 frames at 30 fps, looping: a skating stride (push out to the side, glide), body
#          banking over the gliding leg, leaning forward, arms swept back ninja-run style
#   jump - snaps from the push-off into a leap (knees tucked, arms swept back) and holds it

import math
import os

import bmesh
import bpy

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
root = empty("Mercury", (0, 0, 0))
hips = empty("hips", (0, 0, HIP_Z), root)

bm = bmesh.new()
add_shard(bm, [(0.0, 0.26, 0.17)], top=0.1, bottom=-0.15)
pelvis = mesh_object("pelvis", bm, (0, 0, 0), hips)

# Chest: a kite, a point at the waist, widest across the shoulders
bm = bmesh.new()
add_shard(bm, [(0.42, 0.52, 0.26), (0.5, 0.34, 0.18)], top=None, bottom=0.0)
chest = mesh_object("chest", bm, (0, 0, 0.17), hips)

# Head: a sharp mask (pointed brow, cheekbones, a chin to a point) with a small skull behind
# it, and the spikes growing out of the mask: three horns off the brow, the middle one
# biggest, and a short point off each brow corner
bm = bmesh.new()
mask_outline = [
    (0.0, 0.25), (-0.09, 0.17), (-0.23, 0.23), (-0.19, 0.06), (-0.15, -0.04), (-0.06, -0.14), (0.0, -0.23),
    (0.06, -0.14), (0.15, -0.04), (0.19, 0.06), (0.23, 0.23), (0.09, 0.17),
]
add_mask(bm, mask_outline, rim=0.03, front=(0, 0.13, 0.04), back=(0, -0.03, 0.04))
add_shard(bm, [(0.04, 0.2, 0.17)], top=0.17, bottom=-0.1, offset=(0, -0.08, 0))
add_spike(bm, (0, 0.0, 0.2), (0, -0.07, 0.8), 0.06)
for s in (-1, 1):
    add_spike(bm, (s * 0.12, 0.0, 0.18), (s * 0.34, -0.06, 0.55), 0.045)
    add_spike(bm, (s * 0.21, 0.0, 0.2), (s * 0.4, -0.05, 0.3), 0.03)
head = mesh_object("head", bm, (0, 0, 0.7), chest)
for s in (-1, 1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.1, 0.02, 0.026), verts=bm.verts)
    eye = mesh_object(f"eye_{'L' if s < 0 else 'R'}", bm, (s * 0.062, 0.085, 0.07), head, EYE)
    eye.rotation_euler = (0, s * 0.45, -s * 0.5)  # slanted into a V, lying along the mask

# Spikes off the back of the shoulders
for s in (-1, 1):
    bm = bmesh.new()
    add_spike(bm, (0, 0, 0), (s * 0.24, -0.14, 0.34), 0.055)
    mesh_object(f"shoulder_{'L' if s < 0 else 'R'}", bm, (s * 0.28, -0.04, 0.47), chest)

# Arms: a long blade each, from just off the shoulder (posed swept back, ninja-run style)
arms = {}
for s, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    add_shard(bm, [(-0.2, 0.17, 0.1), (-0.04, 0.07, 0.06)], top=None, bottom=-0.86)
    arm = mesh_object(f"arm_{tag}", bm, (s * 0.34, 0, 0.44), chest)
    arms[tag] = (arm, s)

# Legs: a big thigh blade, a gap for the knee, then a shin blade to a point. A guard on the
# front of each shin rises up past the knee.
legs = {}
for s, tag in ((-1, "L"), (1, "R")):
    bm = bmesh.new()
    add_shard(bm, [(-0.56, 0.15, 0.13), (-0.15, 0.42, 0.22), (0.0, 0.17, 0.13)], top=None, bottom=-(THIGH - 0.06))
    thigh = mesh_object(f"thigh_{tag}", bm, (s * 0.14, 0, -0.06), hips)
    bm = bmesh.new()
    add_shard(bm, [(-0.17, 0.3, 0.16), (0.0, 0.13, 0.11)], top=None, bottom=-SHIN)
    add_shard(bm, [(-0.02, 0.28, 0.1)], top=0.36, bottom=-0.26, offset=(0, 0.11, 0))  # knee guard
    shin = mesh_object(f"shin_{tag}", bm, (0, 0, -THIGH), thigh)
    legs[tag] = (thigh, shin)

for obj in scene.objects:
    obj.rotation_mode = "XYZ"

# --- Animation ---------------------------------------------------------------------------

REST = {obj.name: (obj.location.copy(), obj.rotation_euler.copy()) for obj in scene.objects}
deg = math.radians
RUN_FRAMES = 24  # one push with each leg


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


def ninja_arms(frame, sway=0.0, rx=-74):
    # Swept straight back, a little out, trailing behind like a ninja run
    for tag, (arm, s) in arms.items():
        key(arm, frame, rx=rx + sway * s, ry=s * 14)


def run_keys():
    # Skating: one leg glides under the body, knee bent, while the other pushes out to the
    # side and back, snaps straight, then lifts, folds and swings back in to glide.
    # (swing forward, out to the side, knee bend) every 6 frames for the left leg; the right is
    # half a cycle behind, mirrored.
    stride = [
        (14, 0, -38),  # frame 0: gliding under the body
        (-14, 24, -20),  # 6: pushing out and back
        (-34, 38, -2),  # 12: push snapped straight
        (-6, 12, -80),  # 18: lifted, knee folded, swinging back in
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
    for frame, shift_x, bank, bob in ((0, -0.1, -9, 0.0), (6, -0.05, -5, -0.06), (10, 0.02, 2, 0.03),
                                      (12, 0.1, 9, 0.0), (18, 0.05, 5, -0.06), (22, -0.02, -2, 0.03), (24, -0.1, -9, 0.0)):
        key(hips, frame, ry=bank, x=shift_x, z=bob - 0.08)
        key(chest, frame, rx=-32, rz=-bank * 1.2)
        key(head, frame, rx=36, ry=-bank * 0.6)  # head up against the lean, eyes on the track
        ninja_arms(frame, sway=bank * 0.6)


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
    ninja_arms(0, rx=-60)
    for frame in (5, 8):
        key(hips, frame, rx=-12, z=0.05)
        key(chest, frame, rx=-30)
        key(head, frame, rx=26)
        key(thigh_l, frame, rx=88, ry=8)
        key(shin_l, frame, rx=-125)
        key(thigh_r, frame, rx=50, ry=-10)
        key(shin_r, frame, rx=-115)
        ninja_arms(frame, rx=-88)


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


bake("run", run_keys, "SINE")  # smooth, gliding
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
