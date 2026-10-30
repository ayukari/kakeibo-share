import SwiftUI
import CoreMotion

// 硬貨・お札の絵。Blender で作った 3D を描き出したもの（tools/render3d/money_sprites.py。お札は bill.py で作り込んだもの。Resources/Money）
// 本物と見まちがえないよう、肖像や実際の図柄は描かず、色・質感・形と、このアプリ独自の模様だけ（通貨及証券模造取締法。財務省の FAQ）
// 段階ごとに 8 コマ。0 コマ目が置いたときの姿で、1〜7 コマ目は横の軸で 45° ずつ回した姿（落ちながら回る）
private let frameCount = 8
private let billAspect: CGFloat = 240.0 / 144.0   // お札の絵の横:縦
private func moneyFrame(_ tier: Int, _ f: Int) -> Image {
    Image(uiImage: UIImage(named: "money_t\(tier)_f\(f)") ?? UIImage())
}

// 箱の内側の大きさと、中身 1 枚の大きさ d（pt）。目標額ちょうどの枚数で、箱がちょうどいっぱいになる大きさにする
private struct BoxGeo: Equatable {
    let boxW, lid, left, right, top, bottom, d: CGFloat
    let bill: Bool
    var w: CGFloat { right - left }
    var h: CGFloat { bottom - top }
    // c 枚を積んだときのおよその上端（目盛りに使う）
    func pileTop(_ c: Double) -> CGFloat { bottom - CGFloat(c) * CGFloat(CoinWorld.areaPerItem(bill)) * d * d / w }

    static func of(_ size: CGSize, bill: Bool, capacity: Int64) -> BoxGeo? {
        guard size.width > 0, size.height > 0 else { return nil }
        let labelW: CGFloat = 34, lid: CGFloat = 8, pad: CGFloat = 6
        let boxW = size.width - labelW
        let left = pad, right = boxW - pad, top = lid + pad, bottom = size.height - pad
        let fit = ((right - left) * (bottom - top) * 0.92 / (CGFloat(capacity) * CGFloat(CoinWorld.areaPerItem(bill)))).squareRoot()
        let d = min(max(fit, bill ? 9 : 6), 26)
        return BoxGeo(boxW: boxW, lid: lid, left: left, right: right, top: top, bottom: bottom, d: d, bill: bill)
    }
}

// 物理の箱と、描き直しの合図。画面が開いている間だけ動かす
@Observable
private final class PileModel {
    var tick = 0
    @ObservationIgnored var world: CoinWorld?
    @ObservationIgnored var geo: BoxGeo?
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var lastAngle: Float = .nan

    func prepare(_ geo: BoxGeo?) {
        guard geo != self.geo else { return }
        self.geo = geo
        world = geo.map { CoinWorld(width: Float($0.w / $0.d), height: Float($0.h / $0.d), bill: $0.bill) }
    }

    // 端末の傾き（重力の向き）。机に平らに置いたときは下向きのまま。少しの揺れ（約 7°）は無視
    func startTilt(_ onTilt: @escaping () -> Void) {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity, let w = self.world else { return }
            let gx = Float(g.x), gy = Float(g.y)
            if (gx * gx + gy * gy).squareRoot() < 0.3 { return }
            let a = atan2(gy, gx)
            if !self.lastAngle.isNaN && abs(a - self.lastAngle) < 0.12 { return }
            self.lastAngle = a
            w.setGravity(gx, gy)
            onTilt()
        }
    }

    func stopTilt() { motion.stopDeviceMotionUpdates() }
}

// 目標の貯金箱。中身は貯金額どおりの枚数（2 万円なら 100円玉 200 枚）。1 万で 100円玉、3 万で 500円玉、10 万で千円札、50 万で万札
// 中身の大きさは、目標額ちょうどの枚数で箱がいっぱいになるように決める（だから満ち具合 = 目標に対する割合）
// 物理（Box2D）で、投入口から 1 枚ずつ降ってきて積もる。端末を傾けると転がる。貯金を記録すると増えた分だけ落ちてくる
// 「視差効果を減らす」設定のときは、はじめから積んだ形
struct CoinBox: View {
    let name: String
    let saved: Int64
    let target: Int64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = PileModel()
    @State private var kick = 0
    @State private var size: CGSize = .zero

    private struct RunKey: Equatable { let geo: BoxGeo?; let count: Int; let kick: Int; let still: Bool }

    var body: some View {
        let idx = Savings.coinIndex(saved), coin = Savings.coins[idx]
        let count = Savings.coinCount(saved), capacity = Savings.coinCapacity(saved, target)
        let pct = target > 0 ? Int((Double(saved) * 100 / Double(target)).rounded()) : 0
        let geo = BoxGeo.of(size, bill: coin.bill, capacity: capacity)
        let tick = model.tick   // 物理が進むたびに描き直す
        Canvas { c, sz in
            _ = tick
            draw(c, sz, idx: idx, pct: pct, capacity: capacity)
        }
        .frame(height: 140)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: RunKey(geo: geo, count: Int(min(count, Int64(CoinWorld.maxBodies))), kick: kick, still: reduceMotion)) {
            model.prepare(geo)
            guard let w = model.world else { return }
            w.setCount(Int(min(count, Int64(CoinWorld.maxBodies))), animate: !reduceMotion)
            model.tick += 1
            if reduceMotion { return }
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let dt = Float((now - last) / .seconds(1)); last = now
                let moving = w.step(dt)
                model.tick += 1
                if !moving { break }   // みんな止まったら計算をやめる（電池を使わない）
            }
        }
        .onAppear { if !reduceMotion { model.startTilt { kick += 1 } } }
        .onDisappear { model.stopTilt() }
        .accessibilityElement()
        .accessibilityLabel("\(name)の貯金箱 \(pct)%・\(coin.name) \(count)枚")
    }

    private func draw(_ c: GraphicsContext, _ size: CGSize, idx: Int, pct: Int, capacity: Int64) {
        guard let g = model.geo else { return }
        // 箱と、上の投入口
        let box = Path(roundedRect: CGRect(x: 0, y: g.lid, width: g.boxW, height: size.height - g.lid), cornerRadius: 8)
        c.fill(box, with: .color(.kBg))
        c.stroke(box, with: .color(.kLine), lineWidth: 1.5)
        c.fill(Path(roundedRect: CGRect(x: g.boxW / 2 - 20, y: g.lid - 2, width: 40, height: 4), cornerRadius: 2), with: .color(Color.kInk.opacity(0.6)))
        let d = g.d, iw = g.bill ? d * billAspect : d
        let frames = (0..<frameCount).map { c.resolve(moneyFrame(idx, $0)) }
        var inner = c
        inner.clip(to: Path(CGRect(x: g.left, y: g.top, width: g.w, height: g.h)))
        if let w = model.world {
            for i in 0..<w.count {
                let cx = g.left + CGFloat(w.xs[i]) * d, cy = g.bottom - CGFloat(w.ys[i]) * d
                var ic = inner
                ic.translateBy(x: cx, y: cy); ic.rotate(by: .radians(-Double(w.angles[i])))
                ic.draw(frames[w.frames[i]], in: CGRect(x: -iw / 2, y: -d / 2, width: iw, height: d))
            }
        }
        // 25・50・75・100% の目盛り（目標額の何割の枚数を積んだ高さか。箱の中は点線、右に数字）
        for q in [25, 50, 75, 100] {
            let y = g.pileTop(Double(capacity) * Double(q) / 100)
            if y < g.top { continue }
            var l = Path(); l.move(to: CGPoint(x: g.left, y: y)); l.addLine(to: CGPoint(x: g.right, y: y))
            c.stroke(l, with: .color(Color.kSub.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            c.draw(Text("\(q)%").font(.system(size: 11, weight: pct >= q ? .bold : .regular)).foregroundColor(pct >= q ? .kInk : .kSub),
                   at: CGPoint(x: g.boxW + 6, y: y), anchor: .leading)
        }
    }
}

// 枚数・段階の並び（10円 → 100円 → 500円 → 千円札 → 万札）。届いた段階は濃く、今の段階は太字
struct CoinSteps: View {
    let saved: Int64
    let done: Bool
    var body: some View {
        let idx = Savings.coinIndex(saved)
        VStack(spacing: 6) {
            if Savings.coinCount(saved) > 0 {
                Text(countText).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kInk).multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(Savings.coins.enumerated()), id: \.offset) { i, coin in
                    VStack(spacing: 1) {
                        moneyFrame(i, 0).resizable().interpolation(.medium).aspectRatio(contentMode: .fit).frame(width: coin.bill ? 37 : 22, height: 22)
                        Text(coin.short).font(.system(size: 11, weight: i == idx ? .bold : .regular)).foregroundStyle(Color.kInk)
                        Text(coin.from == 0 ? "〜" : "\(coin.from / 10_000)万〜").font(.system(size: 10)).foregroundStyle(Color.kFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(i <= idx ? 1 : 0.35)
                }
            }
            Text(message).font(.system(size: 14, weight: done ? .bold : .regular)).foregroundStyle(done ? Color.kAccent : Color.kSub).multilineTextAlignment(.center)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var countText: String {
        let coin = Savings.coins[Savings.coinIndex(saved)]
        let count = Savings.coinCount(saved), rest = Savings.coinRemainder(saved)
        var t = "\(coin.name) \(count.formatted())枚"
        if rest > 0 { t += "・端数 \(Money.format(rest))" }
        if count > Int64(CoinWorld.maxBodies) { t += "（箱には \(CoinWorld.maxBodies.formatted()) 枚まで）" }
        return t
    }

    private var message: String {
        if done { return "目標を達成しました！" }
        guard let next = Savings.nextCoin(saved) else { return "万札まで貯まりました" }
        if saved <= 0 { return "貯金すると、箱に 10円玉が入ります" }
        return "あと \(Money.format(next.left)) で\(next.coin.name)に変わります"
    }
}
