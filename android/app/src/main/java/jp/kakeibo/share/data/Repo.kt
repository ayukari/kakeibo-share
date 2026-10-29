package jp.kakeibo.share.data

import android.content.Context
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.exceptions.HttpRequestException
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.ktor.client.call.body
import io.ktor.client.plugins.HttpRequestTimeoutException
import jp.kakeibo.share.BuildConfig
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.ErrorKind
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.IOException
import java.time.LocalDate

// サーバー（Supabase）とのやりとりをまとめる。書き込みと計算はすべて DB の関数（RPC）で行い、権限は RLS と関数で確かめられる
class Repo(val client: SupabaseClient) {

    val auth get() = client.auth
    fun userId(): String? = client.auth.currentUserOrNull()?.id

    // 例外を共通のエラー分類にする（保存が失敗したら、必ず呼び出し側にエラーとして返す）
    suspend fun <T> call(block: suspend () -> T): T = try {
        block()
    } catch (e: AppError) {
        throw e
    } catch (e: PostgrestRestException) {
        throw AppError.fromCode(e.code, e.error, e.hint, e.statusCode)
    } catch (e: AuthRestException) {
        throw AppError(authKind(e), e.errorCode?.value ?: e.error, cause = e)
    } catch (e: RestException) {
        throw AppError.fromCode(null, e.error, null, e.statusCode)
    } catch (e: HttpRequestException) {
        throw AppError(ErrorKind.Network, cause = e)
    } catch (e: HttpRequestTimeoutException) {
        throw AppError(ErrorKind.Network, cause = e)
    } catch (e: IOException) {
        throw AppError(ErrorKind.Network, cause = e)
    }

    private fun authKind(e: AuthRestException) = when (e.statusCode) {
        400, 422 -> ErrorKind.Validation
        401 -> ErrorKind.Unauthorized
        403 -> ErrorKind.Forbidden
        429 -> ErrorKind.Conflict
        else -> ErrorKind.Server
    }

    private suspend inline fun <reified T : Any> rpc(fn: String, params: JsonObject): T =
        call { client.postgrest.rpc(fn, params).decodeAs<T>() }
    private suspend inline fun <reified T : Any> rpcList(fn: String, params: JsonObject): List<T> =
        call { client.postgrest.rpc(fn, params).decodeList<T>() }
    private suspend fun rpcUnit(fn: String, params: JsonObject) { call { client.postgrest.rpc(fn, params) } }

    // ---------- 認証 ----------
    suspend fun signUp(email: String, password: String, displayName: String) = call {
        client.auth.signUpWith(Email) { this.email = email.trim(); this.password = password; data = buildJsonObject { put("display_name", displayName.trim()) } }
    }
    suspend fun verifySignUp(email: String, code: String) = call { client.auth.verifyEmailOtp(OtpType.Email.EMAIL, email.trim(), code.trim()) }
    suspend fun signIn(email: String, password: String) = call { client.auth.signInWith(Email) { this.email = email.trim(); this.password = password } }
    suspend fun signOut() = call { client.auth.signOut() }       // サーバー側のセッションも無効にする
    suspend fun sendReset(email: String) = call { client.auth.resetPasswordForEmail(email.trim()) }
    suspend fun verifyReset(email: String, code: String) = call { client.auth.verifyEmailOtp(OtpType.Email.RECOVERY, email.trim(), code.trim()) }
    suspend fun changePassword(newPassword: String) = call { client.auth.updateUser { password = newPassword } }
    suspend fun changeEmail(newEmail: String) = call { client.auth.updateUser { email = newEmail.trim() } }
    suspend fun deleteAccount(): String? = call {
        val res = client.functions.invoke("delete-account", body = buildJsonObject { put("confirm", "DELETE") })
        if (res.status.value == 200) null else res.body<JsonObject>()["code"]?.jsonPrimitive?.content ?: "server"
    }

    // ---------- プロフィール・グループ ----------
    suspend fun myProfile(): Profile? = call { client.from("profiles").select { filter { eq("id", userId() ?: "") } }.decodeSingleOrNull<Profile>() }
    suspend fun updateProfile(name: String): Profile = rpc("update_profile", buildJsonObject { put("p_display_name", name.trim()) })
    suspend fun groups(): List<Group> = call { client.from("groups").select { order("created_at", Order.ASCENDING) }.decodeList<Group>() }
    suspend fun createGroup(name: String): Group = rpc("create_group", buildJsonObject { put("p_name", name.trim()) })
    suspend fun renameGroup(g: String, name: String): Group = rpc("rename_group", buildJsonObject { put("p_group", g); put("p_name", name.trim()) })
    suspend fun deleteGroup(g: String) = rpcUnit("delete_group", buildJsonObject { put("p_group", g) })
    suspend fun leaveGroup(g: String) = rpcUnit("leave_group", buildJsonObject { put("p_group", g) })

    // ---------- メンバー・招待 ----------
    suspend fun members(g: String): List<Member> = call { client.from("group_members").select { filter { eq("group_id", g) }; order("joined_at", Order.ASCENDING) }.decodeList<Member>() }
    suspend fun changeRole(member: String, role: String): Member = rpc("change_member_role", buildJsonObject { put("p_member", member); put("p_role", role) })
    suspend fun removeMember(member: String) = rpcUnit("remove_member", buildJsonObject { put("p_member", member) })
    suspend fun transferOwnership(member: String) = rpcUnit("transfer_ownership", buildJsonObject { put("p_member", member) })
    suspend fun invitations(g: String): List<Invitation> = call { client.from("invitations").select { filter { eq("group_id", g) }; order("created_at", Order.DESCENDING) }.decodeList<Invitation>() }
    suspend fun createInvitation(g: String, role: String, hours: Int, maxUses: Int): NewInvitation =
        rpc("create_invitation", buildJsonObject { put("p_group", g); put("p_role", role); put("p_expires_hours", hours); put("p_max_uses", maxUses) })
    suspend fun revokeInvitation(id: String) = rpcUnit("revoke_invitation", buildJsonObject { put("p_invitation", id) })
    // 無効なコードはサーバーが null を返す（総当たりを数えるため）
    suspend fun acceptInvitation(code: String, displayName: String?): Member? = call {
        client.postgrest.rpc("accept_invitation", buildJsonObject { put("p_code", code); displayName?.let { put("p_display_name", it) } }).decodeAsOrNull<Member>()
    }

    // ---------- カテゴリ・支払い方法 ----------
    suspend fun categories(g: String): List<Category> = call { client.from("categories").select { filter { eq("group_id", g) }; order("sort", Order.ASCENDING) }.decodeList<Category>() }
    suspend fun saveCategory(g: String, id: String?, kind: String, name: String, color: String, icon: String, sort: Int, version: Int?): Category =
        rpc("save_category", buildJsonObject { put("p_group", g); put("p_id", id); put("p_kind", kind); put("p_name", name.trim()); put("p_color", color); put("p_icon", icon); put("p_sort", sort); put("p_version", version) })
    suspend fun deleteCategory(id: String): String = call { client.postgrest.rpc("delete_category", buildJsonObject { put("p_category", id) }).decodeAs<String>() }
    suspend fun paymentMethods(g: String): List<PaymentMethod> = call { client.from("payment_methods").select { filter { eq("group_id", g) } }.decodeList<PaymentMethod>() }

    // ---------- 取引 ----------
    suspend fun transactions(g: String, from: LocalDate, toExclusive: LocalDate): List<Txn> = call {
        client.from("transactions").select {
            filter { eq("group_id", g); eq("status", "active"); gte("occurred_on", from.toString()); lt("occurred_on", toExclusive.toString()) }
            order("occurred_on", Order.DESCENDING); order("created_at", Order.DESCENDING)
        }.decodeList<Txn>()
    }
    suspend fun recentTransactions(g: String, limit: Long = 5): List<Txn> = call {
        client.from("transactions").select { filter { eq("group_id", g); eq("status", "active") }; order("occurred_on", Order.DESCENDING); order("created_at", Order.DESCENDING); limit(limit) }.decodeList<Txn>()
    }
    suspend fun splits(ids: List<String>): List<Split> = if (ids.isEmpty()) emptyList() else call {
        client.from("transaction_splits").select { filter { isIn("transaction_id", ids) } }.decodeList<Split>()
    }
    suspend fun saveTransaction(g: String, t: TxnInput): Txn = rpc("save_transaction", buildJsonObject {
        put("p_group", g)
        put("p", buildJsonObject {
            t.id?.let { put("id", it) }; t.version?.let { put("version", it) }
            put("client_request_id", t.clientRequestId); put("kind", t.kind); put("amount", t.amount); put("occurred_on", t.occurredOn)
            put("category_id", t.categoryId); put("payer_member_id", t.payerMemberId); put("payment_method_id", t.paymentMethodId)
            put("memo", t.memo); put("visibility", t.visibility); put("split_mode", t.splitMode)
            put("splits", when (t.splitMode) {
                "equal" -> buildJsonArray { t.equalMembers.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) } }
                "custom" -> buildJsonArray { t.customShares.forEach { (m, a) -> add(buildJsonObject { put("member_id", m); put("amount", a) }) } }
                else -> buildJsonArray { }
            })
        })
    })
    suspend fun deleteTransaction(id: String, version: Int) = rpcUnit("delete_transaction", buildJsonObject { put("p_id", id); put("p_version", version) })
    suspend fun similar(g: String, amount: Long, date: String, category: String): List<Txn> =
        rpcList("similar_transactions", buildJsonObject { put("p_group", g); put("p_amount", amount); put("p_occurred_on", date); put("p_category", category) })

    // ---------- 集計・予算 ----------
    suspend fun monthSummary(g: String, month: LocalDate): MonthSummary = rpc("month_summary", buildJsonObject { put("p_group", g); put("p_month", month.withDayOfMonth(1).toString()) })
    suspend fun monthlySeries(g: String, end: LocalDate, months: Int = 12): List<MonthPoint> =
        rpcList("monthly_series", buildJsonObject { put("p_group", g); put("p_end_month", end.withDayOfMonth(1).toString()); put("p_months", months) })
    suspend fun budgetStatus(g: String, month: LocalDate): List<BudgetStatus> = rpcList("budget_status", buildJsonObject { put("p_group", g); put("p_month", month.withDayOfMonth(1).toString()) })
    suspend fun budgets(g: String): List<Budget> = call { client.from("budgets").select { filter { eq("group_id", g) }; order("start_month", Order.DESCENDING) }.decodeList<Budget>() }
    suspend fun saveBudget(g: String, scope: String, category: String?, member: String?, startMonth: LocalDate, amount: Long): Budget =
        rpc("save_budget", buildJsonObject { put("p_group", g); put("p_scope", scope); put("p_category", category); put("p_member", member); put("p_start_month", startMonth.withDayOfMonth(1).toString()); put("p_amount", amount) })
    suspend fun deleteBudget(id: String) = rpcUnit("delete_budget", buildJsonObject { put("p_id", id) })

    // ---------- 精算 ----------
    suspend fun balances(g: String): List<Balance> = rpcList("group_balances", buildJsonObject { put("p_group", g) })
    suspend fun suggestions(g: String): List<Suggestion> = rpcList("settlement_suggestions", buildJsonObject { put("p_group", g) })
    suspend fun settlements(g: String): List<Settlement> = call { client.from("settlements").select { filter { eq("group_id", g) }; order("created_at", Order.DESCENDING) }.decodeList<Settlement>() }
    suspend fun recordSettlement(g: String, from: String, to: String, amount: Long, note: String, requestId: String): Settlement =
        rpc("record_settlement", buildJsonObject { put("p_group", g); put("p_from", from); put("p_to", to); put("p_amount", amount); put("p_note", note); put("p_client_request_id", requestId) })
    suspend fun confirmSettlement(id: String): Settlement = rpc("confirm_settlement", buildJsonObject { put("p_id", id) })
    suspend fun cancelSettlement(id: String): Settlement = rpc("cancel_settlement", buildJsonObject { put("p_id", id) })

    // ---------- 定期取引 ----------
    suspend fun recurring(g: String): List<Recurring> = call { client.from("recurring_transactions").select { filter { eq("group_id", g) }; order("next_run_on", Order.ASCENDING) }.decodeList<Recurring>() }
    suspend fun saveRecurring(g: String, p: JsonObject): Recurring = rpc("save_recurring", buildJsonObject { put("p_group", g); put("p", p) })
    suspend fun deleteRecurring(id: String) = rpcUnit("delete_recurring", buildJsonObject { put("p_id", id) })
    suspend fun generateDue(g: String): Int = rpc("generate_due_recurring", buildJsonObject { put("p_group", g) })

    // ---------- 操作履歴 ----------
    suspend fun audit(g: String, limit: Long = 200): List<AuditLog> = call {
        client.from("audit_logs").select { filter { eq("group_id", g) }; order("at", Order.DESCENDING); limit(limit) }.decodeList<AuditLog>()
    }

    companion object {
        fun configured() = BuildConfig.SUPABASE_URL.startsWith("https://") && BuildConfig.SUPABASE_ANON_KEY.isNotBlank()

        fun create(context: Context): Repo = Repo(createSupabaseClient(BuildConfig.SUPABASE_URL, BuildConfig.SUPABASE_ANON_KEY) {
            install(Auth) {
                sessionManager = SecureSessionManager(context.applicationContext)
                alwaysAutoRefresh = true
                autoLoadFromStorage = true
            }
            install(Postgrest)
            install(Functions)
        })
    }
}
