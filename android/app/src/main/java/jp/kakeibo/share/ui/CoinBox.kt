package jp.kakeibo.share.ui

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.kakeibo.share.R
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Savings
import jp.kakeibo.share.physics.CoinWorld
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.roundToInt
import kotlin.math.sqrt

// 硬貨・お札の絵。Blender で作った 3D を描き出したもの（tools/render3d/money_sprites.py。お札は bill.py で作り込んだもの）
// 本物と見まちがえないよう、肖像や実際の図柄は描かず、色・質感・形と、このアプリ独自の模様だけ（通貨及証券模造取締法。財務省の FAQ）
// 段階ごとに 8 コマ。0 コマ目が置いたときの姿で、1〜7 コマ目は横の軸で 45° ずつ回した姿（落ちながら回る）
private val FRAME_IDS = arrayOf(
    intArrayOf(R.drawable.money_t0_f0, R.drawable.money_t0_f1, R.drawable.money_t0_f2, R.drawable.money_t0_f3, R.drawable.money_t0_f4, R.drawable.money_t0_f5, R.drawable.money_t0_f6, R.drawable.money_t0_f7),
    intArrayOf(R.drawable.money_t1_f0, R.drawable.money_t1_f1, R.drawable.money_t1_f2, R.drawable.money_t1_f3, R.drawable.money_t1_f4, R.drawable.money_t1_f5, R.drawable.money_t1_f6, R.drawable.money_t1_f7),
    intArrayOf(R.drawable.money_t2_f0, R.drawable.money_t2_f1, R.drawable.money_t2_f2, R.drawable.money_t2_f3, R.drawable.money_t2_f4, R.drawable.money_t2_f5, R.drawable.money_t2_f6, R.drawable.money_t2_f7),
    intArrayOf(R.drawable.money_t3_f0, R.drawable.money_t3_f1, R.drawable.money_t3_f2, R.drawable.money_t3_f3, R.drawable.money_t3_f4, R.drawable.money_t3_f5, R.drawable.money_t3_f6, R.drawable.money_t3_f7),
    intArrayOf(R.drawable.money_t4_f0, R.drawable.money_t4_f1, R.drawable.money_t4_f2, R.drawable.money_t4_f3, R.drawable.money_t4_f4, R.drawable.money_t4_f5, R.drawable.money_t4_f6, R.drawable.money_t4_f7),
)
private const val BILL_ASPECT = 240f / 144f   // お札の絵の横:縦

@Composable
private fun moneyFrames(tier: Int): List<ImageBitmap> {
    val res = LocalContext.current.resources
    return remember(tier) { FRAME_IDS[tier].map { ImageBitmap.imageResource(res, it) } }
}

private fun DrawScope.sprite(img: ImageBitmap, tl: Offset, w: Float, h: Float) =
    drawImage(img, dstOffset = IntOffset(tl.x.roundToInt(), tl.y.roundToInt()), dstSize = IntSize(w.roundToInt(), h.roundToInt()), filterQuality = FilterQuality.Medium)

// 箱の内側の大きさと、中身 1 枚の大きさ d（px）。目標額ちょうどの枚数で、箱がちょうどいっぱいになる大きさにする
private class BoxGeo(val boxW: Float, val lid: Float, val left: Float, val right: Float, val top: Float, val bottom: Float, val d: Float, val bill: Boolean) {
    val w get() = right - left
    val h get() = bottom - top
    // c 枚を積んだときのおよその上端（目盛りに使う）
    fun pileTop(c: Double): Float = bottom - (c * CoinWorld.areaPerItem(bill) * d * d / w).toFloat()

    companion object {
        fun of(size: IntSize, px: (Float) -> Float, bill: Boolean, capacity: Long): BoxGeo? {
            if (size.width <= 0 || size.height <= 0) return null
            val labelW = px(34f); val lid = px(8f); val pad = px(6f)
            val boxW = size.width - labelW
            val left = pad; val right = boxW - pad; val top = lid + pad; val bottom = size.height - pad
            val fit = sqrt((right - left) * (bottom - top) * 0.92f / (capacity * CoinWorld.areaPerItem(bill)))
            val d = fit.coerceIn(px(if (bill) 9f else 6f), px(26f))
            return BoxGeo(boxW, lid, left, right, top, bottom, d, bill)
        }
    }
}

// 端末の傾き（重力の向き）。画面の座標（右が x、上が y）で返す。机に平らに置いたときは下向きのまま
@Composable
private fun TiltEffect(enabled: Boolean, onTilt: (Float, Float) -> Unit) {
    val ctx = LocalContext.current
    val latest by rememberUpdatedState(onTilt)
    DisposableEffect(enabled) {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: sm?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (!enabled || sm == null || sensor == null) return@DisposableEffect onDispose { }
        var lastAngle = Float.NaN
        val listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val gx = -e.values[0]; val gy = -e.values[1]
                if (sqrt(gx * gx + gy * gy) < 3f) return          // ほぼ平ら: 向きを変えない
                val a = atan2(gy, gx)
                if (!lastAngle.isNaN() && abs(a - lastAngle) < 0.12f) return   // 少しの揺れは無視（約 7°）
                lastAngle = a
                latest(gx, gy)
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        onDispose { sm.unregisterListener(listener) }
    }
}

// 目標の貯金箱。中身は貯金額どおりの枚数（2 万円なら 100円玉 200 枚）。1 万で 100円玉、3 万で 500円玉、10 万で千円札、50 万で万札
// 中身の大きさは、目標額ちょうどの枚数で箱がいっぱいになるように決める（だから満ち具合 = 目標に対する割合）
// 物理（Box2D）で、投入口から 1 枚ずつ降ってきて積もる。端末を傾けると転がる。貯金を記録すると増えた分だけ落ちてくる
// 「動きを減らす」設定のときは、はじめから積んだ形。物理の部品が読み込めないとき（テストなど）は、段に並べて描く
@Composable
fun CoinBox(name: String, saved: Long, target: Long, modifier: Modifier = Modifier) {
    val idx = Savings.coinIndex(saved)
    val coin = Savings.COINS[idx]
    val count = Savings.coinCount(saved)
    val capacity = Savings.coinCapacity(saved, target)
    val frames = moneyFrames(idx)
    val bg = T.bg; val line = T.line; val ink = T.ink; val sub = T.sub
    val measurer = rememberTextMeasurer()
    val pct = if (target > 0) Math.round(saved * 100.0 / target) else 0L
    val ctx = LocalContext.current
    val density = LocalDensity.current
    val still = remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    var size by remember { mutableStateOf(IntSize.Zero) }
    val geo = remember(size, coin.bill, capacity) { BoxGeo.of(size, { with(density) { it.dp.toPx() } }, coin.bill, capacity) }
    val world = remember(geo) { if (geo != null && CoinWorld.available) CoinWorld(geo.w / geo.d, geo.h / geo.d, coin.bill) else null }
    DisposableEffect(world) { onDispose { world?.close() } }
    var tick by remember { mutableIntStateOf(0) }
    var kick by remember { mutableIntStateOf(0) }
    LaunchedEffect(world, count, kick) {
        val w = world ?: return@LaunchedEffect
        w.setCount(count.toInt().coerceAtMost(CoinWorld.MAX_BODIES), animate = !still)
        tick++
        if (still) return@LaunchedEffect
        var last = 0L
        while (true) {
            val now = withFrameNanos { it }
            val moving = w.step(if (last == 0L) 0f else (now - last) / 1e9f)
            last = now; tick++
            if (!moving) break   // みんな止まったら計算をやめる（電池を使わない）
        }
    }
    TiltEffect(world != null && !still) { gx, gy -> world?.setGravity(gx, gy); kick++ }

    Canvas(modifier.fillMaxWidth().height(140.dp).onSizeChanged { size = it }.testTag("coinbox")
        .semantics { contentDescription = "${name}の貯金箱 ${pct}%・${coin.name} ${count}枚" }) {
        @Suppress("UNUSED_EXPRESSION") tick   // 物理が進むたびに描き直す
        val g = geo ?: return@Canvas
        // 箱と、上の投入口
        drawRoundRect(bg, Offset(0f, g.lid), Size(g.boxW, size.height - g.lid), CornerRadius(8.dp.toPx()))
        drawRoundRect(line, Offset(0f, g.lid), Size(g.boxW, size.height - g.lid), CornerRadius(8.dp.toPx()), style = Stroke(1.5.dp.toPx()))
        drawRoundRect(ink.copy(alpha = 0.6f), Offset(g.boxW / 2 - 20.dp.toPx(), g.lid - 2.dp.toPx()), Size(40.dp.toPx(), 4.dp.toPx()), CornerRadius(2.dp.toPx()))
        val d = g.d
        val iw = if (coin.bill) d * BILL_ASPECT else d
        clipRect(g.left, g.top, g.right, g.bottom) {
            if (world != null) {
                for (i in 0 until world.count) {
                    val cx = g.left + world.xs[i] * d; val cy = g.bottom - world.ys[i] * d
                    rotate(-Math.toDegrees(world.angles[i].toDouble()).toFloat(), Offset(cx, cy)) {
                        sprite(frames[world.frames[i]], Offset(cx - iw / 2, cy - d / 2), iw, d)
                    }
                }
            } else {
                // 物理なし: 下から段に並べる
                val hw = CoinWorld.halfWidth(coin.bill) * d; val hh = CoinWorld.halfHeight(coin.bill) * d
                val perRow = maxOf(1, ((g.w) / (2 * hw)).toInt())
                for (i in 0 until count.toInt().coerceAtMost(CoinWorld.MAX_BODIES)) {
                    val row = i / perRow; val col = i % perRow
                    val cx = g.left + hw + col * 2 * hw + (if (row % 2 == 1) hw / 2 else 0f)
                    val cy = g.bottom - hh - row * 2 * hh
                    sprite(frames[0], Offset(cx - iw / 2, cy - d / 2), iw, d)
                }
            }
        }
        // 25・50・75・100% の目盛り（目標額の何割の枚数を積んだ高さか。箱の中は点線、右に数字）
        for (q in listOf(25, 50, 75, 100)) {
            val y = g.pileTop(capacity * q / 100.0)
            if (y < g.top) continue
            drawLine(sub.copy(alpha = 0.45f), Offset(g.left, y), Offset(g.right, y), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            val t = measurer.measure("$q%", TextStyle(color = if (pct >= q) ink else sub, fontSize = 11.sp, fontWeight = if (pct >= q) FontWeight.Bold else FontWeight.Normal))
            drawText(t, topLeft = Offset(g.boxW + 6.dp.toPx(), y - t.size.height / 2f))
        }
    }
}

// 枚数・段階の並び（10円 → 100円 → 500円 → 千円札 → 万札）。届いた段階は濃く、今の段階は太字
@Composable
fun CoinSteps(saved: Long, done: Boolean) {
    val idx = Savings.coinIndex(saved)
    val coin = Savings.COINS[idx]
    val count = Savings.coinCount(saved); val rest = Savings.coinRemainder(saved)
    if (count > 0) Text("${coin.name} ${"%,d".format(count)}枚" + (if (rest > 0) "・端数 ${Money.format(rest)}" else "") +
        (if (count > CoinWorld.MAX_BODIES) "（箱には ${"%,d".format(CoinWorld.MAX_BODIES)} 枚まで）" else ""),
        Modifier.fillMaxWidth().padding(top = 6.dp), color = T.ink, fontSize = 14.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Savings.COINS.forEachIndexed { i, c ->
            val img = moneyFrames(i)[0]
            Column(Modifier.weight(1f).alpha(if (i <= idx) 1f else 0.35f), horizontalAlignment = Alignment.CenterHorizontally) {
                Canvas(Modifier.size(if (c.bill) 37.dp else 22.dp, 22.dp)) {
                    val h = if (c.bill) size.width / BILL_ASPECT else size.height
                    sprite(img, Offset(0f, (size.height - h) / 2), size.width, h)
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
