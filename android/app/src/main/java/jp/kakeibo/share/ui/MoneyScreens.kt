package jp.kakeibo.share.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.viewmodel.compose.viewModel
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Validate
import java.time.LocalDate
import java.util.UUID

// ---------- 精算（立て替えの差額。提案・記録・相手の確認・履歴） ----------
data class SettleData(val balances: List<Balance>, val suggestions: List<Suggestion>, val history: List<Settlement>)

@Composable
fun SettlementScreen(ctx: GroupCtx) {
    val vm: LoadVM<SettleData> = viewModel(key = "settle-${ctx.g.id}-r${ctx.rev}") {
        LoadVM { SettleData(ctx.repo.balances(ctx.g.id), ctx.repo.suggestions(ctx.g.id), ctx.repo.settlements(ctx.g.id)) }
    }
    val st by vm.state.collectAsState()
    val busy by vm.busy.collectAsState()
    val host = remember { SnackbarHostState() }
    MessageEffect(vm, host)
    var record by remember { mutableStateOf<Suggestion?>(null) }
    var cancel by remember { mutableStateOf<Settlement?>(null) }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
            item {
                LoadableView(st, { vm.reload() }) { d ->
                    Column {
                        Sub("割り勘にした支出だけで計算します。プラスは受け取る側、マイナスは払う側です。")
                        SectionLabel("いまの差額")
                        ListPaper {
                            d.balances.forEachIndexed { i, b ->
                                if (i > 0) DashedLine()
                                val m = ctx.members.firstOrNull { it.id == b.memberId }
                                ItemRow(b.displayName + if (b.status != "active") "（退出）" else "", "立て替え ${Money.format(b.paid)}・負担 ${Money.format(b.burden)}",
                                    (if (b.net > 0) "+" else "") + Money.format(b.net), b.displayName, "#6b7280", amountColor = if (b.net < 0) T.danger else T.ink)
                            }
                        }
                        SectionLabel("精算の提案")
                        if (d.suggestions.isEmpty()) Paper { Sub("いま精算が必要な人はいません（確認待ちの精算は差し引いています）") }
                        else ListPaper {
                            d.suggestions.forEachIndexed { i, sg ->
                                if (i > 0) DashedLine()
                                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text("${ctx.memberName(sg.fromMember)} → ${ctx.memberName(sg.toMember)}", Modifier.weight(1f), color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                    Text(Money.format(sg.amount), color = T.ink, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp)
                                    if (ctx.can("member")) TextButton({ record = sg }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text("払った", color = T.accent, fontWeight = FontWeight.Bold) }
                                }
                            }
                        }
                        val pending = d.history.filter { it.status == "pending" }
                        if (pending.isNotEmpty()) {
                            SectionLabel("確認待ち")
                            ListPaper {
                                pending.forEachIndexed { i, p ->
                                    if (i > 0) DashedLine()
                                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                                        Text("${ctx.memberName(p.fromMember)} → ${ctx.memberName(p.toMember)}  ${Money.format(p.amount)}", color = T.ink, fontWeight = FontWeight.Bold)
                                        Row {
                                            // 受け取った人（か管理者）が確認すると差額に入る
                                            if (p.toMember == ctx.me?.id || ctx.can("admin")) TextButton({ vm.act("受け取りを確認しました") { ctx.repo.confirmSettlement(p.id) } }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text("受け取りを確認", color = T.accent, fontWeight = FontWeight.Bold) }
                                            if (p.fromMember == ctx.me?.id || p.toMember == ctx.me?.id || ctx.can("admin")) TextButton({ cancel = p }, Modifier.heightIn(min = 48.dp), enabled = !busy) { Text("取り消す", color = T.danger) }
                                        }
                                    }
                                }
                            }
                        }
                        SectionLabel("精算の履歴")
                        val done = d.history.filter { it.status != "pending" }
                        if (done.isEmpty()) Paper { Sub("まだありません") }
                        else ListPaper {
                            done.forEachIndexed { i, h ->
                                if (i > 0) DashedLine()
                                Text("${(h.confirmedAt ?: h.createdAt ?: "").take(10)}  ${ctx.memberName(h.fromMember)} → ${ctx.memberName(h.toMember)}  ${Money.format(h.amount)}" + if (h.status == "cancelled") "（取り消し）" else "",
                                    Modifier.padding(horizontal = 16.dp, vertical = 12.dp), color = T.ink, fontSize = 14.sp)
                            }
                        }
                    }
                }
            }
        }
        SnackbarHost(host, Modifier.align(Alignment.BottomCenter))
    }

    record?.let { s ->
        var amt by remember(s) { mutableStateOf(s.amount.toString()) }
        var note by remember(s) { mutableStateOf("") }
        val reqId = remember(s) { UUID.randomUUID().toString() }
        val err = Validate.amount(amt) ?: if ((Money.parse(amt) ?: 0) > s.amount) "提案の金額（${Money.format(s.amount)}）をこえています" else null
        AlertDialog({ record = null }, title = { Text("精算を記録") }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${ctx.memberName(s.fromMember)} が ${ctx.memberName(s.toMember)} に払った金額を記録します。受け取った人が確認すると差額に入ります。")
                AmountField(amt, { amt = it }, error = err)
                OutlinedTextField(note, { note = it.take(200) }, Modifier.fillMaxWidth(), label = { Text("メモ（例: 現金で）") })
            }
        }, confirmButton = { TextButton({ record = null; vm.act("記録しました。相手の確認待ちです") { ctx.repo.recordSettlement(ctx.g.id, s.fromMember, s.toMember, Money.parse(amt)!!, note, reqId) } }, enabled = err == null) { Text("記録する") } },
            dismissButton = { TextButton({ record = null }) { Text("やめる") } })
    }
    cancel?.let { s -> ConfirmDialog("精算を取り消しますか", "${Money.format(s.amount)} の精算を取り消します。", "取り消す", { cancel = null; vm.act("取り消しました") { ctx.repo.cancelSettlement(s.id) } }, { cancel = null }) }
}

// ---------- レポート（月ごとの推移・カテゴリ別・払った人別） ----------
data class ReportData(val series: List<MonthPoint>, val sum: MonthSummary)

@Composable
fun ReportScreen(ctx: GroupCtx, month: LocalDate, setMonth: (LocalDate) -> Unit) {
    val vm: LoadVM<ReportData> = viewModel(key = "report-${ctx.g.id}-r${ctx.rev}-$month") { LoadVM { ReportData(ctx.repo.monthlySeries(ctx.g.id, month, 6), ctx.repo.monthSummary(ctx.g.id, month)) } }
    val st by vm.state.collectAsState()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
        item { MonthBar(month, setMonth) }
        item {
            LoadableView(st, { vm.reload() }) { d ->
                Column {
                    SectionLabel("支出の推移（6 か月）")
                    Paper {
                        ExpenseBars(d.series)
                        Spacer(Modifier.height(8.dp))
                        d.series.forEachIndexed { i, p ->
                            DashedLine()
                            Row(Modifier.fillMaxWidth().padding(vertical = 6.dp)) { Faint(p.month.take(7).replace('-', '/'), Modifier.weight(1f)); Text("収入 ${Money.format(p.income)}・支出 ${Money.format(p.expense)}", color = T.sub, fontSize = 12.sp) }
                        }
                    }
                    SectionLabel("カテゴリ別の支出")
                    if (d.sum.byCategory.isEmpty()) Paper { Sub("この月の支出はありません") }
                    else Paper(padding = 12.dp) {
                        val sorted = d.sum.byCategory.sortedByDescending { it.amount }
                        Donut(sorted.map { Slice(ctx.cat(it.categoryId)?.name ?: "不明", ctx.cat(it.categoryId)?.color, it.amount) }, "支出", d.sum.expense)
                        sorted.forEach { a -> CategoryBar(ctx.cat(a.categoryId)?.name ?: "不明", ctx.cat(a.categoryId)?.color, a.amount, sorted.first().amount) }
                    }
                    if (d.sum.byPayer.isNotEmpty()) {
                        SectionLabel("払った人別")
                        Paper(padding = 12.dp) { val sorted = d.sum.byPayer.sortedByDescending { it.amount }; sorted.forEach { a -> CategoryBar(ctx.memberName(a.memberId), "#6b7f99", a.amount, sorted.first().amount) } }
                    }
                    if (d.sum.byBurden.isNotEmpty()) {
                        SectionLabel("負担した人別（割り勘のあと）")
                        Paper(padding = 12.dp) { val sorted = d.sum.byBurden.sortedByDescending { it.amount }; sorted.forEach { a -> CategoryBar(ctx.memberName(a.memberId), "#6b7f99", a.amount, sorted.first().amount) } }
                    }
                }
            }
        }
    }
}

// 1 系列の棒グラフ（色は 1 色、数字は下の表にも出す）
@Composable
private fun ExpenseBars(series: List<MonthPoint>) {
    val max = (series.maxOfOrNull { it.expense } ?: 0).coerceAtLeast(1)
    val color = T.accent
    val grid = T.line
    Canvas(Modifier.fillMaxWidth().height(160.dp).semantics { contentDescription = "支出の推移の棒グラフ。数字は下の表にあります" }) {
        val n = series.size.coerceAtLeast(1); val slot = size.width / n; val w = (slot * 0.5f).coerceAtMost(48.dp.toPx())
        drawLine(grid, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
        series.forEachIndexed { i, p ->
            val h = size.height * p.expense / max
            if (h > 0) drawRoundRect(color, Offset(slot * i + (slot - w) / 2, size.height - h), Size(w, h), CornerRadius(2.dp.toPx()))
        }
    }
}

// 予算の 1 行（名前・使った額 / 予算・進み具合の棒・あと / こえた額）
@Composable
fun BudgetRow(ctx: GroupCtx, b: BudgetStatus) {
    val name = (if (b.scope == "personal") ctx.memberName(b.memberId) + "の負担・" else "") + (ctx.cat(b.categoryId)?.name ?: "全体")
    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (b.categoryId != null) { CategoryDot(ctx.cat(b.categoryId)?.name, ctx.cat(b.categoryId)?.color, 14.dp); Spacer(Modifier.width(8.dp)) }
            Text(name, Modifier.weight(1f), color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            Text("${Money.format(b.spent)} / ${Money.format(b.amount)}", color = T.sub, fontSize = 14.sp)
        }
        Meter(b.ratio.toFloat(), if (b.over) T.danger else T.accent, null, Modifier.padding(top = 6.dp))
        Faint(if (b.remaining >= 0) "あと ${Money.format(b.remaining)}" else "${Money.format(-b.remaining)} こえています", Modifier.padding(top = 4.dp))
    }
}

// ---------- 予算 ----------
@Composable
fun BudgetScreen(ctx: GroupCtx, month: LocalDate) {
    data class B(val status: List<BudgetStatus>, val all: List<Budget>)
    val vm: LoadVM<B> = viewModel(key = "budget-${ctx.g.id}-r${ctx.rev}-$month") { LoadVM { B(ctx.repo.budgetStatus(ctx.g.id, month), ctx.repo.budgets(ctx.g.id)) } }
    val st by vm.state.collectAsState()
    val busy by vm.busy.collectAsState()
    val host = remember { SnackbarHostState() }
    MessageEffect(vm, host)
    var scope by remember { mutableStateOf("group") }
    var cat by remember { mutableStateOf<Category?>(null) }
    var member by remember { mutableStateOf(ctx.me) }
    var amount by remember { mutableStateOf("") }
    var del by remember { mutableStateOf<BudgetStatus?>(null) }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
            item {
                SectionLabel("${month.year}年${month.monthValue}月の予算")
                LoadableView(st, { vm.reload() }, isEmpty = { it.status.isEmpty() }, empty = { EmptyBox("予算はまだありません", "カテゴリごと・全体の月の上限を決められます") }) { d ->
                    Paper { d.status.forEachIndexed { i, b -> if (i > 0) DashedLine(); BudgetRow(ctx, b); if (ctx.can("admin")) TextButton({ del = b }) { Text("この予算をやめる", color = T.danger) } } }
                }
            }
            if (ctx.can("admin")) item {
                SectionTitle("予算を決める（この月から、次に変えるまで続く）")
                Segmented(listOf("グループ全体の支出", "1 人の負担"), if (scope == "group") 0 else 1, { scope = if (it == 0) "group" else "personal" })
                Spacer(Modifier.height(8.dp))
                Picker("カテゴリ", listOf<Category?>(null) + ctx.cats.filter { it.kind == "expense" && it.archivedAt == null }, cat, { it?.name ?: "全体（すべての支出）" }, { cat = it })
                if (scope == "personal") Picker("人", ctx.activeMembers, member, { it.displayName }, { member = it })
                AmountField(amount, { amount = it }, label = "月の上限（円）")
                val err = Validate.amount(amount)
                Button({ vm.act("予算を保存しました", onDone = { if (it) amount = "" }) { ctx.repo.saveBudget(ctx.g.id, scope, cat?.id, if (scope == "personal") member?.id else null, month, Money.parse(amount)!!) } },
                    Modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = err == null && !busy && (scope == "group" || member != null)) { Text("保存する") }
            }
        }
        SnackbarHost(host, Modifier.align(Alignment.BottomCenter))
    }
    del?.let { b -> ConfirmDialog("予算をやめますか", "この予算を消します（これまでの月の記録には影響しません）。", "やめる", { del = null; vm.act("予算をやめました") { ctx.repo.deleteBudget(b.budgetId) } }, { del = null }) }
}
