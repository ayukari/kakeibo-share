import jp.kakeibo.share.physics.CoinWorld
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.awt.Color
import java.awt.RenderingHints
import java.awt.geom.AffineTransform
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import kotlin.math.sqrt

// 貯金箱の物理を PC で動かして確かめる。アプリの CoinWorld.kt と同じコード（Box2D の窓口だけ PC 用）
// 落ちきって止まること・全部が箱の中にあること・枚数が貯金額どおりなことを確かめ、途中と最後の絵を build/pile に描き出す
class PileTest {
    private val res = File(System.getProperty("kb.res"))
    private val out = File(System.getProperty("kb.out")).apply { mkdirs() }

    // 箱の内側（スマホの貯金箱と同じくらい: 幅 318dp・高さ 120dp）
    private val boxW = 318f; private val boxH = 120f

    private fun sizeFor(capacity: Long, bill: Boolean): Float =
        sqrt(boxW * boxH * 0.92f / (capacity * CoinWorld.areaPerItem(bill))).coerceIn(if (bill) 9f else 6f, 26f)

    private fun run(name: String, tier: Int, count: Int, capacity: Long) {
        val bill = tier >= 3
        val d = sizeFor(capacity, bill)
        val w = CoinWorld(boxW / d, boxH / d, bill)
        w.setCount(count, animate = true)
        val shots = ArrayList<BufferedImage>()
        var t = 0f; var moving = true
        val snapAt = mutableListOf(0.4f, 0.9f, 1.6f)
        while (moving && t < 15f) {
            moving = w.step(1f / 60f); t += 1f / 60f
            if (snapAt.isNotEmpty() && t >= snapAt[0]) { snapAt.removeAt(0); shots += draw(w, tier, d) }
            // 全部が箱（とその上の投入口の空き）の中にある
            for (i in 0 until w.count) {
                assertTrue("$name: x ${w.xs[i]}", w.xs[i] in -0.1f..(w.width + 0.1f))
                assertTrue("$name: y ${w.ys[i]}", w.ys[i] in -0.1f..(w.height + CoinWorld.LID_GAP + 0.1f))
            }
        }
        shots += draw(w, tier, d)
        assertFalse("$name: 15 秒たっても止まらない", moving)
        assertEquals("$name: 枚数", count, w.count)
        val top = (0 until w.count).maxOf { w.ys[it] }
        println("$name: d=${"%.1f".format(d)}dp 箱 ${"%.1f".format(w.width)}×${"%.1f".format(w.height)} 止まるまで ${"%.1f".format(t)} 秒 いちばん上 ${"%.2f".format(top / w.height * 100)}%")
        assertTrue("$name: 箱からあふれた", top <= w.height + 0.2f)
        // 途中 3 枚と最後を縦に並べて保存
        val img = BufferedImage(shots[0].width, shots.sumOf { it.height + 6 }, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics(); var y = 0
        for (s in shots) { g.drawImage(s, 0, y, null); y += s.height + 6 }
        g.dispose(); ImageIO.write(img, "png", File(out, "$name.png"))
        w.close()
    }

    private fun draw(w: CoinWorld, tier: Int, d: Float): BufferedImage {
        val k = 3f   // 1dp = 3px
        val img = BufferedImage(((boxW + 12) * k).toInt(), ((boxH + 12) * k).toInt(), BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.color = Color(0xE9, 0xEB, 0xEE); g.fillRoundRect(0, 0, img.width, img.height, 24, 24)
        g.color = Color(0xCD, 0xD1, 0xD6); g.drawRoundRect(0, 0, img.width - 1, img.height - 1, 24, 24)
        val left = 6 * k; val bottom = (boxH + 6) * k
        g.clipRect((6 * k).toInt(), (6 * k).toInt(), (boxW * k).toInt(), (boxH * k).toInt())
        val bill = tier >= 3
        val ih = d * k; val iw = if (bill) ih * 240f / 144f else ih
        for (i in 0 until w.count) {
            val cx = left + w.xs[i] * d * k; val cy = bottom - w.ys[i] * d * k
            val sprite = ImageIO.read(File(res, "money_t${tier}_f${w.frames[i]}.png"))
            val at = AffineTransform()
            at.translate(cx.toDouble(), cy.toDouble()); at.rotate(-w.angles[i].toDouble())
            at.translate(-iw / 2.0, -ih / 2.0); at.scale(iw / sprite.width.toDouble(), ih / sprite.height.toDouble())
            g.drawImage(sprite, at, null)
        }
        g.dispose()
        return img
    }

    // 2 万円（目標 10 万円）: 100円玉 200 枚が、箱の 20% まで
    @Test fun coins100x200() = run("t1_200of1000", 1, 200, 1_000)
    // 6 万円（目標 12 万円）: 500円玉 120 枚が、箱の半分
    @Test fun coins500x120() = run("t2_120of240", 2, 120, 240)
    // 9,990 円（目標 1 万円）: 10円玉 999 枚で、ほぼいっぱい
    @Test fun coins10x999() = run("t0_999of1000", 0, 999, 1_000)
    // 20 万円（目標 25 万円）: 千円札 200 枚
    @Test fun bills1000x200() = run("t3_200of250", 3, 200, 250)
    // 60 万円（目標 60 万円）: 万札 60 枚で、いっぱい
    @Test fun bills10000x60() = run("t4_60of60", 4, 60, 60)
}
