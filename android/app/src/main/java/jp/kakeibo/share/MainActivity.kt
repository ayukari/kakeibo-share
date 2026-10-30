package jp.kakeibo.share

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import jp.kakeibo.share.ui.KakeiboRoot

// 指紋・顔・暗証番号でのロック（BiometricPrompt）に FragmentActivity が要る
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val repo = (application as KakeiboApp).repo
        setContent { KakeiboRoot(repo) }
    }
}
