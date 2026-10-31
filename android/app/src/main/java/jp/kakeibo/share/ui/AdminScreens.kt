package jp.kakeibo.share.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import jp.kakeibo.share.data.*
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.Money
import jp.kakeibo.share.domain.Validate
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.io.File
import java.time.LocalDate

// ---------- カテゴリ ----------
@Composable
fun CategoryScreen(ctx: GroupCtx) {
    val vm: LoadVM<List<Category>> = viewModel(key = "cats-${ctx.g.id}-r${ctx.rev}") { LoadVM { ctx.repo.categories(ctx.g.id) } }
    val st by vm.state.collectAsState()
    val busy by vm.busy.collectAsState()
    val host = remember { SnackbarHostState() }
    MessageEffect(vm, host)
    var edit by remember { mutableStateOf<Category?>(null) }
    var creating by remember { mutableStateOf<String?>(null) }
    var del by remember { mutableStateOf<Category?>(null) }
    val admin = ctx.can("admin")

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
            item { if (!admin) Text("カテゴリを変えられるのは管理者とオーナーです", style = MaterialTheme.typography.bodySmall) }
            item {
                LoadableView(st, { vm.reload() }) { cs ->
                    Column {
                        listOf("expense" to "支出", "income" to "収入").forEach { (k, l) ->
                            SectionTitle(l)
                            cs.filter { it.kind == k && it.archivedAt == null }.forEach { c ->
                                ListItem(headlineContent = { Text(c.name, fontWeight = FontWeight.Bold) }, leadingContent = { CategoryDot(c.name, c.color, icon = c.icon) }, modifier = Modifier.clickable(enabled = admin) { edit = c },
                                    trailingContent = { if (admin) TextButton({ del = c }) { Text("消す", color = OverColor) } })
                            }
                            if (admin) TextButton({ creating = k }, enabled = !busy) { Text("＋ ${l}のカテゴリを足す") }
                        }
                        val archived = cs.filter { it.archivedAt != null }
                        if (archived.isNotEmpty()) { SectionTitle("使われなくなったカテゴリ（過去の記録のために残しています）"); archived.forEach { Text(it.name, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                    }
                }
            }
        }
        SnackbarHost(host, Modifier.align(Alignment.BottomCenter))
    }
    val target = edit; val newKind = creating
    if (target != null || newKind != null) {
        var name by remember(target, newKind) { mutableStateOf(target?.name ?: "") }
        var icon by remember(target, newKind) { mutableStateOf(target?.icon ?: "・") }
        var color by remember(target, newKind) { mutableStateOf(target?.color ?: "#6b7280") }
        val err = Validate.categoryName(name)
        AlertDialog({ edit = null; creating = null }, title = { Text(if (target == null) "カテゴリを足す" else "カテゴリを直す") }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it.take(20) }, label = { Text("名前") }, singleLine = true, isError = err != null && name.isNotEmpty())
                Label("色（点と棒に使います）")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("#e07a3f", "#3f8fd0", "#7a5cc7", "#e0b23f", "#3fb0b0", "#d04f6a", "#4f9a6a", "#6b7280").forEach { h ->
                        Box(Modifier.size(32.dp).clip(androidx.compose.foundation.shape.CircleShape).background(parseColor(h)).then(if (color == h) Modifier.border(3.dp, T.ink, androidx.compose.foundation.shape.CircleShape) else Modifier).clickable { color = h })
                    }
                }
                OutlinedTextField(icon, { icon = it.take(2) }, label = { Text("絵文字（1 文字・任意）") }, singleLine = true)
            }
        }, confirmButton = {
            TextButton({
                val c = target; edit = null; creating = null
                vm.act("保存しました", onDone = { if (it) ctx.reloadMeta() }) {
                    ctx.repo.saveCategory(ctx.g.id, c?.id, c?.kind ?: newKind!!, name, color, icon.ifBlank { "・" }, c?.sort ?: 100, c?.version)
                }
            }, enabled = err == null) { Text("保存") }
        }, dismissButton = { TextButton({ edit = null; creating = null }) { Text("やめる") } })
    }
    del?.let { c ->
        ConfirmDialog("「${c.name}」を消しますか", "記録で使われているときは、消さずに「使われなくなったカテゴリ」に移します（過去の記録はそのまま）。", "消す",
            { del = null; vm.act(null, onDone = { if (it) ctx.reloadMeta() }) { val r = ctx.repo.deleteCategory(c.id); vm.message.value = if (r == "archived") "使われているので、使われなくなったカテゴリに移しました" else "消しました" } }, { del = null })
    }
}

// ---------- メンバーと招待 ----------
data class MemberData(val members: List<Member>, val invites: List<Invitation>)

@Composable
fun MemberScreen(ctx: GroupCtx) {
    val admin = ctx.can("admin")
    val vm: LoadVM<MemberData> = viewModel(key = "members-${ctx.g.id}-r${ctx.rev}") {
        LoadVM { MemberData(ctx.repo.members(ctx.g.id), if (admin) ctx.repo.invitations(ctx.g.id) else emptyList()) }
    }
    val st by vm.state.collectAsState()
    val busy by vm.busy.collectAsState()
    val host = remember { SnackbarHostState() }
    MessageEffect(vm, host)
    val context = LocalContext.current
    var newCode by remember { mutableStateOf<NewInvitation?>(null) }
    var role by remember { mutableStateOf("member") }
    var hours by remember { mutableIntStateOf(72) }
    var menuFor by remember { mutableStateOf<Member?>(null) }
    var confirm by remember { mutableStateOf<Pair<String, suspend () -> Unit>?>(null) }
    fun after(ok: Boolean) { if (ok) ctx.app.refreshMembers() }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
            item {
                LoadableView(st, { vm.reload() }) { d ->
                    Column {
                        SectionTitle("メンバー")
                        d.members.filter { it.status == "active" }.forEach { m ->
                            ListItem(headlineContent = { Text(m.displayName + if (m.id == ctx.me?.id) "（あなた）" else "") }, supportingContent = { Text(ROLE_NAMES[m.role] ?: m.role) },
                                trailingContent = { if (admin && m.id != ctx.me?.id && m.role != "owner") TextButton({ menuFor = m }) { Text("変える") } })
                        }
                        val gone = d.members.filter { it.status != "active" }
                        if (gone.isNotEmpty()) { SectionTitle("抜けた人（過去の記録のために名前を残しています）"); gone.forEach { Text(it.displayName, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                        if (admin) {
                            SectionTitle("招待する")
                            Text("招待コードは作ったときに 1 度だけ表示されます。LINE などで本人にだけ送ってください。", style = MaterialTheme.typography.bodySmall)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                listOf("member" to "メンバー", "viewer" to "閲覧のみ").forEach { (k, l) -> FilterChip(role == k, { role = k }, { Text(l) }) }
                                listOf(24 to "1 日", 72 to "3 日", 168 to "7 日").forEach { (h, l) -> FilterChip(hours == h, { hours = h }, { Text(l) }) }
                            }
                            Button({ vm.act(null) { newCode = ctx.repo.createInvitation(ctx.g.id, role, hours, 1) } }, Modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = !busy) { Text("招待コードを作る（1 人用）") }
                            val live = d.invites.filter { it.revokedAt == null && it.usedCount < it.maxUses }
                            if (live.isNotEmpty()) SectionTitle("有効な招待")
                            live.forEach { i ->
                                ListItem(headlineContent = { Text("…${i.codeHint}（${ROLE_NAMES[i.role]}）") }, supportingContent = { Text("期限 ${i.expiresAt.take(16).replace('T', ' ')}（UTC）・${i.usedCount}/${i.maxUses} 回") },
                                    trailingContent = { TextButton({ vm.act("招待を取り消しました") { ctx.repo.revokeInvitation(i.id) } }, enabled = !busy) { Text("取り消す", color = OverColor) } })
                            }
                        }
                    }
                }
            }
        }
        SnackbarHost(host, Modifier.align(Alignment.BottomCenter))
    }
    newCode?.let { inv ->
        AlertDialog({ newCode = null }, title = { Text("招待コード") }, text = {
            Column {
                Text(inv.code.chunked(4).joinToString("-"), fontFamily = FontFamily.Monospace, fontSize = 26.sp)
                Text("この画面を閉じると、もう表示できません。${ROLE_NAMES[inv.role]}として参加します。", Modifier.padding(top = 8.dp))
            }
        }, confirmButton = {
            TextButton({
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("招待コード", inv.code))
                ctx.app.toast("コピーしました")
            }) { Text("コピー") }
        }, dismissButton = { TextButton({ newCode = null }) { Text("閉じる") } })
    }
    menuFor?.let { m ->
        AlertDialog({ menuFor = null }, title = { Text(m.displayName) }, text = {
            Column {
                Text("権限を変える")
                listOf("admin", "member", "viewer").filter { it != m.role && (it != "admin" || ctx.can("owner")) }.forEach { r ->
                    TextButton({ menuFor = null; vm.act("${ROLE_NAMES[r]}にしました", onDone = ::after) { ctx.repo.changeRole(m.id, r) } }) { Text("${ROLE_NAMES[r]}にする") }
                }
                if (ctx.can("owner")) TextButton({ menuFor = null; confirm = "${m.displayName}さんをオーナーにします。あなたは管理者になります。" to { ctx.repo.transferOwnership(m.id) } }) { Text("オーナーを渡す") }
                TextButton({ menuFor = null; confirm = "${m.displayName}さんをグループから外します。過去の記録と精算の差額は残ります。" to { ctx.repo.removeMember(m.id) } }) { Text("グループから外す", color = OverColor) }
            }
        }, confirmButton = { TextButton({ menuFor = null }) { Text("閉じる") } })
    }
    confirm?.let { (body, action) -> ConfirmDialog("よろしいですか", body, "はい", { confirm = null; vm.act("変更しました", onDone = ::after) { action() } }, { confirm = null }) }
}

// ---------- 定期的な収支（家賃・サブスクなど。期日が来たら自動で記録。何度動いても二重にならない） ----------
@Composable
fun RecurringScreen(ctx: GroupCtx) {
    val vm: LoadVM<List<Recurring>> = viewModel(key = "rec-${ctx.g.id}-r${ctx.rev}") { LoadVM { ctx.repo.recurring(ctx.g.id) } }
    val st by vm.state.collectAsState()
    val busy by vm.busy.collectAsState()
    val host = remember { SnackbarHostState() }
    MessageEffect(vm, host)
    val admin = ctx.can("admin")
    var kind by remember { mutableStateOf("expense") }
    var amount by remember { mutableStateOf("") }
    var cat by remember { mutableStateOf<Category?>(null) }
    var payer by remember { mutableStateOf(ctx.me) }
    var memo by remember { mutableStateOf("") }
    var freq by remember { mutableStateOf("monthly") }
    var day by remember { mutableStateOf("1") }
    var weekday by remember { mutableIntStateOf(1) }
    var month by remember { mutableStateOf("1") }
    var start by remember { mutableStateOf(Money.todayJst()) }
    var equal by remember { mutableStateOf(false) }
    var del by remember { mutableStateOf<Recurring?>(null) }
    val weekdays = listOf("日", "月", "火", "水", "木", "金", "土")

    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
            item {
                LoadableView(st, { vm.reload() }, isEmpty = { it.isEmpty() }, empty = { EmptyBox("定期的な収支はありません", "家賃や給料、サブスクを登録すると、期日に自動で記録されます") }) { rs ->
                    Column {
                        rs.forEach { r ->
                            val rule = when (r.freq) { "weekly" -> "毎週${weekdays[r.weekday ?: 0]}曜"; "monthly" -> "毎月${r.dayOfMonth}日"; else -> "毎年${r.monthOfYear}月${r.dayOfMonth}日" }
                            ListItem(headlineContent = { Text("${ctx.cat(r.categoryId)?.name ?: "不明"} ${Money.format(r.amount)}" + if (r.memo.isNotBlank()) "・${r.memo}" else "") },
                                supportingContent = { Text("$rule（月末より後の日は月末に）・次は ${r.nextRunOn}" + if (!r.active) "・停止中" else "") },
                                trailingContent = { if (admin) TextButton({ del = r }) { Text("やめる", color = OverColor) } })
                        }
                    }
                }
            }
            if (admin) item {
                SectionTitle("登録する")
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("expense" to "支出", "income" to "収入").forEach { (k, l) -> FilterChip(kind == k, { kind = k; cat = null }, { Text(l) }) } }
                    AmountField(amount, { amount = it })
                    Picker("カテゴリ", ctx.cats.filter { it.kind == kind && it.archivedAt == null }, cat, { it.name }, { cat = it })
                    Picker(if (kind == "income") "受け取る人" else "払う人", ctx.activeMembers, payer, { it.displayName }, { payer = it })
                    OutlinedTextField(memo, { memo = it.take(500) }, Modifier.fillMaxWidth(), label = { Text("メモ（例: 家賃）") })
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("weekly" to "毎週", "monthly" to "毎月", "yearly" to "毎年").forEach { (k, l) -> FilterChip(freq == k, { freq = k }, { Text(l) }) } }
                    when (freq) {
                        "weekly" -> Row { weekdays.forEachIndexed { i, w -> FilterChip(weekday == i, { weekday = i }, { Text(w) }, Modifier.padding(end = 2.dp)) } }
                        "monthly" -> OutlinedTextField(day, { day = it.filter(Char::isDigit).take(2) }, label = { Text("日（1〜31。31 は月末）") }, singleLine = true)
                        else -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedTextField(month, { month = it.filter(Char::isDigit).take(2) }, Modifier.weight(1f), label = { Text("月") }, singleLine = true)
                            OutlinedTextField(day, { day = it.filter(Char::isDigit).take(2) }, Modifier.weight(1f), label = { Text("日") }, singleLine = true)
                        }
                    }
                    DateField(start, { start = it }, label = "開始日")
                    if (kind == "expense") Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(equal, { equal = it }); Text("今いる全員で均等に割り勘") }
                    val err = Validate.amount(amount) ?: (if (cat == null) "カテゴリを選んでください" else null) ?: (if (payer == null) "払う人を選んでください" else null)
                        ?: (if (freq != "weekly" && day.toIntOrNull() !in 1..31) "日は 1〜31 です" else null) ?: (if (freq == "yearly" && month.toIntOrNull() !in 1..12) "月は 1〜12 です" else null)
                    err?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                    Button({
                        val p = buildJsonObject {
                            put("kind", kind); put("amount", Money.parse(amount)!!); put("category_id", cat!!.id); put("payer_member_id", payer!!.id); put("memo", memo.trim())
                            put("split_mode", if (equal && kind == "expense") "equal" else "none")
                            put("splits", buildJsonArray { if (equal && kind == "expense") ctx.activeMembers.forEach { add(JsonPrimitive(it.id)) } })
                            put("freq", freq); put("start_on", start.toString())
                            when (freq) { "weekly" -> put("weekday", weekday); "monthly" -> put("day_of_month", day.toInt()); else -> { put("day_of_month", day.toInt()); put("month_of_year", month.toInt()) } }
                        }
                        vm.act("登録しました", onDone = { if (it) { amount = ""; memo = "" } }) { ctx.repo.saveRecurring(ctx.g.id, p); ctx.repo.generateDue(ctx.g.id) }
                    }, Modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = err == null && !busy) { Text("登録する") }
                }
            }
        }
        SnackbarHost(host, Modifier.align(Alignment.BottomCenter))
    }
    del?.let { r -> ConfirmDialog("定期的な収支をやめますか", "これから先は自動で記録しません。もう記録された分は残ります。", "やめる", { del = null; vm.act("やめました") { ctx.repo.deleteRecurring(r.id) } }, { del = null }) }
}

// ---------- 操作の履歴（管理者以上） ----------
@Composable
fun AuditScreen(ctx: GroupCtx) {
    val vm: LoadVM<List<AuditLog>> = viewModel(key = "audit-${ctx.g.id}-r${ctx.rev}") { LoadVM { ctx.repo.audit(ctx.g.id) } }
    val st by vm.state.collectAsState()
    val tables = mapOf("transactions" to "収支", "settlements" to "精算", "group_members" to "メンバー", "invitations" to "招待", "categories" to "カテゴリ", "budgets" to "予算",
        "recurring_transactions" to "定期", "groups" to "グループ", "payment_methods" to "支払い方法", "transaction_splits" to "割り勘")
    val actions = mapOf("insert" to "追加", "update" to "変更", "delete" to "削除")
    LoadableView(st, { vm.reload() }, isEmpty = { it.isEmpty() }, empty = { EmptyBox("履歴はありません", "") }) { logs ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp)) {
            items(logs, key = { it.id }) { l ->
                val who = ctx.members.firstOrNull { it.userId == l.actor }?.displayName ?: if (l.actor == null) "自動" else "抜けた人"
                val d = l.detail as? JsonObject
                val extra = buildList {
                    d?.get("amount")?.jsonPrimitive?.longOrNull?.let { add(Money.format(it)) }
                    d?.get("status_to")?.jsonPrimitive?.contentOrNull?.let { add("状態→$it") }
                    d?.get("role_to")?.jsonPrimitive?.contentOrNull?.let { add("権限→${ROLE_NAMES[it] ?: it}") }
                }.joinToString("・")
                Column(Modifier.padding(vertical = 6.dp)) {
                    Text("${who}が${tables[l.targetTable] ?: l.targetTable}を${actions[l.action.substringAfter('.')] ?: l.action}" + if (extra.isNotEmpty()) "（$extra）" else "")
                    Text(l.at.take(19).replace('T', ' ') + "（UTC）", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                HorizontalDivider()
            }
        }
    }
}

// ---------- アカウントと設定 ----------
@Composable
fun AccountScreen(ctx: GroupCtx, onLeft: () -> Unit) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(ctx.me?.displayName ?: "") }
    var groupName by remember { mutableStateOf(ctx.g.name) }
    var pw by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var msg by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf<Triple<String, String, suspend () -> Unit>?>(null) }
    fun run(ok: String, block: suspend () -> Unit) { busy = true; msg = null; scope.launch { try { block(); msg = ok } catch (e: AppError) { msg = e.userMessage } finally { busy = false } } }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        msg?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        SectionTitle("表示名")
        OutlinedTextField(name, { name = it.take(30) }, Modifier.fillMaxWidth(), singleLine = true)
        Button({ Validate.displayName(name)?.let { msg = it } ?: run("表示名を変えました") { ctx.repo.updateProfile(name); ctx.app.refreshMembers() } }, enabled = !busy) { Text("変える") }
        if (ctx.can("admin")) {
            SectionTitle("家計簿の名前")
            OutlinedTextField(groupName, { groupName = it.take(40) }, Modifier.fillMaxWidth(), singleLine = true)
            Button({ Validate.groupName(groupName)?.let { msg = it } ?: run("名前を変えました") { val g = ctx.repo.renameGroup(ctx.g.id, groupName); ctx.app.select(g); ctx.app.loadGroups() } }, enabled = !busy) { Text("変える") }
        }
        SectionTitle("パスワード")
        OutlinedTextField(pw, { pw = it }, Modifier.fillMaxWidth(), label = { Text("新しいパスワード（8 文字以上）") }, singleLine = true, visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation())
        Button({ Validate.password(pw)?.let { msg = it } ?: run("パスワードを変えました") { ctx.repo.changePassword(pw); pw = "" } }, enabled = !busy) { Text("変える") }
        SectionTitle("メールアドレス")
        OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth(), label = { Text("新しいメールアドレス") }, singleLine = true)
        Button({ Validate.email(email)?.let { msg = it } ?: run("確認のメールを送りました。新しいアドレスで確認すると変わります") { ctx.repo.changeEmail(email) } }, enabled = !busy) { Text("変える") }
        SectionTitle("ロック")
        val context = LocalContext.current
        var lockOn by remember { mutableStateOf(AppLock.enabled(context)) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(lockOn, { on ->
                if (on && !AppLock.available(context)) { msg = "端末に画面ロック（指紋・顔・暗証番号）を設定してから、もう一度ためしてください"; return@Switch }
                AppLock.setEnabled(context, on); lockOn = on; msg = if (on) "ロックを有効にしました。次に開いたときから使えます" else "ロックを切りました"
            })
            Column(Modifier.padding(start = 8.dp)) { Text("アプリにロックをかける", color = T.ink); Faint("開くとき・1 分以上はなれたあとに、指紋・顔・暗証番号で解除します") }
        }
        SectionTitle("ログアウト・退出・削除")
        OutlinedButton({ ctx.app.signOut() }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("ログアウト") }
        if (ctx.me?.role != "owner") OutlinedButton({ confirm = Triple("この家計簿から抜けますか", "抜けても過去の記録と精算の差額は残ります。", { ctx.repo.leaveGroup(ctx.g.id); onLeft() }) }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("この家計簿から抜ける", color = OverColor) }
        if (ctx.can("owner")) OutlinedButton({ confirm = Triple("この家計簿を削除しますか", "全員がこの家計簿を見られなくなります。先に CSV で書き出しておくことをおすすめします。", { ctx.repo.deleteGroup(ctx.g.id); onLeft() }) }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("この家計簿を削除する", color = OverColor) }
        OutlinedButton({ confirm = Triple("アカウントを削除しますか", "ログインできなくなります。オーナーの家計簿があるときは、先に誰かにオーナーを渡してください。元には戻せません。", {
            when (ctx.repo.deleteAccount()) { null -> ctx.app.signOut(); "owner_must_transfer" -> throw AppError(jp.kakeibo.share.domain.ErrorKind.Conflict, "owner_must_transfer"); else -> throw AppError(jp.kakeibo.share.domain.ErrorKind.Server) }
        }) }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("アカウントを削除する", color = OverColor) }
    }
    confirm?.let { (t, b, action) -> ConfirmDialog(t, b, "はい", { confirm = null; run("完了しました", action) }, { confirm = null }) }
}

// ---------- CSV の書き出し（Excel で文字化けしないよう UTF-8 の BOM 付き） ----------
@Composable
fun ExportScreen(ctx: GroupCtx) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var from by remember { mutableStateOf(Money.todayJst().withDayOfMonth(1).minusMonths(11)) }
    var to by remember { mutableStateOf(Money.todayJst()) }
    var busy by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("あなたが見られる記録（自分だけの記録を含む）を CSV にします。ファイルは共有先を選んで保存してください。")
        DateField(from, { from = it }, label = "いつから")
        DateField(to, { to = it }, label = "いつまで")
        Button({
            if (to < from) { msg = "期間が逆です"; return@Button }
            busy = true; msg = null
            scope.launch {
                try {
                    val list = ctx.repo.transactions(ctx.g.id, from, to.plusDays(1))
                    val splits = ctx.repo.splits(list.filter { it.splitMode != "none" }.map { it.id }).groupBy { it.transactionId }
                    val csv = Csv.transactions(list, splits, ctx)
                    val dir = File(context.cacheDir, "exports").apply { mkdirs() }
                    dir.listFiles()?.forEach { it.delete() }   // 前回の書き出しを残さない
                    val f = File(dir, "kakeibo_${from}_${to}.csv"); f.writeBytes(Csv.BOM + csv.toByteArray(Charsets.UTF_8))
                    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/csv").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "CSV を保存・共有"))
                    msg = "${list.size} 件を書き出しました"
                } catch (e: AppError) { msg = e.userMessage } catch (e: Exception) { msg = "ファイルを作れませんでした" } finally { busy = false }
            }
        }, Modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = !busy) { Text("CSV を書き出す") }
        msg?.let { Text(it) }
        SectionTitle("バックアップについて")
        Text("無料プランの Supabase は自動バックアップがありません。管理者が定期的に pg_dump でバックアップを取ります（docs/backup-restore.md）。この CSV は個人の控えとして使えます。",
            style = MaterialTheme.typography.bodySmall)
    }
}

object Csv {
    val BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
    private val HEADER = listOf("日付", "種類", "金額", "カテゴリ", "払った人", "支払い方法", "メモ", "公開範囲", "割り勘", "負担の内訳", "ID")

    // 表計算ソフトで式として動かないよう、= + - @ で始まる値の先頭に ' を付ける
    fun cell(s: String): String {
        val safe = if (s.isNotEmpty() && s[0] in "=+-@\t\r") "'$s" else s
        return if (safe.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) "\"" + safe.replace("\"", "\"\"") + "\"" else safe
    }
    fun row(cells: List<String>) = cells.joinToString(",") { cell(it) }

    fun transactions(list: List<Txn>, splits: Map<String, List<Split>>, ctx: GroupCtx): String = transactions(list, splits, { ctx.cat(it)?.name ?: "" }, ctx::memberName, { id -> ctx.pms.firstOrNull { it.id == id }?.name ?: "" })

    fun transactions(list: List<Txn>, splits: Map<String, List<Split>>, cat: (String) -> String, member: (String?) -> String, pm: (String?) -> String): String = buildString {
        append(row(HEADER)).append("\r\n")
        list.sortedBy { it.occurredOn }.forEach { t ->
            append(row(listOf(t.occurredOn, if (t.kind == "income") "収入" else if (t.isRefund) "返金" else "支出", t.amount.toString(), cat(t.categoryId), member(t.payerMemberId), pm(t.paymentMethodId), t.memo,
                if (t.visibility == "private") "自分だけ" else "グループ", when (t.splitMode) { "equal" -> "均等"; "custom" -> "指定"; else -> "" },
                splits[t.id].orEmpty().joinToString(" ") { "${member(it.memberId)}:${it.amount}" }, t.id))).append("\r\n")
        }
    }
}
