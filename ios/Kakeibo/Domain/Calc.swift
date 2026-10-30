import Foundation

// 電卓つきキーボードの計算（Android の Calc.kt と同じ決まり）。
// 円の整数。× ÷ を先に計算し、途中の割り算は小数のまま、最後に四捨五入する。式がおかしければ nil
enum Calc {
    static func evaluate(_ expr: String) -> Int64? {
        let s = expr.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        var nums: [Double] = []
        var ops: [Character] = []
        var cur = ""
        for c in s {
            if c.isASCII && c.isNumber { cur.append(c) }
            else if "+-*/".contains(c) {
                if cur.isEmpty { return nil }
                nums.append(Double(cur)!); ops.append(c); cur = ""
            } else { return nil }
        }
        if cur.isEmpty {   // 最後が記号なら、その記号は無視する（「1200+」→ 1200）
            if ops.isEmpty { return nil }
            ops.removeLast()
        } else { nums.append(Double(cur)!) }
        var n2: [Double] = [nums[0]]
        var o2: [Character] = []
        for (i, op) in ops.enumerated() {
            let b = nums[i + 1]
            switch op {
            case "*": n2[n2.count - 1] *= b
            case "/": if b == 0 { return nil }; n2[n2.count - 1] /= b
            default: o2.append(op); n2.append(b)
            }
        }
        var r = n2[0]
        for (i, op) in o2.enumerated() { r = op == "+" ? r + n2[i + 1] : r - n2[i + 1] }
        if r.isNaN || r.isInfinite || r > 9.99e11 { return nil }
        return Int64(r.rounded())
    }

    static func hasOperator(_ expr: String) -> Bool { expr.contains { "+-*/×÷−".contains($0) } }

    // キーを押したときの次の式。key は "0".."9" / "00" / "+" "−" "×" "÷" / "⌫" / "C" / "="
    static func press(_ expr: String, _ key: String) -> String {
        let ops = "+−×÷"
        switch key {
        case "C": return ""
        case "⌫": return String(expr.dropLast())
        case "=": if let v = evaluate(expr), v >= 0 { return String(v) }; return expr
        case "+", "−", "×", "÷":
            guard let last = expr.last else { return expr }
            return ops.contains(last) ? String(expr.dropLast()) + key : expr + key
        case "00":
            guard let last = expr.last, !ops.contains(last) else { return expr }
            return String((expr + "00").prefix(16))
        default:
            return expr == "0" ? key : String((expr + key).prefix(16))
        }
    }

    // 割合（%）で分けた金額。端数の円は、並びの先頭から 1 円ずつ。合計が 100 でなければ nil
    // 比で分ける（60:40 の % でも、2:1:1 の口数でもよい）。割り切れない 1 円は前の人から
    static func ratioSplit(_ amount: Int64, _ percents: [Int]) -> [Int64]? {
        let sum = percents.reduce(0, +)
        if percents.isEmpty || percents.contains(where: { $0 < 0 }) || sum <= 0 { return nil }
        let base = percents.map { amount * Int64($0) / Int64(sum) }
        var rest = amount - base.reduce(0, +)
        return base.enumerated().map { i, b in
            if rest > 0 && percents[i] > 0 { rest -= 1; return b + 1 }
            return b
        }
    }
}
