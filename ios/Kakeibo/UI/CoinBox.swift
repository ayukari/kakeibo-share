import SwiftUI

// 硬貨・お札の絵。Blender で作った 3D を描き出したもの（tools/render3d/money_sprites.py。Resources/Money）
// 本物と見まちがえないよう、肖像や図柄は描かず、色・金属の質感・形だけ（通貨及証券模造取締法。財務省の FAQ）
// 段階ごとに 8 コマ。0 コマ目が置いたときの姿で、1〜7 コマ目は横の軸で 45° ずつ回した姿（落ちながら回る）
private let frameCount = 8
private func moneyFrame(_ tier: Int, _ f: Int) -> Image {
    Image(uiImage: UIImage(named: "money_t\(tier)_f\(f)") ?? UIImage())
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
        let labelW: CGFloat = 34, lid: CGFloat = 8, pad: CGFloat = 6
        let boxW = size.width - labelW, boxH = size.height - lid
        // 箱と、上の投入口
        let box = Path(roundedRect: CGRect(x: 0, y: lid, width: boxW, height: boxH), cornerRadius: 8)
        c.fill(box, with: .color(.kBg))
        c.stroke(box, with: .color(.kLine), lineWidth: 1.5)
        c.fill(Path(roundedRect: CGRect(x: boxW / 2 - 20, y: lid - 2, width: 40, height: 4), cornerRadius: 2), with: .color(Color.kInk.opacity(0.6)))
        let left = pad, right = boxW - pad, bottom = size.height - pad, innerH = boxH - pad * 2 - 4, topY = lid + pad
        let fillH: CGFloat = saved > 0 ? max(innerH * CGFloat(min(max(ratio, 0), 1)), 1) : 0
        let d: CGFloat = 20, bw: CGFloat = 50, bh: CGFloat = 30
        let spots = bill ? stack(fillH: fillH, left: left, right: right, bottom: bottom, item: bh, step: bh * 0.6, w: bw, gap: 0, shiftOdd: bw * 0.5, bill: true)
                         : stack(fillH: fillH, left: left, right: right, bottom: bottom, item: d, step: d * 0.62, w: d * 0.92, gap: 0, shiftOdd: d * 0.46, bill: false)
        let frames = (0..<frameCount).map { c.resolve(moneyFrame(idx, $0)) }
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
            // 落ちている間は 1 回転半して、着いたときに置いた姿（0 コマ目）になる。1 枚ごとに回る向きを変える
            let spin = t >= 0.78 ? 0 : Int((1 - t / 0.78) * CGFloat(frameCount) * 1.5) % frameCount
            let img = frames[k % 2 == 0 ? spin : (frameCount - spin) % frameCount]
            if bill {
                inner.draw(img, in: CGRect(x: s.x, y: (topY - bh) + (s.y - (topY - bh)) * f, width: bw, height: bh))
            } else {
                let y = (topY - d / 2) + (s.y - (topY - d / 2)) * f
                inner.draw(img, in: CGRect(x: s.x - d / 2, y: y - d / 2, width: d, height: d))
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
                        moneyFrame(i, 0).resizable().interpolation(.medium).aspectRatio(contentMode: .fit).frame(width: coin.bill ? 34 : 22, height: 22)
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
