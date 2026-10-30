import SwiftUI

// ---------- 貯金（かざすレシートの「貯金」と同じ: 合計 → 目標の封筒 → 1 年のグラフ → 通帳） ----------
struct SavingsData {
    let goals: [SavingsGoal]
    let status: [SavingsStatus]
    let passbook: [PassbookRow]
    let series: [SavingsPoint]
    let income: Int64
    let monthlyExpense: [Int64]
}

// 記録する画面を開く合図（目標・種類・向き）
struct SaveIntent: Identifiable {
    let id = UUID()
    let goalId: String?
    let kind: String
    let dir: Int
}

struct SavingsView: View {
    let ctx: GroupCtx
    @State private var state: Loadable<SavingsData> = .loading
    @State private var saveIntent: SaveIntent?
    @State private var pbGoal: String?
    @State private var pbRows = 20
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LoadableView(state: state, retry: load) { d in
                    SavingsContent(ctx: ctx, d: d, today: Money.todayJST(), onSave: { saveIntent = $0 }, pbGoal: $pbGoal, pbRows: $pbRows)
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.kBg)
        .task(id: ctx.refresh) { await load() }
        .refreshable { await load() }
        .toast($message)
        .sheet(item: $saveIntent) { si in
            if case .ready(let d) = state {
                NavigationStack { SaveSheet(ctx: ctx, goals: d.goals, intent: si) { msg in saveIntent = nil; if let msg { message = msg; Task { await load() } } } }
            }
        }
    }

    private func load() async {
        do {
            let today = Money.todayJST()
            state = .ready(SavingsData(goals: try await ctx.repo.goals(ctx.g), status: try await ctx.repo.savingsStatus(ctx.g), passbook: try await ctx.repo.passbook(ctx.g),
                                       series: try await ctx.repo.savingsSeries(ctx.g, end: today), income: try await ctx.repo.monthSummary(ctx.g, today).income,
                                       monthlyExpense: try await ctx.repo.monthlySeries(ctx.g, end: Money.addMonths(today, -1)).map(\.expense)))
        } catch { state = .failed(Repo.map(error)) }
    }
}

// 貯金の中身（読み込んだデータから描く）
struct SavingsContent: View {
    let ctx: GroupCtx
    let d: SavingsData
    let today: Date
    let onSave: (SaveIntent) -> Void
    @Binding var pbGoal: String?
    @Binding var pbRows: Int

    var body: some View {
        if d.goals.isEmpty { SavingsEmpty(ctx: ctx, d: d) }
        else {
            let total = d.status.reduce(Int64(0)) { $0 + $1.saved }
            let monthKey = String(Money.dateString(today).prefix(7))
            let thisMonth = d.passbook.filter { $0.day.hasPrefix(monthKey) }.reduce(Int64(0)) { $0 + $1.amount }
            let main = d.goals.first(where: { $0.isMain })?.id ?? d.goals[0].id
            Paper {
                Text("貯金の合計").font(.system(size: 14)).foregroundStyle(Color.kSub)
                BigYen(yen: total)
                SubText("今月 \(thisMonth > 0 ? "+" : "")\(Money.format(thisMonth))" + (d.income > 0 && thisMonth > 0 ? "・収入の \(Int((Double(thisMonth) * 100 / Double(d.income)).rounded()))%" : ""))
                if ctx.can("member") {
                    HStack(spacing: 6) {
                        actionButton("貯金した", primary: true) { onSave(SaveIntent(goalId: main, kind: "manual", dir: 1)) }
                        actionButton("取り崩した") { onSave(SaveIntent(goalId: main, kind: "manual", dir: -1)) }
                        actionButton("つもり貯金") { onSave(SaveIntent(goalId: main, kind: "tsumori", dir: 1)) }
                    }.padding(.top, 12)
                }
            }
            SectionLabel(text: "目標", trailing: "\(d.goals.count) 件")
            VStack(spacing: 10) {
                ForEach(d.goals.sorted { $0.isMain && !$1.isMain }) { g in
                    if let s = d.status.first(where: { $0.goalId == g.id }) {
                        Envelope(ctx: ctx, g: g, s: s, rows: d.passbook.filter { $0.goalId == g.id }, today: today, onRecord: { onSave(SaveIntent(goalId: g.id, kind: "manual", dir: 1)) })
                    }
                }
            }
            if d.goals.count < 10 && ctx.can("member") {
                NavigationLink { GoalView(ctx: ctx, goal: nil) } label: {
                    Text("＋ 目標を作る").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                }.buttonStyle(.plain).padding(.top, 10)
            }
            if d.series.contains(where: { $0.deposit > 0 || $0.withdrawal > 0 }) {
                SectionLabel(text: "この 1 年の貯金")
                Paper { SavingsChart(series: d.series) }
            }
            PassbookView(d: d, goalId: $pbGoal, shownRows: $pbRows)
        }
    }

    private func actionButton(_ title: String, primary: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(primary ? Color.kAccentInk : Color.kInk).frame(maxWidth: .infinity, minHeight: 48)
                .background(primary ? Color.kAccent : Color.kCard, in: buttonShape).overlay(buttonShape.stroke(primary ? Color.clear : Color.kLine, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// 目標がまだないとき: ひな形（もしものとき・旅行・家電・帰省）と、自分で作る
struct SavingsEmpty: View {
    let ctx: GroupCtx
    let d: SavingsData
    var body: some View {
        let em = Savings.emergencyTarget(d.monthlyExpense)
        let tpl: [(String, Int64?, String)] = [
            ("もしものとき", em?.target ?? 300000, em.map { "月の支出の平均 \(Money.format($0.avg)) × 3 か月" } ?? "生活費の 3〜6 か月分が目安"),
            ("旅行", nil, "行き先や時期を名前に入れると続きやすい"),
            ("家電の買い替え", nil, "冷蔵庫・スマホ・パソコンなど"),
            ("帰省・イベント", nil, "年末年始・お祝いなど"),
        ]
        Paper {
            Text("貯金を始めましょう").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.kInk)
            SubText("貯める目的に名前を付けて、目標の金額を決めます。目的ごとに分けると、使わずに貯まりやすくなります。記録は通帳のように残ります。").padding(.top, 6)
            if ctx.can("member") {
                VStack(spacing: 8) {
                    ForEach(tpl, id: \.0) { t in
                        NavigationLink { GoalView(ctx: ctx, goal: nil, presetName: t.0, presetTarget: t.1) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(t.0).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk); FaintText(t.2) }
                                Spacer()
                                if let v = t.1 { Text(Money.format(v)).font(.system(size: 14)).foregroundStyle(Color.kSub) }
                            }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56)
                                .background(Color.kCard, in: buttonShape).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 12)
                NavigationLink { GoalView(ctx: ctx, goal: nil) } label: {
                    Text("自分で目標を作る").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kAccentInk).frame(maxWidth: .infinity, minHeight: 52).background(Color.kAccent, in: buttonShape)
                }.buttonStyle(.plain).padding(.top, 12)
            } else { FaintText("目標を作れるのはメンバー以上です").padding(.top, 8) }
        }
        FaintText("ここは記録です。お金を実際に移すのは、銀行の自動積立・自動振替などで行ってください。").padding(.horizontal, 4).padding(.top, 12)
    }
}

// 目標の封筒（上辺に封のかぶせの線）。中に貯金箱（貯まった額で硬貨からお札に変わる。CoinBox.swift）
struct Envelope: View {
    let ctx: GroupCtx
    let g: SavingsGoal
    let s: SavingsStatus
    let rows: [PassbookRow]
    let today: Date
    let onRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: geo.size.width / 2, y: 12)); p.addLine(to: CGPoint(x: geo.size.width, y: 0)) }
                    .stroke(Color.kLine, lineWidth: 1)
            }.frame(height: 12)
            HStack(spacing: 6) {
                Text(g.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).lineLimit(1)
                if g.isMain { Text("いちばん大事").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.kInk).padding(.horizontal, 6).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.kInk, lineWidth: 1)) }
                if g.visibility == "private" { FaintText("自分だけ") }
                Spacer()
                Text("\(Int((s.ratio * 100).rounded()))%").font(.system(size: 14)).foregroundStyle(Color.kSub)
            }.padding(.top, 4)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(Money.format(s.saved)).font(.system(size: 24, weight: .heavy)).monospacedDigit().foregroundStyle(Color.kInk)
                Text(" / \(Money.format(g.target))").font(.system(size: 14)).foregroundStyle(Color.kSub)
            }
            CoinBox(name: g.name, saved: s.saved, target: g.target).padding(.top, 10)
            CoinSteps(saved: s.saved, done: s.done)
            SubText(Savings.pace(g, s)).padding(.top, 8)
            if let ms = Savings.milestone(target: g.target, rows: rows, today: today), ms.thisMonth {
                Text(ms.text).font(.system(size: 14)).foregroundStyle(Color.kInk).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.kBg, in: paperShape).padding(.top, 10)
            }
            HStack(spacing: 8) {
                if ctx.can("member") {
                    Button(action: onRecord) {
                        Text("記録する").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 44).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                NavigationLink { GoalView(ctx: ctx, goal: g) } label: {
                    Text("直す・記録を見る").font(.system(size: 14)).foregroundStyle(Color.kSub).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
            }.padding(.top, 10)
        }
        .padding(.horizontal, 16).padding(.bottom, 14)
        .background(Color.kCard, in: paperShape).overlay(paperShape.stroke(Color.kLine, lineWidth: 1))
    }
}

// 12 か月の貯金（預け入れ・引き出し）
struct SavingsChart: View {
    let series: [SavingsPoint]
    var body: some View {
        let mx = max(1, series.map { max($0.deposit, $0.withdrawal) }.max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            Canvas { c, size in
                let gw = size.width / CGFloat(series.count), bw = min(10, (gw - 4) / 2)
                func h(_ v: Int64) -> CGFloat { size.height * CGFloat(v) / CGFloat(mx) }
                var axis = Path(); axis.move(to: CGPoint(x: 0, y: size.height)); axis.addLine(to: CGPoint(x: size.width, y: size.height))
                c.stroke(axis, with: .color(.kLine), lineWidth: 1)
                for (i, m) in series.enumerated() {
                    let x = gw * CGFloat(i) + gw / 2
                    if m.deposit > 0 { c.fill(Path(roundedRect: CGRect(x: x - bw - 1, y: size.height - h(m.deposit), width: bw, height: h(m.deposit)), cornerRadius: 1), with: .color(.kAccent)) }
                    if m.withdrawal > 0 { c.fill(Path(roundedRect: CGRect(x: x + 1, y: size.height - h(m.withdrawal), width: bw, height: h(m.withdrawal)), cornerRadius: 1), with: .color(Color.kDanger.opacity(0.75))) }
                }
            }.frame(height: 110).accessibilityLabel("12 か月の貯金")
            HStack(spacing: 0) {
                ForEach(Array(series.enumerated()), id: \.offset) { i, m in
                    Text(i % 2 == series.count % 2 ? "" : "\(Int(m.month.dropFirst(5).prefix(2)) ?? 0)月").font(.system(size: 10)).foregroundStyle(Color.kFaint).frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Color.kAccent).frame(width: 8, height: 8); Text("預け入れ").font(.system(size: 12)).foregroundStyle(Color.kSub)
                if series.contains(where: { $0.withdrawal > 0 }) { RoundedRectangle(cornerRadius: 2).fill(Color.kDanger).frame(width: 8, height: 8).padding(.leading, 8); Text("引き出し").font(.system(size: 12)).foregroundStyle(Color.kSub) }
            }.padding(.top, 4)
        }
    }
}

// 通帳: 日付順で、いちばん新しい行が下（本物の通帳と同じ）。上の行に年月日・お引出し・お預入れ・差引残高、下の行に摘要
struct PassbookView: View {
    let d: SavingsData
    @Binding var goalId: String?
    @Binding var shownRows: Int

    var body: some View {
        let rows: [PassbookRow] = {
            guard let goalId else { return d.passbook }
            var b: Int64 = 0
            return d.passbook.filter { $0.goalId == goalId }.map { r in b += r.amount; var x = r; x.balance = b; return x }
        }()
        let shown = Array(rows.suffix(shownRows))
        SectionLabel(text: "通帳", trailing: "\(rows.count) 件")
        if d.goals.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("すべて", on: goalId == nil) { goalId = nil; shownRows = 20 }
                    ForEach(d.goals) { g in chip(g.name, on: goalId == g.id) { goalId = g.id; shownRows = 20 } }
                }
            }.padding(.bottom, 8)
        }
        ListPaper {
            HStack {
                Text("年月日").frame(maxWidth: .infinity, alignment: .leading)
                Text("お引出し").frame(maxWidth: .infinity, alignment: .trailing)
                Text("お預入れ").frame(maxWidth: .infinity, alignment: .trailing)
                Text("差引残高").frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.system(size: 11, weight: .bold)).foregroundStyle(Color.kSub).padding(.horizontal, 12).padding(.vertical, 8).background(Color.kBg)
            if rows.count > shown.count {
                Button("前の \(min(20, rows.count - shown.count)) 件を見る") { shownRows += 20 }.font(.system(size: 14)).foregroundStyle(Color.kSub).frame(maxWidth: .infinity, minHeight: 44)
            }
            if shown.isEmpty { SubText("まだ記録がありません。「貯金した」から始めましょう。").padding(14) }
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(r.day.dropFirst(2).prefix(2))-\(r.day.dropFirst(5).prefix(2))-\(r.day.dropFirst(8))").foregroundStyle(Color.kSub).frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.amount < 0 ? Money.format(-r.amount) : "").foregroundStyle(Color.kDanger).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(r.amount > 0 ? Money.format(r.amount) : "").foregroundStyle(Color.kInk).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(Money.format(r.balance)).fontWeight(.bold).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, alignment: .trailing)
                    }.font(.system(size: 13)).monospacedDigit()
                    Text(memo(r)).font(.system(size: 11)).foregroundStyle(Color.kSub).lineLimit(1).padding(.leading, 56)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(i % 2 == 0 ? Color.kCard : Color.kBg.opacity(0.35))
                .accessibilityElement(children: .combine)
                DashedLine()
            }
        }
    }

    private func memo(_ r: PassbookRow) -> String {
        var t = r.amount < 0 ? "引出" : (Savings.kindNames[r.kind] ?? "預入")
        if goalId == nil { t += "・\(r.goalName)" }
        if !r.memo.isEmpty && r.kind != "leftover" && r.kind != "auto" { t += "・\(r.memo)" }
        return t
    }

    private func chip(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(on ? Color.kCard : Color.kInk).padding(.horizontal, 12).frame(minHeight: 44)
                .background(on ? Color.kInk : Color.kCard, in: buttonShape).overlay(buttonShape.stroke(on ? Color.kInk : Color.kLine, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// 貯金した・取り崩した・つもり貯金
struct SaveSheet: View {
    let ctx: GroupCtx
    let goals: [SavingsGoal]
    let intent: SaveIntent
    let onDone: (String?) -> Void
    @State private var dir = 1
    @State private var amount = ""
    @State private var memo = ""
    @State private var goalId = ""
    @State private var day = Money.todayJST()
    @State private var error: String?
    @State private var busy = false
    @State private var requestId = UUID().uuidString.lowercased()
    @State private var started = false

    private var tsumori: Bool { intent.kind == "tsumori" }

    var body: some View {
        Form {
            SubText(tsumori ? "買うのをやめた物の金額を、貯金したことにします（あとで実際に移しておくと確実です）。" : "口座や貯金箱に移した金額を記録します。")
            if !tsumori { Picker("", selection: $dir) { Text("貯金した").tag(1); Text("取り崩した").tag(-1) }.pickerStyle(.segmented) }
            AmountField(label: "金額（円）", text: $amount, error: error)
            TextField(tsumori ? "がまんした物（例: コンビニのコーヒー）" : "メモ（なくてもよい）", text: $memo)
            if goals.count > 1 { Picker("どの目標に", selection: $goalId) { ForEach(goals) { Text($0.name).tag($0.id) } } }
            DatePicker("日付", selection: $day, in: ...Money.todayJST(), displayedComponents: .date).environment(\.timeZone, Money.tokyo)
            Button { submit() } label: { HStack { Spacer(); if busy { ProgressView() } else { Text("記録する").bold() }; Spacer() }.frame(minHeight: 44) }.disabled(busy)
        }
        .navigationTitle(tsumori ? "つもり貯金" : dir < 0 ? "取り崩しを記録する" : "貯金を記録する")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("やめる") { onDone(nil) } } }
        .onAppear { if !started { started = true; dir = intent.dir; goalId = intent.goalId ?? goals.first?.id ?? "" } }
    }

    private func submit() {
        if let e = Validate.amount(amount) { error = e; return }
        let a = (Money.parse(amount) ?? 0) * Int64(dir)
        busy = true; error = nil
        Task { @MainActor in
            do {
                try await ctx.repo.recordSaving(goal: goalId, day: day, amount: a, kind: intent.kind, memo: memo.trimmingCharacters(in: .whitespaces), requestId: requestId)
                onDone(a < 0 ? "\(Money.format(-a)) を取り崩しました" : "\(Money.format(a)) 貯金しました")
            } catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }
}

// ---------- 目標を作る・直す（名前・金額・期限・毎月の先取り・いちばん大事か・自分だけか）。記録の一覧と、やめることも ----------
struct GoalView: View {
    let ctx: GroupCtx
    let goal: SavingsGoal?
    var presetName: String? = nil
    var presetTarget: Int64? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target = ""
    @State private var hasDue = false
    @State private var due = Money.addMonths(Money.monthStart(Money.todayJST()), 12)
    @State private var auto = ""
    @State private var dom = 25
    @State private var isMain = false
    @State private var isPrivate = false
    @State private var error: String?
    @State private var busy = false
    @State private var askArchive = false
    @State private var rows: Loadable<[PassbookRow]> = .loading
    @State private var started = false

    private var canEdit: Bool { goal == nil || ctx.can("admin") || goal?.createdBy?.lowercased() == ctx.repo.userId }

    var body: some View {
        Form {
            Section {
                TextField("目的（例: 旅行・車検・もしものとき）", text: $name).disabled(!canEdit)
                AmountField(label: "目標の金額（円）", text: $target)
                Toggle("期限を決める", isOn: $hasDue).disabled(!canEdit)
                if hasDue {
                    Picker("いつまでに", selection: $due) {
                        ForEach(0..<61, id: \.self) { k in let m = Money.addMonths(Money.monthStart(Money.todayJST()), k); Text(Money.monthLabel(m)).tag(m) }
                    }
                }
                AmountField(label: "毎月の先取り貯金（円。なければ空のまま）", text: $auto)
                if !auto.isEmpty {
                    Picker("先取りする日（給料日など）", selection: $dom) { ForEach(Array(1...31) + [99], id: \.self) { Text(Savings.domLabel($0)).tag($0) } }
                }
                Toggle(isOn: $isMain) { VStack(alignment: .leading) { Text("いちばん大事な目標にする"); FaintText("ホームにはこの目標だけを出します") } }
                    .disabled(!canEdit).onChange(of: isMain) { if isMain { isPrivate = false } }
                Toggle(isOn: $isPrivate) { VStack(alignment: .leading) { Text("自分だけに見せる"); FaintText("ほかのメンバーには見えません（へそくりなど）") } }
                    .disabled(!canEdit).onChange(of: isPrivate) { if isPrivate { isMain = false } }
            }
            if let error { Text(error).foregroundStyle(Color.kDanger) }
            Section {
                if canEdit {
                    Button { submit() } label: { HStack { Spacer(); if busy { ProgressView() } else { Text(goal == nil ? "目標を作る" : "保存する").bold() }; Spacer() }.frame(minHeight: 44) }.disabled(busy)
                    if goal != nil { Button("この目標をやめる", role: .destructive) { askArchive = true }.disabled(busy) }
                } else { FaintText("この目標を直せるのは、作った人と管理者です") }
            }
            if goal != nil {
                Section("記録") {
                    LoadableView(state: rows, retry: loadRows) { rs in
                        if rs.isEmpty { SubText("まだ記録がありません") }
                        ForEach(rs.reversed().prefix(30)) { r in
                            HStack {
                                Text("\(r.day.dropFirst(5).replacingOccurrences(of: "-", with: "/")) \(Savings.kindNames[r.kind] ?? "")" + (!r.memo.isEmpty && r.kind != "leftover" && r.kind != "auto" ? "・\(r.memo)" : "")).font(.system(size: 14))
                                Spacer()
                                Text((r.amount > 0 ? "+" : "") + Money.format(r.amount)).bold().monospacedDigit().foregroundStyle(r.amount < 0 ? Color.kDanger : Color.kInk)
                            }
                            .swipeActions {
                                if r.kind != "auto" && (r.createdBy?.lowercased() == ctx.repo.userId || ctx.can("admin")) {
                                    Button("消す", role: .destructive) { Task { @MainActor in do { try await ctx.repo.deleteSaving(r.id); await loadRows() } catch { self.error = Repo.map(error).userMessage } } }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(goal == nil ? "貯金の目標を作る" : "貯金の目標を直す")
        .task { await start() }
        .confirmationDialog("「\(goal?.name ?? "")」をやめますか", isPresented: $askArchive, titleVisibility: .visible) {
            Button("やめる", role: .destructive) { archive() }
        } message: { Text("目標と、その記録が見えなくなります（お金そのものは動きません）。") }
    }

    private func start() async {
        guard !started else { return }
        started = true
        name = goal?.name ?? presetName ?? ""
        target = goal.map { String($0.target) } ?? presetTarget.map { String($0) } ?? ""
        if let d = goal?.dueMonth, let date = Money.date(d) { hasDue = true; due = date }
        auto = goal?.autoAmount.map { String($0) } ?? ""
        dom = goal?.autoDom ?? 25
        isMain = goal?.isMain ?? false
        isPrivate = goal?.visibility == "private"
        if goal != nil { await loadRows() }
    }

    private func loadRows() async {
        guard let goal else { return }
        do { rows = .ready(try await ctx.repo.passbook(ctx.g, goal: goal.id)) } catch { rows = .failed(Repo.map(error)) }
    }

    private func submit() {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { error = "目的を入れてください"; return }
        if let e = Validate.amount(target) { error = e; return }
        if !auto.isEmpty, let e = Validate.amount(auto) { error = e; return }
        busy = true; error = nil
        Task { @MainActor in
            do {
                try await ctx.repo.saveGoal(ctx.g, goal: goal, name: name, target: Money.parse(target) ?? 0, dueMonth: hasDue ? due : nil, isMain: isMain,
                                            autoAmount: auto.isEmpty ? nil : Money.parse(auto), autoDom: auto.isEmpty ? nil : dom,
                                            startOn: goal.flatMap { Money.date($0.startOn) } ?? Money.todayJST(), isPrivate: isPrivate)
                try? await ctx.repo.generateDueSavings(ctx.g)
                ctx.app.toast = goal == nil ? "「\(name.trimmingCharacters(in: .whitespaces))」の目標を作りました" : "保存しました"
                ctx.refresh += 1
                dismiss()
            } catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }

    private func archive() {
        guard let goal else { return }
        busy = true
        Task { @MainActor in
            do { try await ctx.repo.archiveGoal(goal.id); ctx.app.toast = "目標をやめました"; ctx.refresh += 1; dismiss() } catch { self.error = Repo.map(error).userMessage }
            busy = false
        }
    }
}

// ---------- ホームの貯金のカード（いちばん大事な目標だけ。先月の予算の余りを回す提案も） ----------
struct SavingsHome {
    let goal: SavingsGoal?
    let status: SavingsStatus?
    let others: Int
    let leftover: Int64?
    let leftoverMonth: String
    let leftoverDone: Bool

    static func load(_ ctx: GroupCtx) async throws -> SavingsHome {
        let today = Money.todayJST()
        let goals = try await ctx.repo.goals(ctx.g)
        let status = try await ctx.repo.savingsStatus(ctx.g)
        let main = goals.first(where: { $0.isMain && $0.visibility == "group" }) ?? goals.first(where: { g in status.first(where: { $0.goalId == g.id })?.done == false }) ?? goals.first
        let prev = Money.addMonths(Money.monthStart(today), -1)
        let prevKey = String(Money.dateString(prev).prefix(7))
        let left = goals.isEmpty ? nil : Savings.leftover(try await ctx.repo.budgetStatus(ctx.g, prev))
        let done = left != nil ? try await ctx.repo.passbook(ctx.g).contains { $0.kind == "leftover" && $0.memo == prevKey } : false
        return SavingsHome(goal: main, status: status.first { $0.goalId == main?.id }, others: max(0, goals.count - 1), leftover: left, leftoverMonth: prevKey, leftoverDone: done)
    }
}

struct SavingsCard: View {
    let ctx: GroupCtx
    let h: SavingsHome
    let onChanged: () -> Void
    @State private var busy = false

    var body: some View {
        if let g = h.goal, let s = h.status {
            Paper {
                HStack { Text("貯金・\(g.name)").font(.system(size: 14)).foregroundStyle(Color.kSub); Spacer(); FaintText("\(Int((s.ratio * 100).rounded()))%") }
                HStack(alignment: .lastTextBaseline, spacing: 0) { BigYen(yen: s.saved, size: 28); Text(" / \(Money.format(g.target))").font(.system(size: 14)).foregroundStyle(Color.kSub) }
                Meter(ratio: s.ratio).padding(.top, 6)
                SubText(Savings.pace(g, s)).padding(.top, 8)
                if s.thisMonth > 0 { FaintText("今月 \(Money.format(s.thisMonth)) 貯金しました").padding(.top, 2) }
                if let left = h.leftover, !h.leftoverDone, ctx.can("member") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Savings.yyyymm(h.leftoverMonth + "-01"))の予算が \(Money.format(left)) 余りました。").font(.system(size: 14)).foregroundStyle(Color.kInk)
                        Button { moveLeftover(g, left) } label: {
                            Text("\(Money.format(left)) を「\(g.name)」に回す").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kAccentInk).frame(maxWidth: .infinity, minHeight: 44).background(Color.kAccent, in: buttonShape)
                        }.buttonStyle(.plain).disabled(busy)
                    }.padding(12).background(Color.kBg, in: paperShape).padding(.top, 12)
                }
                NavigationLink { SavingsView(ctx: ctx).navigationTitle("貯金") } label: {
                    Text("通帳を見る・貯金した").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 48).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                }.buttonStyle(.plain).padding(.top, 12)
                if h.others > 0 { FaintText("ほかの目標 \(h.others) 件は「貯金」にあります").frame(maxWidth: .infinity).padding(.top, 10) }
            }
        } else {
            Paper {
                Text("貯金の目標を作りませんか").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk)
                SubText("目的に名前を付けて、期限と金額を決めると「毎月いくら」が分かります。毎月決まった日に先に分けておく「先取り貯金」もできます。").padding(.top, 6).padding(.bottom, 12)
                NavigationLink { GoalView(ctx: ctx, goal: nil) } label: {
                    Text("貯金を始める").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 52).overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private func moveLeftover(_ g: SavingsGoal, _ left: Int64) {
        busy = true
        Task { @MainActor in
            do {
                try await ctx.repo.recordSaving(goal: g.id, day: Money.todayJST(), amount: left, kind: "leftover", memo: h.leftoverMonth, requestId: UUID().uuidString.lowercased())
                ctx.app.toast = "\(Money.format(left)) を貯金に回しました"; onChanged()
            } catch { ctx.app.toast = Repo.map(error).userMessage }
            busy = false
        }
    }
}
