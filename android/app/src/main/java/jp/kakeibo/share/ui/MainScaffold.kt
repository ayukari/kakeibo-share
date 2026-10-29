package jp.kakeibo.share.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.Money
import java.time.LocalDate

// 開いているグループの共通情報（メンバー・カテゴリ・支払い方法）
class GroupCtx(val app: AppVM, val g: Group, val me: Member?, val members: List<Member>, val cats: List<Category>, val pms: List<PaymentMethod>, val reloadMeta: () -> Unit) {
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
}

private enum class Tab(val label: String, val icon: String) { Home("ホーム", "⌂"), Txns("収支", "≡"), Settle("精算", "⇄"), Report("レポート", "▥"), More("その他", "…") }

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
    val ctx = GroupCtx(app, g, me, members, m.value.cats, m.value.pms) { metaVm.reload() }
    val push: (Sub) -> Unit = { stack = stack + it }
    val pop: () -> Unit = { stack = stack.dropLast(1) }
    val toast: (String) -> Unit = { msg -> app.toast(msg) }
    LaunchedEffect(Unit) { app.toasts.collect { host.showSnackbar(it) } }

    BackHandler(enabled = stack.isNotEmpty()) { pop() }
    val sub = stack.lastOrNull()
    if (sub != null) {
        Scaffold(snackbarHost = { SnackbarHost(host) }, topBar = {
            TopAppBar(title = { Text(subTitle(sub)) }, navigationIcon = { TextButton(pop, Modifier.heightIn(min = 48.dp)) { Text("‹ 戻る") } })
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
                }
            }
        }
        return
    }

    Scaffold(
        snackbarHost = { SnackbarHost(host) },
        topBar = {
            TopAppBar(title = { Column { Text(g.name, maxLines = 1, overflow = TextOverflow.Ellipsis); Text("${me?.displayName ?: ""}・${ROLE_NAMES[me?.role] ?: ""}", style = MaterialTheme.typography.bodySmall) } },
                actions = { TextButton({ app.select(null) }, Modifier.heightIn(min = 48.dp)) { Text("切替") } })
        },
        floatingActionButton = {
            if (ctx.can("member") && (tab == Tab.Home || tab == Tab.Txns))
                ExtendedFloatingActionButton({ push(Sub.EditTxn(null)) }, Modifier.testTag("addTxn")) { Text("＋ 記録する") }
        },
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { t ->
                    NavigationBarItem(selected = tab == t, onClick = { tab = t }, icon = { Text(t.icon, fontSize = 18.sp) }, label = { Text(t.label) })
                }
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            key(refresh) {
                when (tab) {
                    Tab.Home -> DashboardScreen(ctx, month, { month = it }, open = push)
                    Tab.Txns -> TxnListScreen(ctx, month, { month = it }, open = push)
                    Tab.Settle -> SettlementScreen(ctx)
                    Tab.Report -> ReportScreen(ctx, month, { month = it })
                    Tab.More -> MoreScreen(ctx, push)
                }
            }
        }
    }
}

@Composable
private fun rememberSaveableTab() = androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(Tab.Home) }

private fun subTitle(s: Sub) = when (s) {
    is Sub.EditTxn -> if (s.txn == null) "記録する" else "取引の編集"
    Sub.Budgets -> "予算"; Sub.Categories -> "カテゴリ"; Sub.Members -> "メンバーと招待"; Sub.Recurring -> "定期的な収支"
    Sub.Audit -> "操作の履歴"; Sub.Account -> "アカウントと設定"; Sub.Export -> "書き出しとバックアップ"
}

// ---------- ホーム ----------
data class Dash(val sum: MonthSummary, val budgets: List<BudgetStatus>, val recent: List<Txn>, val balances: List<Balance>)

@Composable
fun DashboardScreen(ctx: GroupCtx, month: LocalDate, setMonth: (LocalDate) -> Unit, open: (Sub) -> Unit) {
    val vm: LoadVM<Dash> = viewModel(key = "dash-${ctx.g.id}-$month") {
        LoadVM { Dash(ctx.repo.monthSummary(ctx.g.id, month), ctx.repo.budgetStatus(ctx.g.id, month), ctx.repo.recentTransactions(ctx.g.id, 5), ctx.repo.balances(ctx.g.id)) }
    }
    val st by vm.state.collectAsState()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp)) {
        item { MonthBar(month, setMonth) }
        item {
            LoadableView(st, { vm.reload() }) { d ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp)) {
                            Text("今月の収支", style = MaterialTheme.typography.labelLarge)
                            MoneyText(d.sum.balance, big = true, signed = true, color = if (d.sum.balance < 0) OverColor else Color0)
                            Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                                Column(Modifier.weight(1f)) { Text("収入", style = MaterialTheme.typography.bodySmall); MoneyText(d.sum.income, color = IncomeColor) }
                                Column(Modifier.weight(1f)) { Text("支出", style = MaterialTheme.typography.bodySmall); MoneyText(d.sum.expense) }
                            }
                            if (d.sum.prevExpense > 0) {
                                val diff = d.sum.expense - d.sum.prevExpense
                                Text("先月の支出より ${Money.format(kotlin.math.abs(diff))} ${if (diff >= 0) "多い" else "少ない"}", Modifier.padding(top = 6.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    if (d.budgets.isNotEmpty()) {
                        SectionTitle("予算")
                        d.budgets.forEach { b -> BudgetRow(ctx, b) }
                    }
                    val mine = d.balances.firstOrNull { it.memberId == ctx.me?.id }
                    if (mine != null && d.balances.size > 1) {
                        SectionTitle("精算")
                        Text(when { mine.net > 0 -> "あなたは ${Money.format(mine.net)} 受け取る側です"; mine.net < 0 -> "あなたは ${Money.format(-mine.net)} 払う側です"; else -> "あなたの精算は済んでいます" })
                    }
                    SectionTitle("最近の記録")
                    if (d.recent.isEmpty()) EmptyBox("まだ記録がありません", if (ctx.can("member")) "右下の「記録する」から最初の収支を入れてください" else "閲覧のみの権限です")
                    d.recent.forEach { t -> TxnRow(ctx, t) { if (ctx.canEdit(t)) open(Sub.EditTxn(t)) } }
                }
            }
        }
    }
}

private val Color0 = androidx.compose.ui.graphics.Color.Unspecified

@Composable
fun BudgetRow(ctx: GroupCtx, b: BudgetStatus) {
    val name = (if (b.scope == "personal") ctx.memberName(b.memberId) + "の負担・" else "") + (ctx.cat(b.categoryId)?.name ?: "全体")
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Row { Text(name, Modifier.weight(1f)); Text("${Money.format(b.spent)} / ${Money.format(b.amount)}", style = MaterialTheme.typography.bodySmall) }
        LinearProgressIndicator({ b.ratio.toFloat().coerceIn(0f, 1f) }, Modifier.fillMaxWidth().padding(top = 4.dp).height(8.dp),
            color = if (b.over) OverColor else if (b.ratio >= 0.8) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.primary)
        if (b.over) Text("予算を ${Money.format(-b.remaining)} こえています", color = OverColor, style = MaterialTheme.typography.bodySmall)
        else if (b.ratio >= 0.8) Text("残り ${Money.format(b.remaining)}（8 割をこえました）", style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun TxnRow(ctx: GroupCtx, t: Txn, onClick: () -> Unit) {
    val c = ctx.cat(t.categoryId)
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).heightIn(min = 56.dp).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(c?.icon ?: "・", Modifier.width(36.dp), fontSize = 20.sp)
        Column(Modifier.weight(1f)) {
            Text((c?.name ?: "不明") + (if (t.memo.isNotBlank()) "・${t.memo}" else ""), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${t.occurredOn.substring(5).replace('-', '/')}・${ctx.memberName(t.payerMemberId)}が払った" + (if (t.splitMode != "none") "・割り勘" else "") + (if (t.visibility == "private") "・自分だけ" else ""),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        MoneyText(if (t.kind == "income") t.amount else -t.amount, signed = true, color = if (t.kind == "income") IncomeColor else Color0)
    }
    HorizontalDivider()
}

// ---------- その他 ----------
@Composable
fun MoreScreen(ctx: GroupCtx, open: (Sub) -> Unit) {
    val items = buildList {
        add("予算" to Sub.Budgets); add("カテゴリ" to Sub.Categories); add("メンバーと招待" to Sub.Members); add("定期的な収支" to Sub.Recurring)
        add("CSV の書き出し・バックアップ" to Sub.Export); if (ctx.can("admin")) add("操作の履歴" to Sub.Audit); add("アカウントと設定" to Sub.Account)
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
        items(items) { (label, s) ->
            ListItem(headlineContent = { Text(label) }, trailingContent = { Text("›") }, modifier = Modifier.clickable { open(s) }.heightIn(min = 56.dp))
            HorizontalDivider()
        }
    }
}
