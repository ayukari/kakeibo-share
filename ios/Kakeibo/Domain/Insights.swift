import Foundation

// ホームのペースの線などの計算（Android の Insights.kt と同じ決まり）。
// 「ふだんの支出」= 公開範囲がグループの支出のうち、定期的な収支（固定費）から作られたものを除く
enum Insights {
    // 年月（その月の 1 日）
    static func lengthOfMonth(_ month: Date) -> Int { Money.calendar.range(of: .day, in: .month, for: month)!.count }

    private static func inMonth(_ t: Txn, _ month: Date) -> Bool {
        let c = Money.calendar.dateComponents([.year, .month], from: month)
        return t.occurredOn.hasPrefix(String(format: "%04d-%02d", c.year!, c.month!))
    }
    private static func isExpense(_ t: Txn) -> Bool { t.kind == "expense" && t.status == "active" && t.visibility == "group" }
    private static func day(_ t: Txn) -> Int? { Int(t.occurredOn.dropFirst(8).prefix(2)) }

    // その月の 1 日から月末までの、ふだんの支出の累計（日ごと）
    static func variableCumulative(_ txns: [Txn], month: Date) -> [Int64] {
        var days = [Int64](repeating: 0, count: lengthOfMonth(month))
        for t in txns where isExpense(t) && t.recurringId == nil && inMonth(t, month) {
            if let d = day(t), d >= 1, d <= days.count { days[d - 1] += t.amount }
        }
        for i in days.indices.dropFirst() { days[i] += days[i - 1] }
        return days
    }

    // 固定費（定期的な収支から作られた支出）の合計
    static func fixedTotal(_ txns: [Txn], month: Date) -> Int64 {
        txns.filter { isExpense($0) && $0.recurringId != nil && inMonth($0, month) }.reduce(0) { $0 + $1.amount }
    }

    // その月の、今日を含む残りの日数（過去の月は 0、先の月は月の日数）
    static func daysLeft(month: Date, today: Date) -> Int {
        let cur = Money.monthStart(today), m = Money.monthStart(month)
        if m == cur { return lengthOfMonth(m) - Money.calendar.component(.day, from: today) + 1 }
        return m > cur ? lengthOfMonth(m) : 0
    }

    // 1 日あたり使える額（残りがあって、日が残っているときだけ）
    static func perDay(left: Int64, daysLeft: Int) -> Int64 { daysLeft > 0 && left > 0 ? left / Int64(daysLeft) : 0 }

    // 予算の目安の線（毎日同じだけ使う場合の累計）
    static func idealLine(varBudget: Int64, len: Int) -> [Int64]? {
        varBudget > 0 ? (0..<len).map { Int64((Double(varBudget) * Double($0 + 1) / Double(len)).rounded()) } : nil
    }

    // 日ごとの支出の合計（カレンダー用。公開範囲がグループの支出）
    static func dailyExpense(_ txns: [Txn], month: Date) -> [Int64] {
        var days = [Int64](repeating: 0, count: lengthOfMonth(month))
        for t in txns where isExpense(t) && inMonth(t, month) {
            if let d = day(t), d >= 1, d <= days.count { days[d - 1] += t.amount }
        }
        return days
    }

    // カレンダーの濃さの 5 段階（0 = なし、1〜4 = 少し〜多い）
    static func step(_ v: Int64, max: Int64) -> Int {
        if v <= 0 || max <= 0 { return 0 }
        let r = Double(v) / Double(max)
        return r <= 0.25 ? 1 : r <= 0.5 ? 2 : r <= 0.75 ? 3 : 4
    }

    // 金額の短い表記（1 万円以上は千円単位の k）
    static func short(_ v: Int64) -> String {
        if v >= 10_000 { return "\(Int((Double(v) / 1000).rounded()))k" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}
