# バックアップと戻し方

無料プランの Supabase には自動バックアップがないので、管理者が手で取ります（目安: 週 1 回と、大きな変更の前）。

## 取る
Project Settings → Database → Connection string（Session pooler）を使う。パスワードはコマンドに直接書かず、聞かれたら入れる。
```
pg_dump "postgresql://postgres.<ref>@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres" -Fc -n public -f backups/kakeibo_YYYY-MM-DD.dump
```
- `backups/` は git に入らない。ファイルには家計簿の中身が入るので、暗号化した場所（BitLocker のドライブなど）に置く。
- ログインの情報（auth スキーマ）は Supabase が管理するので、ここでは取らない。戻すときは各自のアカウントが残っている前提。

## 戻す
1. 新しいプロジェクトに戻すときは、先に docs/supabase-setup.md の 1〜3 を行う（マイグレーションまで）。
2. 中身を戻す:
```
pg_restore --no-owner --data-only --disable-triggers -d "<接続文字列>" backups/kakeibo_YYYY-MM-DD.dump
```
3. アプリで、件数と精算の差額がバックアップ前と同じか確かめる。

## 練習（2026-10-28 にローカルで実施）
ローカルの PostgreSQL 17 で、テストのデータが入った DB を `pg_dump -Fc` → 別の DB に `pg_restore --clean --if-exists --no-owner`。
- 収支 19 件・割り勘 18 行・精算 1 件・履歴 137 件・金額の合計 767,849 円が、戻す前と同じ。
- 戻した DB で `group_balances` が同じ結果。
本物の Supabase での練習は、プロジェクトができてから行う（未テスト）。
