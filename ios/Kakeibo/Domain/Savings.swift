import Foundation

// 貯金の言葉と節目（Android の Savings.kt と同じ決まり）。数字の計算はサーバー（savings_status）
enum Savings {
    static let kindNames = ["manual": "預入", "tsumori": "つもり貯金", "leftover": "予算の余り", "auto": "先取り"]
    private static let pct = [25: "4 分の 1", 50: "半分", 75: "4 分の 3", 100: "目標"]

    // "2026-10-01" → "2026年10月"
    static func yyyymm(_ month: String?) -> String {
        guard let m = month, m.count >= 7, let y = Int(m.prefix(4)), let mo = Int(m.dropFirst(5).prefix(2)) else { return "" }
        return "\(y)年\(mo)月"
    }

    static func domLabel(_ dom: Int?) -> String { dom == 99 ? "月末" : "\(dom ?? 0)日" }

    // 進み具合のひとこと
    static func pace(_ g: SavingsGoal, _ s: SavingsStatus) -> String {
        if s.done { return "目標に届きました。" }
        if s.overdue { return "期限（\(yyyymm(g.dueMonth))）をすぎています。" }
        if let per = s.perMonth {
            var t = "\(yyyymm(g.dueMonth))までに毎月 \(Money.format(per))"
            if let a = g.autoAmount { t += s.onTrack == true ? "・先取りで届きます" : "・先取りでは \(Money.format(per - a)) 足りません" }
            return t
        }
        var t = "あと \(Money.format(s.remaining))"
        if let a = g.autoAmount { t += "・毎月\(domLabel(g.autoDom))に \(Money.format(a)) 先取り" }
        return t
    }

    struct Milestone: Equatable {
        let pct: Int
        let day: String
        let thisMonth: Bool
        var text: String { "今月、\(Savings.pct[pct] ?? "")\(pct == 100 ? "に届きました" : "まで来ました")（\(pct)%）。" }
    }

    // いちばん新しく越えた節目（25・50・75・100%）と、それが今月か。rows はその目標の通帳（日付順）
    static func milestone(target: Int64, rows: [PassbookRow], today: Date) -> Milestone? {
        var bal: Int64 = 0
        var hit: (Int, String)? = nil
        for r in rows {
            let before = bal; bal += r.amount
            for p in [25, 50, 75, 100] where before * 100 < target * Int64(p) && bal * 100 >= target * Int64(p) { hit = (p, r.day) }
        }
        guard let hit else { return nil }
        let cur = String(Money.dateString(today).prefix(7))
        return Milestone(pct: hit.0, day: hit.1, thisMonth: hit.1.hasPrefix(cur))
    }

    // 生活防衛資金の目安: 直近の月（記録がある月、最大 3 か月）の支出の平均 × 3、1 万円単位に切り上げ
    static func emergencyTarget(_ monthlyExpense: [Int64]) -> (avg: Int64, target: Int64)? {
        let ms = Array(monthlyExpense.filter { $0 > 0 }.suffix(3))
        if ms.isEmpty { return nil }
        let avg = Int64((Double(ms.reduce(0, +)) / Double(ms.count)).rounded())
        return (avg, Int64((Double(avg) * 3 / 10000).rounded(.up)) * 10000)
    }

    // 予算の余り（カテゴリの予算、なければ全体の予算の残り）。余りがなければ nil
    // 翌月に繰り越す予算の余りは、貯金に回さない（二重に使わないため）
    static func leftover(_ budgets: [BudgetStatus]) -> Int64? {
        let cat = budgets.filter { $0.scope == "group" && $0.categoryId != nil && !$0.rolls }
        let rows = cat.isEmpty ? budgets.filter { $0.scope == "group" && $0.categoryId == nil && !$0.rolls } : cat
        if rows.isEmpty { return nil }
        let left = rows.reduce(Int64(0)) { $0 + $1.amount } - rows.reduce(Int64(0)) { $0 + $1.spent }
        return left > 0 ? left : nil
    }

    // 貯金箱の中身。貯まった額で、硬貨からお札に変わっていく（目標の大きさにかかわらず同じ段階）
    struct Coin: Hashable { let name: String; let short: String; let from: Int64; let bill: Bool; let face: Int64 }
    static let coins = [
        Coin(name: "10円玉", short: "10円", from: 0, bill: false, face: 10), Coin(name: "100円玉", short: "100円", from: 10_000, bill: false, face: 100),
        Coin(name: "500円玉", short: "500円", from: 30_000, bill: false, face: 500), Coin(name: "千円札", short: "千円札", from: 100_000, bill: true, face: 1_000),
        Coin(name: "1万円札", short: "万札", from: 500_000, bill: true, face: 10_000),
    ]
    static func coinIndex(_ saved: Int64) -> Int { max(0, coins.lastIndex { saved >= $0.from } ?? 0) }
    // 箱に入れる枚数（貯金額をその段階の額面で割った数。2 万円なら 100円玉 200 枚）と、額面に満たない端数
    static func coinCount(_ saved: Int64) -> Int64 { max(0, saved) / coins[coinIndex(saved)].face }
    static func coinRemainder(_ saved: Int64) -> Int64 { max(0, saved) % coins[coinIndex(saved)].face }
    // 目標額ちょうどの枚数（箱がいっぱいになる枚数）。中身の大きさを決めるのに使う
    static func coinCapacity(_ saved: Int64, _ target: Int64) -> Int64 { max(1, target / coins[coinIndex(saved)].face) }

    // 次の段階と、そこまでの残り（いちばん上なら nil）
    static func nextCoin(_ saved: Int64) -> (coin: Coin, left: Int64)? {
        let i = coinIndex(saved) + 1
        return i < coins.count ? (coins[i], coins[i].from - saved) : nil
    }
}
