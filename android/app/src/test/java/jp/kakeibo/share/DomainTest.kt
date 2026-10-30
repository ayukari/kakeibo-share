package jp.kakeibo.share

import jp.kakeibo.share.data.Split
import jp.kakeibo.share.data.Txn
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.ErrorKind
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Validate
import jp.kakeibo.share.domain.Calc
import jp.kakeibo.share.domain.Insights
import jp.kakeibo.share.domain.Savings
import jp.kakeibo.share.data.*
import jp.kakeibo.share.ui.Csv
import java.time.YearMonth
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.time.LocalDate

class DomainTest {
    // 両 OS とサーバーで共有するテストの値（tests/vectors）
    private fun vector(name: String) = Json.parseToJsonElement(File("../../tests/vectors/$name").readText()).jsonObject

    @Test fun equalSplitMatchesSharedVectors() {
        val cases = vector("splits.json")["cases"]!!.jsonArray
        assertTrue(cases.size >= 6)
        cases.forEach { c ->
            val o = c.jsonObject
            val got = Money.equalSplit(o["amount"]!!.jsonPrimitive.long, o["members"]!!.jsonPrimitive.int)
            assertEquals(o["expected"]!!.jsonArray.map { it.jsonPrimitive.long }, got)
            assertEquals(o["amount"]!!.jsonPrimitive.long, got.sum())
        }
    }

    @Test fun parseAcceptsJapaneseInputAndRejectsFractions() {
        assertEquals(1200L, Money.parse("1,200"))
        assertEquals(1200L, Money.parse("¥１２００円"))
        assertNull(Money.parse("12.5"))
        assertNull(Money.parse("-100"))
        assertNull(Money.parse(""))
        assertNull(Money.parse("1e3"))
    }

    @Test fun amountRange() {
        assertNotNull(Validate.amount("0"))
        assertNull(Validate.amount("1"))
        assertNull(Validate.amount("999,999,999"))
        assertNotNull(Validate.amount("1000000000"))
    }

    @Test fun formatYen() {
        assertEquals("¥1,234", Money.format(1234))
        assertEquals("−¥500", Money.format(-500))
    }

    @Test fun otherValidations() {
        assertNotNull(Validate.date(null))
        assertNotNull(Validate.date(LocalDate.of(1999, 12, 31)))
        assertNull(Validate.date(Money.todayJst()))
        assertNotNull(Validate.memo("a".repeat(501)))
        assertNotNull(Validate.groupName("  "))
        assertNotNull(Validate.email("abc"))
        assertNull(Validate.email("a@b.jp"))
        assertNotNull(Validate.password("1234567"))
        assertNotNull(Validate.customSplit(1000, listOf(500, 400)))
        assertNull(Validate.customSplit(1000, listOf(600, 400)))
    }

    @Test fun errorKindsMatchSharedVectors() {
        vector("errors.json")["cases"]!!.jsonArray.forEach { c ->
            val o = c.jsonObject
            val code = o["code"]!!.jsonPrimitive.contentOrNull
            assertEquals("$code/${o["http"]}", o["kind"]!!.jsonPrimitive.content, AppError.fromCode(code, "", null, o["http"]!!.jsonPrimitive.int).kind.name)
        }
    }

    @Test fun serverErrorCodesMapToKinds() {
        assertEquals(ErrorKind.Unauthorized, AppError.fromCode("KB401", "", null, 400).kind)
        assertEquals(ErrorKind.Forbidden, AppError.fromCode("KB403", "forbidden", null, 400).kind)
        assertEquals(ErrorKind.Forbidden, AppError.fromCode("42501", "", null, 401).kind)
        assertEquals(ErrorKind.NotFound, AppError.fromCode("KB404", "", null, 400).kind)
        assertEquals(ErrorKind.Conflict, AppError.fromCode("KB409", "conflict", null, 400).kind)
        val v = AppError.fromCode("KB422", "amount_invalid", "amount", 400)
        assertEquals(ErrorKind.Validation, v.kind); assertEquals("amount", v.field)
        assertTrue(v.userMessage.contains("999,999,999"))
        assertEquals(ErrorKind.Server, AppError.fromCode(null, "", null, 500).kind)
        assertTrue(AppError(ErrorKind.Network).userMessage.contains("保存はされていません"))
    }

    @Test fun csvEscapesAndBlocksFormulas() {
        assertEquals("'=SUM(A1)", Csv.cell("=SUM(A1)"))
        assertEquals("\"a,b\"", Csv.cell("a,b"))
        assertEquals("\"say \"\"hi\"\"\"", Csv.cell("say \"hi\""))
        val t = Txn("t1", "g", "expense", 1000, "2026-10-01", "c1", "m1", memo = "+danger,1", splitMode = "equal")
        val out = Csv.transactions(listOf(t), mapOf("t1" to listOf(Split("t1", "m1", 500), Split("t1", "m2", 500))), { "食費" }, { if (it == "m1") "A" else "B" }, { "" })
        val lines = out.split("\r\n")
        assertTrue(lines[0].startsWith("日付,種類,金額"))
        assertEquals("2026-10-01,支出,1000,食費,A,,\"'+danger,1\",グループ,均等,A:500 B:500,t1", lines[1])
        assertEquals(3, Csv.BOM.size)
    }

    private fun tx(day: Int, amount: Long, kind: String = "expense", recurring: String? = null, vis: String = "group", month: String = "2026-10") =
        Txn("t$day$amount", "g", kind, amount, "$month-%02d".format(day), "c", "m", recurringId = recurring, visibility = vis)

    @Test fun paceCumulativeSkipsFixedPrivateAndIncome() {
        val m = YearMonth.of(2026, 10)
        val t = listOf(tx(1, 1000), tx(1, 500), tx(3, 200), tx(2, 80000, recurring = "r"), tx(2, 999, vis = "private"), tx(4, 5000, kind = "income"), tx(5, 300, month = "2026-09"))
        val c = Insights.variableCumulative(t, m)
        assertEquals(31, c.size)
        assertEquals(1500L, c[0]); assertEquals(1500L, c[1]); assertEquals(1700L, c[2]); assertEquals(1700L, c[30])
        assertEquals(80000L, Insights.fixedTotal(t, m))
    }

    @Test fun perDayAndDaysLeft() {
        val m = YearMonth.of(2026, 10)
        assertEquals(3, Insights.daysLeft(m, java.time.LocalDate.of(2026, 10, 29)))
        assertEquals(31, Insights.daysLeft(m, java.time.LocalDate.of(2026, 9, 15)))
        assertEquals(0, Insights.daysLeft(m, java.time.LocalDate.of(2026, 11, 2)))
        assertEquals(6933L, Insights.perDay(20800, 3))
        assertEquals(0L, Insights.perDay(-5, 3)); assertEquals(0L, Insights.perDay(100, 0))
        assertEquals(listOf(10L, 20L, 30L), Insights.idealLine(30, 3)!!.toList())
        assertNull(Insights.idealLine(0, 3))
    }

    @Test fun calendarStepsAndShortAmounts() {
        assertEquals(0, Insights.step(0, 100)); assertEquals(1, Insights.step(25, 100)); assertEquals(2, Insights.step(26, 100)); assertEquals(3, Insights.step(75, 100)); assertEquals(4, Insights.step(76, 100))
        assertEquals("3,200", Insights.short(3200)); assertEquals("80k", Insights.short(80000)); assertEquals("12k", Insights.short(12400))
    }

    @Test fun savingsPaceWords() {
        val g = SavingsGoal("g", "g", "旅行", 120000, dueMonth = "2027-09-01", startOn = "2026-10-01", autoAmount = 5000, autoDom = 25)
        fun st(done: Boolean = false, over: Boolean = false, per: Long? = null, on: Boolean? = null) = SavingsStatus("g", 29000, 91000, 0.24, done, 12, per, over, on, 0)
        assertEquals("目標に届きました。", Savings.pace(g, st(done = true)))
        assertEquals("期限（2027年9月）をすぎています。", Savings.pace(g, st(over = true)))
        assertEquals("2027年9月までに毎月 ¥7,584・先取りでは ¥2,584 足りません", Savings.pace(g, st(per = 7584, on = false)))
        assertEquals("2027年9月までに毎月 ¥4,000・先取りで届きます", Savings.pace(g, st(per = 4000, on = true)))
        assertEquals("あと ¥91,000・毎月25日に ¥5,000 先取り", Savings.pace(g.copy(dueMonth = null), st()))
        assertEquals("月末", Savings.domLabel(99))
    }

    @Test fun savingsMilestoneAndEmergency() {
        fun r(day: String, a: Long) = PassbookRow(day + a, "g", "x", day, a, "manual", balance = 0)
        val m = Savings.milestone(100000, listOf(r("2026-09-01", 30000), r("2026-10-05", 25000)), java.time.LocalDate.of(2026, 10, 29))!!
        assertEquals(50, m.pct); assertTrue(m.thisMonth); assertEquals("今月、半分まで来ました（50%）。", m.text)
        assertNull(Savings.milestone(100000, listOf(r("2026-10-01", 1000)), java.time.LocalDate.of(2026, 10, 29)))
        assertEquals(100, Savings.milestone(1000, listOf(r("2026-09-01", 1200)), java.time.LocalDate.of(2026, 10, 29))!!.pct)
        assertEquals(110000L to 330000L, Savings.emergencyTarget(listOf(0, 100000, 120000, 110000)))
        assertEquals(97000L to 300000L, Savings.emergencyTarget(listOf(97000)))
        assertNull(Savings.emergencyTarget(listOf(0, 0)))
    }

    @Test fun savingsLeftover() {
        fun b(cat: String?, amount: Long, spent: Long) = BudgetStatus("b", "group", cat, null, amount, spent, amount - spent, spent.toDouble() / amount, spent > amount)
        assertEquals(6000L, Savings.leftover(listOf(b("c1", 40000, 36000), b("c2", 5000, 3000), b(null, 99999, 0))))
        assertNull(Savings.leftover(listOf(b("c1", 10000, 12000))))
        assertNull(Savings.leftover(emptyList()))
    }

    @Test fun calculatorKeypad() {
        assertEquals(1580L, Calc.evaluate("1200+380"))
        assertEquals(1250L, Calc.evaluate("1000+500÷2"))
        assertEquals(333L, Calc.evaluate("1000÷3"))
        assertEquals(1200L, Calc.evaluate("1200+"))
        assertNull(Calc.evaluate("5÷0")); assertNull(Calc.evaluate("")); assertNull(Calc.evaluate("−5"))
        var e = ""; listOf("1", "2", "+", "×", "3", "=").forEach { e = Calc.press(e, it) }
        assertEquals("36", e)
        assertEquals("", Calc.press("12", "C")); assertEquals("1", Calc.press("12", "⌫")); assertEquals("", Calc.press("", "00")); assertEquals("7", Calc.press("0", "7"))
        assertTrue(Calc.hasOperator("1+2")); assertFalse(Calc.hasOperator("12"))
    }

    @Test fun ratioSplit() {
        assertEquals(listOf(600L, 400L), Calc.ratioSplit(1000, listOf(60, 40)))
        assertEquals(listOf(340L, 330L, 330L), Calc.ratioSplit(1000, listOf(34, 33, 33)))
        assertEquals(listOf(34L, 33L, 33L), Calc.ratioSplit(100, listOf(34, 33, 33)))
        assertEquals(listOf(2L, 2L, 1L), Calc.ratioSplit(5, listOf(34, 33, 33)))
        assertEquals(listOf(4L, 3L), Calc.ratioSplit(7, listOf(50, 50)))
        assertEquals(listOf(0L, 1000L), Calc.ratioSplit(1000, listOf(0, 100)))
        assertNull(Calc.ratioSplit(1000, listOf(60, 30)))
    }
}
