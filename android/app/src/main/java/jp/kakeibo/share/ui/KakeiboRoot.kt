package jp.kakeibo.share.ui

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.jan.supabase.auth.status.SessionStatus
import jp.kakeibo.share.data.Group
import jp.kakeibo.share.data.Member
import jp.kakeibo.share.data.Repo
import jp.kakeibo.share.domain.AppError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

// 端末に残すのは「最後に開いたグループの ID」だけ（家計簿のデータは端末に保存しない）
private val Context.prefs by preferencesDataStore("kakeibo_prefs")
private val LAST_GROUP = stringPreferencesKey("last_group")

class AppVM(val repo: Repo, private val ctx: Context) : ViewModel() {
    val session = repo.auth.sessionStatus
    val groups = MutableStateFlow<Loadable<List<Group>>>(Loadable.Loading)
    val current = MutableStateFlow<Group?>(null)
    val me = MutableStateFlow<Member?>(null)
    val members = MutableStateFlow<List<Member>>(emptyList())
    val toasts = kotlinx.coroutines.flow.MutableSharedFlow<String>(extraBufferCapacity = 8)
    fun toast(s: String) { toasts.tryEmit(s) }

    fun loadGroups() = viewModelScope.launch {
        groups.value = Loadable.Loading
        try {
            val gs = repo.groups()
            groups.value = Loadable.Ready(gs)
            val last = ctx.prefs.data.map { it[LAST_GROUP] }.first()
            val pick = gs.firstOrNull { it.id == (current.value?.id ?: last) }
            if (pick != null) select(pick) else current.value = null
        } catch (e: AppError) { groups.value = Loadable.Failed(e) }
    }

    fun select(g: Group?) = viewModelScope.launch {
        current.value = g
        ctx.prefs.edit { if (g == null) it.remove(LAST_GROUP) else it[LAST_GROUP] = g.id }
        if (g != null) refreshMembers()
    }

    fun refreshMembers() = viewModelScope.launch {
        val g = current.value ?: return@launch
        try {
            val ms = repo.members(g.id)
            members.value = ms
            me.value = ms.firstOrNull { it.userId == repo.userId() && it.status == "active" }
            if (me.value?.role != "viewer") runCatching { repo.generateDue(g.id) }   // 期日の来た定期取引を作る（何度呼んでも二重にならない）
        } catch (_: AppError) { }
    }

    fun signOut() = viewModelScope.launch {
        runCatching { repo.signOut() }
        current.value = null; me.value = null; members.value = emptyList()
    }

    fun can(min: String) = roleRank(me.value?.role) >= roleRank(min)
}

@Composable
fun KakeiboRoot(repo: Repo?) = KakeiboTheme {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        if (repo == null) { ConfigMissing(); return@Surface }
        val ctx = LocalContext.current.applicationContext
        val app: AppVM = viewModel { AppVM(repo, ctx) }
        val status by app.session.collectAsState()
        when (status) {
            is SessionStatus.Initializing -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            is SessionStatus.Authenticated -> GroupGate(app)
            else -> AuthScreen(repo, refreshFailed = status is SessionStatus.RefreshFailure)
        }
    }
}

@Composable
private fun GroupGate(app: AppVM) {
    LaunchedEffect(Unit) { app.loadGroups() }
    val groups by app.groups.collectAsState()
    val current by app.current.collectAsState()
    val g = current
    if (g == null) GroupSelectScreen(app, groups) else MainScaffold(app, g)
}

@Composable
private fun ConfigMissing() = Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
    Text("接続先が設定されていません", style = MaterialTheme.typography.titleLarge)
    Text("このビルドには Supabase の URL と anon キーが入っていません。android/local.properties に SUPABASE_URL と SUPABASE_ANON_KEY を書いてビルドし直してください（docs/setup-android.md）。",
        Modifier.padding(top = 8.dp), textAlign = TextAlign.Center)
}
