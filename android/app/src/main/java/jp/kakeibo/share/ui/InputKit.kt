package jp.kakeibo.share.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.kakeibo.share.data.Category
import jp.kakeibo.share.domain.Calc
import jp.kakeibo.share.domain.Money
import java.time.LocalDate

// 入力の部品（上位の家計簿アプリと同じ作り: 日付の左右の矢印・大きな金額・電卓のキー・カテゴリのタイル）

private val DOW = listOf("月", "火", "水", "木", "金", "土", "日")

// 日付: ‹ 10月30日(木) ›。真ん中を押すと日付を選べる
@Composable
fun DateStepper(date: LocalDate, onChange: (LocalDate) -> Unit) {
    val ctx = LocalContext.current
    val today = Money.todayJst()
    MonthNav(
        "${date.monthValue}月${date.dayOfMonth}日(${DOW[date.dayOfWeek.value - 1]})" + if (date == today) "・今日" else "",
        { onChange(date.minusDays(1)) },
        if (date < today.plusDays(366)) ({ onChange(date.plusDays(1)) }) else null,
        onLabel = { DatePickerDialog(ctx, { _, y, m, d -> onChange(LocalDate.of(y, m + 1, d)) }, date.year, date.monthValue - 1, date.dayOfMonth).show() },
    )
}

// 大きな金額の表示（式があれば下に「= 計算結果」）
@Composable
fun AmountDisplay(expr: String, error: String?) {
    val v = Calc.evaluate(expr)
    Column(Modifier.fillMaxWidth().clip(PaperShape).background(T.card).border(if (error != null) 2.dp else 1.dp, if (error != null) T.danger else T.line, PaperShape)
        .padding(horizontal = 16.dp, vertical = 10.dp).testTag("amount").semantics { contentDescription = "金額 ${if (v != null) Money.format(v) else "未入力"}" }, horizontalAlignment = Alignment.End) {
        Text(if (expr.isEmpty()) "¥0" else "¥" + pretty(expr), color = if (expr.isEmpty()) T.faint else T.ink, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold,
            maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
        if (Calc.hasOperator(expr) && v != null) Text("= ${Money.format(v)}", color = T.sub, fontSize = 16.sp)
        if (error != null) Text(error, color = T.danger, fontSize = 12.sp)
    }
}

// 式の数字に 3 桁ごとのカンマを付ける
private fun pretty(expr: String): String = Regex("\\d+").replace(expr) { m -> m.value.toLongOrNull()?.let { "%,d".format(it) } ?: m.value }

// 電卓のキー（4 列 × 5 段）
@Composable
fun CalcKeypad(onKey: (String) -> Unit) {
    val rows = listOf(listOf("7", "8", "9", "÷"), listOf("4", "5", "6", "×"), listOf("1", "2", "3", "−"), listOf("0", "00", "⌫", "+"), listOf("C", "="))
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { k ->
                    val op = k in listOf("÷", "×", "−", "+", "=")
                    val w = if (row.size == 2) 2f else 1f
                    Box(Modifier.weight(w).height(48.dp).clip(ButtonShape).background(if (k == "=") T.ink else if (op) T.accent2 else T.card)
                        .border(1.dp, T.line, ButtonShape).clickable { onKey(k) }.testTag("key_$k")
                        .semantics { contentDescription = when (k) { "⌫" -> "1 文字消す"; "C" -> "全部消す"; "÷" -> "割る"; "×" -> "掛ける"; "−" -> "引く"; "+" -> "足す"; "=" -> "計算する"; else -> k } },
                        contentAlignment = Alignment.Center) {
                        Text(k, color = if (k == "=") T.card else T.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

// カテゴリのタイル（4 列。色の丸と名前。選ぶと黒い枠）
@Composable
fun CategoryGrid(cats: List<Category>, selected: Category?, onPick: (Category) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        cats.chunked(4).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { c ->
                    val on = selected?.id == c.id
                    Column(Modifier.weight(1f).heightIn(min = 72.dp).clip(RoundedCornerShape(8.dp)).background(if (on) T.accent2 else T.card)
                        .border(if (on) 2.dp else 1.dp, if (on) T.ink else T.line, RoundedCornerShape(8.dp)).clickable { onPick(c) }.padding(vertical = 8.dp, horizontal = 4.dp)
                        .testTag("cat_${c.name}"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        CategoryDot(c.name, c.color, 30.dp, c.icon)
                        Text(c.name, color = T.ink, fontSize = 12.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                    }
                }
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
