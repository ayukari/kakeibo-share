package jp.kakeibo.share.domain

import jp.kakeibo.share.data.Txn
import java.time.LocalDate
import java.time.YearMonth

// ホームのペースの線などの計算（かざすレシートの insights.mjs の pace / budgetStatus と同じ考え方）。
// 「ふだんの支出」= 公開範囲がグループの支出のうち、定期的な収支（固定費）から作られたものを除く
object Insights {
    private fun inMonth(t: Txn, m: YearMonth) = t.occurredOn.startsWith("%04d-%02d".format(m.year, m.monthValue))
    private fun isExpense(t: Txn) = t.kind == "expense" && t.status == "active" && t.visibility == "group"

    // その月の 1 日から月末までの、ふだんの支出の累計（日ごと）
    fun variableCumulative(txns: List<Txn>, month: YearMonth): LongArray {
        val days = LongArray(month.lengthOfMonth())
        for (t in txns) if (isExpense(t) && t.recurringId == null && inMonth(t, month)) {
            val d = t.occurredOn.substring(8, 10).toIntOrNull() ?: continue
            if (d in 1..days.size) days[d - 1] += t.amount
        }
        for (i in 1 until days.size) days[i] += days[i - 1]
        return days
    }

    // 固定費（定期的な収支から作られた支出）の合計
    fun fixedTotal(txns: List<Txn>, month: YearMonth): Long = txns.filter { isExpense(it) && it.recurringId != null && inMonth(it, month) }.sumOf { it.amount }

    // その月の、今日を含む残りの日数（過去の月は 0、先の月は月の日数）
    fun daysLeft(month: YearMonth, today: LocalDate): Int {
        val cur = YearMonth.from(today)
        return when {
            month == cur -> month.lengthOfMonth() - today.dayOfMonth + 1
            month.isAfter(cur) -> month.lengthOfMonth()
            else -> 0
        }
    }

    // 1 日あたり使える額（残りがあって、日が残っているときだけ）
    fun perDay(left: Long, daysLeft: Int): Long = if (daysLeft > 0 && left > 0) left / daysLeft else 0

    // 予算の目安の線（毎日同じだけ使う場合の累計）
    fun idealLine(varBudget: Long, len: Int): LongArray? = if (varBudget > 0) LongArray(len) { Math.round(varBudget.toDouble() * (it + 1) / len) } else null

    // 日ごとの支出の合計（カレンダー用。公開範囲がグループの支出。キーは日）
    fun dailyExpense(txns: List<Txn>, month: YearMonth): LongArray {
        val days = LongArray(month.lengthOfMonth())
        for (t in txns) if (isExpense(t) && inMonth(t, month)) {
            val d = t.occurredOn.substring(8, 10).toIntOrNull() ?: continue
            if (d in 1..days.size) days[d - 1] += t.amount
        }
        return days
    }

    // カレンダーの濃さの 5 段階（0 = なし、1〜4 = 少し〜多い）
    fun step(v: Long, max: Long): Int = when {
        v <= 0 || max <= 0 -> 0
        v <= max * 0.25 -> 1
        v <= max * 0.5 -> 2
        v <= max * 0.75 -> 3
        else -> 4
    }

    // 金額の短い表記（1 万円以上は千円単位の k）
    fun short(v: Long): String = if (v >= 10_000) "${Math.round(v / 1000.0)}k" else "%,d".format(v)
}
