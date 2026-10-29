import SwiftUI
import Supabase

// ---------- カテゴリ ----------
struct CategoryView: View {
    let ctx: GroupCtx
    @State private var loader: Loader<[Category]>
    @State private var editing: Category?
    @State private var creatingKind: String?
    @State private var name = ""
    @State private var icon = ""
    @State private var del: Category?

    init(ctx: GroupCtx) { self.ctx = ctx; _loader = State(initialValue: Loader { try await ctx.repo.categories(ctx.g) }) }

    var body: some View {
        let admin = ctx.can("admin")
        List {
            if !admin { Text("カテゴリを変えられるのは管理者とオーナーです").font(.footnote) }
            LoadableView(state: loader.state, retry: { await loader.reload() }) { cs in
                ForEach(["expense", "income"], id: \.self) { k in
                    let l = k == "expense" ? "支出" : "収入"
                    Section(l) {
                        ForEach(cs.filter { $0.kind == k && $0.archivedAt == nil }) { c in
                            Button("\(c.icon) \(c.name)") { name = c.name; icon = c.icon; editing = c }.disabled(!admin).foregroundStyle(.primary)
                                .swipeActions { if admin { Button("消す", role: .destructive) { del = c } } }
                        }
                        if admin { Button("＋ \(l)のカテゴリを足す") { name = ""; icon = "・"; creatingKind = k } }
                    }
                }
                let archived = cs.filter { $0.archivedAt != nil }
                if !archived.isEmpty {
                    Section("使われなくなったカテゴリ（過去の記録のために残しています）") { ForEach(archived) { Text("\($0.icon) \($0.name)").foregroundStyle(.secondary) } }
                }
            }
        }
        .navigationTitle("カテゴリ")
        .task { await loader.reload() }
        .toast($loader.message)
        .alert(editing == nil ? "カテゴリを足す" : "カテゴリを直す", isPresented: Binding(get: { editing != nil || creatingKind != nil }, set: { if !$0 { editing = nil; creatingKind = nil } })) {
            TextField("名前", text: $name)
            TextField("絵文字（1 文字）", text: $icon)
            Button("保存") {
                let c = editing, k = creatingKind
                guard Validate.categoryName(name) == nil else { loader.message = Validate.categoryName(name); return }
                Task {
                    if await loader.act("保存しました", {
                        _ = try await ctx.repo.saveCategory(ctx.g, id: c?.id, kind: c?.kind ?? k ?? "expense", name: name, color: c?.color ?? "#6b7280",
                                                            icon: String(icon.prefix(2)).isEmpty ? "・" : String(icon.prefix(2)), sort: c?.sort ?? 100, version: c?.version)
                    }) { await ctx.loadMeta() }
                }
            }
            Button("やめる", role: .cancel) {}
        }
        .confirmationDialog("「\(del?.name ?? "")」を消しますか", isPresented: Binding(get: { del != nil }, set: { if !$0 { del = nil } }), titleVisibility: .visible) {
            Button("消す", role: .destructive) {
                if let c = del {
                    Task {
                        var result = ""
                        if await loader.act(nil, { result = try await ctx.repo.deleteCategory(c.id) }) {
                            loader.message = result == "archived" ? "使われているので、使われなくなったカテゴリに移しました" : "消しました"
                            await ctx.loadMeta()
                        }
                    }
                }
                del = nil
            }
        } message: { Text("記録で使われているときは、消さずに「使われなくなったカテゴリ」に移します（過去の記録はそのまま）。") }
    }
}

// ---------- メンバーと招待 ----------
struct MemberView: View {
    let ctx: GroupCtx
    struct MemberData { let members: [Member]; let invites: [Invitation] }
    @State private var loader: Loader<MemberData>
    @State private var role = "member"
    @State private var hours = 72
    @State private var newCode: NewInvitation?
    @State private var target: Member?
    @State private var confirm: (String, () async throws -> Void)?

    init(ctx: GroupCtx) {
        self.ctx = ctx
        let admin = ctx.can("admin")
        _loader = State(initialValue: Loader { MemberData(members: try await ctx.repo.members(ctx.g), invites: admin ? try await ctx.repo.invitations(ctx.g) : []) })
    }

    var body: some View {
        let admin = ctx.can("admin")
        List {
            LoadableView(state: loader.state, retry: { await loader.reload() }) { d in
                Section("メンバー") {
                    ForEach(d.members.filter { $0.status == "active" }) { m in
                        HStack {
                            VStack(alignment: .leading) { Text(m.displayName + (m.id == ctx.me?.id ? "（あなた）" : "")); Text(roleNames[m.role] ?? m.role).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if admin && m.id != ctx.me?.id && m.role != "owner" { Button("変える") { target = m }.buttonStyle(.borderless) }
                        }
                    }
                }
                let gone = d.members.filter { $0.status != "active" }
                if !gone.isEmpty { Section("抜けた人（過去の記録のために名前を残しています）") { ForEach(gone) { Text($0.displayName).foregroundStyle(.secondary) } } }
                if admin {
                    Section {
                        Picker("権限", selection: $role) { Text("メンバー").tag("member"); Text("閲覧のみ").tag("viewer") }.pickerStyle(.segmented)
                        Picker("期限", selection: $hours) { Text("1 日").tag(24); Text("3 日").tag(72); Text("7 日").tag(168) }.pickerStyle(.segmented)
                        Button("招待コードを作る（1 人用）") { Task { await loader.act(nil) { newCode = try await ctx.repo.createInvitation(ctx.g, role: role, hours: hours, maxUses: 1) } } }.disabled(loader.busy)
                    } header: { Text("招待する") } footer: { Text("招待コードは作ったときに 1 度だけ表示されます。LINE などで本人にだけ送ってください。") }
                    let live = d.invites.filter { $0.revokedAt == nil && $0.usedCount < $0.maxUses }
                    if !live.isEmpty {
                        Section("有効な招待") {
                            ForEach(live) { i in
                                VStack(alignment: .leading) {
                                    Text("…\(i.codeHint)（\(roleNames[i.role] ?? i.role)）")
                                    Text("期限 \(i.expiresAt.prefix(16).replacingOccurrences(of: "T", with: " "))（UTC）・\(i.usedCount)/\(i.maxUses) 回").font(.caption).foregroundStyle(.secondary)
                                }.swipeActions { Button("取り消す", role: .destructive) { Task { await loader.act("招待を取り消しました") { try await ctx.repo.revokeInvitation(i.id) } } } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("メンバーと招待")
        .task { await loader.reload() }
        .toast($loader.message)
        .alert("招待コード", isPresented: Binding(get: { newCode != nil }, set: { if !$0 { newCode = nil } })) {
            Button("コピー") { UIPasteboard.general.string = newCode?.code; ctx.app.toast = "コピーしました" }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("\(MemberView.grouped(newCode?.code ?? ""))\nこの画面を閉じると、もう表示できません。")
        }
        .confirmationDialog(target?.displayName ?? "", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible) {
            if let m = target {
                ForEach(["admin", "member", "viewer"].filter { $0 != m.role && ($0 != "admin" || ctx.can("owner")) }, id: \.self) { r in
                    Button("\(roleNames[r]!)にする") { Task { if await loader.act("\(roleNames[r]!)にしました", { _ = try await ctx.repo.changeRole(m.id, r) }) { await ctx.app.refreshMembers() } } }
                }
                if ctx.can("owner") { Button("オーナーを渡す") { confirm = ("\(m.displayName)さんをオーナーにします。あなたは管理者になります。", { try await ctx.repo.transferOwnership(m.id) }) } }
                Button("グループから外す", role: .destructive) { confirm = ("\(m.displayName)さんをグループから外します。過去の記録と精算の差額は残ります。", { try await ctx.repo.removeMember(m.id) }) }
            }
        }
        .alert("よろしいですか", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("はい", role: .destructive) { if let c = confirm { Task { if await loader.act("変更しました", c.1) { await ctx.app.refreshMembers() } } } }
            Button("やめる", role: .cancel) {}
        } message: { Text(confirm?.0 ?? "") }
    }
}

extension MemberView {
    // 読みやすいよう 4 文字ずつ区切る（参加するときの区切りは無視される）
    static func grouped(_ code: String) -> String {
        let c = Array(code)
        return stride(from: 0, to: c.count, by: 4).map { String(c[$0..<Swift.min($0 + 4, c.count)]) }.joined(separator: "-")
    }
}

// ---------- 定期的な収支（期日が来たら自動で記録。何度動いても二重にならない） ----------
struct RecurringView: View {
    let ctx: GroupCtx
    @State private var loader: Loader<[Recurring]>
    @State private var kind = "expense"
    @State private var amount = ""
    @State private var catId: String?
    @State private var payerId: String?
    @State private var memo = ""
    @State private var freq = "monthly"
    @State private var day = 1
    @State private var weekday = 1
    @State private var monthOfYear = 1
    @State private var start = Money.todayJST()
    @State private var equal = false
    @State private var del: Recurring?
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    init(ctx: GroupCtx) {
        self.ctx = ctx
        _loader = State(initialValue: Loader { try await ctx.repo.recurring(ctx.g) })
        _payerId = State(initialValue: ctx.me?.id)
    }

    var body: some View {
        Form {
            LoadableView(state: loader.state, retry: { await loader.reload() }, isEmpty: { $0.isEmpty }, empty: {
                EmptyBox(title: "定期的な収支はありません", message: "家賃や給料、サブスクを登録すると、期日に自動で記録されます")
            }) { rs in
                Section("登録済み") {
                    ForEach(rs) { r in
                        VStack(alignment: .leading) {
                            Text("\(ctx.cat(r.categoryId)?.name ?? "不明") \(Money.format(r.amount))" + (r.memo.isEmpty ? "" : "・\(r.memo)"))
                            Text("\(rule(r))（月末より後の日は月末に）・次は \(r.nextRunOn)" + (r.active ? "" : "・停止中")).font(.caption).foregroundStyle(.secondary)
                        }.swipeActions { if ctx.can("admin") { Button("やめる", role: .destructive) { del = r } } }
                    }
                }
            }
            if ctx.can("admin") {
                Section("登録する") {
                    Picker("種類", selection: $kind) { Text("支出").tag("expense"); Text("収入").tag("income") }.pickerStyle(.segmented)
                    AmountField(label: "金額（円）", text: $amount)
                    Picker("カテゴリ", selection: $catId) {
                        Text("選んでください").tag(String?.none)
                        ForEach(ctx.cats.filter { $0.kind == kind && $0.archivedAt == nil }) { Text("\($0.icon) \($0.name)").tag(Optional($0.id)) }
                    }
                    Picker(kind == "income" ? "受け取る人" : "払う人", selection: $payerId) { ForEach(ctx.activeMembers) { Text($0.displayName).tag(Optional($0.id)) } }
                    TextField("メモ（例: 家賃）", text: $memo)
                    Picker("くり返し", selection: $freq) { Text("毎週").tag("weekly"); Text("毎月").tag("monthly"); Text("毎年").tag("yearly") }.pickerStyle(.segmented)
                    switch freq {
                    case "weekly": Picker("曜日", selection: $weekday) { ForEach(0..<7, id: \.self) { Text(weekdays[$0]).tag($0) } }
                    case "monthly": Stepper("毎月 \(day) 日（31 は月末）", value: $day, in: 1...31)
                    default:
                        Stepper("\(monthOfYear) 月", value: $monthOfYear, in: 1...12)
                        Stepper("\(day) 日", value: $day, in: 1...31)
                    }
                    DatePicker("開始日", selection: $start, displayedComponents: .date).environment(\.timeZone, Money.tokyo)
                    if kind == "expense" { Toggle("今いる全員で均等に割り勘", isOn: $equal) }
                    let err = Validate.amount(amount) ?? (catId == nil ? "カテゴリを選んでください" : nil) ?? (payerId == nil ? "払う人を選んでください" : nil)
                    if let err { Text(err).font(.caption).foregroundStyle(.red) }
                    Button("登録する") { save() }.disabled(err != nil || loader.busy)
                }
            }
        }
        .navigationTitle("定期的な収支")
        .task { await loader.reload() }
        .toast($loader.message)
        .confirmationDialog("定期的な収支をやめますか", isPresented: Binding(get: { del != nil }, set: { if !$0 { del = nil } }), titleVisibility: .visible) {
            Button("やめる", role: .destructive) { if let r = del { Task { await loader.act("やめました") { try await ctx.repo.deleteRecurring(r.id) } } }; del = nil }
        } message: { Text("これから先は自動で記録しません。もう記録された分は残ります。") }
    }

    private func rule(_ r: Recurring) -> String {
        switch r.freq {
        case "weekly": "毎週\(weekdays[r.weekday ?? 0])曜"
        case "monthly": "毎月\(r.dayOfMonth ?? 1)日"
        default: "毎年\(r.monthOfYear ?? 1)月\(r.dayOfMonth ?? 1)日"
        }
    }

    private func save() {
        let split = equal && kind == "expense"
        var p: [String: AnyJSON] = [
            "kind": .string(kind), "amount": .integer(Int(Money.parse(amount) ?? 0)), "category_id": .string(catId ?? ""), "payer_member_id": .string(payerId ?? ""),
            "memo": .string(memo.trimmingCharacters(in: .whitespaces)), "split_mode": .string(split ? "equal" : "none"),
            "splits": .array(split ? ctx.activeMembers.map { .string($0.id) } : []), "freq": .string(freq), "start_on": .string(Money.dateString(start)),
        ]
        switch freq {
        case "weekly": p["weekday"] = .integer(weekday)
        case "monthly": p["day_of_month"] = .integer(day)
        default: p["day_of_month"] = .integer(day); p["month_of_year"] = .integer(monthOfYear)
        }
        let params = p
        Task {
            if await loader.act("登録しました", { try await ctx.repo.saveRecurring(ctx.g, params); try await ctx.repo.generateDue(ctx.g) }) {
                amount = ""; memo = ""; ctx.refresh += 1
            }
        }
    }
}

// ---------- 操作の履歴（管理者以上） ----------
struct AuditView: View {
    let ctx: GroupCtx
    @State private var state: Loadable<[AuditLog]> = .loading
    private let tables = ["transactions": "収支", "settlements": "精算", "group_members": "メンバー", "invitations": "招待", "categories": "カテゴリ", "budgets": "予算",
                          "recurring_transactions": "定期", "groups": "グループ", "payment_methods": "支払い方法", "transaction_splits": "割り勘"]
    private let actions = ["insert": "追加", "update": "変更", "delete": "削除"]

    var body: some View {
        List {
            LoadableView(state: state, retry: load, isEmpty: { $0.isEmpty }, empty: { EmptyBox(title: "履歴はありません", message: "") }) { logs in
                ForEach(logs) { l in
                    let who = ctx.members.first { $0.userId?.lowercased() == l.actor?.lowercased() }?.displayName ?? (l.actor == nil ? "自動" : "抜けた人")
                    let extra = [l.detail?.amount.map { Money.format($0) }, l.detail?.statusTo.map { "状態→\($0)" }, l.detail?.roleTo.map { "権限→\(roleNames[$0] ?? $0)" }].compactMap { $0 }.joined(separator: "・")
                    VStack(alignment: .leading) {
                        Text("\(who)が\(tables[l.targetTable] ?? l.targetTable)を\(actions[String(l.action.split(separator: ".").last ?? "")] ?? l.action)" + (extra.isEmpty ? "" : "（\(extra)）"))
                        Text(l.at.prefix(19).replacingOccurrences(of: "T", with: " ") + "（UTC）").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("操作の履歴")
        .task { await load() }
    }

    private func load() async {
        do { state = .ready(try await ctx.repo.audit(ctx.g)) } catch { state = .failed(Repo.map(error)) }
    }
}

// ---------- アカウントと設定 ----------
struct AccountView: View {
    let ctx: GroupCtx
    @State private var name = ""
    @State private var groupName = ""
    @State private var password = ""
    @State private var email = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirm: (String, String, () async throws -> Void)?

    var body: some View {
        Form {
            if let message { Text(message).foregroundStyle(Color.income) }
            Section("表示名") {
                TextField("表示名", text: $name)
                Button("変える") { if let e = Validate.displayName(name) { message = e } else { run("表示名を変えました") { _ = try await ctx.repo.updateProfile(name); await ctx.app.refreshMembers() } } }.disabled(busy)
            }
            if ctx.can("admin") {
                Section("家計簿の名前") {
                    TextField("家計簿の名前", text: $groupName)
                    Button("変える") {
                        if let e = Validate.groupName(groupName) { message = e } else { run("名前を変えました") { _ = try await ctx.repo.renameGroup(ctx.g, groupName); await ctx.app.loadGroups() } }
                    }.disabled(busy)
                }
            }
            Section("パスワード") {
                SecureField("新しいパスワード（8 文字以上）", text: $password).textContentType(.newPassword)
                Button("変える") { if let e = Validate.password(password) { message = e } else { run("パスワードを変えました") { try await ctx.repo.changePassword(password); password = "" } } }.disabled(busy)
            }
            Section("メールアドレス") {
                TextField("新しいメールアドレス", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                Button("変える") { if let e = Validate.email(email) { message = e } else { run("確認のメールを送りました。新しいアドレスで確認すると変わります") { try await ctx.repo.changeEmail(email) } } }.disabled(busy)
            }
            Section("ログアウト・退出・削除") {
                Button("ログアウト") { Task { await ctx.app.signOut() } }
                if ctx.me?.role != "owner" {
                    Button("この家計簿から抜ける", role: .destructive) {
                        confirm = ("この家計簿から抜けますか", "抜けても過去の記録と精算の差額は残ります。", { try await ctx.repo.leaveGroup(ctx.g); await ctx.app.select(nil); await ctx.app.loadGroups() })
                    }
                }
                if ctx.can("owner") {
                    Button("この家計簿を削除する", role: .destructive) {
                        confirm = ("この家計簿を削除しますか", "全員がこの家計簿を見られなくなります。先に CSV で書き出しておくことをおすすめします。", { try await ctx.repo.deleteGroup(ctx.g); await ctx.app.select(nil); await ctx.app.loadGroups() })
                    }
                }
                Button("アカウントを削除する", role: .destructive) {
                    confirm = ("アカウントを削除しますか", "ログインできなくなります。オーナーの家計簿があるときは、先に誰かにオーナーを渡してください。元には戻せません。", {
                        switch try await ctx.repo.deleteAccount() {
                        case nil: await ctx.app.signOut()
                        case "owner_must_transfer": throw AppError(kind: .Conflict, key: "owner_must_transfer")
                        default: throw AppError(kind: .Server)
                        }
                    })
                }
            }
        }
        .navigationTitle("アカウントと設定")
        .onAppear { name = ctx.me?.displayName ?? ""; groupName = ctx.group.name }
        .alert(confirm?.0 ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("はい", role: .destructive) { if let c = confirm { run("完了しました", c.2) } }
            Button("やめる", role: .cancel) {}
        } message: { Text(confirm?.1 ?? "") }
    }

    private func run(_ ok: String, _ block: @escaping () async throws -> Void) {
        busy = true; message = nil
        Task { @MainActor in
            do { try await block(); message = ok } catch { message = Repo.map(error).userMessage }
            busy = false
        }
    }
}

// ---------- CSV の書き出し（Excel で文字化けしないよう UTF-8 の BOM 付き） ----------
struct ExportView: View {
    let ctx: GroupCtx
    @State private var from = Money.addMonths(Money.monthStart(Money.todayJST()), -11)
    @State private var to = Money.todayJST()
    @State private var file: URL?
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        Form {
            Text("あなたが見られる記録（自分だけの記録を含む）を CSV にします。")
            DatePicker("いつから", selection: $from, displayedComponents: .date).environment(\.timeZone, Money.tokyo)
            DatePicker("いつまで", selection: $to, displayedComponents: .date).environment(\.timeZone, Money.tokyo)
            Button("CSV を作る") { make() }.disabled(busy)
            if let file { ShareLink(item: file) { Label("保存・共有する", systemImage: "square.and.arrow.up") } }
            if let message { Text(message) }
            Section("バックアップについて") {
                Text("無料プランの Supabase は自動バックアップがありません。管理者が定期的に pg_dump でバックアップを取ります（docs/backup-restore.md）。この CSV は個人の控えとして使えます。").font(.footnote)
            }
        }
        .navigationTitle("書き出し")
    }

    private func make() {
        if to < from { message = "期間が逆です"; return }
        busy = true; message = nil; file = nil
        Task { @MainActor in
            do {
                let list = try await ctx.repo.transactions(ctx.g, from: from, toExclusive: Money.addDays(to, 1))
                let splits = Dictionary(grouping: try await ctx.repo.splits(list.filter { $0.splitMode != "none" }.map(\.id)), by: \.transactionId)
                let csv = Csv.transactions(list, splits: splits, cat: { ctx.cat($0)?.name ?? "" }, member: ctx.memberName, pm: { id in ctx.pms.first { $0.id == id }?.name ?? "" })
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
                try? FileManager.default.removeItem(at: dir)   // 前回の書き出しを残さない
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("kakeibo_\(Money.dateString(from))_\(Money.dateString(to)).csv")
                try (Csv.bom + Data(csv.utf8)).write(to: url, options: [.completeFileProtection])
                file = url
                message = "\(list.count) 件を書き出しました"
            } catch { message = (error as? AppError)?.userMessage ?? "ファイルを作れませんでした" }
            busy = false
        }
    }
}

enum Csv {
    static let bom = Data([0xEF, 0xBB, 0xBF])
    static let header = ["日付", "種類", "金額", "カテゴリ", "払った人", "支払い方法", "メモ", "公開範囲", "割り勘", "負担の内訳", "ID"]

    // 表計算ソフトで式として動かないよう、= + - @ で始まる値の先頭に ' を付ける
    static func cell(_ s: String) -> String {
        let safe = (s.first.map { "=+-@\t\r".contains($0) } ?? false) ? "'" + s : s
        return safe.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
    }
    static func row(_ cells: [String]) -> String { cells.map(cell).joined(separator: ",") }

    static func transactions(_ list: [Txn], splits: [String: [Split]], cat: (String) -> String, member: (String?) -> String, pm: (String?) -> String) -> String {
        var out = row(header) + "\r\n"
        for t in list.sorted(by: { $0.occurredOn < $1.occurredOn }) {
            let mode = t.splitMode == "equal" ? "均等" : t.splitMode == "custom" ? "指定" : ""
            let detail = (splits[t.id] ?? []).map { "\(member($0.memberId)):\($0.amount)" }.joined(separator: " ")
            out += row([t.occurredOn, t.kind == "income" ? "収入" : "支出", String(t.amount), cat(t.categoryId), member(t.payerMemberId), pm(t.paymentMethodId), t.memo,
                        t.visibility == "private" ? "自分だけ" : "グループ", mode, detail, t.id]) + "\r\n"
        }
        return out
    }
}
