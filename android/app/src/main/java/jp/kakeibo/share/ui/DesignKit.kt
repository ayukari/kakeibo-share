package jp.kakeibo.share.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// かざすレシートの DESIGN.md と同じ決まり。紙のような面・1px の線・点線の区切り・緑は「進む操作と今」だけ・赤は「こえた・取消」だけ。
// 文字は 12 / 14 / 16 / 20 / 28 / 44 の 6 段階、太さは 400 と 700（合計の金額だけ 800）。角丸は面 6dp・ボタン 10dp。
@Immutable
data class Tokens(
    val bg: Color, val card: Color, val ink: Color, val sub: Color, val faint: Color, val line: Color,
    val accent: Color, val accent2: Color, val accentInk: Color, val danger: Color,
)

val LightTokens = Tokens(Color(0xFFE9EBEE), Color(0xFFFCFCFA), Color(0xFF16181D), Color(0xFF5B616B), Color(0xFF6F747E), Color(0xFFCDD1D6),
    Color(0xFF0E7656), Color(0xFFDCEFE7), Color.White, Color(0xFFB42318))
val DarkTokens = Tokens(Color(0xFF0E0F11), Color(0xFF1A1B1E), Color(0xFFECEEF1), Color(0xFFA7ACB5), Color(0xFF858B95), Color(0xFF33363C),
    Color(0xFF47C79B), Color(0xFF16302A), Color(0xFF05261B), Color(0xFFFF8A7A))

val LocalTokens = staticCompositionLocalOf { LightTokens }
val T: Tokens @Composable @ReadOnlyComposable get() = LocalTokens.current

val PaperShape = RoundedCornerShape(6.dp)
val ButtonShape = RoundedCornerShape(10.dp)

// 紙の面（枠は影ではなく 1px の線）
@Composable
fun Paper(modifier: Modifier = Modifier, padding: Dp = 20.dp, content: @Composable ColumnScope.() -> Unit) =
    Column(modifier.fillMaxWidth().clip(PaperShape).background(T.card).border(1.dp, T.line, PaperShape).padding(padding), content = content)

// 行が並ぶ面。行と行のあいだは点線
@Composable
fun ListPaper(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) =
    Column(modifier.fillMaxWidth().clip(PaperShape).background(T.card).border(1.dp, T.line, PaperShape), content = content)

@Composable
fun DashedLine(modifier: Modifier = Modifier) {
    val c = T.line
    Canvas(modifier.fillMaxWidth().height(1.dp)) {
        drawLine(c, Offset(0f, 0f), Offset(size.width, 0f), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 3.dp.toPx())))
    }
}

@Composable
fun SectionLabel(text: String, trailing: String? = null) {
    Row(Modifier.fillMaxWidth().padding(start = 2.dp, end = 2.dp, top = 24.dp, bottom = 8.dp), verticalAlignment = Alignment.Bottom) {
        Text(text, Modifier.weight(1f), color = T.ink, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        if (trailing != null) Text(trailing, color = T.faint, fontSize = 12.sp)
    }
}

// 小さな補足の文字
@Composable fun Sub(text: String, modifier: Modifier = Modifier) = Text(text, modifier, color = T.sub, fontSize = 14.sp)
@Composable fun Faint(text: String, modifier: Modifier = Modifier) = Text(text, modifier, color = T.faint, fontSize = 12.sp)
@Composable fun Label(text: String) = Text(text, color = T.sub, fontSize = 14.sp)

@Composable
fun Big(yen: Long, modifier: Modifier = Modifier, size: Int = 44, color: Color = T.ink, signed: Boolean = false) =
    Text((if (signed && yen > 0) "+" else "") + jp.kakeibo.share.domain.Money.format(yen), modifier, color = color, fontSize = size.sp, fontWeight = FontWeight.ExtraBold,
        lineHeight = (size * 1.15f).sp, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))

@Composable
fun KeyValue(key: String, value: String, first: Boolean = false, valueColor: Color = T.ink) {
    if (!first) DashedLine()
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Text(key, Modifier.weight(1f), color = T.sub, fontSize = 14.sp)
        Text(value, color = valueColor, fontWeight = FontWeight.Bold, fontSize = 16.sp, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
    }
}

// カテゴリの色の丸（色は点・棒・アイコンだけ。文字には使わない）。中は名前の頭の 1 文字
fun parseColor(hex: String?): Color = try { Color(android.graphics.Color.parseColor(hex ?: "#6b7280")) } catch (_: Exception) { Color(0xFF6B7280) }

@Composable
fun CategoryDot(name: String?, colorHex: String?, size: Dp = 40.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(parseColor(colorHex)), contentAlignment = Alignment.Center) {
        if (size >= 20.dp) Text((name ?: "?").take(1), color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.42f).sp)
    }
}

// 1 行（カテゴリの丸・題・補足・右に金額）。押せる行は高さ 56dp 以上
@Composable
fun ItemRow(title: String, sub: String, amount: String, catName: String?, catColor: String?, amountColor: Color = T.ink, onClick: (() -> Unit)? = null) {
    val m = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
    Row(Modifier.fillMaxWidth().then(m).heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CategoryDot(catName, catColor)
        Column(Modifier.weight(1f)) {
            Text(title, color = T.ink, fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(sub, color = T.faint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(amount, color = amountColor, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp, maxLines = 1, softWrap = false,
            style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
    }
}

// 進み具合の棒。tick は「今日までの目安」の位置（0..1）
@Composable
fun Meter(ratio: Float, color: Color = T.accent, tick: Float? = null, modifier: Modifier = Modifier) {
    val track = T.line; val ink = T.ink
    Canvas(modifier.fillMaxWidth().height(8.dp)) {
        drawRoundRect(track, size = size, cornerRadius = CornerRadius(2.dp.toPx()))
        drawRoundRect(color, size = Size(size.width * ratio.coerceIn(0f, 1f), size.height), cornerRadius = CornerRadius(2.dp.toPx()))
        if (tick != null) drawRect(ink.copy(alpha = 0.35f), Offset(size.width * tick.coerceIn(0f, 1f) - 1.dp.toPx(), -2.dp.toPx()), Size(2.dp.toPx(), size.height + 4.dp.toPx()))
    }
}

// カテゴリの横棒
@Composable
fun CategoryBar(name: String, colorHex: String?, amount: Long, max: Long) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.width(112.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CategoryDot(name, colorHex, 26.dp)
            Text(name, color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        val c = parseColor(colorHex)
        Canvas(Modifier.weight(1f).height(12.dp)) {
            val w = size.width * (amount.toFloat() / max.coerceAtLeast(1)).coerceAtLeast(0.015f)
            drawRoundRect(c, size = Size(w, size.height), cornerRadius = CornerRadius(2.dp.toPx()))
        }
        Text(jp.kakeibo.share.domain.Money.format(amount), Modifier.widthIn(min = 84.dp), color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp,
            style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"), maxLines = 1, softWrap = false)
    }
}

// 切り替え（黒い印字のつまみ）。original の .tabs と同じ
@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().clip(ButtonShape).background(T.card).border(1.dp, T.line, ButtonShape).padding(3.dp)) {
        options.forEachIndexed { i, s ->
            val on = i == selected
            Box(Modifier.weight(1f).heightIn(min = 40.dp).clip(RoundedCornerShape(7.dp)).background(if (on) T.ink else Color.Transparent).clickable { onSelect(i) }, contentAlignment = Alignment.Center) {
                Text(s, color = if (on) T.card else T.sub, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
        }
    }
}

// 一覧の上の月の切り替え（前の月・月名・次の月）
@Composable
fun MonthNav(label: String, onPrev: () -> Unit, onNext: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        SquareButton("前の月", onPrev) { Chevron(left = true) }
        Text(label, Modifier.weight(1f), color = T.ink, fontWeight = FontWeight.Bold, fontSize = 16.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        SquareButton("次の月", onNext) { Chevron(left = false) }
    }
}

@Composable
private fun SquareButton(desc: String, onClick: (() -> Unit)?, content: @Composable () -> Unit) {
    val enabled = onClick != null
    Box(Modifier.size(44.dp).alpha(if (enabled) 1f else 0.3f).clip(ButtonShape).background(T.card).border(1.dp, T.line, ButtonShape)
        .then(if (enabled) Modifier.clickable(onClick = onClick!!) else Modifier)
        .semantics { contentDescription = desc }, contentAlignment = Alignment.Center) { content() }
}

@Composable
fun Chevron(left: Boolean, color: Color = T.ink) {
    Canvas(Modifier.size(18.dp)) {
        val p = Path()
        val w = size.width; val h = size.height
        if (left) { p.moveTo(w * 0.65f, h * 0.15f); p.lineTo(w * 0.3f, h * 0.5f); p.lineTo(w * 0.65f, h * 0.85f) }
        else { p.moveTo(w * 0.35f, h * 0.15f); p.lineTo(w * 0.7f, h * 0.5f); p.lineTo(w * 0.35f, h * 0.85f) }
        drawPath(p, color, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

// 下の切り替えの線のアイコン（絵文字は使わない）
enum class Glyph { Home, List, Swap, Chart, More }

@Composable
fun LineIcon(g: Glyph, color: Color, size: Dp = 22.dp) {
    Canvas(Modifier.size(size)) {
        val s = Stroke(2.dp.toPx() * size.value / 24f * 1.1f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        val u = this.size.width / 24f
        fun pt(x: Float, y: Float) = Offset(x * u, y * u)
        val p = Path()
        when (g) {
            Glyph.Home -> { p.moveTo(4 * u, 11 * u); p.lineTo(12 * u, 4 * u); p.lineTo(20 * u, 11 * u); p.lineTo(20 * u, 19 * u); p.lineTo(15 * u, 19 * u); p.lineTo(15 * u, 13 * u); p.lineTo(9 * u, 13 * u); p.lineTo(9 * u, 19 * u); p.lineTo(4 * u, 19 * u); p.close() }
            Glyph.List -> { for (y in listOf(7f, 12f, 17f)) { p.moveTo(8 * u, y * u); p.lineTo(20 * u, y * u); p.moveTo(4 * u, y * u); p.lineTo(4.5f * u, y * u) } }
            Glyph.Swap -> { p.moveTo(5 * u, 9 * u); p.lineTo(19 * u, 9 * u); p.moveTo(15 * u, 5 * u); p.lineTo(19 * u, 9 * u); p.lineTo(15 * u, 13 * u); p.moveTo(19 * u, 16 * u); p.lineTo(5 * u, 16 * u); p.moveTo(9 * u, 12 * u); p.lineTo(5 * u, 16 * u); p.lineTo(9 * u, 20 * u) }
            Glyph.Chart -> { p.moveTo(4 * u, 20 * u); p.lineTo(20 * u, 20 * u); p.moveTo(7 * u, 16 * u); p.lineTo(7 * u, 11 * u); p.moveTo(12 * u, 16 * u); p.lineTo(12 * u, 6 * u); p.moveTo(17 * u, 16 * u); p.lineTo(17 * u, 8 * u) }
            Glyph.More -> { for (x in listOf(6f, 12f, 18f)) { p.moveTo(x * u, 12 * u); p.lineTo((x + 0.01f) * u, 12 * u) } }
        }
        drawPath(p, color, style = s)
    }
}
