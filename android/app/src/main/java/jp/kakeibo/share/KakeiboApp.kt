package jp.kakeibo.share

import android.app.Application
import jp.kakeibo.share.data.Repo

class KakeiboApp : Application() {
    // Supabase の設定がないビルドでは null（設定が必要な画面を出す）
    val repo: Repo? by lazy { if (Repo.configured()) Repo.create(this) else null }
}
