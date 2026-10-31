import SwiftUI
import Charts

// ---------- 精算（立て替えの差額。提案・記録・相手の確認・履歴） ----------
struct SettlementView: View {
    let ctx: GroupCtx
    struct SettleData { let balances: [Balance]; let suggestions: [Suggestion]; let history: [Settlement] }
    @State private var loader: Loader<SettleData>
    @State private var record: Suggestion?
    @State private var recordAmount = ""
    @State private var recordNote = ""
    @State private var recordId = UUID().uuidString.lowercased()
    @State private var cancel: Settlement?

    init(ctx: GroupCtx) {
        self.ctx = ctx
        _loader = State(initialValue: Loader { SettleData(balances: try await ctx.repo.balances(ctx.g), suggestions: try await ctx.repo.suggestions(ctx.g), history: try await ctx.repo.settlements(ctx.g)) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LoadableView(state: loader.state, retry: { await loader.reload() }) { d in
                    SubText("割り勘にした支出だけで計算します。プラスは受け取る側、マイナスは払う側です。")
                    SectionLabel(text: "いまの差額")
                    ListPaper {
                        ForEach(Array(d.balances.enumerated()), id: \.element.memberId) { i, b in
                            if i > 0 { DashedLine() }
                            ItemRow(title: b.displayName + (b.status != "active" ? "（退出）" : ""), sub: "立て替え \(Money.format(b.paid))・負担 \(Money.format(b.burden))",
                                    amount: (b.net > 0 ? "+" : "") + Money.format(b.net), catName: b.displayName, catColor: "#6b7280", amountColor: b.net < 0 ? .kDanger : .kInk)
                        }
                    }
                    SectionLabel(text: "精算の提案")
                    if d.suggestions.isEmpty { Paper { SubText("いま精算が必要な人はいません（確認待ちの精算は差し引いています）") } }
                    else {
                        ListPaper {
                            ForEach(Array(d.suggestions.enumerated()), id: \.element.id) { i, sg in
                                if i > 0 { DashedLine() }
                                HStack {
                                    Text("\(ctx.memberName(sg.fromMember)) → \(ctx.memberName(sg.toMember))").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kInk)
                                    Spacer()
                                    Text(Money.format(sg.amount)).font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundStyle(Color.kInk)
                                    if ctx.can("member") { Button("払った") { recordAmount = String(sg.amount); recordNote = ""; recordId = UUID().uuidString.lowercased(); record = sg }.font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kAccent).frame(minHeight: 44) }
                                }.padding(.horizontal, 16).padding(.vertical, 4)
                            }
                        }
                    }
                    let pending = d.history.filter { $0.status == "pending" }
                    if !pending.isEmpty {
                        SectionLabel(text: "確認待ち")
                        ListPaper {
                            ForEach(Array(pending.enumerated()), id: \.element.id) { i, p in
                                if i > 0 { DashedLine() }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(ctx.memberName(p.fromMember)) → \(ctx.memberName(p.toMember))  \(Money.format(p.amount))").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kInk)
                                    HStack(spacing: 16) {
                                        // 受け取った人（か管理者）が確認すると差額に入る
                                        if p.toMember == ctx.me?.id || ctx.can("admin") {
                                            Button("受け取りを確認") { Task { await loader.act("受け取りを確認しました") { try await ctx.repo.confirmSettlement(p.id) } } }.font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kAccent).frame(minHeight: 44)
                                        }
                                        if p.fromMember == ctx.me?.id || p.toMember == ctx.me?.id || ctx.can("admin") {
                                            Button("取り消す", role: .destructive) { cancel = p }.font(.system(size: 14)).foregroundStyle(Color.kDanger).frame(minHeight: 44)
                                        }
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                    }
                    SectionLabel(text: "精算の履歴")
                    let done = d.history.filter { $0.status != "pending" }
                    if done.isEmpty { Paper { SubText("まだありません") } }
                    else {
                        ListPaper {
                            ForEach(Array(done.enumerated()), id: \.element.id) { i, h in
                                if i > 0 { DashedLine() }
                                Text("\((h.confirmedAt ?? h.createdAt ?? "").prefix(10))  \(ctx.memberName(h.fromMember)) → \(ctx.memberName(h.toMember))  \(Money.format(h.amount))" + (h.status == "cancelled" ? "（取り消し）" : ""))
                                    .font(.system(size: 14)).foregroundStyle(Color.kInk).padding(.horizontal, 16).padding(.vertical, 12)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.kBg)
        .task(id: ctx.refresh) { await loader.reload() }
        .refreshable { await loader.reload() }
        .toast($loader.message)
        .sheet(item: $record) { s in
            NavigationStack {
                Form {
                    Text("\(ctx.memberName(s.fromMember)) が \(ctx.memberName(s.toMember)) に払った金額を記録します。受け取った人が確認すると差額に入ります。")
                    let err = Validate.amount(recordAmount) ?? ((Money.parse(recordAmount) ?? 0) > s.amount ? "提案の金額（\(Money.format(s.amount))）をこえています" : nil)
                    AmountField(label: "金額", text: $recordAmount, error: err)
                    TextField("メモ（例: 現金で）", text: $recordNote)
                    Button("記録する") {
                        let amt = Money.parse(recordAmount) ?? 0
                        record = nil
                        Task { await loader.act("記録しました。相手の確認待ちです") { try await ctx.repo.recordSettlement(ctx.g, from: s.fromMember, to: s.toMember, amount: amt, note: recordNote, requestId: recordId) } }
                    }.disabled(err != nil || loader.busy)
                }
                .navigationTitle("精算を記録")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("やめる") { record = nil } } }
            }
        }
        .confirmationDialog("精算を取り消しますか", isPresented: Binding(get: { cancel != nil }, set: { if !$0 { cancel = nil } }), titleVisibility: .visible) {
            Button("取り消す", role: .destructive) { if let s = cancel { Task { await loader.act("取り消しました") { try await ctx.repo.cancelSettlement(s.id) } } }; cancel = nil }
        }
    }
}

extension Suggestion: Identifiable { var id: String { "\(fromMember)-\(toMember)-\(amount)" } }

// ---------- レポート（月ごとの推移・カテゴリ別・払った人別） ----------
struct ReportView: View {
    let ctx: GroupCtx
    @Binding var month: Date
    struct ReportData { let series: [MonthPoint]; let sum: MonthSummary }
    @State private var state: Loadable<ReportData> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MonthBar(month: $month)
                LoadableView(state: state, retry: load) { d in
                    SectionLabel(text: "支出の推移（6 か月）")
                    Paper {
                        // 1 系列なので 1 色。数字は下の表にも出す
                        Chart(d.series, id: \.month) { p in
                            BarMark(x: .value("月", String(p.month.prefix(7))), y: .value("支出", p.expense)).cornerRadius(2).foregroundStyle(Color.kAccent)
                        }
                        .frame(height: 160)
                        .accessibilityLabel("支出の推移の棒グラフ。数字は下の表にあります")
                        ForEach(d.series, id: \.month) { p in
                            DashedLine()
                            HStack { FaintText(p.month.prefix(7).replacingOccurrences(of: "-", with: "/")); Spacer(); Text("収入 \(Money.format(p.income))・支出 \(Money.format(p.expense))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.kSub) }.padding(.vertical, 6)
                        }
                    }
                    SectionLabel(text: "カテゴリ別の支出")
                    if d.sum.byCategory.isEmpty { Paper { SubText("この月の支出はありません") } }
                    else {
                        Paper(padding: 12) {
                            let sorted = d.sum.byCategory.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
                            Donut(slices: sorted.map { DonutSlice(label: ctx.cat($0.categoryId)?.name ?? "不明", colorHex: ctx.cat($0.categoryId)?.color, amount: $0.amount) }, centerLabel: "支出", centerValue: d.sum.expense)
                            ForEach(sorted, id: \.self) { a in CategoryBar(name: ctx.cat(a.categoryId)?.name ?? "不明", colorHex: ctx.cat(a.categoryId)?.color, amount: a.amount, max: sorted[0].amount, icon: ctx.cat(a.categoryId)?.icon, total: sorted.reduce(0) { $0 + $1.amount }) }
                        }
                    }
                    if !d.sum.byPayer.isEmpty {
                        SectionLabel(text: "払った人別")
                        Paper(padding: 12) { let sorted = d.sum.byPayer.sorted { $0.amount > $1.amount }; ForEach(sorted, id: \.self) { a in CategoryBar(name: ctx.memberName(a.memberId), colorHex: "#6b7f99", amount: a.amount, max: sorted[0].amount) } }
                    }
                    if !d.sum.byBurden.isEmpty {
                        SectionLabel(text: "負担した人別（割り勘のあと）")
                        Paper(padding: 12) { let sorted = d.sum.byBurden.sorted { $0.amount > $1.amount }; ForEach(sorted, id: \.self) { a in CategoryBar(name: ctx.memberName(a.memberId), colorHex: "#6b7f99", amount: a.amount, max: sorted[0].amount) } }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.kBg)
        .task(id: "\(month)-\(ctx.refresh)") { await load() }
    }

    private func load() async {
        do { state = .ready(ReportData(series: try await ctx.repo.monthlySeries(ctx.g, end: month), sum: try await ctx.repo.monthSummary(ctx.g, month))) }
        catch { state = .failed(Repo.map(error)) }
    }
}

// ---------- 予算 ----------
struct BudgetView: View {
    let ctx: GroupCtx
    let month: Date
    @State private var loader: Loader<[BudgetStatus]>
    @State private var scope = "group"
    @State private var catId: String? = nil
    @State private var memberId: String? = nil
    @State private var amount = ""
    @State private var rollover = false
    @State private var del: BudgetStatus?

    init(ctx: GroupCtx, month: Date) {
        self.ctx = ctx; self.month = month
        _loader = State(initialValue: Loader { try await ctx.repo.budgetStatus(ctx.g, month) })
        _memberId = State(initialValue: ctx.me?.id)
    }

    var body: some View {
        Form {
            Section("\(Money.monthLabel(month))の予算") {
                LoadableView(state: loader.state, retry: { await loader.reload() }, isEmpty: { $0.isEmpty }, empty: {
                    EmptyBox(title: "予算はまだありません", message: "カテゴリごと・全体の月の上限を決められます")
                }) { list in
                    ForEach(list, id: \.budgetId) { b in
                        BudgetRow(ctx: ctx, b: b)
                            .swipeActions { if ctx.can("admin") { Button("やめる", role: .destructive) { del = b } } }
                    }
                }
            }
            if ctx.can("admin") {
                Section {
                    Picker("対象", selection: $scope) { Text("グループ全体の支出").tag("group"); Text("1 人の負担").tag("personal") }.pickerStyle(.segmented)
                    Picker("カテゴリ", selection: $catId) {
                        Text("全体（すべての支出）").tag(String?.none)
                        ForEach(ctx.cats.filter { $0.kind == "expense" && $0.archivedAt == nil }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if scope == "personal" {
                        Picker("人", selection: $memberId) { ForEach(ctx.activeMembers) { Text($0.displayName).tag(Optional($0.id)) } }
                    }
                    AmountField(label: "月の上限（円）", text: $amount)
                    Toggle("余りを翌月に回す（使いすぎた分は翌月から引く）", isOn: $rollover)
                    Button("保存する") {
                        let a = Money.parse(amount) ?? 0
                        Task { if await loader.act("予算を保存しました", { try await ctx.repo.saveBudget(ctx.g, scope: scope, category: catId, member: scope == "personal" ? memberId : nil, start: month, amount: a, rollover: rollover) }) { amount = "" } }
                    }.disabled(Validate.amount(amount) != nil || loader.busy || (scope == "personal" && memberId == nil))
                } header: { Text("予算を決める（この月から、次に変えるまで続く）") }
            }
        }
        .navigationTitle("予算")
        .task { await loader.reload() }
        .toast($loader.message)
        .confirmationDialog("予算をやめますか", isPresented: Binding(get: { del != nil }, set: { if !$0 { del = nil } }), titleVisibility: .visible) {
            Button("やめる", role: .destructive) { if let b = del { Task { await loader.act("予算をやめました") { try await ctx.repo.deleteBudget(b.budgetId) } } }; del = nil }
        }
    }
}
