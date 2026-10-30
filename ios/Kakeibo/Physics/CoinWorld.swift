import Foundation
import box2d

// 貯金箱の中の物理（Box2D v3.2。iOS は Box2D 公式の Swift Package、Android は box2d-jni。CoinWorld.kt と同じ作り）
// 単位は「中身 1 枚の大きさ d = 1」。y は上向き。箱の内側は 0 ≦ x ≦ width、0 ≦ y ≦ height
// 中身は角の丸い横長の箱（置いた硬貨・お札を横から見た形）。箱の上に投入口ぶんの空きがあり、そこから落とす
final class CoinWorld {
    static let gravity: Float = 40        // 1 秒あたり d の何倍で加速するか（小さな硬貨が、見て気持ちよく落ちる速さ）
    static let lidGap: Float = 3          // 箱の上の、投入口から落ちてくる空き
    static let spawnSeconds: Float = 1.2  // 入れる枚数が多くても、この時間で全部を落とし始める
    static let maxBodies = 1200           // 物理で動かす枚数の上限（それより多いときは、絵の下に書く）
    private static let stepTime: Float = 1.0 / 60
    static func halfWidth(_ bill: Bool) -> Float { bill ? 0.8 : 0.455 }
    static func halfHeight(_ bill: Bool) -> Float { bill ? 0.14 : 0.3 }
    // 1 枚が箱の中でしめる広さ（d² の何倍か。すき間ぶんで割る）。目標額の枚数で箱がいっぱいになる大きさを決めるのに使う
    static func areaPerItem(_ bill: Bool) -> Float { 4 * halfWidth(bill) * halfHeight(bill) / 0.78 }

    let width: Float, height: Float, bill: Bool
    private let world: b2WorldId
    private var bodies: [b2BodyId] = []
    private var shapeDef = b2DefaultShapeDef()
    private var bodyDef = b2DefaultBodyDef()
    private var poly: b2Polygon
    private var pending = 0, spawned = 0
    private var spawnClock: Float = 0, spawnRate: Float = 0, acc: Float = 0
    private var phase: [Float] = []

    // 描くための値（体ごと。作った順）: 位置・角度・回っている絵のコマ
    private(set) var xs: [Float] = [], ys: [Float] = [], angles: [Float] = [], frames: [Int] = []
    var count: Int { xs.count }

    init(width: Float, height: Float, bill: Bool) {
        self.width = width; self.height = height; self.bill = bill
        var def = b2DefaultWorldDef()
        def.gravity = b2Vec2(x: 0, y: -CoinWorld.gravity)
        world = b2CreateWorld(&def)
        let r: Float = 0.06
        poly = b2MakeRoundedBox(CoinWorld.halfWidth(bill) - r, CoinWorld.halfHeight(bill) - r, r)
        // 壁: 左・右・底、投入口の上のふた。厚さ 1
        let top = height + CoinWorld.lidGap
        wall(-0.5, top / 2, 0.5, top / 2 + 1); wall(width + 0.5, top / 2, 0.5, top / 2 + 1)
        wall(width / 2, -0.5, width / 2 + 1, 0.5); wall(width / 2, top + 0.5, width / 2 + 1, 0.5)
        // 中身: よく止まり、少しだけはねる
        bodyDef.type = b2_dynamicBody
        shapeDef.material.friction = 0.6; shapeDef.material.restitution = 0.15; shapeDef.material.rollingResistance = 0.05
        shapeDef.density = 1
    }

    deinit { b2DestroyWorld(world) }

    private func wall(_ cx: Float, _ cy: Float, _ hx: Float, _ hy: Float) {
        var def = b2DefaultBodyDef()
        def.position = b2Vec2(x: cx, y: cy)
        let id = b2CreateBody(world, &def)
        var box = b2MakeBox(hx, hy)
        var sd = b2DefaultShapeDef()
        _ = b2CreatePolygonShape(id, &sd, &box)
    }

    // 0〜1 のばらつき（同じ番号なら毎回同じ。Android と同じ並びにする）
    private func hash(_ i: Int, _ salt: Int32) -> Float {
        var h = Int32(truncatingIfNeeded: i) &* 374761393 &+ salt &* 668265263
        h = (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 13)) &* 1274126177
        return Float((h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16)) & 0xFFFF) / 65535
    }

    private func create(_ x: Float, _ y: Float, _ vy: Float, _ spin: Float) {
        bodyDef.position = b2Vec2(x: x, y: y)
        bodyDef.linearVelocity = b2Vec2(x: 0, y: vy)
        bodyDef.angularVelocity = spin
        let id = b2CreateBody(world, &bodyDef)
        _ = b2CreatePolygonShape(id, &shapeDef, &poly)
        bodies.append(id)
    }

    // 入っている枚数をそろえる。増えた分は投入口から 1 枚ずつ落とし、減った分は上から取り出す
    func setCount(_ n: Int, animate: Bool) {
        let want = min(max(n, 0), CoinWorld.maxBodies)
        let have = bodies.count + pending
        if want > have {
            if animate { pending += want - have; spawnRate = max(Float(pending) / CoinWorld.spawnSeconds, 12) }
            else { fill(want - have) }
        } else if want < have {
            var drop = have - want
            let p = min(pending, drop); pending -= p; drop -= p
            for _ in 0..<drop {
                guard let top = bodies.indices.max(by: { b2Body_GetPosition(bodies[$0]).y < b2Body_GetPosition(bodies[$1]).y }) else { break }
                b2DestroyBody(bodies[top]); bodies.remove(at: top)
            }
            wakeAll()
        }
        if !animate { for _ in 0..<240 { b2World_Step(world, CoinWorld.stepTime, 4) } }
        sync(0)
    }

    // 動きなし: 下から段に並べて置き、物理で落ち着かせる
    private func fill(_ k: Int) {
        let hw = CoinWorld.halfWidth(bill), hh = CoinWorld.halfHeight(bill)
        let perRow = max(1, Int(width / (2 * hw + 0.02)))
        for _ in 0..<k {
            let i = bodies.count
            let row = i / perRow, col = i % perRow
            let shift = min(row % 2 == 1 ? hw * 0.5 : 0, max(0, width - Float(col + 1) * (2 * hw + 0.02)))
            create(hw + 0.01 + Float(col) * (2 * hw + 0.02) + shift, hh + 0.01 + Float(row) * (2 * hh + 0.02), 0, 0)
        }
    }

    // 端末の傾き（重力の向き）。少しでも変われば、止まっている中身も起こして転がす
    func setGravity(_ gx: Float, _ gy: Float) {
        let len = (gx * gx + gy * gy).squareRoot()
        guard len > 0.01 else { return }
        b2World_SetGravity(world, b2Vec2(x: gx / len * CoinWorld.gravity, y: gy / len * CoinWorld.gravity))
        wakeAll()
    }

    private func wakeAll() { for b in bodies { b2Body_SetAwake(b, true) } }

    // 時間を進める（画面のコマごと）。まだ動いているか、落とす予定があれば true
    @discardableResult
    func step(_ dt: Float) -> Bool {
        acc = min(acc + dt, CoinWorld.stepTime * 3)
        while acc >= CoinWorld.stepTime {
            acc -= CoinWorld.stepTime
            if pending > 0 {
                spawnClock += CoinWorld.stepTime * spawnRate
                while spawnClock >= 1 && pending > 0 {
                    spawnClock -= 1; pending -= 1
                    let i = spawned; spawned += 1
                    let hw = CoinWorld.halfWidth(bill)
                    create(hw + hash(i, 1) * (width - 2 * hw), height + 0.6 + hash(i, 2) * (CoinWorld.lidGap - 1.2), -6, (hash(i, 3) - 0.5) * 14)
                }
            }
            b2World_Step(world, CoinWorld.stepTime, 4)
        }
        sync(dt)
        return pending > 0 || b2World_GetAwakeBodyCount(world) > 0
    }

    private func sync(_ dt: Float) {
        let n = bodies.count
        if phase.count < n { phase += Array(repeating: 0, count: n - phase.count) }
        xs = Array(repeating: 0, count: n); ys = xs; angles = xs; frames = Array(repeating: 0, count: n)
        for i in 0..<n {
            let t = b2Body_GetTransform(bodies[i])
            xs[i] = t.p.x; ys[i] = t.p.y; angles[i] = atan2(t.q.s, t.q.c)
            let v = b2Body_GetLinearVelocity(bodies[i])
            let speed = (v.x * v.x + v.y * v.y).squareRoot()
            // 速く動いている間は、3D の絵を回して見せる（速さに合わせてコマを進める）。止まると置いた姿
            phase[i] += speed * dt * 1.1
            frames[i] = speed < 1.5 ? 0 : Int(phase[i]) % 8
        }
    }
}
