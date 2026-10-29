# backend

サーバーは Supabase（PostgreSQL + Auth + RLS）で、独自のサーバーは持たない。中身は `../supabase/` にある。

- `../supabase/migrations/` 表・関数・RLS・履歴・実行権限（計算と権限の確認はすべてここ）
- `../supabase/functions/delete-account/` アカウント削除（service_role が必要な唯一の処理。Edge Function）
- `../supabase/tests/` DB のテスト（`bash supabase/tests/run.sh`）
- 共有のテストの値は `../tests/vectors/`（DB・Android・iOS の 3 か所で同じ値を使う）
