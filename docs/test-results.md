# テストの結果（2026-10-28、Windows 11 の PC で実行）

## DB（PostgreSQL 17.11、Supabase の auth を真似た土台）
`bash supabase/tests/run.sh`
```
migrations: OK
PASS t_01_access.sql
PASS t_02_money.sql
PASS t_03_privileges.sql
```
t_03 は、Supabase の既定の権限のせいで内部用の関数（`_write_splits` など）を利用者が直接呼べる穴を見つけて、`20261028000400_privileges.sql` で塞いだあとに通ったもの。

## Android
`./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleRelease`
| | 結果 |
|---|---|
| DomainTest（JUnit） | 8 件 成功 |
| UiTest（Robolectric + Compose UI テスト） | 7 件 成功 |
| lint | エラー 0・警告 17（新しい版がある・KTX 推奨など。動きに関わるものはなし） |
| debug APK | 作成できた |
| release APK（R8 で縮小、署名なし） | 作成できた。**起動は未確認**（縮小で通信の部品が壊れていないかは実機で要確認） |

## iOS
**未テスト（一度もビルドしていない）**。Windows では Xcode と Swift が使えない。`.github/workflows/ci.yml` の `ios` ジョブで、クラウドの Mac でビルドとテストを行う予定（GitHub に置くかは社長の判断待ち）。

## バックアップと戻し
ローカルで練習済み（docs/backup-restore.md）。本物の Supabase では未テスト。

## まだやっていない確認
- 本物の Supabase につないだ通しの確認（tests/integration-checklist.md の 16 項目、両 OS とも）
- Android の実機・エミュレーターでの確認（この PC にエミュレーターがない）
- メールの送信（SMTP 未設定）
- CI（GitHub Actions）の実行
