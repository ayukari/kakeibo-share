package jp.kakeibo.share.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

// サーバーの行・関数の結果（docs/api.md）。日付は "YYYY-MM-DD"、日時は ISO 8601（UTC）の文字列のまま持つ

@Serializable data class Group(val id: String, val name: String, @SerialName("created_at") val createdAt: String? = null)

@Serializable data class Member(
    val id: String,
    @SerialName("group_id") val groupId: String,
    @SerialName("user_id") val userId: String? = null,
    val role: String,
    val status: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("joined_at") val joinedAt: String? = null,
)

@Serializable data class Category(
    val id: String,
    @SerialName("group_id") val groupId: String,
    val kind: String,
    val name: String,
    val color: String,
    val icon: String,
    val sort: Int = 0,
    @SerialName("archived_at") val archivedAt: String? = null,
    val version: Int = 1,
)

@Serializable data class PaymentMethod(val id: String, @SerialName("group_id") val groupId: String, val name: String, @SerialName("archived_at") val archivedAt: String? = null)

@Serializable data class Txn(
    val id: String,
    @SerialName("group_id") val groupId: String,
    val kind: String,
    val amount: Long,
    @SerialName("occurred_on") val occurredOn: String,
    @SerialName("category_id") val categoryId: String,
    @SerialName("payer_member_id") val payerMemberId: String,
    @SerialName("payment_method_id") val paymentMethodId: String? = null,
    val memo: String = "",
    val visibility: String = "group",
    @SerialName("split_mode") val splitMode: String = "none",
    val status: String = "active",
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_by_member") val createdByMember: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val version: Int = 1,
    @SerialName("recurring_id") val recurringId: String? = null,
)

@Serializable data class Split(@SerialName("transaction_id") val transactionId: String, @SerialName("member_id") val memberId: String, val amount: Long)

@Serializable data class Balance(
    @SerialName("member_id") val memberId: String,
    @SerialName("display_name") val displayName: String,
    val status: String,
    val paid: Long, val burden: Long,
    @SerialName("settled_out") val settledOut: Long,
    @SerialName("settled_in") val settledIn: Long,
    val net: Long,
)

@Serializable data class Suggestion(@SerialName("from_member") val fromMember: String, @SerialName("to_member") val toMember: String, val amount: Long)

@Serializable data class Settlement(
    val id: String,
    @SerialName("group_id") val groupId: String,
    @SerialName("from_member") val fromMember: String,
    @SerialName("to_member") val toMember: String,
    val amount: Long,
    val status: String,
    val note: String = "",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("confirmed_at") val confirmedAt: String? = null,
)

@Serializable data class Budget(
    val id: String,
    @SerialName("group_id") val groupId: String,
    val scope: String,
    @SerialName("category_id") val categoryId: String? = null,
    @SerialName("member_id") val memberId: String? = null,
    @SerialName("start_month") val startMonth: String,
    @SerialName("end_month") val endMonth: String? = null,
    val amount: Long,
)

@Serializable data class BudgetStatus(
    @SerialName("budget_id") val budgetId: String,
    val scope: String,
    @SerialName("category_id") val categoryId: String? = null,
    @SerialName("member_id") val memberId: String? = null,
    val amount: Long, val spent: Long, val remaining: Long,
    val ratio: Double, val over: Boolean,
)

@Serializable data class AmountBy(@SerialName("category_id") val categoryId: String? = null, @SerialName("member_id") val memberId: String? = null, val amount: Long)

@Serializable data class MonthSummary(
    val month: String,
    val income: Long, val expense: Long, val balance: Long,
    @SerialName("prev_income") val prevIncome: Long,
    @SerialName("prev_expense") val prevExpense: Long,
    @SerialName("by_category") val byCategory: List<AmountBy> = emptyList(),
    @SerialName("by_payer") val byPayer: List<AmountBy> = emptyList(),
    @SerialName("by_burden") val byBurden: List<AmountBy> = emptyList(),
)

@Serializable data class MonthPoint(val month: String, val income: Long, val expense: Long)

@Serializable data class Recurring(
    val id: String,
    @SerialName("group_id") val groupId: String,
    val kind: String,
    val amount: Long,
    @SerialName("category_id") val categoryId: String,
    @SerialName("payer_member_id") val payerMemberId: String,
    @SerialName("payment_method_id") val paymentMethodId: String? = null,
    val memo: String = "",
    val visibility: String = "group",
    @SerialName("split_mode") val splitMode: String = "none",
    @SerialName("split_spec") val splitSpec: JsonElement? = null,
    val freq: String,
    @SerialName("day_of_month") val dayOfMonth: Int? = null,
    val weekday: Int? = null,
    @SerialName("month_of_year") val monthOfYear: Int? = null,
    @SerialName("start_on") val startOn: String,
    @SerialName("end_on") val endOn: String? = null,
    @SerialName("next_run_on") val nextRunOn: String,
    val active: Boolean,
    val version: Int = 1,
)

@Serializable data class Invitation(
    val id: String,
    @SerialName("code_hint") val codeHint: String,
    val role: String,
    @SerialName("expires_at") val expiresAt: String,
    @SerialName("max_uses") val maxUses: Int,
    @SerialName("used_count") val usedCount: Int,
    @SerialName("revoked_at") val revokedAt: String? = null,
)

@Serializable data class NewInvitation(val id: String, val code: String, @SerialName("expires_at") val expiresAt: String, val role: String, @SerialName("max_uses") val maxUses: Int)

@Serializable data class AuditLog(
    val id: Long,
    val actor: String? = null,
    val action: String,
    @SerialName("target_table") val targetTable: String,
    @SerialName("target_id") val targetId: String? = null,
    val detail: JsonElement? = null,
    val at: String,
)

@Serializable data class Profile(val id: String, @SerialName("display_name") val displayName: String)

// 取引の入力（save_transaction に渡す形）
data class TxnInput(
    val id: String? = null,
    val version: Int? = null,
    val clientRequestId: String,
    val kind: String,
    val amount: Long,
    val occurredOn: String,
    val categoryId: String,
    val payerMemberId: String,
    val paymentMethodId: String?,
    val memo: String,
    val visibility: String,
    val splitMode: String,
    val equalMembers: List<String> = emptyList(),
    val customShares: Map<String, Long> = emptyMap(),
)

// ---------- 貯金（目標＝封筒・記録＝通帳） ----------
@Serializable data class SavingsGoal(
    val id: String,
    @SerialName("group_id") val groupId: String,
    val name: String,
    val target: Long,
    @SerialName("due_month") val dueMonth: String? = null,
    @SerialName("is_main") val isMain: Boolean = false,
    @SerialName("auto_amount") val autoAmount: Long? = null,
    @SerialName("auto_dom") val autoDom: Int? = null,
    @SerialName("start_on") val startOn: String,
    val visibility: String = "group",
    @SerialName("created_by") val createdBy: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    val version: Int = 1,
)

@Serializable data class SavingsStatus(
    @SerialName("goal_id") val goalId: String,
    val saved: Long,
    val remaining: Long,
    val ratio: Double,
    val done: Boolean,
    @SerialName("months_left") val monthsLeft: Int? = null,
    @SerialName("per_month") val perMonth: Long? = null,
    val overdue: Boolean = false,
    @SerialName("on_track") val onTrack: Boolean? = null,
    @SerialName("this_month") val thisMonth: Long = 0,
)

@Serializable data class PassbookRow(
    val id: String,
    @SerialName("goal_id") val goalId: String,
    @SerialName("goal_name") val goalName: String,
    val day: String,
    val amount: Long,
    val kind: String,
    val memo: String = "",
    val balance: Long,
    @SerialName("created_by") val createdBy: String? = null,
)

@Serializable data class SavingsPoint(val month: String, val deposit: Long, val withdrawal: Long)
