import XCTest
@testable import Kakeibo

// 貯金箱の物理（Box2D）: 落ちきって止まること・全部が箱の中にあること・枚数が貯金額どおりなこと（Android の physicspreview と同じ確かめ）
final class PhysicsTests: XCTestCase {
    private func settle(_ bill: Bool, count: Int, capacity: Double) -> CoinWorld {
        let w: Float = 318, h: Float = 120
        let d = min(max((w * h * 0.92 / (Float(capacity) * CoinWorld.areaPerItem(bill))).squareRoot(), bill ? 9 : 6), 26)
        let world = CoinWorld(width: w / d, height: h / d, bill: bill)
        world.setCount(count, animate: true)
        var t: Float = 0, moving = true
        while moving && t < 15 {
            moving = world.step(1.0 / 60); t += 1.0 / 60
            for i in 0..<world.count {
                XCTAssert(world.xs[i] > -0.1 && world.xs[i] < world.width + 0.1)
                XCTAssert(world.ys[i] > -0.1 && world.ys[i] < world.height + CoinWorld.lidGap + 0.1)
            }
        }
        XCTAssertFalse(moving, "15 秒たっても止まらない")
        XCTAssertEqual(world.count, count)
        XCTAssertLessThanOrEqual(world.ys.max() ?? 0, world.height + 0.2, "箱からあふれた")
        return world
    }

    func testCoinsSettle() {   // 2 万円（目標 10 万円）: 100円玉 200 枚
        let w = settle(false, count: 200, capacity: 1000)
        XCTAssertLessThan((w.ys.max() ?? 0) / w.height, 0.4)
    }

    func testBillsSettle() { _ = settle(true, count: 200, capacity: 250) }

    func testWithdrawRemovesFromTop() {
        let w = settle(false, count: 120, capacity: 240)
        w.setCount(100, animate: true)
        XCTAssertEqual(w.count, 100)
    }
}
