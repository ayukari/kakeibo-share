package jp.kakeibo.share

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import android.graphics.Canvas
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.MemoryCodeVerifierCache
import io.github.jan.supabase.auth.MemorySessionManager
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.ui.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.LocalDate

// 見た目の確認用: ホームの絵を build/shots に書き出す（通信しない。ダミーのデータで描く）
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h1700dp-xhdpi")
class DesignShotTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private fun repo() = Repo(createSupabaseClient("https://example.invalid", "test-anon") {
        install(Auth) { sessionManager = MemorySessionManager(); codeVerifierCache = MemoryCodeVerifierCache(); autoLoadFromStorage = false; alwaysAutoRefresh = false }
        install(Postgrest)
    })

    private val cats = listOf(
        Category("c1", "g", "expense", "食費", "#e07a3f", "🍚"), Category("c2", "g", "expense", "日用品", "#3f8fd0", "🧺"), Category("c3", "g", "expense", "家賃", "#7a5cc7", "🏠"),
        Category("c4", "g", "expense", "交通費", "#5c7ac7", "🚃"), Category("c5", "g", "income", "給与", "#2f8f5f", "💴"),
    )

    private fun ctx(): GroupCtx {
        val app = AppVM(repo(), ApplicationProvider.getApplicationContext())
        val me = Member("m1", "g", "u1", "owner", "active", "あき")
        return GroupCtx(app, Group("g", "うちの家計簿"), me, listOf(me, Member("m2", "g", "u2", "member", "active", "はる")), cats, emptyList()) {}
    }

    private fun txn(id: String, day: Int, cat: String, amount: Long, kind: String = "expense", recurring: String? = null, memo: String = "", month: LocalDate) =
        Txn(id, "g", kind, amount, "%04d-%02d-%02d".format(month.year, month.monthValue, day), cat, "m1", memo = memo, recurringId = recurring, createdBy = "u1")

    private fun shot(name: String, content: @androidx.compose.runtime.Composable () -> Unit) {
        rule.setContent { KakeiboTheme { Column(Modifier.fillMaxWidth().background(T.bg).verticalScroll(rememberScrollState()).padding(16.dp)) { content() } } }
        rule.waitForIdle()
        val v = rule.activity.window.decorView
        v.measure(View.MeasureSpec.makeMeasureSpec(v.width.coerceAtLeast(1), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(v.height.coerceAtLeast(1), View.MeasureSpec.EXACTLY))
        v.layout(0, 0, v.measuredWidth, v.measuredHeight)
        val bmp = Bitmap.createBitmap(v.measuredWidth, v.measuredHeight, Bitmap.Config.ARGB_8888)
        v.draw(Canvas(bmp))
        val dir = File("build/shots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun home() {
        val c = ctx(); val month = Money.todayJst().withDayOfMonth(1); val prev = month.minusMonths(1)
        val txns = listOf(
            txn("t1", 1, "c3", 80000, recurring = "r1", memo = "家賃", month = month), txn("t2", 2, "c1", 3200, month = month), txn("t3", 4, "c2", 1800, month = month),
            txn("t4", 6, "c1", 5400, memo = "スーパー", month = month), txn("t5", 9, "c4", 2300, month = month), txn("t6", 12, "c1", 4100, month = month),
            txn("t7", 15, "c1", 6800, memo = "まとめ買い", month = month), txn("t8", 20, "c2", 2600, month = month), txn("t9", 25, "c5", 280000, kind = "income", month = month),
        ).filter { it.occurredOn.substring(8).toInt() <= maxOf(Money.todayJst().dayOfMonth, 1) }
        val prevTx = listOf(txn("p1", 1, "c3", 80000, recurring = "r1", month = prev), txn("p2", 5, "c1", 9000, month = prev), txn("p3", 14, "c1", 7000, month = prev), txn("p4", 22, "c2", 4000, month = prev))
        val spent = txns.filter { it.kind == "expense" }.sumOf { it.amount }
        val d = Dash(
            MonthSummary(month.toString(), 280000, spent, 280000 - spent, 0, 0, listOf(AmountBy("c3", null, 80000), AmountBy("c1", null, 19500), AmountBy("c2", null, 4400), AmountBy("c4", null, 2300))),
            listOf(BudgetStatus("b1", "group", "c1", null, 40000, 19500, 20500, 0.4875, false), BudgetStatus("b2", "group", "c2", null, 5000, 4400, 600, 0.88, false), BudgetStatus("b3", "group", "c4", null, 2000, 2300, -300, 1.15, true)),
            txns, prevTx, listOf(Balance("m1", "あき", "active", 10000, 5000, 0, 0, 5000), Balance("m2", "はる", "active", 0, 5000, 0, 0, -5000)),
        )
        shot("home") { DashboardContent(c, d, month, true, {}) }
    }

    @Test fun calendar() {
        val c = ctx(); val month = Money.todayJst().withDayOfMonth(1)
        val t = listOf(1 to 80000L, 2 to 3200L, 4 to 1800L, 6 to 5400L, 9 to 2300L, 12 to 4100L, 15 to 6800L, 20 to 2600L, 26 to 12000L).map { (d, a) -> txn("c$d", d, "c1", a, month = month) } +
            txn("inc", 25, "c5", 280000, kind = "income", month = month)
        shot("calendar") { Column { CalendarSection(c, month, t, 12, {}, {}) } }
    }

    @Test fun savings() {
        val c = ctx(); val today = Money.todayJst(); val m = "%04d-%02d".format(today.year, today.monthValue)
        val g1 = SavingsGoal("g1", "g", "沖縄旅行", 200000, dueMonth = today.withDayOfMonth(1).plusMonths(8).toString(), isMain = true, startOn = "2026-04-01", createdBy = "u1")
        val g2 = SavingsGoal("g2", "g", "もしものとき", 300000, autoAmount = 10000, autoDom = 25, startOn = "2026-04-01", createdBy = "u1")
        val pb = listOf(
            PassbookRow("p1", "g1", "沖縄旅行", "2026-05-03", 30000, "manual", balance = 30000), PassbookRow("p2", "g2", "もしものとき", "2026-05-25", 10000, "auto", "先取り貯金", 40000),
            PassbookRow("p3", "g1", "沖縄旅行", "2026-06-10", 20000, "manual", balance = 60000), PassbookRow("p4", "g2", "もしものとき", "2026-06-25", 10000, "auto", "先取り貯金", 70000),
            PassbookRow("p5", "g1", "沖縄旅行", "2026-07-02", -5000, "manual", "引き出し", 65000), PassbookRow("p6", "g1", "沖縄旅行", "${m}-02", 4500, "tsumori", "コンビニのコーヒー", 69500),
            PassbookRow("p7", "g1", "沖縄旅行", "${m}-05", 6000, "leftover", "2026-09", 75500),
        )
        val st = listOf(SavingsStatus("g1", 55500, 144500, 0.2775, false, 9, 16056, false, null, 10500), SavingsStatus("g2", 20000, 280000, 0.0667, false, null, null, false, null, 0))
        val ser = (11 downTo 0).map { k -> val d = today.withDayOfMonth(1).minusMonths(k.toLong()); SavingsPoint(d.toString(), if (k % 3 == 0) 0 else 10000L + k * 1500, if (k == 3) 5000 else 0) }
        val d = SavingsData(listOf(g1, g2), st, pb, ser, 280000, listOf(120000, 98000, 110000))
        shot("savings") { SavingsContent(c, d, today, {}, {}, null, {}, 20) {} }
    }

    @Test fun entry() {
        val c = ctx()
        shot("entry") { Box(Modifier.height(1500.dp)) { TxnEditScreen(c, null, "expense") {} } }
    }

    @Test fun donut() {
        shot("donut") { Paper { Donut(listOf(Slice("家賃", "#7a5cc7", 80000), Slice("食費", "#e07a3f", 19500), Slice("日用品", "#3f8fd0", 4400), Slice("交通費", "#5c7ac7", 2300)), "支出", 106200) } }
    }
}
