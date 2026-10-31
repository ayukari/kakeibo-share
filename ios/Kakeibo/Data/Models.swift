import Foundation

// サーバーの行・関数の結果（docs/api.md）。日付は "YYYY-MM-DD"、日時は ISO 8601 の文字列のまま持つ
// SwiftUI の Group と名前がぶつからないよう、グループは KGroup

struct KGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    var createdAt: String? = nil
    enum CodingKeys: String, CodingKey { case id, name, createdAt = "created_at" }
}

struct Member: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String
    var userId: String? = nil
    let role: String
    let status: String
    let displayName: String
    var joinedAt: String? = nil
    enum CodingKeys: String, CodingKey { case id, role, status, groupId = "group_id", userId = "user_id", displayName = "display_name", joinedAt = "joined_at" }
}

struct Category: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String
    let kind: String
    let name: String
    let color: String
    let icon: String
    var sort: Int = 0
    var archivedAt: String? = nil
    var version: Int = 1
    enum CodingKeys: String, CodingKey { case id, kind, name, color, icon, sort, version, groupId = "group_id", archivedAt = "archived_at" }
}

struct PaymentMethod: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String
    let name: String
    var archivedAt: String? = nil
    enum CodingKeys: String, CodingKey { case id, name, groupId = "group_id", archivedAt = "archived_at" }
}

struct Txn: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String
    let kind: String
    let amount: Int64
    let occurredOn: String
    let categoryId: String
    let payerMemberId: String
    var paymentMethodId: String? = nil
    var memo: String = ""
    var visibility: String = "group"
    var splitMode: String = "none"
    var status: String = "active"
    var createdBy: String? = nil
    var createdAt: String? = nil
    var version: Int = 1
    var recurringId: String? = nil
    var createdByMember: String? = nil
    var isRefund: Bool? = nil   // 返金（支出だけ。集計と立替では引く）。古いサーバーでは届かない
    var refund: Bool { isRefund ?? false }
    var signed: Int64 { refund ? -amount : amount }
    enum CodingKeys: String, CodingKey {
        case id, kind, amount, memo, visibility, status, version, isRefund = "is_refund"
        case groupId = "group_id", occurredOn = "occurred_on", categoryId = "category_id", payerMemberId = "payer_member_id"
        case paymentMethodId = "payment_method_id", splitMode = "split_mode", createdBy = "created_by", createdAt = "created_at", recurringId = "recurring_id", createdByMember = "created_by_member"
    }
}

struct Split: Codable, Hashable {
    let transactionId: String
    let memberId: String
    let amount: Int64
    enum CodingKeys: String, CodingKey { case amount, transactionId = "transaction_id", memberId = "member_id" }
}

struct Balance: Codable, Hashable {
    let memberId: String
    let displayName: String
    let status: String
    let paid: Int64
    let burden: Int64
    let settledOut: Int64
    let settledIn: Int64
    let net: Int64
    enum CodingKeys: String, CodingKey { case status, paid, burden, net, memberId = "member_id", displayName = "display_name", settledOut = "settled_out", settledIn = "settled_in" }
}

struct Suggestion: Codable, Hashable {
    let fromMember: String
    let toMember: String
    let amount: Int64
    enum CodingKeys: String, CodingKey { case amount, fromMember = "from_member", toMember = "to_member" }
}

struct Settlement: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String
    let fromMember: String
    let toMember: String
    let amount: Int64
    let status: String
    var note: String = ""
    var createdAt: String? = nil
    var confirmedAt: String? = nil
    enum CodingKeys: String, CodingKey { case id, amount, status, note, groupId = "group_id", fromMember = "from_member", toMember = "to_member", createdAt = "created_at", confirmedAt = "confirmed_at" }
}

struct BudgetStatus: Codable, Hashable {
    let budgetId: String
    let scope: String
    var categoryId: String? = nil
    var memberId: String? = nil
    let amount: Int64
    let spent: Int64
    let remaining: Int64
    let ratio: Double
    let over: Bool
    var carry: Int64? = nil      // 前の月からの繰り越し（余りは +、使いすぎは −）
    var rollover: Bool? = nil
    var carried: Int64 { carry ?? 0 }
    var rolls: Bool { rollover ?? false }
    var available: Int64 { amount + carried }
    enum CodingKeys: String, CodingKey { case scope, amount, spent, remaining, ratio, over, carry, rollover, budgetId = "budget_id", categoryId = "category_id", memberId = "member_id" }
}

struct AmountBy: Codable, Hashable {
    var categoryId: String? = nil
    var memberId: String? = nil
    let amount: Int64
    enum CodingKeys: String, CodingKey { case amount, categoryId = "category_id", memberId = "member_id" }
}

struct MonthSummary: Codable, Hashable {
    let month: String
    let income: Int64
    let expense: Int64
    let balance: Int64
    let prevIncome: Int64
    let prevExpense: Int64
    var byCategory: [AmountBy] = []
    var byPayer: [AmountBy] = []
    var byBurden: [AmountBy] = []
    enum CodingKeys: String, CodingKey {
        case month, income, expense, balance
        case prevIncome = "prev_income", prevExpense = "prev_expense", byCategory = "by_category", byPayer = "by_payer", byBurden = "by_burden"
    }
}

struct MonthPoint: Codable, Hashable { let month: String; let income: Int64; let expense: Int64 }

struct Recurring: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let amount: Int64
    let categoryId: String
    let payerMemberId: String
    var memo: String = ""
    var splitMode: String = "none"
    let freq: String
    var dayOfMonth: Int? = nil
    var weekday: Int? = nil
    var monthOfYear: Int? = nil
    let startOn: String
    var endOn: String? = nil
    let nextRunOn: String
    let active: Bool
    enum CodingKeys: String, CodingKey {
        case id, kind, amount, memo, freq, weekday, active
        case categoryId = "category_id", payerMemberId = "payer_member_id", splitMode = "split_mode", dayOfMonth = "day_of_month"
        case monthOfYear = "month_of_year", startOn = "start_on", endOn = "end_on", nextRunOn = "next_run_on"
    }
}

struct Invitation: Codable, Identifiable, Hashable {
    let id: String
    let codeHint: String
    let role: String
    let expiresAt: String
    let maxUses: Int
    let usedCount: Int
    var revokedAt: String? = nil
    enum CodingKeys: String, CodingKey { case id, role, codeHint = "code_hint", expiresAt = "expires_at", maxUses = "max_uses", usedCount = "used_count", revokedAt = "revoked_at" }
}

struct NewInvitation: Codable, Hashable {
    let id: String
    let code: String
    let expiresAt: String
    let role: String
    let maxUses: Int
    enum CodingKeys: String, CodingKey { case id, code, role, expiresAt = "expires_at", maxUses = "max_uses" }
}

// 操作の履歴。detail は中身が表ごとに違うので、使う項目だけ読む
struct AuditLog: Codable, Identifiable, Hashable {
    struct Detail: Codable, Hashable {
        var amount: Int64? = nil
        var statusTo: String? = nil
        var roleTo: String? = nil
        enum CodingKeys: String, CodingKey { case amount, statusTo = "status_to", roleTo = "role_to" }
    }
    let id: Int64
    var actor: String? = nil
    let action: String
    let targetTable: String
    var targetId: String? = nil
    var detail: Detail? = nil
    let at: String
    enum CodingKeys: String, CodingKey { case id, actor, action, detail, at, targetTable = "target_table", targetId = "target_id" }
}

struct Profile: Codable, Hashable {
    let id: String
    let displayName: String
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
}

// 取引の入力（save_transaction に渡す形）
struct TxnInput {
    var id: String? = nil
    var version: Int? = nil
    var clientRequestId: String
    var kind: String
    var amount: Int64
    var occurredOn: String
    var categoryId: String
    var payerMemberId: String
    var paymentMethodId: String?
    var memo: String
    var visibility: String
    var splitMode: String
    var equalMembers: [String] = []
    var customShares: [String: Int64] = [:]
    var isRefund = false
}

// ---------- 貯金（目標＝封筒・記録＝通帳） ----------
struct SavingsGoal: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String
    let name: String
    let target: Int64
    var dueMonth: String? = nil
    var isMain: Bool = false
    var autoAmount: Int64? = nil
    var autoDom: Int? = nil
    let startOn: String
    var visibility: String = "group"
    var createdBy: String? = nil
    var createdAt: String? = nil
    var version: Int = 1
    enum CodingKeys: String, CodingKey {
        case id, name, target, visibility, version
        case groupId = "group_id", dueMonth = "due_month", isMain = "is_main", autoAmount = "auto_amount", autoDom = "auto_dom"
        case startOn = "start_on", createdBy = "created_by", createdAt = "created_at"
    }
}

struct SavingsStatus: Codable, Hashable {
    let goalId: String
    let saved: Int64
    let remaining: Int64
    let ratio: Double
    let done: Bool
    var monthsLeft: Int? = nil
    var perMonth: Int64? = nil
    var overdue: Bool = false
    var onTrack: Bool? = nil
    var thisMonth: Int64 = 0
    enum CodingKeys: String, CodingKey {
        case saved, remaining, ratio, done, overdue
        case goalId = "goal_id", monthsLeft = "months_left", perMonth = "per_month", onTrack = "on_track", thisMonth = "this_month"
    }
}

struct PassbookRow: Codable, Identifiable, Hashable {
    let id: String
    let goalId: String
    let goalName: String
    let day: String
    let amount: Int64
    let kind: String
    var memo: String = ""
    var balance: Int64
    var createdBy: String? = nil
    enum CodingKeys: String, CodingKey { case id, day, amount, kind, memo, balance, goalId = "goal_id", goalName = "goal_name", createdBy = "created_by" }
}

struct SavingsPoint: Codable, Hashable { let month: String; let deposit: Int64; let withdrawal: Int64 }
