# データベース

PostgreSQL（Supabase）。マイグレーションは `supabase/migrations/` に番号順。

| ファイル | 中身 |
|---|---|
| 20261028000100_core.sql | 型・表・索引・RLS（読むだけの方針） |
| 20261028000200_functions.sql | 書き込みと計算の関数（すべて SECURITY DEFINER で権限を確かめる） |
| 20261028000300_audit.sql | 操作の履歴を残すトリガー |
| 20261028000400_privileges.sql | 内部用の関数を利用者から呼べないようにする |

## 表

| 表 | 内容 | 主な決まり |
|---|---|---|
| profiles | 表示名 | 登録時にトリガーで作る |
| groups | 家計簿 | 削除は `deleted_at`（論理削除） |
| group_members | 参加者と権限 | オーナーは 1 グループ 1 人。抜けても行は残る（過去の記録の名前のため） |
| invitations | 招待 | コードは sha256 だけ保存。期限・回数・取り消し |
| invitation_attempts | 招待コードの試行 | 15 分に 10 回まで。利用者からは見えない |
| categories | カテゴリ | 使われていれば消さずに `archived_at` |
| payment_methods | 支払い方法 | |
| transactions | 収支 | 金額 bigint 1..999,999,999、日付 date、`version`、`client_request_id` はグループ内で一意、削除は status = deleted |
| transaction_splits | 割り勘の負担 | 合計 = 金額 |
| budgets | 予算 | (グループ, 範囲, カテゴリ, 人, 開始月) で一意 |
| settlements | 精算 | pending → confirmed / cancelled |
| recurring_transactions | 定期的な収支 | 生成済みの日付は transactions の (recurring_id, 日付) 一意で守る |
| audit_logs | 操作の履歴 | 変わった項目名・権限や状態の変化・金額だけ。招待コードのハッシュは残さない |

## 権限の守り方

1. 表への直接の INSERT / UPDATE / DELETE は anon・authenticated から取り上げている。書き込みは関数だけ。
2. 読むのは RLS: そのグループの参加中のメンバーだけ。「自分だけ」の収支は作った本人だけ。
3. 関数は最初に `_need(グループ, 必要な権限)` で確かめ、足りなければ `KB403`。
4. 内部用の関数（`_write_splits` など）は利用者から実行できない（`t_03_privileges.sql` で確認）。
5. アカウント削除の準備（`prepare_account_deletion`）は service_role だけ（Edge Function から）。

## テスト

`bash supabase/tests/run.sh`（ローカルの PostgreSQL 17 に、Supabase の auth を真似た最小の土台を作って流す）。
- t_01_access: ログインなし・部外者・招待・総当たりの制限・権限ごとの可否・「自分だけ」・他グループ・履歴に秘密がない
- t_02_money: 均等割り（共有の値）・精算の筋書き・二重登録・入力検証・予算・月の集計・同時編集・定期（月末・毎週）・カテゴリの退避・退会
- t_03_privileges: 内部関数の実行権限・表への直接書き込み
