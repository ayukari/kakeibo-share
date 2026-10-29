# 実装計画 — 共有家計簿（Android / iOS ネイティブ + Supabase）

作成: 2026-10-28（フェーズ 1: 調査と設計）。この文書は、作業を進めるたびに更新する。

## 0. 前提と方針の決定

| 項目 | 決定 | 理由 |
|---|---|---|
| 置き場所 | `D:\kakeibo-share`（新しい Git リポジトリ） | 「かざすレシート」（`D:\tapreceipt`）とは分ける（指示: いったん別に）。作業は D ドライブで行う |
| Android | Kotlin + Jetpack Compose（Material 3）+ MVVM（ViewModel + StateFlow）+ Coroutines | 指示どおり |
| iOS | Swift + SwiftUI + MVVM（@Observable）+ Swift Concurrency | 指示どおり |
| DB・認証 | Supabase（PostgreSQL・Auth・RLS）を両アプリで 1 つだけ使う | 指示どおり。両アプリが同じデータを見る |
| 計算と権限 | **PostgreSQL の関数（RPC）と RLS で行う**。アプリは表示と入力の確認だけ | 「重要な計算と権限をクライアントだけに頼らない」。両 OS で結果が必ず一致する |
| 独自サーバー | 原則なし。退会（Auth ユーザーの削除）だけ Supabase Edge Function（`backend/` → `supabase/functions/`） | service_role キーが要る処理だけをサーバーに置く |
| 通信 | Supabase の HTTPS（PostgREST・Auth）。公式の Kotlin クライアント（supabase-kt）と Swift クライアント（supabase-swift） | 独自 API を増やさない |
| オフライン | 初期リリースではしない。通信できなければ保存失敗と表示し、入力内容は画面に残す | 指示 7 |

### この PC の環境（調査結果）

- Windows 11、Node 24、Git、JDK 17、Android SDK（platform 35/36、build-tools 34〜36、cmdline-tools）。
- Gradle 8.11.1 と Compose のキャッシュは一部ある。Android Studio、エミュレーター、システムイメージはない。
  - ハイパーバイザーはある（エミュレーターは入れれば動く見込み）。
- **Mac・Xcode はない → iOS 版はこの PC ではビルドもテストもできない。** コードは書くが、ビルドとテストは Mac で行う必要がある（結果は「未実行」と記録する）。
- Docker も PostgreSQL もない。
  - Supabase をローカルで動かす `supabase start` は Docker が要るため使えない。
  - SQL と RLS のテストは、PostgreSQL の公式バイナリ（zip）を D ドライブに置き、Supabase の `auth` スキーマを最小限まねた環境で行う。本番の Supabase でも同じテストを流す。

### Supabase 無料プランの条件（2026-10-28 に公式の料金ページで確認）

- DB 500MB、MAU 5 万、通信量 5GB、プロジェクト 2 つまで。
- **1 週間使われないと停止**（ダッシュボードから再開できる）。
- **自動バックアップは付かない** → 独自のバックアップが必須（§9）。
- **標準のメール送信は、プロジェクトの組織メンバー宛てにしか届かず、1 時間 2 通程度**。
  - 他の人のパスワード再設定やメール確認には、外部の SMTP の設定が必須（§6）。
- 「永久に無料」とは言えない。条件は変わりうる。

## 1. 画面（両 OS 共通の機能。見た目と操作は各 OS の流儀に合わせる）

1. ログイン・新規登録・パスワード再設定
   - メールに届く 6 桁の確認コードで行う。アプリへのリンクが要らない。
2. グループ選択・作成・招待コードで参加
3. ダッシュボード: 今月の収入・支出・収支、予算の残り、最近の取引、カテゴリ別、メンバー別、前月比、月ごとの推移
4. 収支一覧: 月の切り替え、並び替え、カテゴリ・登録者・支払った人での絞り込み、キーワード検索
5. 収支の登録・編集
   - 区分・金額・日付・カテゴリ・支払った人・支払い方法・メモ・公開範囲・分担
   - 削除は確認してから
6. 予算: グループ全体とカテゴリごと、月ごと。消化率と超過の警告
7. カテゴリ: 追加・編集・アーカイブ（色・アイコン）
8. メンバーと招待: 一覧、役割の変更、削除、招待コードの発行と取り消し（期限・回数）
9. 立替と精算: メンバーごとの立替・負担・差額、誰が誰にいくら払えば精算できるかの提案、精算の記録と確認、履歴
10. 定期取引: 一覧・登録・編集・停止、次の日付、今すぐ反映
11. レポート・グラフ: 月ごとの推移、カテゴリの比較
12. 設定とエクスポート: CSV（期間指定・UTF-8 BOM 付き）を共有シートで書き出す。プロフィール、パスワード変更、退会
13. 操作履歴（管理者以上）
14. エラー・アクセス拒否・データなしの状態（全画面）

| 機能 | Android | iOS |
|---|---|---|
| ナビゲーション | 下のナビゲーションバー + Navigation Compose | TabView + NavigationStack |
| 入力 | 金額は数字キーボード、日付は DatePicker（Material 3） | 金額は数字キーボード、日付は DatePicker |
| CSV 共有 | Storage Access Framework（保存）+ 共有の Intent | ShareLink / UIActivityViewController |
| 認証情報の保存 | Android Keystore（AES-GCM）で暗号化して DataStore に保存（supabase-kt の SessionManager を差し替え） | Keychain（supabase-swift の標準の保存先） |
| 生体認証のロック（任意） | BiometricPrompt | LocalAuthentication |

## 2. データの決まり（両 OS で同じ。詳細は `docs/spec-common.md`）

- **金額**: 日本円の整数（`bigint`、単位は円、小数なし）。`currency` 列は `'JPY'` 固定（CHECK 制約）。表示は ¥1,234。
- **日付**: 取引の発生日は `date`（暦の日付。日本時間で解釈）。記録の日時は `timestamptz`（UTC で保存、日本時間で表示）。月の区切りは日本時間の暦月。
- **識別子**: すべて UUID。カテゴリは ID で参照し、名前を変えても取引はそのまま。
- **取引の状態**: `active` / `deleted`（論理削除。集計から外す。履歴は残す）。
- **同時更新**: 各行に `version`。更新は「読んだときの version と同じなら」だけ成功させ、違えば「ほかの人が先に変更しました」と出して読み直す（楽観的排他）。
- **二重登録の防止**: 登録ごとにアプリが `client_request_id`（UUID）を作り、グループの中で一意にする。同じ送信が 2 回届いても 1 件だけ。さらに「同じ日・同じ金額・同じカテゴリ」が 10 分以内にあれば、登録前に確認する。
- **分担（split）**:
  - 均等割り: `floor(金額 ÷ 人数)` を全員に割り当て、余りの円はメンバーの並び順（参加日時順・同時なら ID 順）の先頭から 1 円ずつ足す。
  - 金額指定: 合計が取引の金額と一致しなければ保存しない。
- **立替と負担**:
  - 立替額 = その人が支払った支出の合計。負担額 = その人に割り当てられた分担の合計。
  - 差額 = 立替 − 負担 + 受け取った精算 − 払った精算（確認済みのものだけ）。プラスなら受け取る側。
- **精算**:
  - 状態は `pending`（払った人が記録）→ `confirmed`（受け取った人が確認）か `cancelled`。
  - 差額に数えるのは `confirmed` だけ。同じ精算を 2 回確認できない（状態遷移を関数で行う）。
  - 精算の記録は「家計簿の上での記録」で、実際の送金はしない（画面に明記）。
  - 精算の提案は、差額の大きい人どうしを順に組み合わせる方法（送金の回数が少なくなる）。
- **予算**:
  - 対象は、その月（暦月）の `active` な支出。グループの予算と比べるのは公開範囲が「グループ」の支出、個人の予算と比べるのは自分が負担した分。
  - 消化率 = 支出 ÷ 予算。100% をこえたら超過。
  - 月が変わると新しい月で数え直す。前月の予算を引き継ぐかどうかは、予算ごとに設定する。
- **定期取引**:
  - 周期は毎週・毎月（日付、月末）・毎年。`next_run_on` を管理する。
  - 生成は関数 `generate_due_recurring(group)` で、`(recurring_id, occurrence_date)` の一意制約によって二重に作らない。何度実行しても同じ結果になる。アプリを開いたときに実行する（サーバーの定期実行は使わない＝無料枠の範囲内）。
- **エラーの分類**: `network`（通信できない）、`unauthorized`（ログインが切れた）、`forbidden`（権限がない）、`not_found`、`conflict`（ほかの人が先に変更）、`validation`（入力の誤り。項目ごと）、`server`。両アプリで同じ文言の表を使う。
- **入力の検証**:
  - 金額は 1〜999,999,999 円の整数。日付は 2000-01-01〜今日から 1 年後まで。
  - メモは 500 字まで。グループ名は 1〜40 字。カテゴリ名は 1〜20 字。
  - アプリとデータベース（CHECK 制約と関数）の両方で確かめる。

## 3. 役割と権限（サーバー＝RLS と関数で必ず確かめる）

| 操作 | owner | admin | member | viewer |
|---|---|---|---|---|
| 公開範囲「グループ」の取引を見る | ○ | ○ | ○ | ○ |
| 公開範囲「自分だけ」の取引を見る | 作った人だけ | 作った人だけ | 作った人だけ | − |
| 取引を登録する | ○ | ○ | ○ | × |
| 取引を編集・削除する | すべて | すべて | 自分が作ったものだけ | × |
| カテゴリ・予算・定期取引を管理する | ○ | ○ | × | × |
| 招待コードを発行する | ○ | ○ | × | × |
| 役割を変える・メンバーを外す | すべて | member と viewer だけ | × | × |
| グループの名前・設定を変える | ○ | ○ | × | × |
| グループを消す・オーナーを譲る | ○ | × | × | × |
| 操作履歴を見る | ○ | ○ | × | × |
| 精算を記録する | 自分が払う側のもの | 同じ | 同じ | × |
| 精算を確認する | 自分が受け取る側のもの | 同じ | 同じ | × |

- 「全員がすべてを見られる」にはしない。公開範囲「自分だけ」の取引と、`viewer`（見るだけ）の役割を用意する。
- **招待**:
  - コードは推測できない 12 文字。DB にはハッシュだけを保存する。期限（初期値 7 日）・使用回数（初期値 1 回）・付与する役割（member か viewer。admin 以上は付与できない）を持つ。
  - コードを知っているだけでは何も見えない。ログインして参加の承認関数を呼んで初めてメンバーになる。
  - コードの総当たりは関数の中で回数を制限する。
- RLS は「そのグループの、承認済みメンバーであること」を `auth.uid()` で確かめる関数（`is_member(group, min_role)`）を通す。グループ ID を書き換えても、他のグループの行は返らない。

## 4. データベース（`supabase/migrations/`。詳細は `docs/database.md`）

- `profiles`(id=auth.users.id, display_name, created_at, updated_at)
- `groups`(id, name, created_by, created_at, updated_at)
- `group_members`(group_id, user_id, role, joined_at, left_at, sort_key) — PK(group_id, user_id)
- `invitations`(id, group_id, code_hash UNIQUE, role, expires_at, max_uses, used_count, created_by, revoked_at)
- `categories`(id, group_id, kind, name, color, icon, sort, archived_at) — UNIQUE(group_id, kind, name) は archived を除く
- `payment_methods`(id, group_id, name)（現金・クレジットカード・電子マネー・QR・口座振替・その他を初期値に）
- `transactions`(id, group_id, kind, amount, currency, occurred_on, category_id, payer_member, payment_method_id, memo, visibility, status, created_by, created_at, updated_at, version, client_request_id, recurring_id, occurrence_date) — UNIQUE(group_id, client_request_id)、UNIQUE(recurring_id, occurrence_date)
- `transaction_splits`(transaction_id, user_id, amount) — PK(transaction_id, user_id)
- `budgets`(id, group_id, month, category_id NULL=全体, scope 'group'|'personal', user_id, amount, carry_over) — 一意制約あり
- `settlements`(id, group_id, from_user, to_user, amount, status, note, created_by, created_at, confirmed_at, confirmed_by, client_request_id)
- `recurring_transactions`(id, group_id, kind, amount, category_id, payer, payment_method_id, memo, freq, interval, day_of_month, weekday, start_on, end_on, next_run_on, active, splits jsonb, created_by, version)
- `audit_logs`(id, group_id, actor, action, target_table, target_id, at, detail jsonb) — トリガーで記録。秘密情報は入れない。誰も UPDATE・DELETE できない
- 外部キーは原則 `ON DELETE RESTRICT`。グループを消すときだけ、関数の中で順番に消す。
- 使われているカテゴリは消さずにアーカイブする（取引の参照を壊さない）。
- 取引と分担の登録・更新、精算の確認、招待の承認、定期取引の生成は、それぞれ 1 つの関数（1 トランザクション）で行う。

## 5. テスト計画（結果は `docs/test-results.md`。実行していないものは「未実行」と書く）

- **DB**（ローカルの PostgreSQL。可能なら本番の Supabase でも）:
  - マイグレーションの適用
  - RLS（未ログイン・別グループ・viewer・member・admin・owner）
  - 招待（期限・回数・役割の上限・総当たり）
  - 計算（`tests/vectors/*.json` の共通ケース: 均等割り・端数・金額指定・立替と負担・精算の提案・予算）
  - 二重登録・同時更新（version の食い違い）・定期取引の再実行
- **Android**:
  - コンパイル、lint、単体テスト（JUnit。共通ケースの表示計算と入力の検証）
  - Compose UI テスト（Robolectric。エミュレーターなしで動く範囲）
  - 実際の Supabase につないだ結合テスト（環境変数があるときだけ）
- **iOS**: XCTest と UI テストを書くが、**この PC では実行できない**（Mac が要る）。
- **両 OS の結合**:
  - 「Android で登録 → iOS で見える」など 6 項目
  - iOS が動かせないため、同じ API を叩く結合テスト（Kotlin 側と、Swift の仕様に合わせた HTTP のテスト）で代わりに確かめる範囲を明記する

## 6. 認証

- Supabase Auth（メールアドレス + パスワード）。パスワードは Supabase が bcrypt でハッシュして保存（平文では持たない）。
- パスワード再設定とメール確認は、メールで届く 6 桁のコード（`verifyOtp`）で行う。アプリへのリンクやドメインが要らない。
  - **外部の SMTP の設定が必須**（無料の候補と条件は `docs/cost-and-limits.md`）。
- アプリに入れる鍵は「公開してよい anon キー」だけ。service_role キーは Edge Function の環境変数だけに置く。
- セッション: Android は Keystore で暗号化して保存、iOS は Keychain。期限が切れる前に更新し、更新に失敗したらログイン画面に戻す。ログアウトではサーバー側のセッションも無効にする。
- 退会: Edge Function `delete-account`。
  - 本人の取引は「退会したメンバー」として残す（共有の家計簿が壊れないように）。プロフィールの名前は消す。
  - オーナーのままのグループがあれば、先に譲るか、グループを消すよう求める。
  - 扱いは画面と `docs/privacy.md` に明記する。

## 7. 進め方（フェーズと完了条件）

| フェーズ | 内容 | 完了条件 |
|---|---|---|
| 1 調査 | 環境・無料枠・ライブラリ | この文書 |
| 2 設計 | DB・RLS・関数・API・共通仕様・エラー表 | `docs/spec-common.md`、`docs/database.md`、`docs/api.md` |
| 3 バックエンド | マイグレーション・RLS・関数・Edge Function、DB テスト | ローカルの PostgreSQL ですべて通る。本番への適用手順 |
| 4 Android | 全機能、単体・UI テスト | `./gradlew build test lint` が通る。実際の Supabase で手動確認 |
| 5 iOS | 全機能、XCTest | コード完成。ビルドとテストは Mac で（未実行と明記） |
| 6 両 OS の検証 | 結合テスト | 実行できた範囲と、できない範囲を記録 |
| 7 セキュリティ・バックアップ | RLS の総当たり確認・バックアップと復元の演習 | 手順の実演結果 |
| 8 配布 | ビルド・署名・ストア公開の手順と費用 | 手順書 |

### 進み具合（2026-10-28 現在）

| フェーズ | 状態 | 根拠 |
|---|---|---|
| 1 調査 | 完了 | この文書 |
| 2 設計 | 完了 | docs/spec-common.md・database.md・api.md |
| 3 バックエンド | ローカルで完了 | DB テスト 3 本が通る（docs/test-results.md）。本物の Supabase への適用は社長のプロジェクト作成待ち |
| 4 Android | コード完成・ローカルのテストまで | 単体 8・UI 7（Robolectric）が通る、lint エラー 0、APK 作成。**実際の Supabase での手動確認は未** |
| 5 iOS | コード完成・**未ビルド** | Mac がないため。CI（クラウドの Mac）の設定まで |
| 6 両 OS の検証 | 未 | tests/integration-checklist.md に 16 項目を用意。Supabase と iOS のビルドが要る |
| 7 セキュリティ・バックアップ | ローカルで完了 | 権限の穴を 1 つ見つけて修正（t_03）。バックアップと戻しをローカルで練習 |
| 8 配布 | 手順書まで | docs/distribution.md・cost-and-limits.md |

## 8. 社長に決めてもらう・してもらうこと

1. **Supabase のアカウントとプロジェクトの作成**（無料）。私はアカウントを作れない。
   - 作成後、プロジェクトの URL と anon キー（公開してよい鍵）を教えてもらう。
   - マイグレーションの適用は、社長が SQL エディターに貼るか、CLI で行う（DB のパスワードは私に渡さない）。
2. **ダウンロードの許可**: Gradle と Android のライブラリ（数百 MB〜1GB 程度）、PostgreSQL の公式バイナリ（約 300MB、DB テスト用）。
   - 置き場所は D ドライブ（`GRADLE_USER_HOME`、`D:\tools\pgsql`）。
3. **Mac の有無**（iOS のビルド・テスト・配布に必須）。
4. **メール送信（SMTP）の選択**（パスワード再設定のメールに必須）。
5. ストア公開をするか。
   - Google Play の開発者登録は一度だけ 25 ドル、Apple Developer Program は年 99 ドル。
   - 家族だけで使うなら、Android は APK の直接配布、iOS は TestFlight（Apple Developer Program が要る）も選べる。

## 9. バックアップ

- 無料プランには自動バックアップがない。
- `pg_dump`（Supabase の接続文字列）で、毎週 D ドライブと別の保存先（社長の Google ドライブなど）に保存する。スクリプトと手順は `docs/backup-restore.md`。
- 復元の演習: ローカルの PostgreSQL に戻して、アプリの関数の結果が一致することを確かめる。
- グループ単位の CSV 書き出しは、利用者の手元の控え（完全なバックアップではない）。
