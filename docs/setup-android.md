# Android の開発環境

- JDK 17、Android SDK（compileSdk 36・minSdk 26）、Gradle 8.14.3（ラッパー同梱）
- Kotlin 2.4 / Jetpack Compose（BOM 2025.12.01）/ MVVM（ViewModel + StateFlow）/ Coroutines
- 通信: supabase-kt 3.8（auth・postgrest・functions）+ Ktor

## 接続先
`android/local.properties`（git に入らない）:
```
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJ...
```
書かずにビルドすると、アプリは「接続先が設定されていません」と出して止まる。

## ビルドとテスト（android/ で）
```
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```
- `testDebugUnitTest`: JUnit（お金・検証・エラー分類・CSV。共有の値 tests/vectors を読む）と、Robolectric の Compose UI テスト（入力の検証・権限での出し分け）。
- 実機・エミュレーターでの確認（Compose の instrumented テスト）は、まだ用意していない。

## 作り
- `domain/` お金・入力の検証・エラー分類（サーバーと同じ決まり）
- `data/` Repo（すべての通信）、Models、SecureSessionManager（Keystore で暗号化したセッション）
- `ui/` 画面。`LoadVM` が読み込み中・失敗・成功の状態と、操作の結果の文を持つ
- リリースは R8 で縮小。`allowBackup=false`、平文の通信は禁止
