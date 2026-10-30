# 3D の硬貨・札束を作って、背景が透明な PNG に描き出す（Blender 5.x、--background --python）
# 本物と見まちがえないよう、図柄は描かない。色・材質・形だけ（数字の刻印もなし）
import bpy, math, os, sys

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
ONLY = sys.argv[sys.argv.index("--") + 2] if "--" in sys.argv and len(sys.argv) > sys.argv.index("--") + 2 else ""
os.makedirs(OUT, exist_ok=True)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.85, 0.87, 0.9, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    return sc

def mat(name, rgb, metal, rough):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m

def srgb(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

def bevel(o, w, seg=4):
    m = o.modifiers.new("b", "BEVEL"); m.width = w; m.segments = seg
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth()

def coin(r, h, m_outer, m_inner=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=r, depth=h)
    o = bpy.context.object; o.data.materials.append(m_outer); bevel(o, h * 0.18)
    # 縁の盛り上がり（リム）
    bpy.ops.mesh.primitive_torus_add(major_radius=r * 0.9, minor_radius=h * 0.12, major_segments=96, minor_segments=12, location=(0, 0, h / 2))
    t = bpy.context.object; t.data.materials.append(m_inner or m_outer); bpy.ops.object.shade_smooth()
    if m_inner:   # 500円玉: 内側が別の色（2 色）
        bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=r * 0.62, depth=h * 1.04)
        i = bpy.context.object; i.data.materials.append(m_inner); bevel(i, h * 0.1)
    return o

def bundle(w, d, h, m_bill, m_band, m_edge):
    # 札束: 紙の層を少しずつずらして重ね、まん中に帯
    for k in range(10):
        bpy.ops.mesh.primitive_cube_add(size=1, location=((k % 3 - 1) * 0.004, (k % 2) * 0.004, k * h / 10))
        o = bpy.context.object; o.scale = (w, d, h / 10 * 0.92)
        o.data.materials.append(m_bill if k == 9 else m_edge); bevel(o, 0.004, 2)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, h * 0.45))
    b = bpy.context.object; b.scale = (w * 0.14, d * 1.04, h * 1.12); b.data.materials.append(m_band); bevel(b, 0.003, 2)
    # 透かしの楕円（凹みではなく、少し明るい楕円）
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=d * 0.22, depth=0.002, location=(w * 0.3, 0, h * 0.95))
    e = bpy.context.object; e.scale = (0.8, 1, 1); e.data.materials.append(mat("wm", tuple(min(1, x * 1.25) for x in m_bill.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value[:3]), 0, 0.6))

def shoot(sc, name, tilt=55, dist=3.2, ortho=1.25, key=250, fill=80):
    bpy.ops.object.camera_add(location=(0, -dist * math.cos(math.radians(tilt)), dist * math.sin(math.radians(tilt))), rotation=(math.radians(90 - tilt), 0, 0))
    cam = bpy.context.object; cam.data.type = "ORTHO"; cam.data.ortho_scale = ortho; sc.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(-1.5, -1.5, 3)); l = bpy.context.object; l.data.energy = key; l.data.size = 3
    bpy.ops.object.light_add(type="AREA", location=(2, 1, 2)); l2 = bpy.context.object; l2.data.energy = fill; l2.data.size = 3
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)

# 10円玉（青銅）・100円玉（白銅）・500円玉（ニッケル黄銅の外側 + 白銅の内側）
for name, outer, inner in [] if ONLY == "bills" else (("coin10", ("C2783F", 1.0, 0.35), None), ("coin100", ("CDD1D6", 1.0, 0.28), None),
                           ("coin500", ("D9B44A", 1.0, 0.3), ("D5D8DC", 1.0, 0.3))):
    sc = reset()
    mo = mat("o", srgb(outer[0]), outer[1], outer[2]); mi = mat("i", srgb(inner[0]), inner[1], inner[2]) if inner else None
    coin(0.5, 0.08, mo, mi)
    shoot(sc, name)

# 千円札の束（青系）・1万円札の束（茶系）。帯は白
for name, col in (("bill1000", "6F95C2"), ("bill10000", "A88C58")):
    sc = reset()
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    bundle(1.0, 0.48, 0.22, mat("b", srgb(col), 0, 0.75), mat("band", srgb("E9E3D2"), 0, 0.55), mat("e", srgb("E6DFCB"), 0, 0.85))
    shoot(sc, name, tilt=38, ortho=1.3, key=90, fill=30)
print("done", OUT)
