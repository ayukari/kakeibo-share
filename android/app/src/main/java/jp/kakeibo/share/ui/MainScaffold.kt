package jp.kakeibo.share.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.Insights
import jp.kakeibo.share.domain.Money
import java.time.LocalDate
import java.time.YearMonth

// 開いているグループの共通情報（メンバー・カテゴリ・支払い方法）
class GroupCtx(val app: AppVM, val g: Group, val me: Member?, val members: List<Member>, val cats: List<Category>, val pms: List<PaymentMethod>, val rev: Int = 0, val reloadMeta: () -> Unit) {
    val repo get() = app.repo
    fun can(min: String) = roleRank(me?.role) >= roleRank(min)
    fun memberName(id: String?) = members.firstOrNull { it.id == id }?.let { if (it.status == "active") it.displayName else "${it.displayName}（退出）" } ?: "不明"
    fun cat(id: String?) = cats.firstOrNull { it.id == id }
    fun canEdit(t: Txn) = can("admin") || (can("member") && t.createdBy == repo.userId())
    val activeMembers get() = members.filter { it.status == "active" }
}

data class Meta(val cats: List<Category>, val pms: List<PaymentMethod>)

sealed interface Sub {
    data class EditTxn(val txn: Txn?, val kind: String = "expense") : Sub
    data object Budgets : Sub
    data object Categories : Sub
    data object Members : Sub
    data object Recurring : Sub
    data object Audit : Sub
    data object Account : Sub
    data object Export : Sub
    data class Goal(val goal: SavingsGoal?, val presetName: String? = null, val presetTarget: Long? = null) : Sub
}

private enum class Tab(val label: String, val glyph: Glyph) { Home("ホーム", Glyph.Home), Txns("収支", Glyph.List), Save("貯金", Glyph.Save), Settle("精算", Glyph.Swap), Report("レポート", Glyph.Chart), More("その他", Glyph.More) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScaffold(app: AppVM, g: Group) {
    val members by app.members.collectAsState()
    val me by app.me.collectAsState()
    val metaVm: LoadVM<Meta> = viewModel(key = "meta-${g.id}") { LoadVM { Meta(app.repo.categories(g.id), app.repo.paymentMethods(g.id)) } }
    val meta by metaVm.state.collectAsState()
    var tab by rememberSaveableTab()
    var stack by remember(g.id) { mutableStateOf(listOf<Sub>()) }
    val host = remember { SnackbarHostState() }
    var month by remember(g.id) { mutableStateOf(Money.todayJst().withDayOfMonth(1)) }
    var refresh by remember { mutableIntStateOf(0) }   // 保存のあとに一覧を読み直す合図

    val m = meta
    if (m !is Loadable.Ready) { Column(Modifier.fillMaxSize().padding(top = 48.dp)) { LoadableView(m, { metaVm.reload() }) {} }; return }
    val ctx = GroupCtx(app, g, me, members, m.value.cats, m.value.pms, refresh) { metaVm.reload() }
    val push: (Sub) -> Unit = { stack = stack + it }
    val pop: () -> Unit = { stack = stack.dropLast(1) }
    val toast: (String) -> Unit = { msg -> app.toast(msg) }
    LaunchedEffect(Unit) { app.toasts.collect { host.showSnackbar(it) } }

    BackHandler(enabled = stack.isNotEmpty()) { pop() }
    val sub = stack.lastOrNull()
    val barColors = TopAppBarDefaults.topAppBarColors(containerColor = T.bg, titleContentColor = T.ink)
    if (sub != null) {
        Scaffold(containerColor = T.bg, snackbarHost = { SnackbarHost(host) }, topBar = {
            TopAppBar(colors = barColors, title = { Text(subTitle(sub), fontWeight = FontWeight.Bold, fontSize = 16.sp) }, navigationIcon = { TextButton(pop, Modifier.heightIn(min = 48.dp)) { Text("‹ 戻る", color = T.ink) } })
        }) { pad ->
            Box(Modifier.padding(pad).fillMaxSize()) {
                when (sub) {
                    is Sub.EditTxn -> TxnEditScreen(ctx, sub.txn, sub.kind, onSaved = { msg -> toast(msg); refresh++; pop() })
                    Sub.Budgets -> BudgetScreen(ctx, month)
                    Sub.Categories -> CategoryScreen(ctx)
                    Sub.Members -> MemberScreen(ctx)
                    Sub.Recurring -> RecurringScreen(ctx)
                    Sub.Audit -> AuditScreen(ctx)
                    Sub.Account -> AccountScreen(ctx, onLeft = { pop(); app.select(null); app.loadGroups() })
                    Sub.Export -> ExportScreen(ctx)
                    is Sub.Goal -> GoalScreen(ctx, sub.goal, sub.presetName, sub.presetTarget) { msg -> toast(msg); refresh++; pop() }
                }
            }
        }
        return
    }

    Scaffold(
        containerColor = T.bg,
        snackbarHost = { SnackbarHost(host) },
        topBar = {
            TopAppBar(colors = barColors, title = { Column { Text(g.name, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.Bold, fontSize = 16.sp); Text("${me?.displayName ?: ""}・${ROLE_NAMES[me?.role] ?: ""}", color = T.sub, fontSize = 12.sp) } },
                actions = { TextButton({ app.select(null) }, Modifier.heightIn(min = 48.dp)) { Text("切替", color = T.ink) } })
        },
        floatingActionButton = {
            if (ctx.can("member") && (tab == Tab.Home || tab == Tab.Txns))
                ExtendedFloatingActionButton({ push(Sub.EditTxn(null)) }, Modifier.testTag("addTxn"), containerColor = T.accent, contentColor = T.accentInk, shape = ButtonShape) { Text("＋ 記録する", fontWeight = FontWeight.Bold) }
        },
        bottomBar = { BottomBar(tab) { tab = it } },
    ) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            key(refresh) {
                when (tab) {
                    Tab.Home -> DashboardScreen(ctx, month, { month = it }, open = push, goSave = { tab = Tab.Save }, onChanged = { msg -> toast(msg); refresh++ })
                    Tab.Save -> SavingsScreen(ctx, push)
                    Tab.Txns -> TxnListScreen(ctx, month, { month = it }, open = push)
                    Tab.Settle -> SettlementScreen(ctx)
                    Tab.Report -> ReportScreen(ctx, month, { month = it })
                    Tab.More -> MoreScreen(ctx, push)
                }
            }
        }
    }
}

// 下の切り替え。線のアイコンと名前。選んでいる所だけ緑
@Composable
private fun BottomBar(tab: Tab, onSelect: (Tab) -> Unit) {
    val line = T.line
    Row(Modifier.fillMaxWidth().background(T.card).drawTopLine(line).navigationBarsPadding().height(64.dp)) {
        Tab.entries.forEach { t ->
            val on = t == tab
            val c = if (on) T.accent else T.sub
            Column(Modifier.weight(1f).fillMaxHeight().clickable { onSelect(t) }, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                LineIcon(t.glyph, c)
                Text(t.label, color = c, fontSize = 12.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal)
            }
        }
    }
}

private fun Modifier.drawTopLine(c: Color) = this.drawBehind { drawLine(c, Offset(0f, 0f), Offset(size.width, 0f), 1.dp.toPx()) }

@Composable
private fun rememberSaveableTab() = androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(Tab.Home) }

private fun subTitle(s: Sub) = when (s) {
    is Sub.EditTxn -> if (s.txn == null) "記録する" else "取引の編集"
    Sub.Budgets -> "予算"; Sub.Categories -> "カテゴリ"; Sub.Members -> "メンバーと招待"; Sub.Recurring -> "定期的な収支"
    Sub.Audit -> "操作の履歴"; Sub.Account -> "アカウントと設定"; Sub.Export -> "書き出しとバックアップ"
    is Sub.Goal -> if (s.goal == null) "貯金の目標を作る" else "貯金の目標を直す"
}

// ---------- ホーム（かざすレシートの家計簿のホームと同じ並び: 今月の支出 → 予算とペース → カテゴリ → 最近の記録） ----------
data class Dash(val sum: MonthSummary, val budgets: List<BudgetStatus>, val txns: List<Txn>, val prev: List<Txn>, val balances: List<Balance>, val savings: SavingsHome? = null)

@Composable
fun DashboardScreen(ctx: GroupCtx, month: LocalDate, setMonth: (LocalDate) -> Unit, open: (Sub) -> Unit, goSave: () -> Unit = {}, onChanged: (String) -> Unit = {}) {
    val vm: LoadVM<Dash> = viewModel(key = "dash-${ctx.g.id}-r${ctx.rev}-$month") {
        LoadVM {
            Dash(ctx.repo.monthSummary(ctx.g.id, month), ctx.repo.budgetStatus(ctx.g.id, month), ctx.repo.transactions(ctx.g.id, month, month.plusMonths(1)),
                ctx.repo.transactions(ctx.g.id, month.minusMonths(1), month), ctx.repo.balances(ctx.g.id), runCatching { loadSavingsHome(ctx) }.getOrNull())
        }
    }
    val st by vm.state.collectAsState()
    val today = Money.todayJst()
    val isCur = month.year == today.year && month.monthValue == today.monthValue
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 112.dp)) {
        item { MonthBar(month, setMonth) }
        item {
            LoadableView(st, { vm.reload() }) { d -> DashboardContent(ctx, d, month, isCur, open, goSave, onChanged) }
        }
    }
}

// ホームの中身（読み込んだデータから描く。画面のテストからも使う）
// ホームの貯金のカードに要るもの（いちばん大事な目標・先月の予算の余り）
suspend fun loadSavingsHome(ctx: GroupCtx): SavingsHome {
    val today = Money.todayJst()
    val goals = ctx.repo.goals(ctx.g.id)
    val status = ctx.repo.savingsStatus(ctx.g.id)
    val main = goals.firstOrNull { it.isMain && it.visibility == "group" } ?: goals.firstOrNull { g -> status.firstOrNull { it.goalId == g.id }?.done == false } ?: goals.firstOrNull()
    val prev = today.withDayOfMonth(1).minusMonths(1)
    val prevKey = "%04d-%02d".format(prev.year, prev.monthValue)
    val left = if (goals.isEmpty()) null else jp.kakeibo.share.domain.Savings.leftover(ctx.repo.budgetStatus(ctx.g.id, prev))
    val done = left != null && ctx.repo.passbook(ctx.g.id).any { it.kind == "leftover" && it.memo == prevKey }
    return SavingsHome(main, status.firstOrNull { it.goalId == main?.id }, (goals.size - 1).coerceAtLeast(0), left, prevKey, done)
}

@Composable
fun DashboardContent(ctx: GroupCtx, d: Dash, month: LocalDate, isCur: Boolean, open: (Sub) -> Unit, goSave: () -> Unit = {}, onChanged: (String) -> Unit = {}) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Spacer(Modifier.height(0.dp))
                    Paper {
                        Label((if (isCur) "今月" else "${month.monthValue}月") + "の支出")
                        Big(d.sum.expense)
                        Faint("${d.txns.count { it.status == "active" && it.visibility == "group" }}件の記録")
                        if (d.sum.income > 0) {
                            Spacer(Modifier.height(12.dp))
                            KeyValue("収入", Money.format(d.sum.income), first = true)
                            KeyValue("収支", (if (d.sum.balance > 0) "+" else "") + Money.format(d.sum.balance), valueColor = if (d.sum.balance < 0) T.danger else T.ink)
                        }
                    }
                    BudgetPaper(ctx, d, month, isCur, open)
                    if (isCur && d.savings != null) SavingsCard(ctx, d.savings, goSave, onChanged)
                    val mine = d.balances.firstOrNull { it.memberId == ctx.me?.id }
                    if (mine != null && d.balances.size > 1) {
                        Row(Modifier.fillMaxWidth().clip(PaperShape).background(T.bg).padding(12.dp, 12.dp)) {
                            Text(when { mine.net > 0 -> "あなたは ${Money.format(mine.net)} 受け取る側です"; mine.net < 0 -> "あなたは ${Money.format(-mine.net)} 払う側です"; else -> "あなたの精算は済んでいます" }, color = T.ink, fontSize = 14.sp)
                        }
                    }
                    if (d.sum.byCategory.isNotEmpty()) {
                        SectionLabel("カテゴリ")
                        Paper(padding = 12.dp) {
                            val sorted = d.sum.byCategory.sortedByDescending { it.amount }
                            sorted.forEach { a -> CategoryBar(ctx.cat(a.categoryId)?.name ?: "不明", ctx.cat(a.categoryId)?.color, a.amount, sorted.first().amount) }
                        }
                    }
                    SectionLabel("最近の記録")
                    val recent = d.txns.filter { it.status == "active" }.take(5)
                    if (recent.isEmpty()) Paper { EmptyBox("まだ記録がありません", if (ctx.can("member")) "右下の「記録する」から最初の収支を入れてください" else "閲覧のみの権限です") }
                    else ListPaper { recent.forEachIndexed { i, t -> if (i > 0) DashedLine(); TxnRow(ctx, t) { if (ctx.canEdit(t)) open(Sub.EditTxn(t)) } } }
                }
}

// 予算の残り・1 日あたり・ペースの線・カテゴリごとの予算
@Composable
private fun BudgetPaper(ctx: GroupCtx, d: Dash, month: LocalDate, isCur: Boolean, open: (Sub) -> Unit) {
    val ym = YearMonth.of(month.year, month.monthValue)
    val today = Money.todayJst()
    if (d.budgets.isEmpty()) {
        Paper {
            Text("予算を決めてみませんか", color = T.ink, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Sub("決めておくと「今月あといくら・1日あたりいくら」が分かります。", Modifier.padding(top = 6.dp, bottom = 12.dp))
            if (ctx.can("admin")) OutlinedButton({ open(Sub.Budgets) }, Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = ButtonShape) { Text("予算を決める", color = T.ink, fontWeight = FontWeight.Bold) }
            else Faint("予算を決められるのは管理者とオーナーです")
        }
        return
    }
    // カテゴリの予算があればその合計、なければ全体の予算
    val catRows = d.budgets.filter { it.scope == "group" && it.categoryId != null }
    val rows = if (catRows.isNotEmpty()) catRows else d.budgets.filter { it.scope == "group" && it.categoryId == null }
    val total = rows.sumOf { it.amount }; val spent = rows.sumOf { it.spent }; val left = total - spent
    val daysLeft = Insights.daysLeft(ym, today)
    Paper {
        Label("予算の残り")
        if (left < 0) Text("予算を ${Money.format(-left)} こえました", color = T.danger, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, lineHeight = 34.sp)
        else Row(verticalAlignment = Alignment.Bottom) { Text("あと ", color = T.ink, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold); Big(left, size = 28) }
        if (isCur && left >= 0) Sub("1日あたり ${Money.format(Insights.perDay(left, daysLeft))}（のこり $daysLeft 日）", Modifier.padding(top = 2.dp))
        if (left < 0) Sub("来月の予算を見直すのも、ひとつの方法です。", Modifier.padding(top = 2.dp))
        val ideal = Insights.idealLine((total - Insights.fixedTotal(d.txns, ym)).coerceAtLeast(0), ym.lengthOfMonth())
        PaceChart(ym, d, isCur, today, ideal)
        Spacer(Modifier.height(10.dp))
        rows.sortedByDescending { it.ratio }.forEachIndexed { i, b ->
            if (i > 0) DashedLine()
            val pos = if (isCur) (today.dayOfMonth - 0.5f) / ym.lengthOfMonth() else 1f
            val name = ctx.cat(b.categoryId)?.name ?: "全体"
            Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (b.categoryId != null) { CategoryDot(name, ctx.cat(b.categoryId)?.color, 14.dp); Spacer(Modifier.width(8.dp)) }
                    Text(name, Modifier.weight(1f), color = T.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text("${Money.format(b.spent)} / ${Money.format(b.amount)}", color = T.sub, fontSize = 14.sp)
                }
                Meter(b.ratio.toFloat(), if (b.over) T.danger else T.accent, pos, Modifier.padding(top = 6.dp))
                Faint(if (b.remaining >= 0) "あと ${Money.format(b.remaining)}" else "${Money.format(-b.remaining)} こえています", Modifier.padding(top = 4.dp))
            }
        }
    }
}

// ペースの線: 今月の累計（緑）・先月の累計（薄い灰）・予算の目安（細い線）
@Composable
private fun PaceChart(ym: YearMonth, d: Dash, isCur: Boolean, today: LocalDate, ideal: LongArray?) {
    val actualAll = Insights.variableCumulative(d.txns, ym)
    val len = actualAll.size
    val upto = if (isCur) today.dayOfMonth else len
    val actual = actualAll.take(upto)
    val prevAll = Insights.variableCumulative(d.prev, ym.minusMonths(1)).let { p -> LongArray(len) { i -> if (i < p.size) p[i] else p.lastOrNull() ?: 0 } }
    val hasPrev = prevAll.any { it > 0 }
    val max = maxOf(1L, actual.maxOrNull() ?: 0, prevAll.maxOrNull() ?: 0, ideal?.maxOrNull() ?: 0)
    val acc = T.accent; val faint = T.faint; val sub = T.sub; val line = T.line; val card = T.card
    Canvas(Modifier.fillMaxWidth().padding(top = 10.dp).height(140.dp)) {
        val l = 6.dp.toPx(); val r = 6.dp.toPx(); val top = 10.dp.toPx(); val bot = 4.dp.toPx()
        fun x(i: Int) = l + (size.width - l - r) * (i.toFloat() / maxOf(1, len - 1))
        fun y(v: Long) = top + (size.height - top - bot) * (1f - v.toFloat() / max)
        fun path(vs: List<Long>): Path = Path().apply { vs.forEachIndexed { i, v -> if (i == 0) moveTo(x(i), y(v)) else lineTo(x(i), y(v)) } }
        drawLine(line, Offset(l, y(0)), Offset(size.width - r, y(0)), 1.dp.toPx())
        if (ideal != null) drawPath(path(ideal.toList()), sub.copy(alpha = 0.5f), style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        if (hasPrev) drawPath(path(prevAll.toList()), faint.copy(alpha = 0.7f), style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        if (actual.isNotEmpty()) {
            drawPath(path(actual), acc, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
            val lx = x(actual.size - 1); val ly = y(actual.last())
            drawCircle(card, 6.5.dp.toPx(), Offset(lx, ly)); drawCircle(acc, 4.5.dp.toPx(), Offset(lx, ly))
        }
    }
    Row(Modifier.fillMaxWidth()) {
        Faint("${ym.monthValue}/1"); Spacer(Modifier.weight(1f)); Faint("最大 ${Money.format(max)}"); Spacer(Modifier.weight(1f)); Faint("${ym.monthValue}/$len")
    }
    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        LegendItem(T.accent, if (isCur) "今月" else "この月")
        if (hasPrev) LegendItem(T.faint, "前の月")
        if (ideal != null) LegendItem(T.sub, "予算の目安")
    }
}

@Composable
private fun LegendItem(c: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(14.dp, 2.dp).clip(CircleShape).background(c)); Text(text, color = T.sub, fontSize = 12.sp)
    }
}

@Composable
fun TxnRow(ctx: GroupCtx, t: Txn, onClick: () -> Unit) {
    val c = ctx.cat(t.categoryId)
    val sub = "${t.occurredOn.substring(5).replace('-', '/')}・${ctx.memberName(t.payerMemberId)}が払った" + (if (t.splitMode != "none") "・割り勘" else "") + (if (t.visibility == "private") "・自分だけ" else "")
    ItemRow((c?.name ?: "不明") + (if (t.memo.isNotBlank()) "・${t.memo}" else ""), sub, (if (t.kind == "income") "+" else "") + Money.format(t.amount), c?.name, c?.color, onClick = onClick)
}

// ---------- その他 ----------
@Composable
fun MoreScreen(ctx: GroupCtx, open: (Sub) -> Unit) {
    val items = buildList {
        add("予算" to Sub.Budgets); add("カテゴリ" to Sub.Categories); add("メンバーと招待" to Sub.Members); add("定期的な収支" to Sub.Recurring)
        add("CSV の書き出し・バックアップ" to Sub.Export); if (ctx.can("admin")) add("操作の履歴" to Sub.Audit); add("アカウントと設定" to Sub.Account)
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 12.dp, 16.dp, 24.dp)) {
        item {
            ListPaper {
                items.forEachIndexed { i, (label, s) ->
                    if (i > 0) DashedLine()
                    Row(Modifier.fillMaxWidth().clickable { open(s) }.heightIn(min = 56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(label, Modifier.weight(1f), color = T.ink, fontWeight = FontWeight.Bold, fontSize = 16.sp); Chevron(left = false, color = T.faint)
                    }
                }
            }
        }
    }
}
