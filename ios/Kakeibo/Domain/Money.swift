import Foundation

// 金額は円の整数（Int64）。計算の正解はサーバー。ここは表示と入力中の確認のため（Android の Money.kt と同じ決まり）
enum Money {
    static let min: Int64 = 1
    static let max: Int64 = 999_999_999
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tokyo
        return c
    }

    static func todayJST() -> Date { calendar.startOfDay(for: Date()) }

    static func format(_ yen: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        let s = f.string(from: NSNumber(value: Swift.abs(yen))) ?? "\(Swift.abs(yen))"
        return (yen < 0 ? "−¥" : "¥") + s
    }

    // 全角数字・カンマ・¥・円を許す。整数でなければ nil
    static func parse(_ input: String) -> Int64? {
        let mapped = input.trimmingCharacters(in: .whitespaces).unicodeScalars.map { u -> Character in
            if (0xFF10...0xFF19).contains(u.value) { return Character(UnicodeScalar(u.value - 0xFF10 + 0x30)!) }
            return Character(u)
        }
        var t = String(mapped)
        for r in [",", "¥", "￥", "円"] { t = t.replacingOccurrences(of: r, with: "") }
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 12, t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int64(t)
    }

    // 均等割り: floor(金額 / 人数) を全員に。余りは並び（参加日時 → ID）の先頭から 1 円ずつ（サーバーの equal_split と同じ）
    static func equalSplit(_ amount: Int64, _ members: Int) -> [Int64] {
        precondition(members > 0)
        let base = amount / Int64(members)
        let rest = Int(amount % Int64(members))
        return (0..<members).map { base + ($0 < rest ? 1 : 0) }
    }

    // "YYYY-MM-DD"（日本時間）
    static func dateString(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func date(_ s: String) -> Date? {
        let p = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func monthStart(_ d: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: d))!
    }

    static func addMonths(_ d: Date, _ n: Int) -> Date { calendar.date(byAdding: .month, value: n, to: d)! }
    static func addDays(_ d: Date, _ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }

    static func monthLabel(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return "\(c.year!)年\(c.month!)月"
    }
}

enum Validate {
    static func amount(_ input: String) -> String? {
        guard let v = Money.parse(input) else { return "金額は 1 円以上の整数で入れてください" }
        if v < Money.min || v > Money.max { return "金額は 1〜999,999,999 円で入れてください" }
        return nil
    }
    static func date(_ d: Date?) -> String? {
        guard let d else { return "日付を選んでください" }
        let lower = Money.calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        if d < lower || d > Money.addDays(Money.todayJST(), 366) { return "日付が範囲外です" }
        return nil
    }
    static func memo(_ s: String) -> String? { s.count > 500 ? "メモは 500 文字までです" : nil }
    static func groupName(_ s: String) -> String? { (1...40).contains(trim(s).count) ? nil : "グループ名は 1〜40 文字で入れてください" }
    static func categoryName(_ s: String) -> String? { (1...20).contains(trim(s).count) ? nil : "カテゴリ名は 1〜20 文字で入れてください" }
    static func displayName(_ s: String) -> String? { (1...30).contains(trim(s).count) ? nil : "名前は 1〜30 文字で入れてください" }
    static func email(_ s: String) -> String? {
        trim(s).range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil ? "メールアドレスの形が正しくありません" : nil
    }
    static func password(_ s: String) -> String? { s.count < 8 ? "パスワードは 8 文字以上にしてください" : nil }
    static func customSplit(_ amount: Int64, _ shares: [Int64]) -> String? {
        if shares.contains(where: { $0 < 0 }) { return "分担はマイナスにできません" }
        let sum = shares.reduce(0, +)
        if sum != amount { return "分担の合計（\(Money.format(sum))）が金額と合いません" }
        return nil
    }
    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}
