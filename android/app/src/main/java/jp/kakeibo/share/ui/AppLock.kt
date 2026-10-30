package jp.kakeibo.share.ui

import android.content.Context
import android.os.SystemClock
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

// アプリのロック（上位の家計簿アプリの「パスコードロック」と同じ役目）。
// 暗証番号を自前で持たず、端末の画面ロック（指紋・顔・PIN）で解除する。設定は端末だけに保存
object AppLock {
    private const val PREFS = "kakeibo_lock"
    private const val KEY = "enabled"
    const val RELOCK_AFTER_MS = 60_000L   // 1 分以上ほかのアプリに行ったら、戻ったときにもう一度ロック

    fun enabled(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, false)
    fun setEnabled(ctx: Context, on: Boolean) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY, on).apply()

    // 端末に画面ロック（または指紋・顔）があるか
    fun available(ctx: Context) = BiometricManager.from(ctx).canAuthenticate(BIOMETRIC_WEAK or DEVICE_CREDENTIAL) == BiometricManager.BIOMETRIC_SUCCESS

    fun prompt(activity: FragmentActivity, onOk: () -> Unit, onFail: (String?) -> Unit) {
        val p = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onOk()
            override fun onAuthenticationError(code: Int, msg: CharSequence) = onFail(if (code == BiometricPrompt.ERROR_USER_CANCELED || code == BiometricPrompt.ERROR_CANCELED) null else msg.toString())
        })
        p.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("共有家計簿のロックを解除").setSubtitle("指紋・顔・画面ロックの暗証番号で")
            .setAllowedAuthenticators(BIOMETRIC_WEAK or DEVICE_CREDENTIAL).build())
    }
}

// ロックが有効なら、解除するまで中身を出さない
@Composable
fun LockGate(content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    val activity = ctx as? FragmentActivity
    var locked by remember { mutableStateOf(AppLock.enabled(ctx) && activity != null) }
    var message by remember { mutableStateOf<String?>(null) }
    var stoppedAt by remember { mutableLongStateOf(0L) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_STOP -> stoppedAt = SystemClock.elapsedRealtime()
                Lifecycle.Event.ON_START -> if (stoppedAt > 0 && AppLock.enabled(ctx) && SystemClock.elapsedRealtime() - stoppedAt >= AppLock.RELOCK_AFTER_MS) locked = true
                else -> {}
            }
        }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
    if (!locked || activity == null) { content(); return }
    LaunchedEffect(Unit) { AppLock.prompt(activity, { locked = false; message = null }, { message = it }) }
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text("ロック中", color = T.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Text("家計簿を見るには、指紋・顔・画面ロックの暗証番号で解除してください。", Modifier.padding(top = 8.dp), color = T.sub, textAlign = TextAlign.Center)
        message?.let { Text(it, Modifier.padding(top = 8.dp), color = T.danger, textAlign = TextAlign.Center) }
        Button({ AppLock.prompt(activity, { locked = false; message = null }, { message = it }) }, Modifier.padding(top = 20.dp).fillMaxWidth().heightIn(min = 52.dp), shape = ButtonShape) {
            Text("ロックを解除する", fontWeight = FontWeight.Bold)
        }
    }
}
