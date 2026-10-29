# API（アプリ → Supabase）

通信は HTTPS + JSON。認証は Supabase Auth（メールとパスワード、確認と再設定はメールの 6 桁のコード）。
読み取りは PostgREST の表（RLS が効く）、書き込みと計算は RPC（`POST /rest/v1/rpc/<関数名>`）。

## 読み取り（表）

`groups` `group_members` `invitations`（管理者以上） `categories` `payment_methods` `transactions` `transaction_splits` `budgets` `settlements` `recurring_transactions` `audit_logs`（管理者以上）

## RPC

| 関数 | 引数 | 戻り | 権限 |
|---|---|---|---|
| update_profile | p_display_name | profiles | 本人 |
| create_group | p_name | groups（既定のカテゴリ 19・支払い方法 6 を作る） | ログイン |
| rename_group / delete_group | p_group (, p_name) | groups / なし | 管理者 / オーナー |
| create_invitation | p_group, p_role(member/viewer), p_expires_hours, p_max_uses | {id, code, expires_at, role, max_uses}（code はこのときだけ） | 管理者 |
| revoke_invitation | p_invitation | なし | 管理者 |
| accept_invitation | p_code (, p_display_name) | group_members / 無効なら null | ログイン |
| change_member_role / remove_member / transfer_ownership | p_member (, p_role) | | 管理者 / 管理者 / オーナー |
| leave_group | p_group | なし | メンバー（オーナー以外） |
| save_category / delete_category | … / p_category | categories / 'deleted' か 'archived' | 管理者 |
| save_payment_method | p_group, p_id, p_name, p_archived | payment_methods | 管理者 |
| save_transaction | p_group, p {id?, version?, client_request_id, kind, amount, occurred_on, category_id, payer_member_id, payment_method_id, memo, visibility, split_mode, splits} | transactions | メンバー（他人の記録は管理者） |
| delete_transaction | p_id, p_version | なし | 同上 |
| similar_transactions | p_group, p_amount, p_occurred_on, p_category | transactions[] | 閲覧以上 |
| group_balances / settlement_suggestions | p_group | 差額[] / 提案[] | 閲覧以上 |
| record_settlement | p_group, p_from, p_to, p_amount, p_note, p_client_request_id | settlements | メンバー |
| confirm_settlement / cancel_settlement | p_id | settlements | 受け取った人か管理者 / 当事者か管理者 |
| save_budget / delete_budget / budget_status | … | | 管理者 / 管理者 / 閲覧以上 |
| month_summary | p_group, p_month | {income, expense, balance, prev_*, by_category, by_payer, by_burden} | 閲覧以上 |
| monthly_series | p_group, p_end_month, p_months | {month, income, expense}[] | 閲覧以上 |
| save_recurring / delete_recurring | … | | 管理者 |
| generate_due_recurring | p_group | 作った件数 | メンバー |

`splits`: 均等なら メンバー ID の配列、指定なら `[{member_id, amount}]`、割り勘なしは `[]`。

## Edge Function

`delete-account`（POST, ログインの JWT, body `{"confirm":"DELETE"}`）: ほかのメンバーがいる家計簿のオーナーなら 409 `owner_must_transfer`（先にオーナーを渡す）。そうでなければ、自分しかいない家計簿は削除し、「自分だけ」の記録を消し、メンバーの行は「退会したメンバー」として残して切り離し、認証のユーザーを削除する。

## エラー

PostgREST のエラー `{code, message, hint}`。code は SQLSTATE（KB401/KB403/KB404/KB409/KB422）、message は理由のキー（`amount_invalid` など）、hint は項目名。分類は docs/spec-common.md。
