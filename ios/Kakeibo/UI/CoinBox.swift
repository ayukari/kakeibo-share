import SwiftUI

// 硬貨・お札の色。本物と見まちがえないよう、肖像や図柄は描かず、色と形だけで表す（通貨及証券模造取締法。財務省の FAQ）
// 金属と紙の色なので、明るい表示でも暗い表示でも同じ
private struct CoinLook { let fill: Color; let edge: Color; var inner: Color? = nil }
private let looks: [CoinLook] = [
    CoinLook(fill: Color(hex: 0xC2783F), edge: Color(hex: 0x8A4F22)),                              // 10円玉（青銅。赤みのある銅色）
    CoinLook(fill: Color(hex: 0xCDD1D6), edge: Color(hex: 0x7E848D)),                              // 100円玉（白銅。銀白色）
    CoinLook(fill: Color(hex: 0xD9B44A), edge: Color(hex: 0x94721A), inner: Color(hex: 0xD5D8DC)), // 500円玉（外側が金色・内側が銀色の 2 色）
    CoinLook(fill: Color(hex: 0x9DBBDC), edge: Color(hex: 0x4D7199)),                              // 千円札（青系）
    CoinLook(fill: Color(hex: 0xCDB98F), edge: Color(hex: 0x85703F)),                              // 1万円札（茶系）
]

private func drawCoin(_ c: GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ look: CoinLook) {
    func circle(_ rr: CGFloat, _ at: CGPoint) -> Path { Path(ellipseIn: CGRect(x: at.x - rr, y: at.y - rr, width: rr * 2, height: rr * 2)) }
    c.fill(circle(r, p), with: .color(look.fill))
    if let inner = look.inner { c.fill(circle(r * 0.62, p), with: .color(inner)) }
    c.stroke(circle(r, p), with: .color(look.edge), lineWidth: 1.2)
    c.stroke(circle(r * 0.62, p), with: .color(look.edge.opacity(0.55)), lineWidth: 0.8)
    c.fill(circle(r * 0.26, CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.35)), with: .color(.white.opacity(0.35)))
}

private func drawBill(_ c: GraphicsContext, _ rect: CGRect, _ look: CoinLook) {
    let shape = Path(roundedRect: rect, cornerRadius: 2)
    c.fill(shape, with: .color(look.fill))
    c.stroke(shape, with: .color(look.edge), lineWidth: 1)
    c.stroke(Path(rect.insetBy(dx: 3, dy: 3)), with: .color(look.edge.opacity(0.45)), lineWidth: 0.8)
    c.stroke(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * 0.24, width: rect.width * 0.22, height: rect.height * 0.52)),
             with: .color(look.edge.opacity(0.5)), lineWidth: 0.8)
}

// 積んだ高さ（いちばん上の段の上端）が fillH をこえない段の数。少しでも貯まっていれば 1 段
private func stackRows(_ fillH: CGFloat, _ item: CGFloat, _ step: CGFloat) -> Int {
    if fillH <= 0 { return 0 }
    if fillH <= item { return 1 }
    return 1 + Int(((fillH - item) / step).rounded(.up))
}

// いちばん上の段の数。次の段までの足りない分だけ少なくする
private func lastRowCount(_ fillH: CGFloat, _ item: CGFloat, _ step: CGFloat, _ r: Int, _ perRow: Int) -> Int {
    if r == 0 { return fillH >= item ? perRow : max(1, Int((CGFloat(perRow) * fillH / item).rounded())) }
    let part = min(max((fillH - item - CGFloat(r - 1) * step) / step, 0), 1)
    return max(1, Int((CGFloat(perRow) * part).rounded()))
}

// 置き場所（硬貨は中心、お札は左上）。下の段から順に並べる
private func stack(fillH: CGFloat, left: CGFloat, right: CGFloat, bottom: CGFloat, item: CGFloat, step: CGFloat, w: CGFloat, gap: CGFloat, shiftOdd: CGFloat, bill: Bool) -> [CGPoint] {
    var out: [CGPoint] = []
    let rows = stackRows(fillH, item, step)
    for r in 0..<rows {
        let shift = r % 2 == 1 ? shiftOdd : 0
        let perRow = max(1, Int(((right - left - shift + gap) / (w + gap)).rounded(.down)))
        let n = r == rows - 1 ? lastRowCount(fillH, item, step, r, perRow) : perRow
        for i in 0..<n {
            let x = left + shift + CGFloat(i) * (w + gap)
            out.append(bill ? CGPoint(x: x, y: bottom - item - CGFloat(r) * step) : CGPoint(x: x + w / 2, y: bottom - item / 2 - CGFloat(r) * step))
        }
    }
    return out
}

// 落ちる動き: はじめは重力のように加速し、底で少しはねる（0 → 1。はねる間だけ少し上に戻る）
private func fall(_ t: CGFloat) -> CGFloat {
    if t <= 0 { return 0 }
    if t < 0.78 { let u = t / 0.78; return u * u }
    if t < 1 { return 1 - 0.07 * sin(.pi * (t - 0.78) / 0.22) }
    return 1
}

// 目標の貯金箱。中身の多さは目標に対する割合、中身の種類は貯まった額（1 万で 100円玉、3 万で 500円玉、10 万で千円札、50 万で万札）
// 画面を開くと、上から 1 枚ずつ降ってきて積もる（「視差効果を減らす」設定のときは、はじめから積んだ形）
struct CoinBox: View {
    let name: String
    let saved: Int64
    let ratio: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var running = true   // 落ちきったら止める（描き直しを続けない）
    private let duration = 1.8

    var body: some View {
        let idx = Savings.coinIndex(saved), coin = Savings.coins[idx], pct = Int((ratio * 100).rounded())
        TimelineView(.animation(paused: reduceMotion || !running)) { tl in
            let p = reduceMotion || !running ? 1 : min(1, max(0, tl.date.timeIntervalSince(start) / duration))
            Canvas { c, size in draw(c, size, CGFloat(p), idx: idx, bill: coin.bill, pct: pct) }
        }
        .frame(height: 140)
        .task(id: saved) {
            start = Date(); running = true
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
            running = false
        }
        .accessibilityElement()
        .accessibilityLabel("\(name)の貯金箱 \(pct)%・中身は\(coin.name)")
    }

    private func draw(_ c: GraphicsContext, _ size: CGSize, _ p: CGFloat, idx: Int, bill: Bool, pct: Int) {
        let look = looks[idx]
        let labelW: CGFloat = 34, lid: CGFloat = 8, pad: CGFloat = 6
        let boxW = size.width - labelW, boxH = size.height - lid
        // 箱と、上の投入口
        let box = Path(roundedRect: CGRect(x: 0, y: lid, width: boxW, height: boxH), cornerRadius: 8)
        c.fill(box, with: .color(.kBg))
        c.stroke(box, with: .color(.kLine), lineWidth: 1.5)
        c.fill(Path(roundedRect: CGRect(x: boxW / 2 - 20, y: lid - 2, width: 40, height: 4), cornerRadius: 2), with: .color(Color.kInk.opacity(0.6)))
        let left = pad, right = boxW - pad, bottom = size.height - pad, innerH = boxH - pad * 2 - 4, topY = lid + pad
        let fillH: CGFloat = saved > 0 ? max(innerH * CGFloat(min(max(ratio, 0), 1)), 1) : 0
        let d: CGFloat = 18, bw: CGFloat = 50, bh: CGFloat = 24
        let spots = bill ? stack(fillH: fillH, left: left, right: right, bottom: bottom, item: bh, step: bh * 0.62, w: bw, gap: 4, shiftOdd: bw * 0.3, bill: true)
                         : stack(fillH: fillH, left: left, right: right, bottom: bottom, item: d, step: d * 0.82, w: d, gap: 0, shiftOdd: d / 2, bill: false)
        // 1 枚ずつ、置き場所の真上から降らせる。下の段から順に、少しばらつかせて落とし始める
        // （全体の 62% の時間で全部が落ち始め、1 枚は 38% の時間で落ちきる）
        var inner = c
        inner.clip(to: Path(CGRect(x: left, y: topY, width: right - left, height: bottom - topY)))
        let n = spots.count
        for (k, s) in spots.enumerated() {
            let order: CGFloat = n <= 1 ? 0 : CGFloat(k) / CGFloat(n - 1)
            let jitter = CGFloat((k * 7919) % 101) / 100
            let t = (p - 0.62 * (0.75 * order + 0.25 * jitter)) / 0.38
            if t <= 0 { continue }
            let f = fall(min(t, 1))
            if bill {
                let y = (topY - bh) + (s.y - (topY - bh)) * f
                let tilt = (1 - min(max(t / 0.78, 0), 1)) * (k % 2 == 0 ? 12 : -12)   // 落ちながら水平に戻る
                var g = inner
                g.translateBy(x: s.x + bw / 2, y: y + bh / 2); g.rotate(by: .degrees(Double(tilt))); g.translateBy(x: -(s.x + bw / 2), y: -(y + bh / 2))
                drawBill(g, CGRect(x: s.x, y: y, width: bw, height: bh), look)
            } else {
                let y = (topY - d / 2) + (s.y - (topY - d / 2)) * f
                drawCoin(inner, CGPoint(x: s.x, y: y), d / 2 - 0.5, look)
            }
        }
        // 25・50・75・100% の目盛り（箱の中は点線、右に数字）
        for q in [25, 50, 75, 100] {
            let y = bottom - innerH * CGFloat(q) / 100
            var l = Path(); l.move(to: CGPoint(x: left, y: y)); l.addLine(to: CGPoint(x: right, y: y))
            c.stroke(l, with: .color(Color.kSub.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            c.draw(Text("\(q)%").font(.system(size: 11, weight: pct >= q ? .bold : .regular)).foregroundColor(pct >= q ? .kInk : .kSub),
                   at: CGPoint(x: boxW + 6, y: y), anchor: .leading)
        }
    }
}

// 段階の並び（10円 → 100円 → 500円 → 千円札 → 万札）。届いた段階は濃く、今の段階は太字
struct CoinSteps: View {
    let saved: Int64
    let done: Bool
    var body: some View {
        let idx = Savings.coinIndex(saved)
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(Savings.coins.enumerated()), id: \.offset) { i, coin in
                    VStack(spacing: 1) {
                        Canvas { c, size in
                            if coin.bill { drawBill(c, CGRect(x: 1, y: 3, width: size.width - 2, height: size.height - 6), looks[i]) }
                            else { drawCoin(c, CGPoint(x: size.width / 2, y: size.height / 2), size.height / 2 - 1, looks[i]) }
                        }.frame(width: 28, height: 18)
                        Text(coin.short).font(.system(size: 11, weight: i == idx ? .bold : .regular)).foregroundStyle(Color.kInk)
                        Text(coin.from == 0 ? "〜" : "\(coin.from / 10_000)万〜").font(.system(size: 10)).foregroundStyle(Color.kFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(i <= idx ? 1 : 0.35)
                }
            }
            Text(message).font(.system(size: 14, weight: done ? .bold : .regular)).foregroundStyle(done ? Color.kAccent : Color.kSub).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if done { return "目標を達成しました！" }
        guard let next = Savings.nextCoin(saved) else { return "万札まで貯まりました" }
        if saved <= 0 { return "貯金すると、箱に 10円玉が入ります" }
        return "あと \(Money.format(next.left)) で\(next.coin.name)に変わります"
    }
}
