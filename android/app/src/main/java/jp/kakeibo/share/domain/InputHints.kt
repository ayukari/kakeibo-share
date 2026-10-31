package jp.kakeibo.share.domain

import jp.kakeibo.share.data.Category
import jp.kakeibo.share.data.Txn

// 入力を速くするための手がかり（自分たちの記録から学ぶ。外のサービスや AI は使わない）
// 先人調査: 家計簿をやめる理由の 1 位は「面倒」、続けている人の負担の 1 位は「カテゴリ分類」（docs/research-deep-2026-10-30.md）
object InputHints {
    // メモの表記ゆれをそろえる（前後の空白・全角空白・大文字小文字）
    fun normalize(memo: String): String = memo.trim().replace('　', ' ').replace(Regex("\\s+"), " ").lowercase()

    // 同じメモでいちばん多く使ったカテゴリ（同数なら新しい記録のほう）。見つからなければ null
    fun categoryForMemo(txns: List<Txn>, memo: String, kind: String): String? {
        val key = normalize(memo)
        if (key.isEmpty()) return null
        val same = txns.filter { it.kind == kind && normalize(it.memo) == key }
        if (same.isEmpty()) return null
        // txns は新しい順。最初に現れた位置が小さいほど新しい
        return same.groupBy { it.categoryId }.maxWithOrNull(compareBy<Map.Entry<String, List<Txn>>> { it.value.size }.thenByDescending { e -> same.indexOfFirst { it.categoryId == e.key } })?.key
    }

    // カテゴリを、よく使う順に並べる（使っていないものは元の並び順のまま後ろ）
    fun categoryOrder(txns: List<Txn>, cats: List<Category>): List<Category> {
        val count = txns.groupingBy { it.categoryId }.eachCount()
        return cats.sortedWith(compareByDescending<Category> { count[it.id] ?: 0 }.thenBy { it.sort })
    }

    // 最近の入力（同じ種類で、カテゴリ・金額・メモが同じものは 1 つにまとめる）。新しい順に n 件
    fun recent(txns: List<Txn>, kind: String, n: Int = 5): List<Txn> =
        txns.filter { it.kind == kind && !it.isRefund }.distinctBy { Triple(it.categoryId, it.amount, normalize(it.memo)) }.take(n)
}
