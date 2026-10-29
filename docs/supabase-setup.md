# Supabase の準備（社長がやること）

アカウントの作成とパスワードの入力は、Claude はしません（安全のため）。以下は社長の手で行ってください。

## 1. プロジェクトを作る
1. https://supabase.com でサインアップ（GitHub かメール）。
2. New project → 名前（例: kakeibo-share）・リージョン **Tokyo (ap-northeast-1)**・DB パスワード（長いもの。パスワード管理アプリに保存）・プランは Free。

## 2. テーブルと関数を入れる
どちらかの方法で、`supabase/migrations/` の 4 ファイルを**番号順に**流します。
- かんたん: ダッシュボードの SQL Editor に、ファイルの中身を 1 つずつ貼って Run。
- CLI: `supabase login` → `supabase link --project-ref <ref>` → `supabase db push`。

流したあと、SQL Editor で次が 0 件なら、内部用の関数が守られています。
```sql
select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute') and p.proname like '\_%';
```

## 3. 認証の設定（Authentication）
- Sign In / Providers → Email: 有効。**Confirm email: ON**。
- Emails → テンプレート「Confirm signup」「Reset password」に `{{ .Token }}`（6 桁のコード）を入れる。アプリはリンクではなくコードを使う。
- Password: 最低 8 文字。
- **SMTP**: 標準の送信は同じ組織のメンバーにしか届かず、1 時間に数通まで。家族・知人に使うなら独自 SMTP が必要（docs/cost-and-limits.md の候補から選ぶ。送信元のドメインが要る）。

## 4. アカウント削除の Edge Function
```
supabase functions deploy delete-account
```
（`SUPABASE_URL`・`SUPABASE_ANON_KEY`・`SUPABASE_SERVICE_ROLE_KEY` は Supabase が自動で渡す。service_role キーはアプリにもリポジトリにも書かない）

## 5. アプリに接続先を書く
Project Settings → API の **Project URL** と **anon public** キーだけを使う。
- Android: `android/local.properties` に `SUPABASE_URL=` と `SUPABASE_ANON_KEY=`
- iOS: `ios/Config/Secrets.xcconfig`（例は Secrets.example.xcconfig）
どちらも git に入らない設定です。anon キーはアプリに入る前提の公開キーで、権限は RLS と関数が守ります。

## 6. 注意（無料プラン）
- 1 週間使われないとプロジェクトが一時停止します（ダッシュボードから再開できる）。
- 自動バックアップはありません。docs/backup-restore.md の手順で定期的に取ってください。

## 実施状況（2026-10-28）
- プロジェクト `kakeibo-share`（リージョン ap-northeast-2 ソウル）を社長が作成。
- マイグレーション 4 本を SQL Editor で適用済み（表 13・関数 45・履歴のトリガー 9・登録時のプロフィール作成のトリガー）。適用後に確認した結果:
  - 内部用の関数（`_` で始まるもの）は authenticated から実行できない。
  - ログインなし（anon）では、表の読み取りも `create_group` も権限エラー（42501）になる。
- 接続先（URL と anon の鍵）は `android/local.properties` と `ios/Config/Secrets.xcconfig` に入れた（どちらも git に入らない）。service_role の鍵は使っていない。
- 未了: ① 独自 SMTP（Resend）の設定とメールのテンプレートへの `{{ .Token }}` の追加。標準の SMTP のままではテンプレートを編集できず、登録の確認がリンクだけのメールになるため、アプリの「6 桁のコード」では確認できない。② Edge Function `delete-account` のデプロイ。
- 「Confirm email」は ON のまま。SMTP ができるまで試すだけなら、一時的に OFF にすれば、メールなしで登録できる（その間は、メールアドレスが本人のものか確認されない）。
