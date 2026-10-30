package jp.kakeibo.share.ui

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Savings
import kotlin.math.ceil
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.sin

// 硬貨・お札の色。本物と見まちがえないよう、肖像や図柄は描かず、色と形だけで表す（通貨及証券模造取締法。財務省の FAQ）
// 金属と紙の色なので、明るい表示でも暗い表示でも同じ
private class CoinLook(val fill: Color, val edge: Color, val inner: Color? = null)
private val LOOKS = listOf(
    CoinLook(Color(0xFFC2783F), Color(0xFF8A4F22)),                       // 10円玉（青銅。赤みのある銅色）
    CoinLook(Color(0xFFCDD1D6), Color(0xFF7E848D)),                       // 100円玉（白銅。銀白色）
    CoinLook(Color(0xFFD9B44A), Color(0xFF94721A), Color(0xFFD5D8DC)),    // 500円玉（外側が金色・内側が銀色の 2 色）
    CoinLook(Color(0xFF9DBBDC), Color(0xFF4D7199)),                       // 千円札（青系）
    CoinLook(Color(0xFFCDB98F), Color(0xFF85703F)),                       // 1万円札（茶系）
)

private fun DrawScope.coin(c: Offset, r: Float, look: CoinLook) {
    drawCircle(look.fill, r, c)
    look.inner?.let { drawCircle(it, r * 0.62f, c) }
    drawCircle(look.edge, r, c, style = Stroke(1.2.dp.toPx()))
    drawCircle(look.edge.copy(alpha = 0.55f), r * 0.62f, c, style = Stroke(0.8.dp.toPx()))
    drawCircle(Color.White.copy(alpha = 0.35f), r * 0.26f, Offset(c.x - r * 0.35f, c.y - r * 0.35f))
}

private fun DrawScope.bill(tl: Offset, s: Size, look: CoinLook) {
    val cr = CornerRadius(2.dp.toPx())
    drawRoundRect(look.fill, tl, s, cr)
    drawRoundRect(look.edge, tl, s, cr, style = Stroke(1.dp.toPx()))
    val inset = 3.dp.toPx()
    drawRect(look.edge.copy(alpha = 0.45f), Offset(tl.x + inset, tl.y + inset), Size(s.width - inset * 2, s.height - inset * 2), style = Stroke(0.8.dp.toPx()))
    drawOval(look.edge.copy(alpha = 0.5f), Offset(tl.x + s.width * 0.6f, tl.y + s.height * 0.24f), Size(s.width * 0.22f, s.height * 0.52f), style = Stroke(0.8.dp.toPx()))
}

// 積んだ高さ（いちばん上の段の上端）が fillH をこえない段の数。少しでも貯まっていれば 1 段
private fun stackRows(fillH: Float, item: Float, step: Float): Int = when {
    fillH <= 0f -> 0
    fillH <= item -> 1
    else -> 1 + ceil((fillH - item) / step).toInt()
}

// いちばん上の段の数。次の段までの足りない分だけ少なくする
private fun lastRowCount(fillH: Float, item: Float, step: Float, r: Int, perRow: Int): Int {
    if (r == 0) return if (fillH >= item) perRow else maxOf(1, Math.round(perRow * fillH / item))
    val part = ((fillH - item - (r - 1) * step) / step).coerceIn(0f, 1f)
    return maxOf(1, Math.round(perRow * part))
}

// 置き場所（硬貨は中心、お札は左上）。下の段から順に並べる
private fun stack(fillH: Float, left: Float, right: Float, bottom: Float, item: Float, step: Float, w: Float, gap: Float, shiftOdd: Float, bill: Boolean): List<Offset> {
    val out = ArrayList<Offset>()
    val rows = stackRows(fillH, item, step)
    for (r in 0 until rows) {
        val shift = if (r % 2 == 1) shiftOdd else 0f
        val perRow = floor((right - left - shift + gap) / (w + gap)).toInt().coerceAtLeast(1)
        val n = if (r == rows - 1) lastRowCount(fillH, item, step, r, perRow) else perRow
        for (i in 0 until n) {
            val x = left + shift + i * (w + gap)
            out += if (bill) Offset(x, bottom - item - r * step) else Offset(x + w / 2, bottom - item / 2 - r * step)
        }
    }
    return out
}

// 落ちる動き: はじめは重力のように加速し、底で少しはねる（0 → 1。はねる間だけ少し上に戻る）
private fun fall(t: Float): Float = when {
    t <= 0f -> 0f
    t < 0.78f -> (t / 0.78f).let { it * it }
    t < 1f -> 1f - 0.07f * sin(PI.toFloat() * (t - 0.78f) / 0.22f)
    else -> 1f
}

// 目標の貯金箱。中身の多さは目標に対する割合、中身の種類は貯まった額（1 万で 100円玉、3 万で 500円玉、10 万で千円札、50 万で万札）
// 画面を開くと、上から 1 枚ずつ降ってきて積もる（端末の「動きを減らす」設定のときは、はじめから積んだ形）
@Composable
fun CoinBox(name: String, saved: Long, ratio: Double, modifier: Modifier = Modifier) {
    val idx = Savings.coinIndex(saved)
    val coin = Savings.COINS[idx]
    val look = LOOKS[idx]
    val bg = T.bg; val line = T.line; val ink = T.ink; val sub = T.sub
    val measurer = rememberTextMeasurer()
    val pct = Math.round(ratio * 100)
    val shown = ratio.toFloat().coerceIn(0f, 1f)
    val ctx = LocalContext.current
    val still = remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    val progress = remember(saved, ratio) { Animatable(if (still) 1f else 0f) }
    LaunchedEffect(saved, ratio) { if (!still) progress.animateTo(1f, tween(1800, easing = LinearEasing)) }
    Canvas(modifier.fillMaxWidth().height(140.dp).testTag("coinbox").semantics { contentDescription = "${name}の貯金箱 ${pct}%・中身は${coin.name}" }) {
        val labelW = 34.dp.toPx(); val lid = 8.dp.toPx(); val pad = 6.dp.toPx()
        val boxW = size.width - labelW; val boxH = size.height - lid
        // 箱と、上の投入口
        drawRoundRect(bg, Offset(0f, lid), Size(boxW, boxH), CornerRadius(8.dp.toPx()))
        drawRoundRect(line, Offset(0f, lid), Size(boxW, boxH), CornerRadius(8.dp.toPx()), style = Stroke(1.5.dp.toPx()))
        drawRoundRect(ink.copy(alpha = 0.6f), Offset(boxW / 2 - 20.dp.toPx(), lid - 2.dp.toPx()), Size(40.dp.toPx(), 4.dp.toPx()), CornerRadius(2.dp.toPx()))
        val left = pad; val right = boxW - pad; val bottom = size.height - pad; val innerH = boxH - pad * 2 - 4.dp.toPx()
        val fillH = if (saved > 0) maxOf(innerH * shown, 1f) else 0f
        val d = 18.dp.toPx(); val bw = 50.dp.toPx(); val bh = 24.dp.toPx()
        val spots = if (coin.bill) stack(fillH, left, right, bottom, bh, bh * 0.62f, bw, 4.dp.toPx(), bw * 0.3f, true)
            else stack(fillH, left, right, bottom, d, d * 0.82f, d, 0f, d / 2, false)
        // 1 枚ずつ、置き場所の真上から降らせる。下の段から順に、少しばらつかせて落とし始める
        // （全体の 62% の時間で全部が落ち始め、1 枚は 38% の時間で落ちきる）
        val p = progress.value; val n = spots.size; val topY = lid + pad
        clipRect(left, topY, right, bottom) {
            spots.forEachIndexed { k, s ->
                val order = if (n <= 1) 0f else k.toFloat() / (n - 1)
                val jitter = ((k * 7919L) % 101) / 100f
                val t = (p - 0.62f * (0.75f * order + 0.25f * jitter)) / 0.38f
                if (t <= 0f) return@forEachIndexed
                val f = fall(t.coerceAtMost(1f))
                if (coin.bill) {
                    val y = (topY - bh) + (s.y - (topY - bh)) * f
                    val tilt = (1f - (t / 0.78f).coerceIn(0f, 1f)) * (if (k % 2 == 0) 12f else -12f)   // 落ちながら水平に戻る
                    rotate(tilt, Offset(s.x + bw / 2, y + bh / 2)) { bill(Offset(s.x, y), Size(bw, bh), look) }
                } else {
                    val y = (topY - d / 2) + (s.y - (topY - d / 2)) * f
                    coin(Offset(s.x, y), d / 2 - 0.5.dp.toPx(), look)
                }
            }
        }
        // 25・50・75・100% の目盛り（箱の中は点線、右に数字）
        for (q in listOf(25, 50, 75, 100)) {
            val y = bottom - innerH * q / 100f
            drawLine(sub.copy(alpha = 0.45f), Offset(left, y), Offset(right, y), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            val t = measurer.measure("$q%", TextStyle(color = if (pct >= q) ink else sub, fontSize = 11.sp, fontWeight = if (pct >= q) FontWeight.Bold else FontWeight.Normal))
            drawText(t, topLeft = Offset(boxW + 6.dp.toPx(), y - t.size.height / 2f))
        }
    }
}

// 段階の並び（10円 → 100円 → 500円 → 千円札 → 万札）。届いた段階は濃く、今の段階は太字
@Composable
fun CoinSteps(saved: Long, done: Boolean) {
    val idx = Savings.coinIndex(saved)
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Savings.COINS.forEachIndexed { i, c ->
            val look = LOOKS[i]
            Column(Modifier.weight(1f).alpha(if (i <= idx) 1f else 0.35f), horizontalAlignment = Alignment.CenterHorizontally) {
                Canvas(Modifier.size(28.dp, 18.dp)) {
                    if (c.bill) bill(Offset(1.dp.toPx(), 3.dp.toPx()), Size(size.width - 2.dp.toPx(), size.height - 6.dp.toPx()), look)
                    else coin(center, size.height / 2 - 1.dp.toPx(), look)
                }
                Text(c.short, color = T.ink, fontSize = 11.sp, fontWeight = if (i == idx) FontWeight.Bold else FontWeight.Normal, textAlign = TextAlign.Center)
                Text(if (c.from == 0L) "〜" else "${c.from / 10_000}万〜", color = T.faint, fontSize = 10.sp, textAlign = TextAlign.Center)
            }
        }
    }
    val next = Savings.nextCoin(saved)
    val msg = when {
        done -> "目標を達成しました！"
        next == null -> "万札まで貯まりました"
        saved <= 0 -> "貯金すると、箱に 10円玉が入ります"
        else -> "あと ${Money.format(next.second)} で${next.first.name}に変わります"
    }
    Text(msg, Modifier.fillMaxWidth().padding(top = 6.dp), color = if (done) T.accent else T.sub, fontSize = 14.sp, fontWeight = if (done) FontWeight.Bold else FontWeight.Normal, textAlign = TextAlign.Center)
}
