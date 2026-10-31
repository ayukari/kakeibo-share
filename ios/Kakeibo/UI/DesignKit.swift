import SwiftUI
import UIKit

// かざすレシートの DESIGN.md と同じ決まり（Android の DesignKit.kt と同じ値）。
// 紙のような面・1px の線・点線の区切り・緑は「進む操作と今」だけ・赤は「こえた・取消」だけ。
// 文字は 12 / 14 / 16 / 20 / 28 / 44 の 6 段階、太さは 400 と 700（合計の金額だけ 800）。角丸は面 6pt・ボタン 10pt。
extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }

    static let kBg = Color(light: 0xE9EBEE, dark: 0x0E0F11)
    static let kCard = Color(light: 0xFCFCFA, dark: 0x1A1B1E)
    static let kInk = Color(light: 0x16181D, dark: 0xECEEF1)
    static let kSub = Color(light: 0x5B616B, dark: 0xA7ACB5)
    static let kFaint = Color(light: 0x646973, dark: 0x858B95)   // 灰色の背景でもコントラスト 4.5 以上（WCAG）
    static let kLine = Color(light: 0xCDD1D6, dark: 0x33363C)
    static let kAccent = Color(light: 0x0E7656, dark: 0x47C79B)
    static let kAccent2 = Color(light: 0xDCEFE7, dark: 0x16302A)
    static let kAccentInk = Color(light: 0xFFFFFF, dark: 0x05261B)
    static let kDanger = Color(light: 0xB42318, dark: 0xFF8A7A)

    // カテゴリの色（"#rrggbb"）。サーバーは小文字の 6 桁だけ受け付ける
    static func fromHex(_ s: String?) -> Color {
        guard let s, s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return Color(hex: 0x6B7280) }
        return Color(hex: v)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

let paperShape = RoundedRectangle(cornerRadius: 6)
let buttonShape = RoundedRectangle(cornerRadius: 10)

// 紙の面（枠は影ではなく 1px の線）
struct Paper<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kCard, in: paperShape)
            .overlay(paperShape.stroke(Color.kLine, lineWidth: 1))
    }
}

// 行が並ぶ面。行と行のあいだは点線（呼ぶ側が DashedLine を入れる）
struct ListPaper<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kCard, in: paperShape)
            .overlay(paperShape.stroke(Color.kLine, lineWidth: 1))
            .clipShape(paperShape)
    }
}

struct DashedLine: View {
    var body: some View {
        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 4000, y: 0)) }
            .stroke(Color.kLine, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            .frame(height: 1).clipped()
    }
}

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 12)).foregroundStyle(Color.kFaint) }
        }.padding(.horizontal, 2).padding(.top, 24).padding(.bottom, 8)
    }
}

struct SubText: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.system(size: 14)).foregroundStyle(Color.kSub) }
}
struct FaintText: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(Color.kFaint) }
}

struct BigYen: View {
    let yen: Int64
    var size: CGFloat = 44
    var color: Color = .kInk
    var body: some View {
        Text(Money.format(yen)).font(.system(size: size, weight: .heavy)).monospacedDigit().foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}

struct KeyValue: View {
    let key: String
    let value: String
    var first = false
    var valueColor: Color = .kInk
    var body: some View {
        VStack(spacing: 0) {
            if !first { DashedLine() }
            HStack { Text(key).font(.system(size: 14)).foregroundStyle(Color.kSub); Spacer(); Text(value).font(.system(size: 16, weight: .bold)).monospacedDigit().foregroundStyle(valueColor) }
                .padding(.vertical, 8)
        }
    }
}

// カテゴリの色の丸（色は点・棒・アイコンだけ。文字には使わない）。中は名前の頭の 1 文字
// カテゴリの色の丸。中はカテゴリの絵文字（なければ名前の頭の 1 文字）
struct CategoryDot: View {
    let name: String?
    let colorHex: String?
    var size: CGFloat = 40
    var icon: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(Color.fromHex(colorHex))
            if size >= 20 {
                if let icon, !icon.trimmingCharacters(in: .whitespaces).isEmpty { Text(icon).font(.system(size: size * 0.5)) }
                else { Text(String((name ?? "?").prefix(1))).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white) }
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

// 1 行（カテゴリの丸・題・補足・右に金額）。押せる行は高さ 56pt 以上
struct ItemRow: View {
    let title: String
    let sub: String
    let amount: String
    let catName: String?
    let catColor: String?
    var amountColor: Color = .kInk
    var catIcon: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            CategoryDot(name: catName, colorHex: catColor, icon: catIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).lineLimit(1)
                Text(sub).font(.system(size: 12)).foregroundStyle(Color.kFaint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amount).font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundStyle(amountColor).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// 進み具合の棒。tick は「今日までの目安」の位置（0...1）
struct Meter: View {
    let ratio: Double
    var color: Color = .kAccent
    var tick: Double? = nil
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.kLine)
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: g.size.width * min(max(ratio, 0), 1))
                if let tick { Rectangle().fill(Color.kInk.opacity(0.35)).frame(width: 2, height: 12).offset(x: g.size.width * min(max(tick, 0), 1) - 1) }
            }
        }.frame(height: 8)
    }
}

// カテゴリの横棒。total を渡すと、全体に占める割合（%）も出す
struct CategoryBar: View {
    let name: String
    let colorHex: String?
    let amount: Int64
    let max: Int64
    var icon: String? = nil
    var total: Int64? = nil
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                CategoryDot(name: name, colorHex: colorHex, size: 26, icon: icon)
                Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kInk).lineLimit(1)
            }.frame(width: 112, alignment: .leading)
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 2).fill(Color.fromHex(colorHex))
                    .frame(width: g.size.width * CGFloat(Swift.max(0.015, Double(amount) / Double(Swift.max(max, 1)))), height: 12)
                    .frame(maxHeight: .infinity, alignment: .center)
            }.frame(height: 12)
            if let total, total > 0 { Text("\(Int((Double(amount) * 100 / Double(total)).rounded()))%").font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.kSub) }
            Text(Money.format(amount)).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(Color.kInk).lineLimit(1).frame(minWidth: 84, alignment: .trailing)
        }.frame(minHeight: 44).accessibilityElement(children: .combine)
    }
}

// 切り替え（黒い印字のつまみ）。かざすレシートの .tabs と同じ
struct Segmented: View {
    let options: [String]
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { selected = i } label: {
                    Text(options[i]).font(.system(size: 14, weight: .bold)).foregroundStyle(i == selected ? Color.kCard : Color.kSub)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(i == selected ? Color.kInk : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(i == selected ? .isSelected : [])
            }
        }.padding(3).background(Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
    }
}

// 画面の地（レジ台のような冷たい灰色）。Form や List の標準の地を置き換える
extension View {
    func kakeiboBackground() -> some View { self.scrollContentBackground(.hidden).background(Color.kBg) }
}
