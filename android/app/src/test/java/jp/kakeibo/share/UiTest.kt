package jp.kakeibo.share

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.core.app.ApplicationProvider
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.MemoryCodeVerifierCache
import io.github.jan.supabase.auth.MemorySessionManager
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import jp.kakeibo.share.data.*
import jp.kakeibo.share.ui.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// 画面のテスト（通信しない範囲: 入力の検証・権限による表示の出し分け）
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class UiTest {
    @get:Rule val rule = createComposeRule()

    private fun repo() = Repo(createSupabaseClient("https://example.invalid", "test-anon") {
        install(Auth) { sessionManager = MemorySessionManager(); codeVerifierCache = MemoryCodeVerifierCache(); autoLoadFromStorage = false; alwaysAutoRefresh = false }
        install(Postgrest)
    })

    private fun ctx(role: String): GroupCtx {
        val app = AppVM(repo(), ApplicationProvider.getApplicationContext())
        val me = Member("m1", "g1", "u1", role, "active", "あき")
        val members = listOf(me, Member("m2", "g1", "u2", "member", "active", "はる"))
        val cats = listOf(Category("c1", "g1", "expense", "食費", "#000", "🍚"), Category("c2", "g1", "income", "給料", "#000", "💴"))
        return GroupCtx(app, Group("g1", "うち"), me, members, cats, emptyList()) {}
    }

    @Test fun loginShowsValidationErrorWithoutNetwork() {
        rule.setContent { KakeiboTheme { AuthScreen(repo()) } }
        rule.onNodeWithTag("email").performTextInput("not-an-email")
        rule.onNodeWithTag("submit").performClick()
        rule.onNodeWithTag("authError").assertTextContains("メールアドレスの形", substring = true)
    }

    @Test fun signUpRequiresLongPassword() {
        rule.setContent { KakeiboTheme { AuthScreen(repo()) } }
        rule.onNodeWithText("はじめての方は新規登録").performClick()
        rule.onNodeWithTag("email").performTextInput("a@b.jp")
        rule.onNodeWithText("表示名（グループの人に見える名前）").performTextInput("あき")
        rule.onNodeWithTag("password").performTextInput("short")
        rule.onNodeWithTag("submit").performClick()
        rule.onNodeWithTag("authError").assertTextContains("8 文字以上", substring = true)
    }

    @Test fun transactionFormRejectsEmptyAmount() {
        val c = ctx("member")
        rule.setContent { KakeiboTheme { TxnEditScreen(c, null, "expense") {} } }
        rule.onNodeWithTag("save").performScrollTo().performClick()
        rule.onNodeWithText("金額は 1 円以上の整数で入れてください", useUnmergedTree = true).assertExists()
    }

    @Test fun transactionFormRequiresCategory() {
        val c = ctx("member")
        rule.setContent { KakeiboTheme { TxnEditScreen(c, null, "expense") {} } }
        listOf("1", "2", "00").forEach { rule.onNodeWithTag("key_$it").performScrollTo().performClick() }
        rule.onNodeWithTag("save").performScrollTo().performClick()
        rule.onNodeWithTag("txnError").assertTextEquals("カテゴリを選んでください")
    }

    @Test fun customSplitShowsRemaining() {
        val c = ctx("member")
        rule.setContent { KakeiboTheme { TxnEditScreen(c, null, "expense") {} } }
        listOf("1", "000").forEach { k -> if (k == "000") { rule.onNodeWithTag("key_00").performScrollTo().performClick(); rule.onNodeWithTag("key_0").performScrollTo().performClick() } else rule.onNodeWithTag("key_$k").performScrollTo().performClick() }
        rule.onNodeWithText("金額").performScrollTo().performClick()
        rule.onNodeWithText("あきの負担").performScrollTo().performTextInput("600")
        rule.onNodeWithText("合計 ¥600（あと ¥400）").assertExists()
    }

    @Test fun keypadCalculatesAndRatioSplits() {
        val c = ctx("member")
        rule.setContent { KakeiboTheme { TxnEditScreen(c, null, "expense") {} } }
        listOf("1", "00", "0", "+", "5", "00").forEach { rule.onNodeWithTag("key_$it").performScrollTo().performClick() }
        rule.onNodeWithText("= ¥1,500").assertExists()
        rule.onNodeWithText("割合").performScrollTo().performClick()
        rule.onNodeWithText("比 50:50 で分けます（60:40 の % でも、大人 2・子ども 1 の口数でも）").performScrollTo().assertExists()
        rule.onAllNodesWithText("¥750", useUnmergedTree = true).assertCountEquals(2)
    }

    @Test fun refundToggleChangesLabels() {
        val c = ctx("member")
        rule.setContent { KakeiboTheme { TxnEditScreen(c, null, "expense") {} } }
        rule.onNodeWithText("支出を記録する").performScrollTo().assertExists()
        rule.onNodeWithTag("refund").performScrollTo().performClick()
        rule.onNodeWithText("返金を記録する").performScrollTo().assertExists()
        rule.onNodeWithText("受け取った人").assertExists()
    }

    @Test fun categoryTilesSelect() {
        val c = ctx("member")
        rule.setContent { KakeiboTheme { TxnEditScreen(c, null, "expense") {} } }
        rule.onNodeWithTag("cat_食費").performScrollTo().performClick()
        listOf("8", "00").forEach { rule.onNodeWithTag("key_$it").performScrollTo().performClick() }
        rule.onNodeWithTag("save").performScrollTo().performClick()
        // 入力の誤りが出ないこと（そのあとの送信はテストではサーバーに届かず、通信のエラーが出るかどうかはタイミングしだいなので見ない）
        rule.onNodeWithText("カテゴリを選んでください").assertDoesNotExist()
        rule.onNodeWithText("金額は 1 円以上の整数で入れてください").assertDoesNotExist()
    }

    @Test fun viewerSeesNoAuditMenu() {
        val c = ctx("viewer")
        rule.setContent { KakeiboTheme { MoreScreen(c) {} } }
        rule.onNodeWithText("操作の履歴").assertDoesNotExist()
        rule.onNodeWithText("予算").assertExists()
    }

    @Test fun adminSeesAuditMenu() {
        val c = ctx("admin")
        rule.setContent { KakeiboTheme { MoreScreen(c) {} } }
        rule.onNodeWithText("操作の履歴").assertExists()
    }
}
