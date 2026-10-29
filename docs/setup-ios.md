# iOS の開発環境

- Xcode 16 以降、iOS 17 以降、Swift 5.10 モード
- SwiftUI / MVVM（`@Observable` の Loader・AppState・GroupCtx）/ Swift Concurrency
- 通信: supabase-swift 2.x（Swift Package Manager）。セッションは Keychain（`KeychainLocalStorage`）
- プロジェクトは XcodeGen で作る（`ios/project.yml`。.xcodeproj は git に入れない）

## Mac で
```
brew install xcodegen
cd ios && xcodegen generate && open Kakeibo.xcodeproj
```
接続先は `ios/Config/Secrets.xcconfig`（`Secrets.example.xcconfig` をコピー。git に入らない）。

## Mac がないとき（クラウドの Mac）
`.github/workflows/ci.yml` の `ios` ジョブが GitHub の macOS ランナーで、プロジェクトの生成 → シミュレーターでのテストを行う。
リポジトリを GitHub に置いて push すると動く（置くかどうか・公開か非公開かは社長が決める。費用は docs/cost-and-limits.md）。

## テスト
- KakeiboTests（XCTest）: お金・検証・エラー分類・CSV・招待コードの表示。共有の値 tests/vectors をテストのバンドルに入れて読む。
- KakeiboUITests: 起動と、ログイン画面の入力検証（通信しない範囲）。

## 状態（2026-10-28）
このリポジトリの iOS のコードは**まだ一度もビルドしていません**（Windows の PC しかなく、Swift と Xcode が使えないため）。
最初の CI の実行で、コンパイルのエラーが出る可能性が高いです。直すのは CI のログを見ながら行います。
