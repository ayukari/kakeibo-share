package jp.kakeibo.share

import jp.kakeibo.share.data.Split
import jp.kakeibo.share.data.Txn
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.ErrorKind
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Validate
import jp.kakeibo.share.ui.Csv
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
}
