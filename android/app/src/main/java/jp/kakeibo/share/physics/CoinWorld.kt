package jp.kakeibo.share.physics

import box2dandroid.*
import kotlin.math.atan2
import kotlin.math.sqrt

// 貯金箱の中の物理（Box2D v3.2。Android は box2d-jni、iOS は Box2D の C のソースをそのまま使う。CoinWorld.swift と同じ作り）
// 単位は「中身 1 枚の大きさ d = 1」。y は上向き。箱の内側は 0 ≦ x ≦ width、0 ≦ y ≦ height
// 中身は角の丸い横長の箱（置いた硬貨・お札を横から見た形）。箱の上に投入口ぶんの空きがあり、そこから落とす
// physicspreview（PC で物理を確かめる）が、このファイルをそのまま写して使う。Android の部品は使わないこと
class CoinWorld(val width: Float, val height: Float, val bill: Boolean) {
    companion object {
        // 物理の部品が読み込めるか（Robolectric のテストなど、読み込めないときは物理なしで並べる）
        val available: Boolean by lazy { try { B2_World.isValid(0L); true } catch (_: Throwable) { false } }
        const val GRAVITY = 40f        // 1 秒あたり d の何倍で加速するか（小さな硬貨が、見て気持ちよく落ちる速さ）
        const val LID_GAP = 3f         // 箱の上の、投入口から落ちてくる空き
        const val SPAWN_SECONDS = 1.2f // 入れる枚数が多くても、この時間で全部を落とし始める
        const val MAX_BODIES = 1200    // 物理で動かす枚数の上限（それより多いときは、絵に「ほか ○ 枚」と書く）
        private const val STEP = 1f / 60f
        fun halfWidth(bill: Boolean) = if (bill) 0.8f else 0.455f
        fun halfHeight(bill: Boolean) = if (bill) 0.14f else 0.3f
        // 1 枚が箱の中でしめる広さ（d² の何倍か。すき間ぶんで割る）。目標額の枚数で箱がいっぱいになる大きさを決めるのに使う
        fun areaPerItem(bill: Boolean) = 4 * halfWidth(bill) * halfHeight(bill) / 0.78f
    }

    private val world: Long
    private val bodies = ArrayList<Long>()
    private val vec = b2Vec2()
    private val bodyDef = b2BodyDef()
    private val shapeDef = b2ShapeDef()
    private val poly = b2Polygon()
    private var pending = 0
    private var spawnClock = 0f
    private var spawnRate = 0f
    private var acc = 0f
    private var spawned = 0
    private var phase = FloatArray(0)

    // 描くための値（体ごと。作った順）: 位置・角度・回っている絵のコマ
    var count = 0; private set
    var xs = FloatArray(0); private set
    var ys = FloatArray(0); private set
    var angles = FloatArray(0); private set
    var frames = IntArray(0); private set

    init {
        val def = b2WorldDef()
        B2_World.defaultWorldDef(def)
        vec.x = 0f; vec.y = -GRAVITY; def.gravity = vec
        world = B2_World.createWorld(def)
        def.destroy()
        // 壁: 左・右・底、投入口の上のふた。厚さ 1
        B2_Body.defaultBodyDef(bodyDef)
        B2_Shape.defaultShapeDef(shapeDef)
        val top = height + LID_GAP
        wall(-0.5f, top / 2, 0.5f, top / 2 + 1); wall(width + 0.5f, top / 2, 0.5f, top / 2 + 1)
        wall(width / 2, -0.5f, width / 2 + 1, 0.5f); wall(width / 2, top + 0.5f, width / 2 + 1, 0.5f)
        // 中身: よく止まり、少しだけはねる
        bodyDef.type = b2BodyType.b2_dynamicBody
        val m = shapeDef.material
        m.friction = 0.6f; m.restitution = 0.15f; m.rollingResistance = 0.05f
        shapeDef.material = m
        shapeDef.density = 1f
        val r = 0.06f
        B2_Geometry.makeRoundedBox(halfWidth(bill) - r, halfHeight(bill) - r, r, poly)
    }

    private fun wall(cx: Float, cy: Float, hx: Float, hy: Float) {
        vec.x = cx; vec.y = cy; bodyDef.position = vec
        val id = B2_Body.createBody(world, bodyDef)
        B2_Geometry.makeBox(hx, hy, poly)
        B2_Shape.createPolygonShape(id, shapeDef, poly)
    }

    // 0〜1 のばらつき（同じ番号なら毎回同じ。両 OS で同じ並びにする）
    private fun hash(i: Int, salt: Int): Float {
        var h = i * 374761393 + salt * 668265263
        h = (h xor (h ushr 13)) * 1274126177
        return ((h xor (h ushr 16)) and 0xFFFF) / 65535f
    }

    private fun create(x: Float, y: Float, vy: Float, spin: Float) {
        vec.x = x; vec.y = y; bodyDef.position = vec
        vec.x = 0f; vec.y = vy; bodyDef.linearVelocity = vec
        bodyDef.angularVelocity = spin
        val id = B2_Body.createBody(world, bodyDef)
        B2_Shape.createPolygonShape(id, shapeDef, poly)
        bodies += id
    }

    // 入っている枚数をそろえる。増えた分は投入口から 1 枚ずつ落とし、減った分は上から取り出す
    fun setCount(n: Int, animate: Boolean) {
        val want = n.coerceIn(0, MAX_BODIES)
        val have = bodies.size + pending
        if (want > have) {
            if (animate) { pending += want - have; spawnRate = maxOf(pending / SPAWN_SECONDS, 12f) }
            else fill(want - have)
        } else if (want < have) {
            var drop = have - want
            val p = minOf(pending, drop); pending -= p; drop -= p
            repeat(drop) {
                val top = bodies.indices.maxByOrNull { B2_Body.getPosition(bodies[it]).y } ?: return@repeat
                B2_Body.destroyBody(bodies[top]); bodies.removeAt(top)
            }
            wakeAll()
        }
        if (!animate) settle()
        sync(0f)
    }

    // 動きなし: 下から段に並べて置き、物理で落ち着かせる
    private fun fill(k: Int) {
        val hw = halfWidth(bill); val hh = halfHeight(bill)
        val perRow = maxOf(1, (width / (2 * hw + 0.02f)).toInt())
        repeat(k) {
            val i = bodies.size
            val row = i / perRow; val col = i % perRow
            create(hw + 0.01f + col * (2 * hw + 0.02f) + (if (row % 2 == 1) hw * 0.5f else 0f).coerceAtMost(width - (col + 1) * (2 * hw + 0.02f)).coerceAtLeast(0f),
                hh + 0.01f + row * (2 * hh + 0.02f), 0f, 0f)
        }
    }

    private fun settle() { repeat(240) { B2_World.step(world, STEP, 4) } }

    // 端末の傾き（重力の向き）。少しでも変われば、止まっている中身も起こして転がす
    fun setGravity(gx: Float, gy: Float) {
        val len = sqrt(gx * gx + gy * gy).takeIf { it > 0.01f } ?: return
        vec.x = gx / len * GRAVITY; vec.y = gy / len * GRAVITY
        B2_World.setGravity(world, vec)
        wakeAll()
    }

    private fun wakeAll() { for (b in bodies) B2_Body.setAwake(b, true) }

    // 時間を進める（画面のコマごと）。まだ動いているか、落とす予定があれば true
    fun step(dt: Float): Boolean {
        acc = minOf(acc + dt, STEP * 3)
        while (acc >= STEP) {
            acc -= STEP
            if (pending > 0) {
                spawnClock += STEP * spawnRate
                while (spawnClock >= 1f && pending > 0) {
                    spawnClock -= 1f; pending--
                    val i = spawned++
                    val hw = halfWidth(bill)
                    create(hw + hash(i, 1) * (width - 2 * hw), height + 0.6f + hash(i, 2) * (LID_GAP - 1.2f), -6f, (hash(i, 3) - 0.5f) * 14f)
                }
            }
            B2_World.step(world, STEP, 4)
        }
        sync(dt)
        return pending > 0 || B2_World.getAwakeBodyCount(world) > 0
    }

    private fun sync(dt: Float) {
        val n = bodies.size
        if (xs.size < n) {
            val cap = maxOf(n, 16) * 3 / 2
            xs = xs.copyOf(cap); ys = ys.copyOf(cap); angles = angles.copyOf(cap); frames = frames.copyOf(cap); phase = phase.copyOf(cap)
        }
        for (i in 0 until n) {
            val t = B2_Body.getTransform(bodies[i])
            val p = t.p; val q = t.q
            xs[i] = p.x; ys[i] = p.y; angles[i] = atan2(q.s, q.c)
            val v = B2_Body.getLinearVelocity(bodies[i])
            val speed = sqrt(v.x * v.x + v.y * v.y)
            // 速く動いている間は、3D の絵を回して見せる（速さに合わせてコマを進める）。止まると置いた姿
            phase[i] += speed * dt * 1.1f
            frames[i] = if (speed < 1.5f) 0 else phase[i].toInt() % 8
        }
        count = n
    }

    fun close() {
        B2_World.destroyWorld(world)
        vec.destroy(); bodyDef.destroy(); shapeDef.destroy(); poly.destroy()
    }
}
