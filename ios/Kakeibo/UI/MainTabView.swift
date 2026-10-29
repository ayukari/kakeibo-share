import SwiftUI

// 開いているグループの共通情報（メンバー・カテゴリ・支払い方法）
@MainActor @Observable
final class GroupCtx {
    let app: AppState
    let group: KGroup
    var cats: [Category] = []
    var pms: [PaymentMethod] = []
    var meta: Loadable<Void> = .loading
    var refresh = 0     // 保存のあとに一覧を読み直す合図

    init(app: AppState, group: KGroup) { self.app = app; self.group = group }

    var repo: Repo { app.repo }
    var g: String { group.id }
    var me: Member? { app.me }
    var members: [Member] { app.members }
    var activeMembers: [Member] { members.filter { $0.status == "active" } }

    func loadMeta() async {
        do { cats = try await repo.categories(g); pms = try await repo.paymentMethods(g); meta = .ready(()) } catch { meta = .failed(Repo.map(error)) }
    }
    func can(_ min: String) -> Bool { app.can(min) }
    func memberName(_ id: String?) -> String {
        guard let m = members.first(where: { $0.id == id }) else { return "不明" }
        return m.status == "active" ? m.displayName : "\(m.displayName)（退出）"
    }
    func cat(_ id: String?) -> Category? { cats.first { $0.id == id } }
    func canEdit(_ t: Txn) -> Bool { can("admin") || (can("member") && t.createdBy?.lowercased() == repo.userId) }
}

struct MainTabView: View {
    let app: AppState
    @State private var ctx: GroupCtx
    @State private var month = Money.monthStart(Money.todayJST())
    @State private var adding = false

    init(app: AppState, group: KGroup) {
        self.app = app
        _ctx = State(initialValue: GroupCtx(app: app, group: group))
    }

    var body: some View {
        Group {
            switch ctx.meta {
            case .loading: ProgressView().task { await ctx.loadMeta() }
            case .failed(let e): ErrorBox(error: e) { await ctx.loadMeta() }
            case .ready:
                TabView {
                    nav { DashboardView(ctx: ctx, month: $month) }.tabItem { Label("ホーム", systemImage: "house") }
                    nav { TxnListView(ctx: ctx, month: $month) }.tabItem { Label("収支", systemImage: "list.bullet") }
                    nav { SavingsView(ctx: ctx) }.tabItem { Label("貯金", systemImage: "envelope") }
                    nav { SettlementView(ctx: ctx) }.tabItem { Label("精算", systemImage: "arrow.left.arrow.right") }
                    nav { ReportView(ctx: ctx, month: $month) }.tabItem { Label("レポート", systemImage: "chart.bar") }
                    nav { MoreView(ctx: ctx, month: month) }.tabItem { Label("その他", systemImage: "ellipsis") }
                }
                .tint(Color.kAccent)
                .toolbarBackground(Color.kCard, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { TxnEditView(ctx: ctx, txn: nil) } }
    }

    private func nav<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        NavigationStack {
            v()
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.kBg, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(ctx.group.name).font(.headline).lineLimit(1)
                            Text("\(ctx.me?.displayName ?? "")・\(roleNames[ctx.me?.role ?? ""] ?? "")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) { Button("切替") { Task { await app.select(nil) } } }
                    if ctx.can("member") {
                        ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Label("記録する", systemImage: "plus") }.accessibilityIdentifier("addTxn") }
                    }
                }
        }
    }
}

// ---------- ホーム（かざすレシートの家計簿のホームと同じ並び: 今月の支出 → 予算とペース → カテゴリ → 最近の記録） ----------
struct DashData { let sum: MonthSummary; let budgets: [BudgetStatus]; let txns: [Txn]; let prev: [Txn]; let balances: [Balance]; var savings: SavingsHome? = nil }

struct DashboardView: View {
    let ctx: GroupCtx
    @Binding var month: Date
    @State private var state: Loadable<DashData> = .loading

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MonthBar(month: $month)
                LoadableView(state: state, retry: load) { d in DashboardContent(ctx: ctx, d: d, month: month) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.kBg)
        .task(id: "\(month)-\(ctx.refresh)") { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            let prev = Money.addMonths(month, -1)
            state = .ready(DashData(sum: try await ctx.repo.monthSummary(ctx.g, month), budgets: try await ctx.repo.budgetStatus(ctx.g, month),
                                    txns: try await ctx.repo.transactions(ctx.g, from: month, toExclusive: Money.addMonths(month, 1)),
                                    prev: try await ctx.repo.transactions(ctx.g, from: prev, toExclusive: month), balances: try await ctx.repo.balances(ctx.g),
                                    savings: try? await SavingsHome.load(ctx)))
        } catch { state = .failed(Repo.map(error)) }
    }
}

struct DashboardContent: View {
    let ctx: GroupCtx
    let d: DashData
    let month: Date

    var body: some View {
        let isCur = Money.monthStart(month) == Money.monthStart(Money.todayJST())
        VStack(spacing: 12) {
            Paper {
                Text((isCur ? "今月" : "\(Money.calendar.component(.month, from: month))月") + "の支出").font(.system(size: 14)).foregroundStyle(Color.kSub)
                BigYen(yen: d.sum.expense)
                FaintText("\(d.txns.filter { $0.status == "active" && $0.visibility == "group" }.count)件の記録")
                if d.sum.income > 0 {
                    Spacer().frame(height: 12)
                    KeyValue(key: "収入", value: Money.format(d.sum.income), first: true)
                    KeyValue(key: "収支", value: (d.sum.balance > 0 ? "+" : "") + Money.format(d.sum.balance), valueColor: d.sum.balance < 0 ? .kDanger : .kInk)
                }
            }
            BudgetPaper(ctx: ctx, d: d, month: month, isCur: isCur)
            if isCur, let sv = d.savings { SavingsCard(ctx: ctx, h: sv) { ctx.refresh += 1 } }
            if let mine = d.balances.first(where: { $0.memberId == ctx.me?.id }), d.balances.count > 1 {
                Text(mine.net > 0 ? "あなたは \(Money.format(mine.net)) 受け取る側です" : mine.net < 0 ? "あなたは \(Money.format(-mine.net)) 払う側です" : "あなたの精算は済んでいます")
                    .font(.system(size: 14)).foregroundStyle(Color.kInk).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.kBg, in: paperShape)
            }
            if !d.sum.byCategory.isEmpty {
                SectionLabel(text: "カテゴリ")
                Paper(padding: 12) {
                    let sorted = d.sum.byCategory.sorted { $0.amount > $1.amount }
                    ForEach(sorted, id: \.self) { a in CategoryBar(name: ctx.cat(a.categoryId)?.name ?? "不明", colorHex: ctx.cat(a.categoryId)?.color, amount: a.amount, max: sorted[0].amount) }
                }
            }
            SectionLabel(text: "最近の記録")
            let recent = Array(d.txns.filter { $0.status == "active" }.prefix(5))
            if recent.isEmpty {
                Paper { EmptyBox(title: "まだ記録がありません", message: ctx.can("member") ? "右上の＋から最初の収支を入れてください" : "閲覧のみの権限です") }
            } else {
                ListPaper { ForEach(Array(recent.enumerated()), id: \.element.id) { i, t in if i > 0 { DashedLine() }; TxnLink(ctx: ctx, t: t) } }
            }
        }
    }
}

// 予算の残り・1 日あたり・ペースの線・カテゴリごとの予算
struct BudgetPaper: View {
    let ctx: GroupCtx
    let d: DashData
    let month: Date
    let isCur: Bool

    var body: some View {
        if d.budgets.isEmpty {
            Paper {
                Text("予算を決めてみませんか").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk)
                SubText("決めておくと「今月あといくら・1日あたりいくら」が分かります。").padding(.top, 6).padding(.bottom, 12)
                if ctx.can("admin") {
                    NavigationLink { BudgetView(ctx: ctx, month: month) } label: {
                        Text("予算を決める").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk).frame(maxWidth: .infinity, minHeight: 52)
                            .overlay(buttonShape.stroke(Color.kLine, lineWidth: 1))
                    }
                } else { FaintText("予算を決められるのは管理者とオーナーです") }
            }
        } else {
            let catRows = d.budgets.filter { $0.scope == "group" && $0.categoryId != nil }
            let rows = catRows.isEmpty ? d.budgets.filter { $0.scope == "group" && $0.categoryId == nil } : catRows
            let total = rows.reduce(Int64(0)) { $0 + $1.amount }, spent = rows.reduce(Int64(0)) { $0 + $1.spent }, left = total - spent
            let daysLeft = Insights.daysLeft(month: month, today: Money.todayJST())
            Paper {
                Text("予算の残り").font(.system(size: 14)).foregroundStyle(Color.kSub)
                if left < 0 { Text("予算を \(Money.format(-left)) こえました").font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.kDanger) }
                else { Text("あと \(Money.format(left))").font(.system(size: 28, weight: .heavy)).monospacedDigit().foregroundStyle(Color.kInk) }
                if isCur && left >= 0 { SubText("1日あたり \(Money.format(Insights.perDay(left: left, daysLeft: daysLeft)))（のこり \(daysLeft) 日）").padding(.top, 2) }
                if left < 0 { SubText("来月の予算を見直すのも、ひとつの方法です。").padding(.top, 2) }
                PaceChart(d: d, month: month, isCur: isCur, ideal: Insights.idealLine(varBudget: max(0, total - Insights.fixedTotal(d.txns, month: month)), len: Insights.lengthOfMonth(month)))
                Spacer().frame(height: 10)
                ForEach(Array(rows.sorted { $0.ratio > $1.ratio }.enumerated()), id: \.element.budgetId) { i, b in
                    if i > 0 { DashedLine() }
                    BudgetRow(ctx: ctx, b: b, tick: isCur ? (Double(Money.calendar.component(.day, from: Money.todayJST())) - 0.5) / Double(Insights.lengthOfMonth(month)) : 1)
                }
            }
        }
    }
}

// ペースの線: 今月の累計（緑）・先月の累計（薄い灰）・予算の目安（細い線）
struct PaceChart: View {
    let d: DashData
    let month: Date
    let isCur: Bool
    let ideal: [Int64]?

    var body: some View {
        let len = Insights.lengthOfMonth(month)
        let all = Insights.variableCumulative(d.txns, month: month)
        let upto = isCur ? Money.calendar.component(.day, from: Money.todayJST()) : len
        let actual = Array(all.prefix(upto))
        let p = Insights.variableCumulative(d.prev, month: Money.addMonths(month, -1))
        let prev = (0..<len).map { $0 < p.count ? p[$0] : (p.last ?? 0) }
        let hasPrev = prev.contains { $0 > 0 }
        let mx = max(1, actual.max() ?? 0, prev.max() ?? 0, ideal?.max() ?? 0)
        let m = Money.calendar.component(.month, from: month)
        VStack(alignment: .leading, spacing: 0) {
            Canvas { ctx, size in
                let l: CGFloat = 6, r: CGFloat = 6, top: CGFloat = 10, bot: CGFloat = 4
                func x(_ i: Int) -> CGFloat { l + (size.width - l - r) * CGFloat(i) / CGFloat(max(1, len - 1)) }
                func y(_ v: Int64) -> CGFloat { top + (size.height - top - bot) * (1 - CGFloat(v) / CGFloat(mx)) }
                func path(_ vs: [Int64]) -> Path { var p = Path(); for (i, v) in vs.enumerated() { i == 0 ? p.move(to: CGPoint(x: x(i), y: y(v))) : p.addLine(to: CGPoint(x: x(i), y: y(v))) }; return p }
                var axis = Path(); axis.move(to: CGPoint(x: l, y: y(0))); axis.addLine(to: CGPoint(x: size.width - r, y: y(0)))
                ctx.stroke(axis, with: .color(.kLine), lineWidth: 1)
                if let ideal { ctx.stroke(path(ideal), with: .color(Color.kSub.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)) }
                if hasPrev { ctx.stroke(path(prev), with: .color(Color.kFaint.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)) }
                if !actual.isEmpty {
                    ctx.stroke(path(actual), with: .color(.kAccent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    let c = CGPoint(x: x(actual.count - 1), y: y(actual.last!))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6.5, y: c.y - 6.5, width: 13, height: 13)), with: .color(.kCard))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(.kAccent))
                }
            }.frame(height: 140).padding(.top, 10).accessibilityLabel("この月の支出のペース")
            HStack { FaintText("\(m)/1"); Spacer(); FaintText("最大 \(Money.format(mx))"); Spacer(); FaintText("\(m)/\(len)") }
            HStack(spacing: 14) {
                legend(.kAccent, isCur ? "今月" : "この月")
                if hasPrev { legend(.kFaint, "前の月") }
                if ideal != nil { legend(.kSub, "予算の目安") }
            }.padding(.top, 8)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { Capsule().fill(c).frame(width: 14, height: 2); Text(t).font(.system(size: 12)).foregroundStyle(Color.kSub) }
    }
}

// 予算の 1 行（名前・使った額 / 予算・進み具合の棒・あと / こえた額）
struct BudgetRow: View {
    let ctx: GroupCtx
    let b: BudgetStatus
    var tick: Double? = nil
    var body: some View {
        let name = (b.scope == "personal" ? ctx.memberName(b.memberId) + "の負担・" : "") + (ctx.cat(b.categoryId)?.name ?? "全体")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if b.categoryId != nil { CategoryDot(name: name, colorHex: ctx.cat(b.categoryId)?.color, size: 14) }
                Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.kInk)
                Spacer()
                Text("\(Money.format(b.spent)) / \(Money.format(b.amount))").font(.system(size: 14)).monospacedDigit().foregroundStyle(Color.kSub)
            }
            Meter(ratio: b.ratio, color: b.over ? .kDanger : .kAccent, tick: tick).padding(.top, 6)
            FaintText(b.remaining >= 0 ? "あと \(Money.format(b.remaining))" : "\(Money.format(-b.remaining)) こえています").padding(.top, 4)
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
}

struct TxnRow: View {
    let ctx: GroupCtx
    let t: Txn
    var body: some View {
        let c = ctx.cat(t.categoryId)
        let sub = "\(t.occurredOn.dropFirst(5).replacingOccurrences(of: "-", with: "/"))・\(ctx.memberName(t.payerMemberId))が払った" + (t.splitMode != "none" ? "・割り勘" : "") + (t.visibility == "private" ? "・自分だけ" : "")
        ItemRow(title: (c?.name ?? "不明") + (t.memo.isEmpty ? "" : "・\(t.memo)"), sub: sub, amount: (t.kind == "income" ? "+" : "") + Money.format(t.amount), catName: c?.name, catColor: c?.color)
    }
}

// 直せる記録だけ編集画面へ
struct TxnLink: View {
    let ctx: GroupCtx
    let t: Txn
    var body: some View {
        if ctx.canEdit(t) { NavigationLink { TxnEditView(ctx: ctx, txn: t) } label: { TxnRow(ctx: ctx, t: t) }.buttonStyle(.plain) }
        else { TxnRow(ctx: ctx, t: t) }
    }
}

// ---------- その他 ----------
struct MoreView: View {
    let ctx: GroupCtx
    let month: Date
    var body: some View {
        ScrollView {
            ListPaper {
                row("予算") { BudgetView(ctx: ctx, month: month) }
                DashedLine(); row("カテゴリ") { CategoryView(ctx: ctx) }
                DashedLine(); row("メンバーと招待") { MemberView(ctx: ctx) }
                DashedLine(); row("定期的な収支") { RecurringView(ctx: ctx) }
                DashedLine(); row("CSV の書き出し・バックアップ") { ExportView(ctx: ctx) }
                if ctx.can("admin") { DashedLine(); row("操作の履歴") { AuditView(ctx: ctx) } }
                DashedLine(); row("アカウントと設定") { AccountView(ctx: ctx) }
            }.padding(16)
        }.background(Color.kBg)
    }

    private func row<D: View>(_ title: String, @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink(destination: dest) {
            HStack { Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.kInk); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.kFaint) }
                .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
