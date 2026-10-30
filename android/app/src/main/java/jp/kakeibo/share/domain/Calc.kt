package jp.kakeibo.share.domain

// 電卓つきキーボードの計算（MoneyNote などの上位アプリと同じく、入力欄で「1200+380」のように足し算できる）。
// 円の整数。× ÷ を先に計算し、途中の割り算は小数のまま、最後に四捨五入する。式がおかしければ null
object Calc {
    fun evaluate(expr: String): Long? {
        val s = expr.replace(",", "").replace("×", "*").replace("÷", "/").replace("−", "-").trim()
        if (s.isEmpty()) return null
        // 数と記号に分ける（先頭の - は認めない。金額はプラスだけ）
        val nums = mutableListOf<Double>(); val ops = mutableListOf<Char>()
        var cur = StringBuilder()
        for (c in s) {
            when {
                c.isDigit() -> cur.append(c)
                c in "+-*/" -> { if (cur.isEmpty()) return null; nums += cur.toString().toDouble(); ops += c; cur = StringBuilder() }
                else -> return null
            }
        }
        if (cur.isEmpty()) {   // 最後が記号なら、その記号は無視する（「1200+」→ 1200）
            if (ops.isEmpty()) return null
            ops.removeAt(ops.lastIndex)
        } else nums += cur.toString().toDouble()
        // × ÷ を先に
        val n2 = mutableListOf(nums[0]); val o2 = mutableListOf<Char>()
        for (i in ops.indices) {
            val b = nums[i + 1]
            when (ops[i]) {
                '*' -> n2[n2.lastIndex] = n2.last() * b
                '/' -> { if (b == 0.0) return null; n2[n2.lastIndex] = n2.last() / b }
                else -> { o2 += ops[i]; n2 += b }
            }
        }
        var r = n2[0]
        for (i in o2.indices) r = if (o2[i] == '+') r + n2[i + 1] else r - n2[i + 1]
        if (r.isNaN() || r.isInfinite() || r > 9.99e11) return null
        return Math.round(r)
    }

    // 式に記号があるか（あれば「= 計算結果」を表示する）
    fun hasOperator(expr: String) = expr.any { it in "+-*/×÷−" }

    // キーを押したときの次の式。key は "0".."9" / "00" / "+" "−" "×" "÷" / "⌫" / "C" / "="
    fun press(expr: String, key: String): String = when (key) {
        "C" -> ""
        "⌫" -> expr.dropLast(1)
        "=" -> evaluate(expr)?.takeIf { it >= 0 }?.toString() ?: expr
        "+", "−", "×", "÷" -> when {
            expr.isEmpty() -> expr
            expr.last() in "+−×÷" -> expr.dropLast(1) + key   // 記号の付け替え
            else -> expr + key
        }
        "00" -> if (expr.isEmpty() || expr.last() in "+−×÷") expr else (expr + "00").take(16)
        else -> if (expr == "0") key else (expr + key).take(16)
    }

    // 割合（%）で分けた金額。端数の円は、並びの先頭から 1 円ずつ（均等割りと同じ決まり）。合計が 100 でなければ null
    fun ratioSplit(amount: Long, percents: List<Int>): List<Long>? {
        if (percents.isEmpty() || percents.any { it < 0 } || percents.sum() != 100) return null
        val base = percents.map { amount * it / 100 }
        var rest = amount - base.sum()
        return base.mapIndexed { i, b -> if (rest > 0 && percents[i] > 0) { rest--; b + 1 } else b }
    }
}
