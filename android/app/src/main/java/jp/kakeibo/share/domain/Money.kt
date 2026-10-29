package jp.kakeibo.share.domain

import java.time.LocalDate
import java.time.ZoneId

// 共通の決まり（docs/spec-common.md）。金額は日本円の整数（Long、円）。浮動小数点は使わない
object Money {
    const val MIN = 1L
    const val MAX = 999_999_999L
    val TOKYO: ZoneId = ZoneId.of("Asia/Tokyo")

    fun todayJst(): LocalDate = LocalDate.now(TOKYO)

    fun format(yen: Long): String {
        val s = "%,d".format(kotlin.math.abs(yen))
        return (if (yen < 0) "−¥" else "¥") + s
    }

    // 入力の文字列を円に。全角数字・カンマ・¥ を許す。整数でなければ null
    fun parse(input: String): Long? {
        val t = input.trim().map { c -> if (c in '０'..'９') ('0' + (c - '０')) else c }.joinToString("")
            .replace(",", "").replace("¥", "").replace("￥", "").replace("円", "").trim()
        if (t.isEmpty() || !t.all { it.isDigit() } || t.length > 12) return null
        return t.toLongOrNull()
    }

    // 均等割り: floor(金額 / 人数) を全員に。余りは並びの先頭から 1 円ずつ（サーバーの equal_split と同じ。表示の下見用）
    fun equalSplit(amount: Long, members: Int): List<Long> {
        require(members > 0)
        val base = amount / members
        val rest = amount % members
        return List(members) { i -> base + if (i < rest) 1 else 0 }
    }
}

// 入力の検証（サーバーでも同じ決まりで確かめる。こちらは入力中に早く知らせるため）
object Validate {
    fun amount(input: String): String? {
        val v = Money.parse(input) ?: return "金額は 1 円以上の整数で入れてください"
        if (v < Money.MIN || v > Money.MAX) return "金額は 1〜999,999,999 円で入れてください"
        return null
    }
    fun date(d: LocalDate?): String? {
        if (d == null) return "日付を選んでください"
        if (d.isBefore(LocalDate.of(2000, 1, 1)) || d.isAfter(Money.todayJst().plusDays(366))) return "日付が範囲外です"
        return null
    }
    fun memo(s: String): String? = if (s.length > 500) "メモは 500 文字までです" else null
    fun groupName(s: String): String? = if (s.trim().length !in 1..40) "グループ名は 1〜40 文字で入れてください" else null
    fun categoryName(s: String): String? = if (s.trim().length !in 1..20) "カテゴリ名は 1〜20 文字で入れてください" else null
    fun displayName(s: String): String? = if (s.trim().length !in 1..30) "名前は 1〜30 文字で入れてください" else null
    fun email(s: String): String? = if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(s.trim())) "メールアドレスの形が正しくありません" else null
    fun password(s: String): String? = if (s.length < 8) "パスワードは 8 文字以上にしてください" else null
    fun customSplit(amount: Long, shares: List<Long>): String? =
        if (shares.any { it < 0 }) "分担はマイナスにできません" else if (shares.sum() != amount) "分担の合計（${Money.format(shares.sum())}）が金額と合いません" else null
}
