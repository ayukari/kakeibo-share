# 貯金箱の中身（硬貨・札束）の 3D を作り、アプリで使う画像に描き出す（Blender 5.x）
#   blender --background --factory-startup --python tools/render3d/money_sprites.py -- <出力先> [<出力先2> ...]
# 本物と見まちがえないよう、図柄は描かない。色・金属の質感・形だけ（通貨及証券模造取締法。docs/research-top-apps.md）
# 硬貨は 1 枚、お札も 1 枚ずつ（箱には貯金額どおりの枚数を入れる）。段階ごとに 8 コマ: money_t{段階}_f{コマ}.png。f0 が置いたときの姿で、f1〜f7 は横の軸で 45° ずつ回した姿（落ちながら回る）
import bpy, math, os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bill as billmod   # 作り込んだお札（bill.py）

OUTS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["."]
FRAMES = 8

def srgb(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def reset(world_strength):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.compression = 100
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.85, 0.87, 0.9, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = world_strength
    root = bpy.data.objects.new("root", None); sc.collection.objects.link(root)
    return sc, root

def mat(name, rgb, metal, rough):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m

def add(root, o, m, bevel=None, seg=4):
    o.data.materials.append(m)
    if bevel:
        mod = o.modifiers.new("b", "BEVEL"); mod.width = bevel; mod.segments = seg
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth()
    o.parent = root

def coin(root, r, h, outer, inner=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=r, depth=h)
    add(root, bpy.context.object, outer, h * 0.18)
    for z in (h / 2, -h / 2):   # 両面の縁の盛り上がり
        bpy.ops.mesh.primitive_torus_add(major_radius=r * 0.9, minor_radius=h * 0.12, major_segments=96, minor_segments=12, location=(0, 0, z))
        add(root, bpy.context.object, inner or outer)
    if inner:   # 500円玉: 内側が別の色（2 色）
        bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=r * 0.62, depth=h * 1.04)
        add(root, bpy.context.object, inner, h * 0.1)

def bundle(root, w, d, h, top, band, edge, mark):
    # 札束: 紙を 10 枚、少しずつずらして重ね、まん中に帯。いちばん上に透かしの楕円
    for k in range(10):
        bpy.ops.mesh.primitive_cube_add(size=1, location=((k % 3 - 1) * 0.004, (k % 2) * 0.004, -h / 2 + (k + 0.5) * h / 10))
        o = bpy.context.object; o.scale = (w, d, h / 10 * 0.92)
        add(root, o, top if k in (0, 9) else edge, 0.004, 2)   # 表と裏は札の色、あいだは紙の縁
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    o = bpy.context.object; o.scale = (w * 0.14, d * 1.04, h * 1.12); add(root, o, band, 0.003, 2)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=d * 0.22, depth=0.002, location=(w * 0.3, 0, h / 2 + 0.001))
    o = bpy.context.object; o.scale = (0.8, 1, 1); add(root, o, mark)

def sheet(root, w, d, t, face, frame, mark):
    # 1 枚の札: 薄い紙。表に、少し明るい枠の線と透かしの楕円（図柄は描かない）
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.object; o.scale = (w, d, t); add(root, o, face, t * 0.3, 1)
    for (x, y, sx, sy) in ((0, d * 0.4, w * 0.9, 0.012), (0, -d * 0.4, w * 0.9, 0.012), (w * 0.45, 0, 0.012, d * 0.8), (-w * 0.45, 0, 0.012, d * 0.8)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, t / 2 + 0.001))
        o = bpy.context.object; o.scale = (sx, sy, 0.002); add(root, o, frame)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=d * 0.2, depth=0.002, location=(w * 0.28, 0, t / 2 + 0.002))
    o = bpy.context.object; o.scale = (0.8, 1, 1); add(root, o, mark)

def camera(sc, tilt, ortho, key, fill):
    dist = 4
    bpy.ops.object.camera_add(location=(0, -dist * math.cos(math.radians(tilt)), dist * math.sin(math.radians(tilt))), rotation=(math.radians(90 - tilt), 0, 0))
    cam = bpy.context.object; cam.data.type = "ORTHO"; cam.data.ortho_scale = ortho; sc.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(-1.5, -1.5, 3)); l = bpy.context.object; l.data.energy = key; l.data.size = 3
    bpy.ops.object.light_add(type="AREA", location=(2, 1, 2)); l = bpy.context.object; l.data.energy = fill; l.data.size = 3

def render_frames(sc, root, tier):
    for f in range(FRAMES):
        root.rotation_euler = (math.radians(45 * f), 0, 0)
        name = f"money_t{tier}_f{f}.png"
        sc.render.filepath = os.path.join(OUTS[0], name)
        bpy.ops.render.render(write_still=True)
        for extra in OUTS[1:]:
            shutil.copyfile(os.path.join(OUTS[0], name), os.path.join(extra, name))

for d in OUTS:
    os.makedirs(d, exist_ok=True)

# 段階 0〜2: 10円玉（青銅）・100円玉（白銅）・500円玉（ニッケル黄銅の外側 + 白銅の内側）。128 × 128
for tier, outer, inner in () if os.environ.get("PREVIEW") else ((0, ("C2783F", 0.35), None), (1, ("CDD1D6", 0.28), None), (2, ("D9B44A", 0.3), ("D5D8DC", 0.3))):
    sc, root = reset(0.9)
    sc.render.resolution_x = sc.render.resolution_y = 128
    coin(root, 0.5, 0.08, mat("o", srgb(outer[0]), 1.0, outer[1]), mat("i", srgb(inner[0]), 1.0, inner[1]) if inner else None)
    camera(sc, 55, 1.1, 250, 80)
    render_frames(sc, root, tier)

# 段階 3・4: 千円札（青系）・1万円札（茶系）を 1 枚ずつ（箱に入れる枚数を貯金額どおりにするため）。240 × 144
# PREVIEW に出力先を入れると、確かめ用の大きな絵（960 × 576）だけを描く
PREVIEW = os.environ.get("PREVIEW")
for tier, dark, light, numeral in ((3, "2B5688", "BCD0E8", "1000"), (4, "634B22", "DCCDA6", "10000")):
    sc, root = reset(0.55)
    sc.render.resolution_x, sc.render.resolution_y = (960, 576) if PREVIEW else (240, 144)
    billmod.bill(root, add, 1.0, 0.5, 0.004, srgb(dark), srgb(light), numeral, mat("num", srgb(dark), 0, 0.5),
                 mat("micro", tuple(0.55 * a + 0.45 * b for a, b in zip(srgb(dark), srgb(light))), 0, 0.6))
    camera(sc, 38, 1.04, 110, 40)
    if PREVIEW:
        sc.render.filepath = os.path.join(PREVIEW, f"bill_t{tier}.png"); bpy.ops.render.render(write_still=True); continue
    render_frames(sc, root, tier)
print("done", OUTS)
