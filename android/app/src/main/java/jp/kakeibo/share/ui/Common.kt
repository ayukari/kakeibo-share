package jp.kakeibo.share.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.ErrorKind
import jp.kakeibo.share.domain.Money
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

// ---------- 見た目（落ち着いた家計簿。数字を見やすく） ----------
private val Light = lightColorScheme(primary = Color(0xFF0E7656), onPrimary = Color.White, secondaryContainer = Color(0xFFDCEFE7), background = Color(0xFFF3F4F6), surface = Color(0xFFFCFCFA), error = Color(0xFFB42318))
private val Dark = darkColorScheme(primary = Color(0xFF47C79B), onPrimary = Color(0xFF05261B), secondaryContainer = Color(0xFF16302A), background = Color(0xFF0E0F11), surface = Color(0xFF1A1B1E), error = Color(0xFFFF8A7A))

@Composable
fun KakeiboTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, content = content)

val IncomeColor @Composable get() = MaterialTheme.colorScheme.primary
val OverColor @Composable get() = MaterialTheme.colorScheme.error

@Composable
fun MoneyText(yen: Long, modifier: Modifier = Modifier, big: Boolean = false, color: Color = Color.Unspecified, signed: Boolean = false) {
    val s = (if (signed && yen > 0) "+" else "") + Money.format(yen)
    Text(s, modifier, color = color, fontWeight = FontWeight.Bold, fontSize = if (big) 30.sp else 16.sp,
        style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
}

// ---------- 読み込みの状態（読み込み中・データなし・通信エラーを必ず出す） ----------
sealed interface Loadable<out T> {
    data object Loading : Loadable<Nothing>
    data class Ready<T>(val value: T) : Loadable<T>
    data class Failed(val error: AppError) : Loadable<Nothing>
}

// 読み込みと操作をまとめた ViewModel。操作の結果（成功・失敗）は message に出す。失敗を成功に見せない
open class LoadVM<T>(private val loader: suspend () -> T) : ViewModel() {
    private val _state = MutableStateFlow<Loadable<T>>(Loadable.Loading)
    val state: StateFlow<Loadable<T>> = _state
    val message = MutableStateFlow<String?>(null)
    val busy = MutableStateFlow(false)

    init { reload() }

    fun reload() = viewModelScope.launch {
        if (_state.value !is Loadable.Ready) _state.value = Loadable.Loading
        _state.value = try { Loadable.Ready(loader()) } catch (e: AppError) { Loadable.Failed(e) } catch (e: Exception) { Loadable.Failed(AppError(ErrorKind.Server, cause = e)) }
    }

    // 書き込みの操作。成功したら読み直す。失敗はエラー文を出して、入力は呼び出し側に残す
    fun act(success: String?, reloadAfter: Boolean = true, onDone: (Boolean) -> Unit = {}, block: suspend () -> Unit) = viewModelScope.launch {
        if (busy.value) return@launch
        busy.value = true
        val ok = try { block(); true } catch (e: AppError) { message.value = e.userMessage; false } catch (e: Exception) { message.value = AppError(ErrorKind.Server).userMessage; false }
        busy.value = false
        if (ok) { success?.let { message.value = it }; if (reloadAfter) reload() }
        onDone(ok)
    }
}

@Composable
fun <T> LoadableView(state: Loadable<T>, onRetry: () -> Unit, isEmpty: (T) -> Boolean = { false }, empty: @Composable () -> Unit = {}, content: @Composable (T) -> Unit) {
    when (state) {
        Loadable.Loading -> Box(Modifier.fillMaxWidth().padding(48.dp), Alignment.Center) { CircularProgressIndicator(Modifier.semantics { contentDescription = "読み込み中" }) }
        is Loadable.Failed -> ErrorBox(state.error, onRetry)
        is Loadable.Ready -> if (isEmpty(state.value)) empty() else content(state.value)
    }
}


@Composable
fun ErrorBox(e: AppError, onRetry: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(24.dp).semantics { liveRegion = LiveRegionMode.Polite }, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(if (e.kind == ErrorKind.Forbidden) "アクセスできません" else "読み込めませんでした", style = MaterialTheme.typography.titleMedium)
        Text(e.userMessage, Modifier.padding(top = 6.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (e.kind != ErrorKind.Forbidden) OutlinedButton(onRetry, Modifier.padding(top = 12.dp).heightIn(min = 48.dp)) { Text("もう一度読み込む") }
    }
}

@Composable
fun EmptyBox(title: String, body: String, action: (@Composable () -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(body, Modifier.padding(top = 6.dp), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
        action?.let { Box(Modifier.padding(top = 12.dp)) { it() } }
    }
}

// 操作の結果をスナックバーで出す
@Composable
fun MessageEffect(vm: LoadVM<*>, host: SnackbarHostState) {
    val msg by vm.message.collectAsState()
    LaunchedEffect(msg) { msg?.let { host.showSnackbar(it); vm.message.value = null } }
}

@Composable
fun AmountField(value: String, onChange: (String) -> Unit, label: String = "金額（円）", error: String? = null, modifier: Modifier = Modifier) {
    OutlinedTextField(value, { v -> onChange(v.filter { it.isDigit() || it == ',' }.take(13)) }, modifier.fillMaxWidth(), label = { Text(label) },
        prefix = { Text("¥") }, singleLine = true, isError = error != null, supportingText = error?.let { { Text(it) } },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
}

@Composable
fun DateField(date: LocalDate, onChange: (LocalDate) -> Unit, label: String = "日付", modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    OutlinedButton({ DatePickerDialog(ctx, { _, y, m, d -> onChange(LocalDate.of(y, m + 1, d)) }, date.year, date.monthValue - 1, date.dayOfMonth).show() },
        modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("$label: ${date.year}年${date.monthValue}月${date.dayOfMonth}日") }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> Picker(label: String, options: List<T>, selected: T?, text: (T) -> String, onPick: (T) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(open, { open = it }, modifier) {
        OutlinedTextField(selected?.let(text) ?: "選んでください", {}, Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).fillMaxWidth(), readOnly = true,
            label = { Text(label) }, trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) })
        ExposedDropdownMenu(open, { open = false }) { options.forEach { o -> DropdownMenuItem({ Text(text(o)) }, { onPick(o); open = false }) } }
    }
}

@Composable
fun ConfirmDialog(title: String, body: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit, danger: Boolean = true) {
    AlertDialog(onDismiss, title = { Text(title) }, text = { Text(body) },
        confirmButton = { TextButton(onConfirm) { Text(confirm, color = if (danger) MaterialTheme.colorScheme.error else Color.Unspecified) } },
        dismissButton = { TextButton(onDismiss) { Text("やめる") } })
}

@Composable
fun MonthBar(month: LocalDate, onChange: (LocalDate) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton({ onChange(month.minusMonths(1)) }) { Text("‹", fontSize = 22.sp) }
        Text("${month.year}年${month.monthValue}月", Modifier.weight(1f), textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium)
        IconButton({ onChange(month.plusMonths(1)) }, enabled = month.withDayOfMonth(1) < Money.todayJst().withDayOfMonth(1).plusMonths(1)) { Text("›", fontSize = 22.sp) }
    }
}

@Composable
fun SectionTitle(text: String) = Text(text, Modifier.padding(top = 20.dp, bottom = 6.dp), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)

val ROLE_NAMES = mapOf("owner" to "オーナー", "admin" to "管理者", "member" to "メンバー", "viewer" to "閲覧のみ")
fun roleRank(r: String?) = when (r) { "owner" -> 4; "admin" -> 3; "member" -> 2; "viewer" -> 1; else -> 0 }
