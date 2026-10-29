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
                    nav { SettlementView(ctx: ctx) }.tabItem { Label("精算", systemImage: "arrow.left.arrow.right") }
                    nav { ReportView(ctx: ctx, month: $month) }.tabItem { Label("レポート", systemImage: "chart.bar") }
                    nav { MoreView(ctx: ctx, month: month) }.tabItem { Label("その他", systemImage: "ellipsis") }
                }
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { TxnEditView(ctx: ctx, txn: nil) } }
    }

    private func nav<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        NavigationStack {
            v()
                .navigationBarTitleDisplayMode(.inline)
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

// ---------- ホーム ----------
struct DashboardView: View {
    let ctx: GroupCtx
    @Binding var month: Date
    struct Dash { let sum: MonthSummary; let budgets: [BudgetStatus]; let recent: [Txn]; let balances: [Balance] }
    @State private var state: Loadable<Dash> = .loading

    var body: some View {
        List {
            MonthBar(month: $month)
            LoadableView(state: state, retry: load) { d in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今月の収支").font(.subheadline)
                        MoneyText(yen: d.sum.balance, big: true, signed: true, color: d.sum.balance < 0 ? .over : nil)
                        HStack {
                            VStack(alignment: .leading) { Text("収入").font(.caption); MoneyText(yen: d.sum.income, color: .income) }
                            Spacer()
                            VStack(alignment: .leading) { Text("支出").font(.caption); MoneyText(yen: d.sum.expense) }
                            Spacer()
                        }
                        if d.sum.prevExpense > 0 {
                            let diff = d.sum.expense - d.sum.prevExpense
                            Text("先月の支出より \(Money.format(Swift.abs(diff))) \(diff >= 0 ? "多い" : "少ない")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !d.budgets.isEmpty { Section("予算") { ForEach(d.budgets, id: \.budgetId) { BudgetRow(ctx: ctx, b: $0) } } }
                if let mine = d.balances.first(where: { $0.memberId == ctx.me?.id }), d.balances.count > 1 {
                    Section("精算") {
                        Text(mine.net > 0 ? "あなたは \(Money.format(mine.net)) 受け取る側です" : mine.net < 0 ? "あなたは \(Money.format(-mine.net)) 払う側です" : "あなたの精算は済んでいます")
                    }
                }
                Section("最近の記録") {
                    if d.recent.isEmpty { EmptyBox(title: "まだ記録がありません", message: ctx.can("member") ? "右上の＋から最初の収支を入れてください" : "閲覧のみの権限です") }
                    ForEach(d.recent) { t in TxnLink(ctx: ctx, t: t) }
                }
            }
        }
        .task(id: "\(month)-\(ctx.refresh)") { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            state = .ready(Dash(sum: try await ctx.repo.monthSummary(ctx.g, month), budgets: try await ctx.repo.budgetStatus(ctx.g, month),
                                recent: try await ctx.repo.recentTransactions(ctx.g), balances: try await ctx.repo.balances(ctx.g)))
        } catch { state = .failed(Repo.map(error)) }
    }
}

struct BudgetRow: View {
    let ctx: GroupCtx
    let b: BudgetStatus
    var body: some View {
        let name = (b.scope == "personal" ? ctx.memberName(b.memberId) + "の負担・" : "") + (ctx.cat(b.categoryId)?.name ?? "全体")
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name); Spacer(); Text("\(Money.format(b.spent)) / \(Money.format(b.amount))").font(.caption).monospacedDigit() }
            ProgressView(value: min(Swift.max(b.ratio, 0), 1)).tint(b.over ? .over : b.ratio >= 0.8 ? .orange : .income)
            if b.over { Text("予算を \(Money.format(-b.remaining)) こえています").font(.caption).foregroundStyle(Color.over) }
            else if b.ratio >= 0.8 { Text("残り \(Money.format(b.remaining))（8 割をこえました）").font(.caption) }
        }.accessibilityElement(children: .combine)
    }
}

struct TxnRow: View {
    let ctx: GroupCtx
    let t: Txn
    var body: some View {
        let c = ctx.cat(t.categoryId)
        HStack(spacing: 10) {
            Text(c?.icon ?? "・").font(.title3).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text((c?.name ?? "不明") + (t.memo.isEmpty ? "" : "・\(t.memo)")).lineLimit(1)
                Text("\(t.occurredOn.dropFirst(5).replacingOccurrences(of: "-", with: "/"))・\(ctx.memberName(t.payerMemberId))が払った" + (t.splitMode != "none" ? "・割り勘" : "") + (t.visibility == "private" ? "・自分だけ" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            MoneyText(yen: t.kind == "income" ? t.amount : -t.amount, signed: true, color: t.kind == "income" ? .income : nil)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

// 直せる記録だけ編集画面へ
struct TxnLink: View {
    let ctx: GroupCtx
    let t: Txn
    var body: some View {
        if ctx.canEdit(t) { NavigationLink { TxnEditView(ctx: ctx, txn: t) } label: { TxnRow(ctx: ctx, t: t) } }
        else { TxnRow(ctx: ctx, t: t) }
    }
}

// ---------- その他 ----------
struct MoreView: View {
    let ctx: GroupCtx
    let month: Date
    var body: some View {
        List {
            NavigationLink("予算") { BudgetView(ctx: ctx, month: month) }
            NavigationLink("カテゴリ") { CategoryView(ctx: ctx) }
            NavigationLink("メンバーと招待") { MemberView(ctx: ctx) }
            NavigationLink("定期的な収支") { RecurringView(ctx: ctx) }
            NavigationLink("CSV の書き出し・バックアップ") { ExportView(ctx: ctx) }
            if ctx.can("admin") { NavigationLink("操作の履歴") { AuditView(ctx: ctx) } }
            NavigationLink("アカウントと設定") { AccountView(ctx: ctx) }
        }
    }
}
