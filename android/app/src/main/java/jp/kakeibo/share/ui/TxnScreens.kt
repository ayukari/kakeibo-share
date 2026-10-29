package jp.kakeibo.share.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import jp.kakeibo.share.domain.Insights
import java.time.YearMonth
import androidx.lifecycle.viewmodel.compose.viewModel
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Validate
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.UUID

// ---------- 収支の一覧（リストとカレンダー。月・種類・カテゴリ・払った人・メモの検索・並べ替え） ----------
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TxnListScreen(ctx: GroupCtx, month: LocalDate, setMonth: (LocalDate) -> Unit, open: (Sub) -> Unit) {
    val vm: LoadVM<List<Txn>> = viewModel(key = "txns-${ctx.g.id}-r${ctx.rev}-$month") { LoadVM { ctx.repo.transactions(ctx.g.id, month, month.plusMonths(1)) } }
    val st by vm.state.collectAsState()
    var mode by remember { mutableIntStateOf(0) }   // 0 = リスト、1 = カレンダー
    var kind by remember { mutableStateOf("all") }
    var cat by remember { mutableStateOf<Category?>(null) }
    var payer by remember { mutableStateOf<Member?>(null) }
    var q by remember { mutableStateOf("") }
    var sort by remember { mutableStateOf("new") }
    var selDay by remember(month) { mutableStateOf<Int?>(null) }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 112.dp)) {
        item { MonthBar(month, setMonth) }
        item { Segmented(listOf("リスト", "カレンダー"), mode, { mode = it }, Modifier.padding(vertical = 8.dp)) }
        if (mode == 1) {
            item {
                LoadableView(st, { vm.reload() }) { all ->
                    CalendarSection(ctx, month, all, selDay, { selDay = it }, open)
                }
            }
        } else {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(q, { q = it }, Modifier.fillMaxWidth().testTag("search"), label = { Text("メモ・カテゴリで探す") }, singleLine = true)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("all" to "すべて", "expense" to "支出", "income" to "収入").forEach { (k, l) -> FilterChip(kind == k, { kind = k }, { Text(l) }) }
                        Spacer(Modifier.weight(1f))
                        FilterChip(sort != "new", { sort = when (sort) { "new" -> "old"; "old" -> "amount"; else -> "new" } }, { Text(when (sort) { "new" -> "新しい順"; "old" -> "古い順"; else -> "金額順" }) })
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Picker("カテゴリ", listOf<Category?>(null) + ctx.cats.filter { kind == "all" || it.kind == kind }, cat, { it?.name ?: "すべて" }, { cat = it }, Modifier.weight(1f))
                        Picker("払った人", listOf<Member?>(null) + ctx.members, payer, { it?.displayName ?: "全員" }, { payer = it }, Modifier.weight(1f))
                    }
                }
            }
            item {
                LoadableView(st, { vm.reload() }) { all ->
                    val list = all.filter { t ->
                        (kind == "all" || t.kind == kind) && (cat == null || t.categoryId == cat!!.id) && (payer == null || t.payerMemberId == payer!!.id) &&
                            (q.isBlank() || t.memo.contains(q.trim(), true) || (ctx.cat(t.categoryId)?.name?.contains(q.trim(), true) == true))
                    }.let { l -> when (sort) { "old" -> l.reversed(); "amount" -> l.sortedByDescending { it.amount }; else -> l } }
                    val inc = list.filter { it.kind == "income" }.sumOf { it.amount }; val exp = list.filter { it.kind == "expense" }.sumOf { it.amount }
                    SectionLabel("${list.size} 件", "収入 ${Money.format(inc)}・支出 ${Money.format(exp)}")
                    if (list.isEmpty()) Paper { EmptyBox(if (all.isEmpty()) "この月の記録はありません" else "条件に合う記録はありません", if (all.isEmpty()) "月を変えるか、記録を追加してください" else "絞り込みを変えてみてください") }
                    else ListPaper { list.forEachIndexed { i, t -> if (i > 0) DashedLine(); TxnRow(ctx, t) { if (ctx.canEdit(t)) open(Sub.EditTxn(t)) else ctx.app.toast("この記録を直す権限がありません") } } }
                }
            }
        }
    }
}

// カレンダー（支出が多い日ほど濃い緑。1 色の濃淡だけ）。日を押すと、その日の記録
@Composable
fun CalendarSection(ctx: GroupCtx, month: LocalDate, all: List<Txn>, selDay: Int?, onSel: (Int?) -> Unit, open: (Sub) -> Unit) {
    val ym = YearMonth.of(month.year, month.monthValue)
    val days = Insights.dailyExpense(all, ym)
    val max = days.maxOrNull() ?: 0
    val today = Money.todayJst()
    val firstDow = ym.atDay(1).dayOfWeek.value - 1   // 月曜 = 0
    val inc = all.filter { it.kind == "income" && it.status == "active" && it.visibility == "group" }.sumOf { it.amount }
    val exp = days.sum()
    val sel = selDay ?: if (today.year == ym.year && today.monthValue == ym.monthValue) today.dayOfMonth else null
    val shades = listOf(T.bg, lerp(T.card, T.accent, 0.18f), lerp(T.card, T.accent, 0.38f), lerp(T.card, T.accent, 0.62f), T.accent)
    Paper(padding = 12.dp) {
        Row(Modifier.fillMaxWidth()) { "月火水木金土日".forEach { Text(it.toString(), Modifier.weight(1f), color = T.faint, fontSize = 12.sp, textAlign = TextAlign.Center) } }
        Spacer(Modifier.height(4.dp))
        val rows = (firstDow + days.size + 6) / 7
        for (r in 0 until rows) {
            Row(Modifier.fillMaxWidth().padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (c in 0 until 7) {
                    val idx = r * 7 + c - firstDow
                    if (idx !in days.indices) { Spacer(Modifier.weight(1f)); continue }
                    val day = idx + 1; val v = days[idx]; val step = Insights.step(v, max)
                    val fg = if (step >= 3) T.accentInk else T.ink
                    val isToday = today.year == ym.year && today.monthValue == ym.monthValue && today.dayOfMonth == day
                    val ring = if (day == sel) Modifier.border(2.dp, T.ink, RoundedCornerShape(4.dp)) else if (isToday) Modifier.border(2.dp, T.accent, RoundedCornerShape(4.dp)) else Modifier
                    Column(Modifier.weight(1f).aspectRatio(1f / 1.05f).clip(RoundedCornerShape(4.dp)).background(shades[step]).then(ring)
                        .clickable { onSel(day) }.padding(vertical = 3.dp).semantics { contentDescription = "${ym.monthValue}月${day}日 ${Money.format(v)}" },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.SpaceBetween) {
                        Text("$day", color = fg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        Text(if (v > 0) Insights.short(v) else "", color = fg.copy(alpha = 0.85f), fontSize = 9.sp, maxLines = 1)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            Faint("少ない ")
            shades.forEach { Box(Modifier.padding(horizontal = 2.dp).size(14.dp).clip(RoundedCornerShape(2.dp)).background(it)) }
            Faint(" 多い")
        }
        Spacer(Modifier.height(8.dp))
        DashedLine()
        Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
            Column(Modifier.weight(1f)) { Faint("収入"); Text(Money.format(inc), color = T.ink, fontWeight = FontWeight.Bold) }
            Column(Modifier.weight(1f)) { Faint("支出"); Text(Money.format(exp), color = T.ink, fontWeight = FontWeight.Bold) }
            Column(Modifier.weight(1f)) { Faint("収支"); Text((if (inc - exp > 0) "+" else "") + Money.format(inc - exp), color = if (inc - exp < 0) T.danger else T.ink, fontWeight = FontWeight.Bold) }
        }
    }
    if (sel != null) {
        val key = "%04d-%02d-%02d".format(ym.year, ym.monthValue, sel)
        val ls = all.filter { it.status == "active" && it.occurredOn == key }
        SectionLabel("${ym.monthValue}/$sel", if (ls.isNotEmpty()) Money.format(ls.filter { it.kind == "expense" }.sumOf { it.amount }) else null)
        if (ls.isEmpty()) Paper { Sub("この日の記録はありません") }
        else ListPaper { ls.forEachIndexed { i, t -> if (i > 0) DashedLine(); TxnRow(ctx, t) { if (ctx.canEdit(t)) open(Sub.EditTxn(t)) } } }
    }
}

// ---------- 取引の入力・編集 ----------
@Composable
fun TxnEditScreen(ctx: GroupCtx, txn: Txn?, initialKind: String, onSaved: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val requestId = remember { txn?.let { "" } ?: UUID.randomUUID().toString() }   // 同じ入力の再送を二重登録にしない
    var kind by remember { mutableStateOf(txn?.kind ?: initialKind) }
    var amount by remember { mutableStateOf(txn?.amount?.toString() ?: "") }
    var date by remember { mutableStateOf(txn?.let { LocalDate.parse(it.occurredOn) } ?: Money.todayJst()) }
    var cat by remember { mutableStateOf(ctx.cat(txn?.categoryId)) }
    var payer by remember { mutableStateOf(ctx.members.firstOrNull { it.id == (txn?.payerMemberId ?: ctx.me?.id) }) }
    var pm by remember { mutableStateOf(ctx.pms.firstOrNull { it.id == txn?.paymentMethodId }) }
    var memo by remember { mutableStateOf(txn?.memo ?: "") }
    var private by remember { mutableStateOf(txn?.visibility == "private") }
    var split by remember { mutableStateOf(txn?.splitMode ?: "none") }
    val equal = remember { mutableStateListOf<String>() }
    val custom = remember { mutableStateMapOf<String, String>() }
    var loadedSplits by remember { mutableStateOf(txn == null || txn.splitMode == "none") }
    var error by remember { mutableStateOf<String?>(null) }
    var amountErr by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var similar by remember { mutableStateOf<List<Txn>?>(null) }
    var askDelete by remember { mutableStateOf(false) }

    LaunchedEffect(txn?.id) {
        if (txn == null) { equal.addAll(ctx.activeMembers.map { it.id }); return@LaunchedEffect }
        if (txn.splitMode != "none") try {
            val ss = ctx.repo.splits(listOf(txn.id))
            equal.addAll(ss.map { it.memberId }); ss.forEach { custom[it.memberId] = it.amount.toString() }
            loadedSplits = true
        } catch (e: AppError) { error = "割り勘の内訳を読めませんでした: ${e.userMessage}" }
    }
    val cats = ctx.cats.filter { it.kind == kind && (it.archivedAt == null || it.id == txn?.categoryId) }
    if (cat?.kind != kind) cat = null
    val splitMembers = ctx.members.filter { it.status == "active" || it.id in equal || custom.containsKey(it.id) }

    fun input(): TxnInput? {
        amountErr = Validate.amount(amount); error = null
        val a = Money.parse(amount)
        val problem = amountErr ?: Validate.date(date) ?: (if (cat == null) "カテゴリを選んでください" else null) ?: (if (payer == null) "払った人を選んでください" else null) ?: Validate.memo(memo)
            ?: (if (split == "equal" && equal.isEmpty()) "割り勘する人を選んでください" else null)
            ?: (if (split == "custom") Validate.customSplit(a ?: 0, splitMembers.mapNotNull { custom[it.id]?.let(Money::parse) }) else null)
            ?: (if (!loadedSplits) "割り勘の内訳を読み込めていません" else null)
        if (problem != null) { if (problem != amountErr) error = problem; return null }   // 金額の誤りは入力欄の下に出す
        return TxnInput(txn?.id, txn?.version, requestId.ifEmpty { UUID.randomUUID().toString() }, kind, a!!, date.toString(), cat!!.id, payer!!.id, pm?.id, memo.trim(),
            if (private) "private" else "group", if (kind == "income" || private) "none" else split,
            equalMembers = equal.toList(), customShares = custom.mapNotNull { (k, v) -> Money.parse(v)?.takeIf { it > 0 }?.let { k to it } }.toMap())
    }
    fun save(t: TxnInput) { busy = true; scope.launch {
        try { ctx.repo.saveTransaction(ctx.g.id, t); onSaved(if (txn == null) "保存しました" else "変更を保存しました") }
        catch (e: AppError) { error = e.userMessage } finally { busy = false }
    } }
    fun trySave() {
        val t = input() ?: return
        if (txn != null) { save(t); return }
        busy = true
        scope.launch {
            try { val s = ctx.repo.similar(ctx.g.id, t.amount, t.occurredOn, t.categoryId); busy = false; if (s.isEmpty()) save(t) else similar = s }
            catch (e: AppError) { busy = false; error = e.userMessage }
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf("expense" to "支出", "income" to "収入").forEachIndexed { i, (k, l) ->
                SegmentedButton(kind == k, { kind = k }, SegmentedButtonDefaults.itemShape(i, 2)) { Text(l) }
            }
        }
        AmountField(amount, { amount = it; amountErr = null }, error = amountErr, modifier = Modifier.testTag("amount"))
        DateField(date, { date = it })
        Picker("カテゴリ", cats, cat, { it.name }, { cat = it })
        Picker(if (kind == "income") "受け取った人" else "払った人", ctx.members.filter { it.status == "active" || it.id == txn?.payerMemberId }, payer, { it.displayName }, { payer = it })
        Picker("支払い方法（任意）", listOf<PaymentMethod?>(null) + ctx.pms.filter { it.archivedAt == null || it.id == txn?.paymentMethodId }, pm, { it?.name ?: "なし" }, { pm = it })
        OutlinedTextField(memo, { memo = it.take(500) }, Modifier.fillMaxWidth(), label = { Text("メモ（任意）") })
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(private, { private = it })
            Text("自分だけに見せる（グループの集計と精算には入りません）", Modifier.padding(start = 8.dp))
        }
        if (kind == "expense" && !private) {
            SectionTitle("割り勘")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf("none" to "しない", "equal" to "均等", "custom" to "金額を指定").forEachIndexed { i, (k, l) -> SegmentedButton(split == k, { split = k }, SegmentedButtonDefaults.itemShape(i, 3)) { Text(l) } }
            }
            val a = Money.parse(amount) ?: 0
            when (split) {
                "equal" -> {
                    val shares = Money.equalSplit(a, equal.size.coerceAtLeast(1))
                    splitMembers.forEach { m ->
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.heightIn(min = 48.dp)) {
                            Checkbox(m.id in equal, { if (it) equal.add(m.id) else equal.remove(m.id) })
                            Text(m.displayName, Modifier.weight(1f))
                            val idx = splitMembers.filter { it.id in equal }.indexOf(m)
                            if (idx >= 0 && a > 0) Text(Money.format(shares.getOrElse(idx) { 0 }))
                        }
                    }
                    Text("割り切れない 1 円は、参加の早い人から順に負担します（サーバーで計算）", style = MaterialTheme.typography.bodySmall)
                }
                "custom" -> {
                    splitMembers.forEach { m -> AmountField(custom[m.id] ?: "", { custom[m.id] = it }, label = "${m.displayName}の負担") }
                    val sum = splitMembers.sumOf { custom[it.id]?.let(Money::parse) ?: 0 }
                    Text(if (sum == a) "合計が金額と合っています" else "合計 ${Money.format(sum)}（あと ${Money.format(a - sum)}）", color = if (sum == a) IncomeColor else OverColor)
                }
            }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("txnError")) }
        Button(::trySave, Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("save"), enabled = !busy) {
            if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text("保存する")
        }
        if (txn != null) OutlinedButton({ askDelete = true }, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = !busy) { Text("この記録を消す", color = MaterialTheme.colorScheme.error) }
    }

    similar?.let { s ->
        ConfirmDialog("似た記録があります", "同じ日・同じ金額・同じカテゴリの記録が ${s.size} 件あります。\n" + s.take(3).joinToString("\n") { "・${it.occurredOn} ${Money.format(it.amount)} ${it.memo}" } + "\n二重に入れていないか確かめてください。",
            "それでも保存", onConfirm = { similar = null; input()?.let(::save) }, onDismiss = { similar = null }, danger = false)
    }
    if (askDelete && txn != null) ConfirmDialog("記録を消しますか", "${txn.occurredOn} ${Money.format(txn.amount)} を消します。操作の履歴には残ります。", "消す",
        onConfirm = { askDelete = false; busy = true; scope.launch {
            try { ctx.repo.deleteTransaction(txn.id, txn.version); onSaved("消しました") } catch (e: AppError) { error = e.userMessage } finally { busy = false }
        } }, onDismiss = { askDelete = false })
}
