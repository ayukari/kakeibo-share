package jp.kakeibo.share.domain

import jp.kakeibo.share.data.PassbookRow
import jp.kakeibo.share.data.SavingsGoal
import jp.kakeibo.share.data.SavingsStatus
import java.time.LocalDate

// 貯金の言葉と節目（かざすレシートの kakeibo.js の envelope / milestone と同じ決まり）。数字の計算はサーバー（savings_status）
object Savings {
    val KIND_NAMES = mapOf("manual" to "預入", "tsumori" to "つもり貯金", "leftover" to "予算の余り", "auto" to "先取り")
    private val PCT = mapOf(25 to "4 分の 1", 50 to "半分", 75 to "4 分の 3", 100 to "目標")

    // "2026-10-01" → "2026年10月"
    fun yyyymm(month: String?): String = month?.let { "${it.substring(0, 4).toInt()}年${it.substring(5, 7).toInt()}月" } ?: ""

    fun domLabel(dom: Int?) = if (dom == 99) "月末" else "${dom}日"

    // 進み具合のひとこと
    fun pace(g: SavingsGoal, s: SavingsStatus): String = when {
        s.done -> "目標に届きました。"
        s.overdue -> "期限（${yyyymm(g.dueMonth)}）をすぎています。"
        s.perMonth != null -> "${yyyymm(g.dueMonth)}までに毎月 ${Money.format(s.perMonth)}" +
            (if (g.autoAmount != null) (if (s.onTrack == true) "・先取りで届きます" else "・先取りでは ${Money.format(s.perMonth - g.autoAmount)} 足りません") else "")
        else -> "あと ${Money.format(s.remaining)}" + (if (g.autoAmount != null) "・毎月${domLabel(g.autoDom)}に ${Money.format(g.autoAmount)} 先取り" else "")
    }

    // いちばん新しく越えた節目（25・50・75・100%）と、それが今月か。rows はその目標の通帳（日付順）
    data class Milestone(val pct: Int, val day: String, val thisMonth: Boolean) {
        val text get() = "今月、${PCT[pct]}${if (pct == 100) "に届きました" else "まで来ました"}（$pct%）。"
    }

    fun milestone(target: Long, rows: List<PassbookRow>, today: LocalDate): Milestone? {
        var bal = 0L
        var hit: Pair<Int, String>? = null
        for (r in rows) {
            val before = bal; bal += r.amount
            for (p in listOf(25, 50, 75, 100)) if (before * 100 < target * p && bal * 100 >= target * p) hit = p to r.day
        }
        val cur = "%04d-%02d".format(today.year, today.monthValue)
        return hit?.let { Milestone(it.first, it.second, it.second.startsWith(cur)) }
    }

    // 生活防衛資金の目安: 終わった直近の月（記録がある月、最大 3 か月）の支出の平均 × 3、1 万円単位に切り上げ
    fun emergencyTarget(monthlyExpense: List<Long>): Pair<Long, Long>? {
        val ms = monthlyExpense.filter { it > 0 }.takeLast(3)
        if (ms.isEmpty()) return null
        val avg = Math.round(ms.sum().toDouble() / ms.size)
        return avg to (Math.ceil(avg * 3 / 10000.0) * 10000).toLong()
    }

    // 予算の余り（先月のカテゴリの予算、なければ全体の予算の残り）。余りがなければ null
    fun leftover(budgetRows: List<jp.kakeibo.share.data.BudgetStatus>): Long? {
        val cat = budgetRows.filter { it.scope == "group" && it.categoryId != null }
        val rows = cat.ifEmpty { budgetRows.filter { it.scope == "group" && it.categoryId == null } }
        if (rows.isEmpty()) return null
        val left = rows.sumOf { it.amount } - rows.sumOf { it.spent }
        return if (left > 0) left else null
    }
}
