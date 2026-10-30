# 1 枚のお札（作り込んだもの）を作る。money_sprites.py から使う
# 本物と見まちがえないよう、肖像・実際の図柄・「日本銀行券」などの文字は描かない（通貨及証券模造取締法。財務省の FAQ）
# 描くのは、このアプリ独自の模様だけ: 波打つ地紋、左のロゼット（花びら状に波打つ線を重ねた模様）、飾り枠、
# 右の透かしの楕円、額面の数字、小さな「KAKEIBO SHARE」の文字
# 紙の繊維の凹凸と光の返り方は ambientCG「Paper 001」（CC0。textures/README.md）
import bpy, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "textures")
ASPECT = 2.0   # 横:縦（本物の紙幣はおよそ 2:1）


def _img(path, colorspace):
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = colorspace
    return im


class _G:
    """シェーダーのノードを数式のように組むための小さな道具"""
    def __init__(self, nt):
        self.N = nt.nodes; self.L = nt.links

    def _in(self, node, i, v):
        if isinstance(v, (int, float)): node.inputs[i].default_value = v
        else: self.L.new(v, node.inputs[i])

    def m(self, op, a, b=None):
        n = self.N.new("ShaderNodeMath"); n.operation = op
        self._in(n, 0, a)
        if b is not None: self._in(n, 1, b)
        return n.outputs[0]

    def add(self, a, b): return self.m("ADD", a, b)
    def sub(self, a, b): return self.m("SUBTRACT", a, b)
    def mul(self, a, b): return self.m("MULTIPLY", a, b)
    def sin(self, a): return self.m("SINE", a)
    def fract(self, a): return self.m("FRACT", a)
    def mx(self, a, b): return self.m("MAXIMUM", a, b)
    def mn(self, a, b): return self.m("MINIMUM", a, b)
    def lt(self, a, b): return self.m("LESS_THAN", a, b)
    def gt(self, a, b): return self.m("GREATER_THAN", a, b)

    def line(self, v, width):
        """v の小数部分が 0.5 の近くだけ 1（等間隔の細い線）"""
        return self.lt(self.m("ABSOLUTE", self.sub(self.fract(v), 0.5)), width)

    def smooth_in(self, d, r, soft=0.004):
        """d < r なら 1（ふちを少しぼかす）"""
        n = self.N.new("ShaderNodeMapRange"); n.clamp = True
        self._in(n, 0, d); n.inputs[1].default_value = r; n.inputs[2].default_value = r - soft
        n.inputs[3].default_value = 0; n.inputs[4].default_value = 1
        return n.outputs[0]

    def mix(self, a, b, fac):
        n = self.N.new("ShaderNodeMix"); n.data_type = "RGBA"
        self._in(n, 0, fac)
        for i, v in ((6, a), (7, b)):
            if isinstance(v, tuple): n.inputs[i].default_value = (*v, 1)
            else: self.L.new(v, n.inputs[i])
        return n.outputs[2]


def bill_material(name, dark, light):
    """dark・light は 0〜1 の線形 RGB。UV（0〜1）に模様を描く"""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL": nt.nodes.remove(n)
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    g = _G(nt)
    bsdf = g.N.new("ShaderNodeBsdfPrincipled"); g.L.new(bsdf.outputs[0], out.inputs[0])

    uv = g.N.new("ShaderNodeTexCoord").outputs["UV"]
    sep = g.N.new("ShaderNodeSeparateXYZ"); g.L.new(uv, sep.inputs[0])
    x = g.mul(sep.outputs[0], ASPECT); y = sep.outputs[1]   # x: 0〜2、y: 0〜1（縦横が同じ縮尺）

    # 地紋: ゆるく波打つ横の線と、斜めの細い線
    ground = g.mx(g.line(g.add(g.mul(y, 46), g.mul(g.sin(g.mul(x, 9)), 0.35)), 0.07),
                  g.line(g.add(g.mul(g.add(x, y), 30), g.mul(g.sin(g.mul(y, 14)), 0.25)), 0.05))

    # ロゼット（左寄り）: 極座標で、花びら状に波打つ同心の線を 2 組ずらして重ねる
    cx, cy = 0.5, 0.48
    dx = g.sub(x, cx); dy = g.sub(y, cy)
    r = g.m("SQRT", g.add(g.mul(dx, dx), g.mul(dy, dy)))
    th = g.m("ARCTAN2", dy, dx)
    ros = g.mx(g.line(g.add(g.mul(r, 46), g.mul(g.sin(g.mul(th, 12)), 0.9)), 0.09),
               g.line(g.add(g.mul(r, 46), g.mul(g.sin(g.add(g.mul(th, 12), math.pi / 12 * 6)), 0.9)), 0.09))
    petals = g.line(g.add(g.mul(th, 24 / (2 * math.pi)), g.mul(g.sin(g.mul(r, 60)), 0.25)), 0.05)   # 放射状の細い線
    in_ros = g.smooth_in(r, 0.28)
    core = g.smooth_in(r, 0.07)
    rosette = g.mx(g.mul(g.mx(ros, g.mul(petals, 0.6)), g.sub(in_ros, core)),
                   g.mul(g.gt(r, 0.266), in_ros))                                  # 外周の線
    rosette = g.mx(rosette, g.mul(g.gt(r, 0.06), core))                            # 中心の小さな輪

    # 透かしの楕円（右寄り）: 地紋を消し、うすい陰と細いふちの線
    ex = g.m("DIVIDE", g.sub(x, 1.6), 0.17); ey = g.m("DIVIDE", g.sub(y, 0.52), 0.27)
    ed = g.m("SQRT", g.add(g.mul(ex, ex), g.mul(ey, ey)))
    in_wm = g.smooth_in(ed, 1.0, 0.05)
    wm_line = g.mul(g.gt(ed, 0.96), g.lt(ed, 1.0))

    # 飾り枠: ふちから 0.035〜0.1 の帯に、交差する波の格子。帯の内と外に細い線
    e = g.mn(g.mn(x, g.sub(ASPECT, x)), g.mn(y, g.sub(1.0, y)))
    band = g.mul(g.gt(e, 0.035), g.lt(e, 0.1))
    lattice = g.mx(g.line(g.add(g.mul(g.add(x, y), 34), g.mul(g.sin(g.mul(g.sub(x, y), 40)), 0.3)), 0.12),
                   g.line(g.add(g.mul(g.sub(x, y), 34), g.mul(g.sin(g.mul(g.add(x, y), 40)), 0.3)), 0.12))
    lines = g.mx(g.mul(g.gt(e, 0.028), g.lt(e, 0.034)), g.mul(g.gt(e, 0.1), g.lt(e, 0.106)))
    border = g.mx(g.mul(band, lattice), lines)

    paper = (0.94, 0.92, 0.87)
    c = g.mix(paper, light, 0.6)                                       # 地の色
    c = g.mix(c, light, g.mul(band, 0.7))                               # 枠の帯は少し濃く
    c = g.mix(c, dark, g.mul(g.mul(ground, g.sub(1, in_wm)), 0.22))     # 地紋（うすく）
    c = g.mix(c, dark, g.mul(rosette, 0.8))                             # ロゼット
    c = g.mix(c, dark, g.mul(border, 0.85))                             # 飾り枠
    c = g.mix(c, paper, g.mul(in_wm, 0.45))                             # 透かし: 紙の色に寄せる
    c = g.mix(c, light, g.mul(g.mul(in_wm, g.smooth_in(ed, 0.6, 0.4)), 0.35))   # 透かしの中のうすい陰
    c = g.mix(c, dark, g.mul(wm_line, 0.35))
    g.L.new(c, bsdf.inputs["Base Color"])

    # 紙の繊維（ambientCG Paper 001）: 凹凸と光の返り方
    mp = g.N.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (ASPECT * 2.5, 2.5, 1); g.L.new(uv, mp.inputs[0])
    nimg = g.N.new("ShaderNodeTexImage"); nimg.image = _img(os.path.join(TEX, "Paper001_NormalGL.png"), "Non-Color"); g.L.new(mp.outputs[0], nimg.inputs[0])
    nm = g.N.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 0.6
    g.L.new(nimg.outputs[0], nm.inputs["Color"]); g.L.new(nm.outputs[0], bsdf.inputs["Normal"])
    rimg = g.N.new("ShaderNodeTexImage"); rimg.image = _img(os.path.join(TEX, "Paper001_Roughness.png"), "Non-Color"); g.L.new(mp.outputs[0], rimg.inputs[0])
    g.L.new(rimg.outputs[0], bsdf.inputs["Roughness"])
    return m


CURL = 0.06   # 紙のたわみ（両はしが中央より上がる高さ。横幅 1 に対して）


def _curl_z(x, w):
    u = x / (w / 2)
    return CURL * u * u


def bill(root, add, w, d, t, dark, light, numeral, num_mat, micro_mat):
    """w × d の紙（厚さ t）。表に模様、額面の数字、小さな文字。横にゆるくたわませる"""
    bpy.ops.mesh.primitive_plane_add(size=1)
    o = bpy.context.object; o.scale = (w, d, 1)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.subdivide(number_cuts=30); bpy.ops.object.mode_set(mode="OBJECT")
    for v in o.data.vertices:
        v.co.z = _curl_z(v.co.x, w)
    sol = o.modifiers.new("t", "SOLIDIFY"); sol.thickness = t; sol.offset = 0
    add(root, o, bill_material("bill", dark, light))
    # 文字: 左上と右下に額面、中央の下に大きな額面（うすい色）、上の帯に小さな「KAKEIBO SHARE」
    # 置き場所は UV（横 0〜2、縦 0〜1）で決める: 左上（ロゼットの上）、右下（透かしの下）、まん中（ロゼットと透かしのあいだ）
    def at(u, v): return ((u / ASPECT - 0.5) * w, (v - 0.5) * d)
    big = 0.21 * w / (len(numeral) * 0.62)
    for (body, (px, py), size, m, bold) in ((numeral, at(0.5, 0.835), d * 0.11, num_mat, True),
                                            (numeral, at(1.6, 0.165), d * 0.1, num_mat, True),
                                            (numeral, at(1.06, 0.5), big, micro_mat, True),
                                            ("KAKEIBO SHARE", at(1.0, 0.932), d * 0.045, num_mat, False)):
        bpy.ops.object.text_add(location=(px, py, 0))
        tx = bpy.context.object; tx.data.body = body; tx.data.size = size
        tx.data.align_x = "CENTER"; tx.data.align_y = "CENTER"
        tx.data.space_character = 1.05 if bold else 1.4
        tx.data.offset = 0.004 if bold else 0.0
        tx.data.resolution_u = 24
        bpy.ops.object.convert(target="MESH")   # 文字を面にして、紙のたわみに沿わせる
        tx = bpy.context.object
        for v in tx.data.vertices:
            v.co.z = _curl_z(px + v.co.x, w) + t / 2 + 0.0008
        tx.data.materials.append(m)
        tx.parent = root
