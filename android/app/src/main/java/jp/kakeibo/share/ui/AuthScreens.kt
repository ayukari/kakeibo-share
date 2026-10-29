package jp.kakeibo.share.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import jp.kakeibo.share.data.Group
import jp.kakeibo.share.data.Repo
import jp.kakeibo.share.domain.AppError
import jp.kakeibo.share.domain.Validate
import kotlinx.coroutines.launch

private enum class AuthMode { Login, SignUp, VerifySignUp, ResetRequest, ResetVerify, NewPassword }

// ログイン・新規登録・パスワード再設定（メールの 6 桁のコードで。アプリへのリンクは使わない）
@Composable
fun AuthScreen(repo: Repo, refreshFailed: Boolean = false, onNewPasswordDone: (() -> Unit)? = null) {
    var mode by rememberSaveable { mutableStateOf(if (onNewPasswordDone != null) AuthMode.NewPassword else AuthMode.Login) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(if (refreshFailed) "ログインの期限が切れました。もう一度ログインしてください" else null) }
    var info by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun run(block: suspend () -> Unit) {
        error = null; info = null; busy = true
        scope.launch { try { block() } catch (e: AppError) { error = e.userMessage } finally { busy = false } }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Spacer(Modifier.height(32.dp))
        Text("共有家計簿", style = MaterialTheme.typography.headlineMedium)
        Text(when (mode) {
            AuthMode.Login -> "ログイン"; AuthMode.SignUp -> "新規登録"; AuthMode.VerifySignUp -> "メールの確認"
            AuthMode.ResetRequest -> "パスワードを忘れたとき"; AuthMode.ResetVerify -> "確認コードの入力"; AuthMode.NewPassword -> "新しいパスワード"
        }, style = MaterialTheme.typography.titleMedium)

        if (mode in listOf(AuthMode.Login, AuthMode.SignUp, AuthMode.ResetRequest))
            OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth().testTag("email"), label = { Text("メールアドレス") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next))
        if (mode == AuthMode.SignUp)
            OutlinedTextField(name, { name = it.take(30) }, Modifier.fillMaxWidth(), label = { Text("表示名（グループの人に見える名前）") }, singleLine = true)
        if (mode in listOf(AuthMode.Login, AuthMode.SignUp, AuthMode.NewPassword))
            OutlinedTextField(password, { password = it }, Modifier.fillMaxWidth().testTag("password"), label = { Text(if (mode == AuthMode.Login) "パスワード" else "パスワード（8 文字以上）") },
                singleLine = true, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done))
        if (mode in listOf(AuthMode.VerifySignUp, AuthMode.ResetVerify)) {
            Text("$email に届いた 6 桁のコードを入れてください。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(code, { code = it.filter(Char::isDigit).take(8) }, Modifier.fillMaxWidth(), label = { Text("確認コード") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
        }

        error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive }.testTag("authError")) }
        info?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

        Button(onClick = {
            when (mode) {
                AuthMode.Login -> { (Validate.email(email) ?: if (password.isEmpty()) "パスワードを入れてください" else null)?.let { error = it } ?: run { repo.signIn(email, password) } }
                AuthMode.SignUp -> (Validate.email(email) ?: Validate.displayName(name) ?: Validate.password(password))?.let { error = it } ?: run {
                    repo.signUp(email, password, name)
                    if (repo.userId() == null) { mode = AuthMode.VerifySignUp; info = "確認のメールを送りました" }
                }
                AuthMode.VerifySignUp -> if (code.length < 6) error = "コードを入れてください" else run { repo.verifySignUp(email, code) }
                AuthMode.ResetRequest -> Validate.email(email)?.let { error = it } ?: run { repo.sendReset(email); mode = AuthMode.ResetVerify; info = "再設定のコードを送りました（届かないときは迷惑メールも確かめてください）" }
                AuthMode.ResetVerify -> if (code.length < 6) error = "コードを入れてください" else run { repo.verifyReset(email, code); mode = AuthMode.NewPassword; password = "" }
                AuthMode.NewPassword -> Validate.password(password)?.let { error = it } ?: run { repo.changePassword(password); info = "パスワードを変えました"; onNewPasswordDone?.invoke() }
            }
        }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("submit")) {
            if (busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(when (mode) {
                AuthMode.Login -> "ログイン"; AuthMode.SignUp -> "登録する"; AuthMode.VerifySignUp, AuthMode.ResetVerify -> "確認する"
                AuthMode.ResetRequest -> "コードを送る"; AuthMode.NewPassword -> "パスワードを変える"
            })
        }
        when (mode) {
            AuthMode.Login -> {
                TextButton({ mode = AuthMode.SignUp; error = null }, Modifier.heightIn(min = 48.dp)) { Text("はじめての方は新規登録") }
                TextButton({ mode = AuthMode.ResetRequest; error = null }, Modifier.heightIn(min = 48.dp)) { Text("パスワードを忘れたとき") }
            }
            AuthMode.NewPassword -> {}
            else -> TextButton({ mode = AuthMode.Login; error = null }, Modifier.heightIn(min = 48.dp)) { Text("ログインに戻る") }
        }
        if (mode == AuthMode.SignUp) Text("登録すると、メールアドレスとパスワードは Supabase の認証で管理されます（パスワードはハッシュにして保存され、平文では残りません）。",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// グループの選択・作成・招待コードでの参加
@Composable
fun GroupSelectScreen(app: AppVM, groups: Loadable<List<Group>>) {
    var newName by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    fun run(block: suspend () -> Unit) { error = null; busy = true; scope.launch { try { block() } catch (e: AppError) { error = e.userMessage } finally { busy = false } } }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Spacer(Modifier.height(24.dp))
        Text("家計簿を選ぶ", style = MaterialTheme.typography.headlineSmall)
        LoadableView(groups, { app.loadGroups() }, isEmpty = { it.isEmpty() }, empty = { Text("まだ参加している家計簿はありません。作るか、招待コードで参加してください。", color = MaterialTheme.colorScheme.onSurfaceVariant) }) { gs ->
            gs.forEach { g -> OutlinedButton({ app.select(g) }, Modifier.fillMaxWidth().heightIn(min = 56.dp)) { Text(g.name) } }
        }
        SectionTitle("新しく作る")
        OutlinedTextField(newName, { newName = it.take(40) }, Modifier.fillMaxWidth(), label = { Text("家計簿の名前（例: うちの家計簿）") }, singleLine = true)
        Button({ Validate.groupName(newName)?.let { error = it } ?: run { val g = app.repo.createGroup(newName); newName = ""; app.loadGroups(); app.select(g) } },
            Modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = !busy) { Text("作る") }
        SectionTitle("招待コードで参加する")
        OutlinedTextField(code, { code = it.uppercase().filter { c -> c.isLetterOrDigit() || c == '-' }.take(16) }, Modifier.fillMaxWidth(), label = { Text("招待コード（12 文字）") }, singleLine = true)
        Button({ if (code.count { it.isLetterOrDigit() } < 12) error = "招待コードは 12 文字です" else run {
            val m = app.repo.acceptInvitation(code, null)
            if (m == null) error = "招待コードが正しくないか、期限切れか、使える回数をこえています" else { code = ""; app.loadGroups() }
        } }, Modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = !busy) { Text("参加する") }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        TextButton({ app.signOut() }, Modifier.align(Alignment.End)) { Text("ログアウト") }
    }
}
