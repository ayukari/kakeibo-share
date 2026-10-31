import Foundation

// 入力を速くするための手がかり（自分たちの記録から学ぶ。外のサービスや AI は使わない。InputHints.kt と同じ）
// 先人調査: 家計簿をやめる理由の 1 位は「面倒」、続けている人の負担の 1 位は「カテゴリ分類」（docs/research-deep-2026-10-30.md）
enum InputHints {
    // メモの表記ゆれをそろえる（前後の空白・全角空白・大文字小文字）
    static func normalize(_ memo: String) -> String {
        memo.replacingOccurrences(of: "　", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .lowercased()
    }

    // 同じメモでいちばん多く使ったカテゴリ（同数なら新しい記録のほう）。txns は新しい順
    static func categoryForMemo(_ txns: [Txn], memo: String, kind: String) -> String? {
        let key = normalize(memo)
        guard !key.isEmpty else { return nil }
        let same = txns.filter { $0.kind == kind && normalize($0.memo) == key }
        guard !same.isEmpty else { return nil }
        var count: [String: Int] = [:], first: [String: Int] = [:]
        for (i, t) in same.enumerated() { count[t.categoryId, default: 0] += 1; if first[t.categoryId] == nil { first[t.categoryId] = i } }
        return count.keys.max { a, b in count[a]! != count[b]! ? count[a]! < count[b]! : first[a]! > first[b]! }
    }

    // カテゴリを、よく使う順に並べる（使っていないものは元の並び順のまま後ろ）
    static func categoryOrder(_ txns: [Txn], _ cats: [Category]) -> [Category] {
        var count: [String: Int] = [:]
        for t in txns { count[t.categoryId, default: 0] += 1 }
        return cats.enumerated().sorted { a, b in
            let x = count[a.element.id] ?? 0, y = count[b.element.id] ?? 0
            if x != y { return x > y }
            if a.element.sort != b.element.sort { return a.element.sort < b.element.sort }
            return a.offset < b.offset
        }.map(\.element)
    }

    // 最近の入力（同じ種類で、カテゴリ・金額・メモが同じものは 1 つにまとめる）。新しい順に n 件
    static func recent(_ txns: [Txn], kind: String, n: Int = 5) -> [Txn] {
        var seen = Set<String>(), out: [Txn] = []
        for t in txns where t.kind == kind && !t.refund {
            let key = "\(t.categoryId)|\(t.amount)|\(normalize(t.memo))"
            if seen.insert(key).inserted { out.append(t) }
            if out.count == n { break }
        }
        return out
    }
}
