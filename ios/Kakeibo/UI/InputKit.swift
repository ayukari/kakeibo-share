import SwiftUI

// 入力の部品（上位の家計簿アプリと同じ作り: 日付の左右の矢印・大きな金額・電卓のキー・カテゴリのタイル）

// 日付: ‹ 10月30日(木) ›。真ん中を押すと日付を選べる
struct DateStepper: View {
    @Binding var date: Date
    @State private var picking = false
    private let dow = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        let c = Money.calendar.dateComponents([.month, .day, .weekday], from: date)
        let isToday = Money.calendar.isDate(date, inSameDayAs: Money.todayJST())
        HStack {
            square("前の日", "chevron.left") { date = Money.addDays(date, -1) }
            Button { picking = true } label: {
                Text("\(c.month!)月\(c.day!)日(\(dow[c.weekday! - 1]))" + (isToday ? "・今日" : "")).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).accessibilityHint("押すと日付を選べます")
            square("次の日", "chevron.right") { date = Money.addDays(date, 1) }
        }
        .sheet(isPresented: $picking) {
            DatePicker("日付", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).environment(\.timeZone, Money.tokyo).padding().presentationDetents([.medium])
        }
    }

    private func square(_ label: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.kInk).frame(width: 44, height: 44)
                .background(Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

// 大きな金額の表示（式があれば下に「= 計算結果」）
struct AmountDisplay: View {
    let expr: String
    let error: String?
    var body: some View {
        let v = Calc.evaluate(expr)
        VStack(alignment: .trailing, spacing: 2) {
            Text(expr.isEmpty ? "¥0" : "¥" + pretty(expr)).font(.system(size: 34, weight: .heavy)).monospacedDigit().foregroundStyle(expr.isEmpty ? Color.kFaint : Color.kInk).lineLimit(1).minimumScaleFactor(0.5)
            if Calc.hasOperator(expr), let v { Text("= \(Money.format(v))").font(.system(size: 16)).foregroundStyle(Color.kSub) }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Color.kDanger) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.kCard, in: paperShape).overlay(paperShape.stroke(error != nil ? Color.kDanger : Color.kLine, lineWidth: error != nil ? 2 : 1))
        .accessibilityElement(children: .combine).accessibilityLabel("金額 \(v.map { Money.format($0) } ?? "未入力")").accessibilityIdentifier("amount")
    }

    private func pretty(_ expr: String) -> String {
        var out = "", num = ""
        func flush() { if let n = Int64(num) { out += Money.format(n).replacingOccurrences(of: "¥", with: "") } else { out += num }; num = "" }
        for c in expr { if c.isNumber { num.append(c) } else { flush(); out.append(c) } }
        flush()
        return out
    }
}

// 電卓のキー（4 列 × 5 段）
struct CalcKeypad: View {
    let onKey: (String) -> Void
    private let rows = [["7", "8", "9", "÷"], ["4", "5", "6", "×"], ["1", "2", "3", "−"], ["0", "00", "⌫", "+"], ["C", "="]]
    private let names = ["⌫": "1 文字消す", "C": "全部消す", "÷": "割る", "×": "掛ける", "−": "引く", "+": "足す", "=": "計算する"]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { k in
                        let op = ["÷", "×", "−", "+", "="].contains(k)
                        Button { onKey(k) } label: {
                            Text(k).font(.system(size: 20, weight: .bold)).foregroundStyle(k == "=" ? Color.kCard : Color.kInk).frame(maxWidth: .infinity, minHeight: 48)
                                .background(k == "=" ? Color.kInk : op ? Color.kAccent2 : Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(names[k] ?? k).accessibilityIdentifier("key_\(k)")
                    }
                }
            }
        }
    }
}

// カテゴリのタイル（4 列。色の丸と名前。選ぶと黒い枠）
struct CategoryGrid: View {
    let cats: [Category]
    @Binding var selected: String?
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(cats) { c in
                let on = selected == c.id
                Button { selected = c.id } label: {
                    VStack(spacing: 4) {
                        CategoryDot(name: c.name, colorHex: c.color, size: 30, icon: c.icon)
                        Text(c.name).font(.system(size: 12, weight: on ? .bold : .regular)).foregroundStyle(Color.kInk).lineLimit(1)
                    }.frame(maxWidth: .infinity, minHeight: 72)
                        .background(on ? Color.kAccent2 : Color.kCard, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.kInk : Color.kLine, lineWidth: on ? 2 : 1))
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("cat_\(c.name)")
            }
        }
    }
}

// カテゴリの内訳のドーナツ（色はカテゴリの色。真ん中に合計）
struct DonutSlice: Hashable { let label: String; let colorHex: String?; let amount: Int64 }

struct Donut: View {
    let slices: [DonutSlice]
    let centerLabel: String
    let centerValue: Int64
    var body: some View {
        let total = Double(max(1, slices.reduce(Int64(0)) { $0 + $1.amount }))
        ZStack {
            Canvas { c, size in
                let lw: CGFloat = 34
                let r = min(size.width, size.height) / 2 - lw / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var start = -90.0
                for s in slices {
                    let sweep = 360 * Double(s.amount) / total
                    var p = Path(); p.addArc(center: center, radius: r, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
                    c.stroke(p, with: .color(Color.fromHex(s.colorHex)), lineWidth: lw)
                    if slices.count > 1 {
                        var g = Path(); g.addArc(center: center, radius: r, startAngle: .degrees(start + sweep - 0.6), endAngle: .degrees(start + sweep + 0.6), clockwise: false)
                        c.stroke(g, with: .color(.kCard), lineWidth: lw + 2)
                    }
                    start += sweep
                }
            }.frame(width: 180, height: 180)
            VStack(spacing: 2) {
                Text(centerLabel).font(.system(size: 12)).foregroundStyle(Color.kSub)
                Text(Money.format(centerValue)).font(.system(size: 20, weight: .heavy)).monospacedDigit().foregroundStyle(Color.kInk)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(centerLabel) \(Money.format(centerValue)) の内訳の円グラフ。数字は下の一覧にあります")
    }
}
