package jp.kakeibo.share.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Savings
import jp.kakeibo.share.domain.Validate
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.UUID

// ---------- 貯金（かざすレシートの「貯金」と同じ: 合計 → 目標の封筒 → 1 年のグラフ → 通帳） ----------
data class SavingsData(
    val goals: List<SavingsGoal>, val status: List<SavingsStatus>, val passbook: List<PassbookRow>, val series: List<SavingsPoint>,
    val income: Long, val monthlyExpense: List<Long>,
)

// 記録する画面を開く合図（目標・種類・向き）
data class SaveIntent(val goalId: String?, val kind: String, val dir: Int)

@Composable
fun SavingsScreen(ctx: GroupCtx, open: (Sub) -> Unit) {
    val today = Money.todayJst()
    val vm: LoadVM<SavingsData> = viewModel(key = "save-${ctx.g.id}-r${ctx.rev}") {
        LoadVM {
            SavingsData(ctx.repo.goals(ctx.g.id), ctx.repo.savingsStatus(ctx.g.id), ctx.repo.passbook(ctx.g.id), ctx.repo.savingsSeries(ctx.g.id, today),
                ctx.repo.monthSummary(ctx.g.id, today).income, ctx.repo.monthlySeries(ctx.g.id, today.minusMonths(1), 6).map { it.expense })
        }
    }
    val st by vm.state.collectAsState()
    val host = remember { SnackbarHostState() }
    MessageEffect(vm, host)
    var saveIntent by remember { mutableStateOf<SaveIntent?>(null) }
    var pbGoal by remember { mutableStateOf<String?>(null) }
    var pbRows by remember { mutableIntStateOf(20) }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 112.dp)) {
            item {
                LoadableView(st, { vm.reload() }) { d -> SavingsContent(ctx, d, today, open, { saveIntent = it }, pbGoal, { pbGoal = it; pbRows = 20 }, pbRows) { pbRows += 20 } }
            }
        }
        SnackbarHost(host, Modifier.align(Alignment.BottomCenter))
    }
    val d = (st as? Loadable.Ready)?.value
    saveIntent?.let { si -> if (d != null) SaveDialog(ctx, d.goals, si, onDone = { msg -> saveIntent = null; if (msg != null) { vm.message.value = msg; vm.reload() } }) }
}


// 貯金の中身（読み込んだデータから描く。画面のテストからも使う）
@Composable
fun SavingsContent(ctx: GroupCtx, d: SavingsData, today: LocalDate, open: (Sub) -> Unit, onSave: (SaveIntent) -> Unit, pbGoal: String?, setPbGoal: (String?) -> Unit, pbRows: Int, more: () -> Unit) {
    if (d.goals.isEmpty()) SavingsEmpty(ctx, d, open)
    else Column {
        val total = d.status.sumOf { it.saved }
        val monthKey = "%04d-%02d".format(today.year, today.monthValue)
        val thisMonth = d.passbook.filter { it.day.startsWith(monthKey) }.sumOf { it.amount }
        Paper {
            Label("貯金の合計")
            Big(total)
            Sub("今月 ${(if (thisMonth > 0) "+" else "") + Money.format(thisMonth)}" + if (d.income > 0 && thisMonth > 0) "・収入の ${Math.round(thisMonth * 100.0 / d.income)}%" else "")
            if (ctx.can("member")) Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val main = d.goals.firstOrNull { it.isMain }?.id ?: d.goals.first().id
                Button({ onSave(SaveIntent(main, "manual", 1)) }, Modifier.weight(1f).heightIn(min = 48.dp), shape = ButtonShape, contentPadding = PaddingValues(4.dp)) { Text("貯金した", fontWeight = FontWeight.Bold, fontSize = 14.sp) }
                OutlinedButton({ onSave(SaveIntent(main, "manual", -1)) }, Modifier.weight(1f).heightIn(min = 48.dp), shape = ButtonShape, contentPadding = PaddingValues(4.dp)) { Text("取り崩した", color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp) }
                OutlinedButton({ onSave(SaveIntent(main, "tsumori", 1)) }, Modifier.weight(1f).heightIn(min = 48.dp), shape = ButtonShape, contentPadding = PaddingValues(4.dp)) { Text("つもり貯金", color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp) }
            }
        }
        SectionLabel("目標", "${d.goals.size} 件")
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            d.goals.sortedByDescending { it.isMain }.forEach { g ->
                val s = d.status.firstOrNull { it.goalId == g.id } ?: return@forEach
                Envelope(ctx, g, s, d.passbook.filter { it.goalId == g.id }, today, onRecord = { onSave(SaveIntent(g.id, "manual", 1)) }, onEdit = { open(Sub.Goal(g)) })
            }
        }
        if (d.goals.size < 10 && ctx.can("member"))
            OutlinedButton({ open(Sub.Goal(null)) }, Modifier.fillMaxWidth().padding(top = 10.dp).heightIn(min = 52.dp), shape = ButtonShape) { Text("＋ 目標を作る", color = T.ink, fontWeight = FontWeight.Bold) }
        if (d.series.any { it.deposit > 0 || it.withdrawal > 0 }) {
            SectionLabel("この 1 年の貯金")
            Paper { SavingsChart(d.series) }
        }
        Passbook(d, pbGoal, setPbGoal, pbRows, more)
    }
}

// 目標がまだないとき: ひな形（もしものとき・旅行・家電・帰省）と、自分で作る
@Composable
private fun SavingsEmpty(ctx: GroupCtx, d: SavingsData, open: (Sub) -> Unit) {
    val em = Savings.emergencyTarget(d.monthlyExpense)
    val tpl = listOf(
        Triple("もしものとき", em?.second ?: 300000L, if (em != null) "月の支出の平均 ${Money.format(em.first)} × 3 か月" else "生活費の 3〜6 か月分が目安"),
        Triple("旅行", null, "行き先や時期を名前に入れると続きやすい"),
        Triple("家電の買い替え", null, "冷蔵庫・スマホ・パソコンなど"),
        Triple("帰省・イベント", null, "年末年始・お祝いなど"),
    )
    Paper {
        Text("貯金を始めましょう", color = T.ink, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Sub("貯める目的に名前を付けて、目標の金額を決めます。目的ごとに分けると、使わずに貯まりやすくなります。記録は通帳のように残ります。", Modifier.padding(top = 6.dp))
        if (ctx.can("member")) {
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                tpl.forEach { (name, target, note) ->
                    Row(Modifier.fillMaxWidth().clip(ButtonShape).border(1.dp, T.line, ButtonShape).background(T.card).clickable { open(Sub.Goal(null, name, target)) }
                        .heightIn(min = 56.dp).padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) { Text(name, color = T.ink, fontWeight = FontWeight.Bold); Faint(note) }
                        if (target != null) Text(Money.format(target), color = T.sub, fontSize = 14.sp)
                    }
                }
            }
            Button({ open(Sub.Goal(null)) }, Modifier.fillMaxWidth().padding(top = 12.dp).heightIn(min = 52.dp), shape = ButtonShape) { Text("自分で目標を作る", fontWeight = FontWeight.Bold) }
        } else Faint("目標を作れるのはメンバー以上です", Modifier.padding(top = 8.dp))
    }
    Faint("ここは記録です。お金を実際に移すのは、銀行の自動積立・自動振替などで行ってください。", Modifier.padding(start = 4.dp, end = 4.dp, top = 12.dp))
}

// 目標の封筒（上辺に封のかぶせの線）。中に貯金箱（貯まった額で硬貨からお札に変わる）
@Composable
fun Envelope(ctx: GroupCtx, g: SavingsGoal, s: SavingsStatus, rows: List<PassbookRow>, today: LocalDate, onRecord: (() -> Unit)?, onEdit: (() -> Unit)?) {
    val line = T.line
    Column(Modifier.fillMaxWidth().clip(PaperShape).background(T.card).border(1.dp, T.line, PaperShape)
        .padding(start = 16.dp, end = 16.dp, top = 0.dp, bottom = 14.dp)) {
        Canvas(Modifier.fillMaxWidth().height(12.dp)) {
            drawLine(line, Offset(0f, 0f), Offset(size.width / 2, size.height), 1.dp.toPx())
            drawLine(line, Offset(size.width, 0f), Offset(size.width / 2, size.height), 1.dp.toPx())
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
            Text(g.name, color = T.ink, fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (g.isMain) Text("いちばん大事", Modifier.padding(start = 6.dp).border(1.dp, T.ink, RoundedCornerShape(3.dp)).padding(horizontal = 6.dp), color = T.ink, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            if (g.visibility == "private") Text("自分だけ", Modifier.padding(start = 6.dp), color = T.faint, fontSize = 12.sp)
            }
            Text("${Math.round(s.ratio * 100)}%", color = T.sub, fontSize = 14.sp)
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Text(Money.format(s.saved), color = T.ink, fontWeight = FontWeight.ExtraBold, fontSize = 24.sp, style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
            Text(" / ${Money.format(g.target)}", color = T.sub, fontSize = 14.sp, modifier = Modifier.padding(bottom = 3.dp))
        }
        CoinBox(g.name, s.saved, s.ratio, Modifier.padding(top = 10.dp))
        CoinSteps(s.saved, s.done)
        Sub(Savings.pace(g, s), Modifier.padding(top = 8.dp))
        val ms = Savings.milestone(g.target, rows, today)
        if (ms?.thisMonth == true) Text(ms.text, Modifier.fillMaxWidth().padding(top = 10.dp).clip(PaperShape).background(T.bg).padding(12.dp), color = T.ink, fontSize = 14.sp)
        if (onRecord != null || onEdit != null) Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (onRecord != null && ctx.can("member")) OutlinedButton(onRecord, Modifier.weight(1f).heightIn(min = 44.dp), shape = ButtonShape) { Text("記録する", color = T.ink, fontWeight = FontWeight.Bold) }
            if (onEdit != null) TextButton(onEdit, Modifier.weight(1f).heightIn(min = 44.dp)) { Text("直す・記録を見る", color = T.sub) }
        }
    }
}

// 12 か月の貯金（預け入れ・引き出し）
@Composable
private fun SavingsChart(series: List<SavingsPoint>) {
    val max = maxOf(1L, series.maxOf { maxOf(it.deposit, it.withdrawal) })
    val acc = T.accent; val dan = T.danger.copy(alpha = 0.75f); val line = T.line
    Canvas(Modifier.fillMaxWidth().height(110.dp).semantics { contentDescription = "12 か月の貯金" }) {
        val gw = size.width / series.size; val bw = minOf(10.dp.toPx(), (gw - 4.dp.toPx()) / 2)
        fun h(v: Long) = size.height * v / max
        drawLine(line, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
        series.forEachIndexed { i, m ->
            val x = gw * i + gw / 2
            if (m.deposit > 0) drawRoundRect(acc, Offset(x - bw - 1.dp.toPx(), size.height - h(m.deposit)), Size(bw, h(m.deposit)), CornerRadius(1.dp.toPx()))
            if (m.withdrawal > 0) drawRoundRect(dan, Offset(x + 1.dp.toPx(), size.height - h(m.withdrawal)), Size(bw, h(m.withdrawal)), CornerRadius(1.dp.toPx()))
        }
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp)) { series.forEachIndexed { i, m -> Text(if (i % 2 == series.size % 2) "" else "${m.month.substring(5, 7).toInt()}月", Modifier.weight(1f), color = T.faint, fontSize = 10.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center) } }
    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(T.accent)); Text("預け入れ", color = T.sub, fontSize = 12.sp)
        if (series.any { it.withdrawal > 0 }) { Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(T.danger)); Text("引き出し", color = T.sub, fontSize = 12.sp) }
    }
}

// 通帳: 日付順で、いちばん新しい行が下（本物の通帳と同じ）。上の行に年月日・お引出し・お預入れ・差引残高、下の行に摘要
@Composable
private fun Passbook(d: SavingsData, goalId: String?, onGoal: (String?) -> Unit, shownRows: Int, onMore: () -> Unit) {
    // 目標で絞ったときは、その目標だけの差引残高にする
    val rows = if (goalId == null) d.passbook else d.passbook.filter { it.goalId == goalId }.let { l -> var b = 0L; l.map { r -> b += r.amount; r.copy(balance = b) } }
    val shown = rows.takeLast(shownRows)
    SectionLabel("通帳", "${rows.size} 件")
    if (d.goals.size > 1) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        PassChip("すべて", goalId == null) { onGoal(null) }
        d.goals.forEach { g -> PassChip(g.name, goalId == g.id) { onGoal(g.id) } }
    }
    val ymd = { day: String -> "${day.substring(2, 4)}-${day.substring(5, 7)}-${day.substring(8)}" }
    ListPaper {
        Row(Modifier.fillMaxWidth().background(T.bg).padding(horizontal = 12.dp, vertical = 8.dp)) {
            listOf("年月日", "お引出し", "お預入れ", "差引残高").forEachIndexed { i, h -> Text(h, Modifier.weight(if (i == 0) 0.9f else 1f), color = T.sub, fontSize = 11.sp, fontWeight = FontWeight.Bold, textAlign = if (i == 0) androidx.compose.ui.text.style.TextAlign.Start else androidx.compose.ui.text.style.TextAlign.End) }
        }
        if (rows.size > shown.size) TextButton(onMore, Modifier.fillMaxWidth().heightIn(min = 44.dp)) { Text("前の ${minOf(20, rows.size - shown.size)} 件を見る", color = T.sub) }
        if (shown.isEmpty()) Sub("まだ記録がありません。「貯金した」から始めましょう。", Modifier.padding(14.dp))
        shown.forEachIndexed { i, r ->
            Column(Modifier.fillMaxWidth().background(if (i % 2 == 0) T.card else androidx.compose.ui.graphics.lerp(T.card, T.bg, 0.35f)).padding(horizontal = 12.dp, vertical = 7.dp)) {
                Row(Modifier.fillMaxWidth()) {
                    val num = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum")
                    Text(ymd(r.day), Modifier.weight(0.9f), color = T.sub, fontSize = 13.sp, style = num)
                    Text(if (r.amount < 0) Money.format(-r.amount) else "", Modifier.weight(1f), color = T.danger, fontSize = 13.sp, style = num, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                    Text(if (r.amount > 0) Money.format(r.amount) else "", Modifier.weight(1f), color = T.ink, fontSize = 13.sp, style = num, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                    Text(Money.format(r.balance), Modifier.weight(1f), color = T.ink, fontSize = 13.sp, fontWeight = FontWeight.Bold, style = num, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                }
                val memo = (if (r.amount < 0) "引出" else Savings.KIND_NAMES[r.kind] ?: "預入") + (if (goalId == null) "・${r.goalName}" else "") +
                    (if (r.memo.isNotBlank() && r.kind != "leftover" && r.kind != "auto") "・${r.memo}" else "")
                Text(memo, Modifier.padding(start = 56.dp), color = T.sub, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            DashedLine()
        }
    }
}

@Composable
private fun PassChip(text: String, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.clip(ButtonShape).background(if (on) T.ink else T.card).border(1.dp, if (on) T.ink else T.line, ButtonShape).clickable(onClick = onClick)
        .heightIn(min = 44.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
        Text(text, color = if (on) T.card else T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp)
    }
}

// 貯金した・取り崩した・つもり貯金
@Composable
fun SaveDialog(ctx: GroupCtx, goals: List<SavingsGoal>, si: SaveIntent, onDone: (String?) -> Unit) {
    val scope = rememberCoroutineScope()
    var dir by remember { mutableIntStateOf(si.dir) }
    var amount by remember { mutableStateOf("") }
    var memo by remember { mutableStateOf("") }
    var goal by remember { mutableStateOf(goals.firstOrNull { it.id == si.goalId } ?: goals.first()) }
    var day by remember { mutableStateOf(Money.todayJst()) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val reqId = remember { UUID.randomUUID().toString() }
    val tsumori = si.kind == "tsumori"
    AlertDialog({ if (!busy) onDone(null) },
        title = { Text(if (tsumori) "つもり貯金" else if (dir < 0) "取り崩しを記録する" else "貯金を記録する", fontWeight = FontWeight.Bold) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Sub(if (tsumori) "買うのをやめた物の金額を、貯金したことにします（あとで実際に移しておくと確実です）。" else "口座や貯金箱に移した金額を記録します。")
                if (!tsumori) Segmented(listOf("貯金した", "取り崩した"), if (dir > 0) 0 else 1, { dir = if (it == 0) 1 else -1 })
                AmountField(amount, { amount = it; error = null }, error = error)
                OutlinedTextField(memo, { memo = it.take(60) }, Modifier.fillMaxWidth(), label = { Text(if (tsumori) "がまんした物（例: コンビニのコーヒー）" else "メモ（なくてもよい）") }, singleLine = true)
                if (goals.size > 1) Picker("どの目標に", goals, goal, { it.name }, { goal = it })
                DateField(day, { if (!it.isAfter(Money.todayJst())) day = it })
            }
        },
        confirmButton = {
            TextButton({
                val e = Validate.amount(amount); if (e != null) { error = e; return@TextButton }
                val a = Money.parse(amount)!! * dir
                busy = true
                scope.launch {
                    try { ctx.repo.recordSaving(goal.id, day, a, si.kind, memo.trim(), reqId); onDone(if (a < 0) "${Money.format(-a)} を取り崩しました" else "${Money.format(a)} 貯金しました") }
                    catch (ex: AppError) { error = ex.userMessage } finally { busy = false }
                }
            }, enabled = !busy) { Text("記録する", color = T.accent, fontWeight = FontWeight.Bold) }
        },
        dismissButton = { TextButton({ onDone(null) }, enabled = !busy) { Text("やめる", color = T.sub) } })
}

// ---------- 目標を作る・直す（名前・金額・期限・毎月の先取り・いちばん大事か・自分だけか）。記録の一覧と、やめることも ----------
@Composable
fun GoalScreen(ctx: GroupCtx, goal: SavingsGoal?, presetName: String?, presetTarget: Long?, onDone: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(goal?.name ?: presetName ?: "") }
    var target by remember { mutableStateOf(goal?.target?.toString() ?: presetTarget?.toString() ?: "") }
    var hasDue by remember { mutableStateOf(goal?.dueMonth != null) }
    var due by remember { mutableStateOf(goal?.dueMonth?.let { LocalDate.parse(it) } ?: Money.todayJst().withDayOfMonth(1).plusMonths(12)) }
    var auto by remember { mutableStateOf(goal?.autoAmount?.toString() ?: "") }
    var dom by remember { mutableIntStateOf(goal?.autoDom ?: 25) }
    var main by remember { mutableStateOf(goal?.isMain ?: false) }
    var private by remember { mutableStateOf(goal?.visibility == "private") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var askArchive by remember { mutableStateOf(false) }
    val rowsVm: LoadVM<List<PassbookRow>>? = goal?.let { g -> viewModel(key = "goalrows-${g.id}-r${ctx.rev}") { LoadVM { ctx.repo.passbook(ctx.g.id, g.id) } } }
    val canEdit = goal == null || ctx.can("admin") || goal.createdBy == ctx.repo.userId()

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedTextField(name, { name = it.take(20) }, Modifier.fillMaxWidth(), label = { Text("目的（例: 旅行・車検・もしものとき）") }, singleLine = true, enabled = canEdit)
        AmountField(target, { target = it }, label = "目標の金額（円）")
        Row(verticalAlignment = Alignment.CenterVertically) { Switch(hasDue, { hasDue = it }, enabled = canEdit); Text("期限を決める", Modifier.padding(start = 8.dp), color = T.ink) }
        if (hasDue) Picker("いつまでに", (0..60).map { Money.todayJst().withDayOfMonth(1).plusMonths(it.toLong()) }, due, { "${it.year}年${it.monthValue}月" }, { due = it })
        AmountField(auto, { auto = it }, label = "毎月の先取り貯金（円。なければ空のまま）")
        if (auto.isNotBlank()) Picker("先取りする日（給料日など）", (1..31).toList() + 99, dom, { Savings.domLabel(it) }, { dom = it })
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(main, { main = it; if (it) private = false }, enabled = canEdit)
            Column(Modifier.padding(start = 8.dp)) { Text("いちばん大事な目標にする", color = T.ink); Faint("ホームにはこの目標だけを出します") }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(private, { private = it; if (it) main = false }, enabled = canEdit)
            Column(Modifier.padding(start = 8.dp)) { Text("自分だけに見せる", color = T.ink); Faint("ほかのメンバーには見えません（へそくりなど）") }
        }
        error?.let { Text(it, color = T.danger) }
        if (canEdit) Button({
            val e = (if (name.isBlank()) "目的を入れてください" else null) ?: Validate.amount(target) ?: (if (auto.isNotBlank()) Validate.amount(auto) else null)
            if (e != null) { error = e; return@Button }
            busy = true; error = null
            scope.launch {
                try {
                    ctx.repo.saveGoal(ctx.g.id, goal, name, Money.parse(target)!!, if (hasDue) due else null, main, auto.takeIf { it.isNotBlank() }?.let { Money.parse(it) },
                        if (auto.isNotBlank()) dom else null, goal?.startOn?.let { LocalDate.parse(it) } ?: Money.todayJst(), private)
                    runCatching { ctx.repo.generateDueSavings(ctx.g.id) }
                    onDone(if (goal == null) "「${name.trim()}」の目標を作りました" else "保存しました")
                } catch (ex: AppError) { error = ex.userMessage } finally { busy = false }
            }
        }, Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = ButtonShape, enabled = !busy) { Text(if (goal == null) "目標を作る" else "保存する", fontWeight = FontWeight.Bold) }
        else Faint("この目標を直せるのは、作った人と管理者です")
        if (goal != null && canEdit) OutlinedButton({ askArchive = true }, Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = ButtonShape, enabled = !busy) { Text("この目標をやめる", color = T.danger) }
        if (rowsVm != null) {
            val rs by rowsVm.state.collectAsState()
            LoadableView(rs, { rowsVm.reload() }) { rows ->
                SectionLabel("記録", Money.format(rows.lastOrNull()?.balance ?: 0))
                if (rows.isEmpty()) Paper { Sub("まだ記録がありません") }
                else ListPaper {
                    rows.reversed().take(30).forEachIndexed { i, r ->
                        if (i > 0) DashedLine()
                        val mine = r.createdBy == ctx.repo.userId() || ctx.can("admin")
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("${r.day.substring(5).replace('-', '/')} ${Savings.KIND_NAMES[r.kind] ?: ""}" + if (r.memo.isNotBlank() && r.kind != "leftover" && r.kind != "auto") "・${r.memo}" else "", color = T.ink, fontSize = 14.sp)
                            }
                            Text((if (r.amount > 0) "+" else "") + Money.format(r.amount), color = if (r.amount < 0) T.danger else T.ink, fontWeight = FontWeight.Bold)
                            if (mine && r.kind != "auto") TextButton({
                                scope.launch { try { ctx.repo.deleteSaving(r.id); rowsVm.reload() } catch (ex: AppError) { error = ex.userMessage } }
                            }, Modifier.heightIn(min = 44.dp)) { Text("消す", color = T.danger) }
                        }
                    }
                }
            }
        }
    }
    if (askArchive && goal != null) ConfirmDialog("「${goal.name}」をやめますか", "目標と、その記録が見えなくなります（お金そのものは動きません）。", "やめる", {
        askArchive = false; busy = true
        scope.launch { try { ctx.repo.archiveGoal(goal.id); onDone("目標をやめました") } catch (ex: AppError) { error = ex.userMessage } finally { busy = false } }
    }, { askArchive = false })
}

// ---------- ホームの貯金のカード（いちばん大事な目標だけ。先月の予算の余りを回す提案も） ----------
data class SavingsHome(val goal: SavingsGoal?, val status: SavingsStatus?, val others: Int, val leftover: Long?, val leftoverMonth: String, val leftoverDone: Boolean)

@Composable
fun SavingsCard(ctx: GroupCtx, h: SavingsHome, openSave: () -> Unit, onChanged: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val g = h.goal; val s = h.status
    var busy by remember { mutableStateOf(false) }
    if (g == null || s == null) {
        Paper {
            Text("貯金の目標を作りませんか", color = T.ink, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Sub("目的に名前を付けて、期限と金額を決めると「毎月いくら」が分かります。毎月決まった日に先に分けておく「先取り貯金」もできます。", Modifier.padding(top = 6.dp, bottom = 12.dp))
            OutlinedButton(openSave, Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = ButtonShape) { Text("貯金を始める", color = T.ink, fontWeight = FontWeight.Bold) }
        }
        return
    }
    Paper {
        Row(Modifier.fillMaxWidth()) { Label("貯金・${g.name}"); Spacer(Modifier.weight(1f)); Faint("${Math.round(s.ratio * 100)}%") }
        Row(verticalAlignment = Alignment.Bottom) { Big(s.saved, size = 28); Text(" / ${Money.format(g.target)}", color = T.sub, fontSize = 14.sp, modifier = Modifier.padding(bottom = 4.dp)) }
        Meter(s.ratio.toFloat(), T.accent, null, Modifier.padding(top = 6.dp))
        Sub(Savings.pace(g, s), Modifier.padding(top = 8.dp))
        if (s.thisMonth > 0) Faint("今月 ${Money.format(s.thisMonth)} 貯金しました", Modifier.padding(top = 2.dp))
        if (h.leftover != null && !h.leftoverDone && ctx.can("member")) {
            Column(Modifier.fillMaxWidth().padding(top = 12.dp).clip(PaperShape).background(T.bg).padding(12.dp)) {
                Text("${Savings.yyyymm(h.leftoverMonth + "-01")}の予算が ${Money.format(h.leftover)} 余りました。", color = T.ink, fontSize = 14.sp)
                Button({
                    busy = true
                    scope.launch {
                        try { ctx.repo.recordSaving(g.id, Money.todayJst(), h.leftover, "leftover", h.leftoverMonth, UUID.randomUUID().toString()); onChanged("${Money.format(h.leftover)} を貯金に回しました") }
                        catch (ex: AppError) { ctx.app.toast(ex.userMessage) } finally { busy = false }
                    }
                }, Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 44.dp), shape = ButtonShape, enabled = !busy) { Text("${Money.format(h.leftover)} を「${g.name}」に回す", fontWeight = FontWeight.Bold) }
            }
        }
        OutlinedButton(openSave, Modifier.fillMaxWidth().padding(top = 12.dp).heightIn(min = 48.dp), shape = ButtonShape) { Text("通帳を見る・貯金した", color = T.ink, fontWeight = FontWeight.Bold) }
        if (h.others > 0) Faint("ほかの目標 ${h.others} 件は「貯金」にあります", Modifier.fillMaxWidth().padding(top = 10.dp))
    }
}
