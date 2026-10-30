import Foundation
import Supabase

// サーバー（Supabase）とのやりとり。書き込みと計算はすべて DB の関数（RPC）。権限は RLS と関数で確かめられる（Android の Repo.kt と同じ）
final class Repo: @unchecked Sendable {
    let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    // ログインのセッションは Keychain に保存（端末の外やバックアップに平文で出さない）
    static func create() -> Repo? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String, s.hasPrefix("https://"), let url = URL(string: s),
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String, !key.isEmpty else { return nil }
        return Repo(client: SupabaseClient(supabaseURL: url, supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(storage: KeychainLocalStorage(service: "jp.kakeibo.share.session"), autoRefreshToken: true))))
    }

    var userId: String? { client.auth.currentUser?.id.uuidString.lowercased() }

    // 例外を共通のエラー分類にする（保存に失敗したら、必ず呼び出し側にエラーとして返す）
    static func map(_ error: Error) -> AppError {
        if let e = error as? AppError { return e }
        if let e = error as? PostgrestError { return AppError.fromCode(e.code, message: e.message, hint: e.hint, http: nil) }
        if let e = error as? AuthError {
            let code = e.errorCode.rawValue
            switch code {
            case "over_email_send_rate_limit", "over_request_rate_limit": return AppError(kind: .Conflict, key: code)
            case "session_not_found", "session_expired", "refresh_token_not_found": return AppError(kind: .Unauthorized, key: code)
            default: return AppError(kind: .Validation, key: code)
            }
        }
        if error is URLError { return AppError(kind: .Network) }
        if (error as NSError).domain == NSURLErrorDomain { return AppError(kind: .Network) }
        return AppError(kind: .Server)
    }

    private func call<T>(_ block: () async throws -> T) async throws -> T {
        do { return try await block() } catch { throw Repo.map(error) }
    }
    private func rpc<T: Decodable>(_ fn: String, _ params: [String: AnyJSON]) async throws -> T {
        try await call { try await client.rpc(fn, params: params).execute().value }
    }
    private func rpcVoid(_ fn: String, _ params: [String: AnyJSON]) async throws {
        _ = try await call { try await client.rpc(fn, params: params).execute() }
    }
    private func s(_ v: String?) -> AnyJSON { v.map { .string($0) } ?? .null }
    private func i(_ v: Int?) -> AnyJSON { v.map { .integer($0) } ?? .null }
    private func month(_ d: Date) -> AnyJSON { .string(Money.dateString(Money.monthStart(d))) }

    // ---------- 認証（パスワード再設定と登録の確認は、メールの 6 桁のコード） ----------
    func signUp(email: String, password: String, displayName: String) async throws -> Bool {
        try await call {
            let r = try await client.auth.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password,
                                                 data: ["display_name": .string(displayName.trimmingCharacters(in: .whitespaces))])
            return r.session != nil
        }
    }
    func verifySignUp(email: String, code: String) async throws { _ = try await call { try await client.auth.verifyOTP(email: email.trimmingCharacters(in: .whitespaces), token: code, type: .email) } }
    func signIn(email: String, password: String) async throws { _ = try await call { try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) } }
    func signOut() async throws { try await call { try await client.auth.signOut() } }
    func sendReset(email: String) async throws { try await call { try await client.auth.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces)) } }
    func verifyReset(email: String, code: String) async throws { _ = try await call { try await client.auth.verifyOTP(email: email.trimmingCharacters(in: .whitespaces), token: code, type: .recovery) } }
    func changePassword(_ pw: String) async throws { _ = try await call { try await client.auth.update(user: UserAttributes(password: pw)) } }
    func changeEmail(_ email: String) async throws { _ = try await call { try await client.auth.update(user: UserAttributes(email: email.trimmingCharacters(in: .whitespaces))) } }

    // 戻り値: nil = 削除できた / "owner_must_transfer" など = できなかった理由
    func deleteAccount() async throws -> String? {
        do {
            try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(body: ["confirm": "DELETE"]))
            return nil
        } catch let FunctionsError.httpError(_, data) {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return obj?["code"] as? String ?? "server"
        } catch { throw Repo.map(error) }
    }

    // ---------- プロフィール・グループ ----------
    func updateProfile(_ name: String) async throws -> Profile { try await rpc("update_profile", ["p_display_name": .string(name.trimmingCharacters(in: .whitespaces))]) }
    func groups() async throws -> [KGroup] { try await call { try await client.from("groups").select().order("created_at", ascending: true).execute().value } }
    func createGroup(_ name: String) async throws -> KGroup { try await rpc("create_group", ["p_name": .string(name.trimmingCharacters(in: .whitespaces))]) }
    func renameGroup(_ g: String, _ name: String) async throws -> KGroup { try await rpc("rename_group", ["p_group": .string(g), "p_name": .string(name.trimmingCharacters(in: .whitespaces))]) }
    func deleteGroup(_ g: String) async throws { try await rpcVoid("delete_group", ["p_group": .string(g)]) }
    func leaveGroup(_ g: String) async throws { try await rpcVoid("leave_group", ["p_group": .string(g)]) }

    // ---------- メンバー・招待 ----------
    func members(_ g: String) async throws -> [Member] { try await call { try await client.from("group_members").select().eq("group_id", value: g).order("joined_at", ascending: true).execute().value } }
    func changeRole(_ m: String, _ role: String) async throws -> Member { try await rpc("change_member_role", ["p_member": .string(m), "p_role": .string(role)]) }
    func removeMember(_ m: String) async throws { try await rpcVoid("remove_member", ["p_member": .string(m)]) }
    func transferOwnership(_ m: String) async throws { try await rpcVoid("transfer_ownership", ["p_member": .string(m)]) }
    func invitations(_ g: String) async throws -> [Invitation] { try await call { try await client.from("invitations").select().eq("group_id", value: g).order("created_at", ascending: false).execute().value } }
    func createInvitation(_ g: String, role: String, hours: Int, maxUses: Int) async throws -> NewInvitation {
        try await rpc("create_invitation", ["p_group": .string(g), "p_role": .string(role), "p_expires_hours": .integer(hours), "p_max_uses": .integer(maxUses)])
    }
    func revokeInvitation(_ id: String) async throws { try await rpcVoid("revoke_invitation", ["p_invitation": .string(id)]) }
    // 無効なコードはサーバーが null を返す（総当たりを数えるため）
    func acceptInvitation(_ code: String) async throws -> Member? { try await rpc("accept_invitation", ["p_code": .string(code)]) }

    // ---------- カテゴリ・支払い方法 ----------
    func categories(_ g: String) async throws -> [Category] { try await call { try await client.from("categories").select().eq("group_id", value: g).order("sort", ascending: true).execute().value } }
    func saveCategory(_ g: String, id: String?, kind: String, name: String, color: String, icon: String, sort: Int, version: Int?) async throws -> Category {
        try await rpc("save_category", ["p_group": .string(g), "p_id": s(id), "p_kind": .string(kind), "p_name": .string(name.trimmingCharacters(in: .whitespaces)),
                                        "p_color": .string(color), "p_icon": .string(icon), "p_sort": .integer(sort), "p_version": i(version)])
    }
    func deleteCategory(_ id: String) async throws -> String { try await rpc("delete_category", ["p_category": .string(id)]) }
    func paymentMethods(_ g: String) async throws -> [PaymentMethod] { try await call { try await client.from("payment_methods").select().eq("group_id", value: g).execute().value } }

    // ---------- 取引 ----------
    func transactions(_ g: String, from: Date, toExclusive: Date) async throws -> [Txn] {
        try await call {
            try await client.from("transactions").select().eq("group_id", value: g).eq("status", value: "active")
                .gte("occurred_on", value: Money.dateString(from)).lt("occurred_on", value: Money.dateString(toExclusive))
                .order("occurred_on", ascending: false).order("created_at", ascending: false).execute().value
        }
    }
    func recentTransactions(_ g: String, limit: Int = 5) async throws -> [Txn] {
        try await call { try await client.from("transactions").select().eq("group_id", value: g).eq("status", value: "active").order("occurred_on", ascending: false).order("created_at", ascending: false).limit(limit).execute().value }
    }
    func splits(_ ids: [String]) async throws -> [Split] {
        if ids.isEmpty { return [] }
        return try await call { try await client.from("transaction_splits").select().in("transaction_id", values: ids).execute().value }
    }
    func saveTransaction(_ g: String, _ t: TxnInput) async throws -> Txn {
        var p: [String: AnyJSON] = [
            "client_request_id": .string(t.clientRequestId), "kind": .string(t.kind), "amount": .integer(Int(t.amount)), "occurred_on": .string(t.occurredOn),
            "category_id": .string(t.categoryId), "payer_member_id": .string(t.payerMemberId), "payment_method_id": s(t.paymentMethodId),
            "memo": .string(t.memo), "visibility": .string(t.visibility), "split_mode": .string(t.splitMode), "is_refund": .bool(t.isRefund),
        ]
        if let id = t.id { p["id"] = .string(id) }
        if let v = t.version { p["version"] = .integer(v) }
        switch t.splitMode {
        case "equal": p["splits"] = .array(t.equalMembers.map { .string($0) })
        case "custom": p["splits"] = .array(t.customShares.map { .object(["member_id": .string($0.key), "amount": .integer(Int($0.value))]) })
        default: p["splits"] = .array([])
        }
        return try await rpc("save_transaction", ["p_group": .string(g), "p": .object(p)])
    }
    func deleteTransaction(_ id: String, version: Int) async throws { try await rpcVoid("delete_transaction", ["p_id": .string(id), "p_version": .integer(version)]) }
    func similar(_ g: String, amount: Int64, date: String, category: String) async throws -> [Txn] {
        try await rpc("similar_transactions", ["p_group": .string(g), "p_amount": .integer(Int(amount)), "p_occurred_on": .string(date), "p_category": .string(category)])
    }

    // ---------- 集計・予算 ----------
    func monthSummary(_ g: String, _ m: Date) async throws -> MonthSummary { try await rpc("month_summary", ["p_group": .string(g), "p_month": month(m)]) }
    func monthlySeries(_ g: String, end: Date, months: Int = 6) async throws -> [MonthPoint] { try await rpc("monthly_series", ["p_group": .string(g), "p_end_month": month(end), "p_months": .integer(months)]) }
    func budgetStatus(_ g: String, _ m: Date) async throws -> [BudgetStatus] { try await rpc("budget_status", ["p_group": .string(g), "p_month": month(m)]) }
    func saveBudget(_ g: String, scope: String, category: String?, member: String?, start: Date, amount: Int64, rollover: Bool = false) async throws {
        try await rpcVoid("save_budget", ["p_group": .string(g), "p_scope": .string(scope), "p_category": s(category), "p_member": s(member), "p_start_month": month(start), "p_amount": .integer(Int(amount)), "p_rollover": .bool(rollover)])
    }
    func deleteBudget(_ id: String) async throws { try await rpcVoid("delete_budget", ["p_id": .string(id)]) }

    // ---------- 精算 ----------
    func balances(_ g: String) async throws -> [Balance] { try await rpc("group_balances", ["p_group": .string(g)]) }
    func suggestions(_ g: String) async throws -> [Suggestion] { try await rpc("settlement_suggestions", ["p_group": .string(g)]) }
    func settlements(_ g: String) async throws -> [Settlement] { try await call { try await client.from("settlements").select().eq("group_id", value: g).order("created_at", ascending: false).execute().value } }
    func recordSettlement(_ g: String, from: String, to: String, amount: Int64, note: String, requestId: String) async throws {
        try await rpcVoid("record_settlement", ["p_group": .string(g), "p_from": .string(from), "p_to": .string(to), "p_amount": .integer(Int(amount)), "p_note": .string(note), "p_client_request_id": .string(requestId)])
    }
    func confirmSettlement(_ id: String) async throws { try await rpcVoid("confirm_settlement", ["p_id": .string(id)]) }
    func cancelSettlement(_ id: String) async throws { try await rpcVoid("cancel_settlement", ["p_id": .string(id)]) }

    // ---------- 定期取引 ----------
    func recurring(_ g: String) async throws -> [Recurring] { try await call { try await client.from("recurring_transactions").select().eq("group_id", value: g).order("next_run_on", ascending: true).execute().value } }
    func saveRecurring(_ g: String, _ p: [String: AnyJSON]) async throws { try await rpcVoid("save_recurring", ["p_group": .string(g), "p": .object(p)]) }
    func deleteRecurring(_ id: String) async throws { try await rpcVoid("delete_recurring", ["p_id": .string(id)]) }
    @discardableResult func generateDue(_ g: String) async throws -> Int { try await rpc("generate_due_recurring", ["p_group": .string(g)]) }

    // ---------- 貯金 ----------
    func goals(_ g: String) async throws -> [SavingsGoal] {
        try await call { try await client.from("savings_goals").select().eq("group_id", value: g).is("archived_at", value: nil).order("created_at", ascending: true).execute().value }
    }
    func saveGoal(_ g: String, goal: SavingsGoal?, name: String, target: Int64, dueMonth: Date?, isMain: Bool, autoAmount: Int64?, autoDom: Int?, startOn: Date, isPrivate: Bool) async throws {
        var p: [String: AnyJSON] = [
            "name": .string(name.trimmingCharacters(in: .whitespaces)), "target": .integer(Int(target)),
            "due_month": dueMonth.map { .string(Money.dateString(Money.monthStart($0))) } ?? .null, "is_main": .bool(isMain),
            "auto_amount": autoAmount.map { .integer(Int($0)) } ?? .null, "auto_dom": i(autoDom),
            "start_on": .string(Money.dateString(startOn)), "visibility": .string(isPrivate ? "private" : "group"),
        ]
        if let goal { p["id"] = .string(goal.id); p["version"] = .integer(goal.version) }
        try await rpcVoid("save_goal", ["p_group": .string(g), "p": .object(p)])
    }
    func archiveGoal(_ id: String) async throws { try await rpcVoid("archive_goal", ["p_id": .string(id)]) }
    func recordSaving(goal: String, day: Date, amount: Int64, kind: String, memo: String, requestId: String) async throws {
        try await rpcVoid("record_saving", ["p_goal": .string(goal), "p_day": .string(Money.dateString(day)), "p_amount": .integer(Int(amount)),
                                            "p_kind": .string(kind), "p_memo": .string(memo), "p_client_request_id": .string(requestId)])
    }
    func deleteSaving(_ id: String) async throws { try await rpcVoid("delete_saving", ["p_id": .string(id)]) }
    @discardableResult func generateDueSavings(_ g: String) async throws -> Int { try await rpc("generate_due_savings", ["p_group": .string(g)]) }
    func savingsStatus(_ g: String) async throws -> [SavingsStatus] { try await rpc("savings_status", ["p_group": .string(g)]) }
    func passbook(_ g: String, goal: String? = nil) async throws -> [PassbookRow] { try await rpc("savings_passbook", ["p_group": .string(g), "p_goal": s(goal)]) }
    func savingsSeries(_ g: String, end: Date, months: Int = 12) async throws -> [SavingsPoint] {
        try await rpc("savings_series", ["p_group": .string(g), "p_end_month": month(end), "p_months": .integer(months)])
    }

    // ---------- 操作の履歴 ----------
    func audit(_ g: String, limit: Int = 200) async throws -> [AuditLog] { try await call { try await client.from("audit_logs").select().eq("group_id", value: g).order("at", ascending: false).limit(limit).execute().value } }
}
